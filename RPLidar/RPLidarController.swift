//
//  RPLidarController.swift
//  RPLidar
//
//  Created by Rob Makina on 4/9/22.
//  Copyright © 2022 OrbitusRobotics. All rights reserved.
//

import UIKit
import SlamwareSDK

enum RPLidarRelocalizationState {
    case idle
    case waiting(progress: Double)
    case running(progress: Double)
    case finished
    case stopped
    case failed
}

enum RPLidarControllerError: LocalizedError {
    case notConnected
    case operationFailed(name: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "The RPLidar is not connected."
        case .operationFailed(let name, let underlying):
            return "\(name) failed: \(underlying.localizedDescription)"
        }
    }
}

class RPLidarController: NSObject {
    var connectionIP: String
    var deviceManager: RPDeviceManager?
    var rpSlamwarePlatformProtocol_object: RPSlamwarePlatformProtocol?
    
    var currentLocation: RPLocation?
    var currentPose: RPPose?
    var currentLaserScan: RPLaserScan?
    var currentLaserPoints: [RPLaserPoint]?
    var currentMap: RPMap?
    var currentCompositeMap: RPCompositeMap?
    private var relocalizationAction: RPMoveActionProtocol?
    
    init(ip: String) {
        connectionIP = ip
        super.init()
        deviceManager = RPDeviceManager.init(delegate: self)
        deviceManager?.start(.BOTH)
        rpSlamwarePlatformProtocol_object = deviceManager?.connect(connectionIP, withPort: 1445)
    }
    
    /// Clears the current map and returns Slamware to normal mapping mode.
    /// A direct clear is fastest on firmware that supports it. This Mapper's
    /// firmware rejects map mutations, so one failure goes immediately to the
    /// proven soft-service-restart path instead of spending time retrying the
    /// other map APIs.
    func resetMap() throws {
        guard let platform = rpSlamwarePlatformProtocol_object else {
            throw RPLidarControllerError.notConnected
        }
        let startedAt = Date()
        var finalPlatform = platform

        do {
            try clearMap(on: platform)
        } catch {
            print("Direct clearMap failed; using fast SLAM service restart: \(error.localizedDescription)")
            relocalizationAction = nil
            do {
                finalPlatform = try restartSlamwareForMapReset(on: platform)
            } catch {
                let recoveryPlatform = rpSlamwarePlatformProtocol_object ?? platform
                try? performSDKOperation(named: "Restore map localization") {
                    recoveryPlatform.setMapLocalization(true)
                }
                try? performSDKOperation(named: "Restore map update") {
                    recoveryPlatform.setMapUpdate(true)
                }
                throw RPLidarControllerError.operationFailed(
                    name: "Fast map reset using SLAM service restart",
                    underlying: error
                )
            }
        }

        currentMap = nil
        currentCompositeMap = nil

        try performSDKOperation(named: "Enable map update") {
            finalPlatform.setMapUpdate(true)
        }
        try performSDKOperation(named: "Enable map localization") {
            finalPlatform.setMapLocalization(true)
        }
        try waitForMapModes(
            on: finalPlatform,
            mapUpdate: true,
            mapLocalization: true
        )
        print(String(format: "Map reset completed in %.2f seconds", Date().timeIntervalSince(startedAt)))
    }

    private func clearMap(on platform: RPSlamwarePlatformProtocol) throws {
        try performSDKOperation(named: "Clear map") {
            platform.clearMap()
        }
    }

    private func exploreMapIsEmpty(on platform: RPSlamwarePlatformProtocol) -> Bool {
        var knownArea: RPRectangleF?
        do {
            try performSDKOperation(named: "Check cleared map") {
                knownArea = platform.getKnownArea(
                    of: RPMapTypeBitmap8Bit,
                    andMapKind: RPMapKindExploreMap
                )
            }
        } catch {
            print("Unable to verify whether the map is empty: \(error.localizedDescription)")
            return false
        }
        return knownArea?.empty() ?? false
    }

    /// Firmware on some Mapper units exposes clearMap but always returns
    /// OperationFail. Replacing the explore layer with an all-unknown bitmap
    /// uses the SDK's supported map-upload path and has the same observable
    /// result once live map updating resumes.
    private func replaceExploreMapWithBlankMap(
        on platform: RPSlamwarePlatformProtocol,
        pose: RPPose?,
        template: RPMap?
    ) throws {
        guard let pose else {
            throw RPLidarControllerError.operationFailed(
                name: "Create blank map",
                underlying: NSError(
                    domain: "RPLidar",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "No current droid pose is available."]
                )
            )
        }

        let defaultResolution: Float = 0.05
        let templateWidth = template?.dimension.width ?? 0
        let templateHeight = template?.dimension.height ?? 0
        let templateResolutionX = template?.resolution.x ?? defaultResolution
        let templateResolutionY = template?.resolution.y ?? defaultResolution
        let hasValidTemplate = templateWidth > 0
            && templateHeight > 0
            && templateResolutionX.isFinite
            && templateResolutionY.isFinite
            && templateResolutionX > 0
            && templateResolutionY > 0
        let width: Int32 = hasValidTemplate ? templateWidth : 32
        let height: Int32 = hasValidTemplate ? templateHeight : 32
        let resolutionX = hasValidTemplate ? templateResolutionX : defaultResolution
        let resolutionY = hasValidTemplate ? templateResolutionY : defaultResolution
        let worldWidth = Float(width) * resolutionX
        let worldHeight = Float(height) * resolutionY
        let fallbackOriginX = pose.location.x - worldWidth / 2
        let fallbackOriginY = pose.location.y - worldHeight / 2
        let originX = hasValidTemplate
            ? template?.origin.x ?? fallbackOriginX
            : fallbackOriginX
        let originY = hasValidTemplate
            ? template?.origin.y ?? fallbackOriginY
            : fallbackOriginY
        let (pixelCount, pixelCountOverflow) = Int(width).multipliedReportingOverflow(
            by: Int(height)
        )

        guard !pixelCountOverflow,
              let origin = RPPointF(
                x: originX,
                andY: originY
              ),
              let dimension = RPSize(width: width, andHeight: height),
              let resolution = RPPointF(x: resolutionX, andY: resolutionY) else {
            throw RPLidarControllerError.operationFailed(
                name: "Create blank map",
                underlying: NSError(
                    domain: "RPLidar",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "The blank map geometry is invalid."]
                )
            )
        }

        // Slamware bitmap values are signed bytes biased by +128 for display;
        // raw zero is therefore neutral gray/unknown space.
        let data = Data(repeating: 0, count: pixelCount)
        let blankMap = RPMap(
            origin: origin,
            andDimension: dimension,
            andResolution: resolution,
            andTimestamp: template?.timestamp ?? 0,
            andData: data
        )

        try performSDKOperation(named: "Upload blank map") {
            platform.setMapWith(
                blankMap,
                of: RPMapTypeBitmap8Bit,
                andMapKind: RPMapKindExploreMap
            )
        }
        try performSDKOperation(named: "Restore pose after blank map upload") {
            platform.setPose(pose)
        }
    }

    private func readCurrentExploreMap(on platform: RPSlamwarePlatformProtocol) -> RPMap? {
        var map: RPMap?
        do {
            try performSDKOperation(named: "Read map template for reset") {
                let knownArea = platform.getKnownArea(
                    of: RPMapTypeBitmap8Bit,
                    andMapKind: RPMapKindExploreMap
                )
                if !knownArea.empty() {
                    map = platform.getMapWith(
                        RPMapTypeBitmap8Bit,
                        inArea: knownArea,
                        of: RPMapKindExploreMap
                    )
                }
            }
        } catch {
            print("Unable to read a map template for reset: \(error.localizedDescription)")
        }
        return map
    }

    private func readCurrentCompositeMap(
        on platform: RPSlamwarePlatformProtocol
    ) -> RPCompositeMap? {
        var map: RPCompositeMap?
        do {
            try performSDKOperation(named: "Read composite map template for reset") {
                map = platform.compositeMap()
            }
        } catch {
            print("Unable to read a composite map template for reset: \(error.localizedDescription)")
        }
        return map
    }

    private func replaceExploreMapWithBlankCompositeMap(
        on platform: RPSlamwarePlatformProtocol,
        pose: RPPose?,
        template: RPCompositeMap?
    ) throws {
        guard let pose else {
            throw RPLidarControllerError.operationFailed(
                name: "Create blank composite map",
                underlying: NSError(
                    domain: "RPLidar",
                    code: 8,
                    userInfo: [NSLocalizedDescriptionKey: "No current droid pose is available."]
                )
            )
        }
        guard let template, let layers = template.maps else {
            throw RPLidarControllerError.operationFailed(
                name: "Create blank composite map",
                underlying: NSError(
                    domain: "RPLidar",
                    code: 9,
                    userInfo: [NSLocalizedDescriptionKey: "Slamware did not provide a composite map template."]
                )
            )
        }

        var replacedExploreLayer = false
        for layer in layers {
            guard layer.usage.caseInsensitiveCompare("explore") == .orderedSame,
                  let gridLayer = layer as? RPGridMapLayer else {
                continue
            }

            let width = Int(gridLayer.dimension.width)
            let height = Int(gridLayer.dimension.height)
            let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
            guard width > 0, height > 0, !overflow else {
                throw RPLidarControllerError.operationFailed(
                    name: "Create blank composite map",
                    underlying: NSError(
                        domain: "RPLidar",
                        code: 10,
                        userInfo: [NSLocalizedDescriptionKey: "The explore layer geometry is invalid."]
                    )
                )
            }

            gridLayer.mapData = Data(repeating: 0, count: pixelCount)
            replacedExploreLayer = true
        }

        guard replacedExploreLayer else {
            throw RPLidarControllerError.operationFailed(
                name: "Create blank composite map",
                underlying: NSError(
                    domain: "RPLidar",
                    code: 11,
                    userInfo: [NSLocalizedDescriptionKey: "The composite map has no explore grid layer."]
                )
            )
        }

        try performSDKOperation(named: "Upload blank composite map") {
            platform.setCompositeMapWithMapData(template, andPose: pose)
        }
    }

    /// Restarts only Slamware's services, reconnects to port 1445, and leaves
    /// the returned platform paused with an empty explore map. This is the
    /// final compatibility path for firmware that rejects all map mutations
    /// while its localization service is stuck in an invalid state.
    private func restartSlamwareForMapReset(
        on platform: RPSlamwarePlatformProtocol,
        timeout: TimeInterval = 30
    ) throws -> RPSlamwarePlatformProtocol {
        var restartRequestError: Error?
        do {
            try performSDKOperation(named: "Request soft SLAM service restart") {
                platform.restartModule(with: RPRestartModeSoft)
            }
        } catch {
            // A successful restart can close the command connection before
            // the SDK receives its reply. Reconnection and a live map query
            // below are authoritative, so retain this only for diagnostics.
            restartRequestError = error
            print("The restart request connection closed: \(error.localizedDescription)")
        }

        let deadline = Date().addingTimeInterval(timeout)
        var lastConnectionError = restartRequestError
        var lastResponsiveCandidate: RPSlamwarePlatformProtocol?
        var attempt = 0
        Thread.sleep(forTimeInterval: 0.2)

        while Date() < deadline {
            attempt += 1
            var candidate: RPSlamwarePlatformProtocol?

            if attempt == 1 {
                // Some SDK/device combinations transparently reconnect the
                // existing platform object after a soft service restart.
                candidate = platform
            } else {
                do {
                    try ExceptionCatcher.catchException {
                        candidate = self.deviceManager?.connect(
                            self.connectionIP,
                            withPort: 1445
                        )
                    }
                } catch {
                    lastConnectionError = error
                }
            }

            if let candidate {
                do {
                    try performSDKOperation(named: "Pause map update after restart") {
                        candidate.setMapUpdate(false)
                    }
                    try performSDKOperation(named: "Pause map localization after restart") {
                        candidate.setMapLocalization(false)
                    }
                    try waitForMapModes(
                        on: candidate,
                        mapUpdate: false,
                        mapLocalization: false,
                        timeout: 2
                    )
                    lastResponsiveCandidate = candidate

                    // A service restart normally starts with no map. If this
                    // firmware retained one, the restarted localization state
                    // should now allow the real clearMap command to succeed.
                    if !exploreMapIsEmpty(on: candidate) {
                        try clearMap(on: candidate)
                    }

                    rpSlamwarePlatformProtocol_object = candidate
                    return candidate
                } catch {
                    lastConnectionError = error
                }
            }

            Thread.sleep(forTimeInterval: 0.25)
        }

        if let lastResponsiveCandidate {
            // Keep the controller attached to the recovered service even when
            // its firmware still refuses the final clear, so normal polling
            // and the error-recovery mode restoration use a live connection.
            rpSlamwarePlatformProtocol_object = lastResponsiveCandidate
        }

        throw RPLidarControllerError.operationFailed(
            name: "Reconnect after soft SLAM service restart",
            underlying: lastConnectionError ?? NSError(
                domain: "RPLidar",
                code: 12,
                userInfo: [NSLocalizedDescriptionKey: "Slamware did not become ready within \(Int(timeout)) seconds."]
            )
        )
    }

    private func waitForMapModes(
        on platform: RPSlamwarePlatformProtocol,
        mapUpdate expectedMapUpdate: Bool,
        mapLocalization expectedMapLocalization: Bool,
        timeout: TimeInterval = 5
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var actualMapUpdate = !expectedMapUpdate
        var actualMapLocalization = !expectedMapLocalization

        repeat {
            try performSDKOperation(named: "Read SLAM mode state") {
                actualMapUpdate = platform.mapUpdate()
                actualMapLocalization = platform.mapLocalization()
            }
            if actualMapUpdate == expectedMapUpdate,
               actualMapLocalization == expectedMapLocalization {
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline

        throw RPLidarControllerError.operationFailed(
            name: "Wait for SLAM mode transition",
            underlying: NSError(
                domain: "RPLidar",
                code: 6,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Expected mapUpdate=\(expectedMapUpdate), mapLocalization=\(expectedMapLocalization); device remained mapUpdate=\(actualMapUpdate), mapLocalization=\(actualMapLocalization)."
                ]
            )
        )
    }

    private func cancelActionForMapMutation(_ action: RPMoveActionProtocol, named name: String) {
        var isEmpty = false
        do {
            try performSDKOperation(named: "Inspect \(name)") {
                isEmpty = action.isEmpty()
            }
            guard !isEmpty else { return }

            try performSDKOperation(named: "Cancel \(name)") {
                action.cancel()
            }
            try performSDKOperation(named: "Wait for \(name) cancellation") {
                _ = action.waitUntilDone()
            }
        } catch {
            // The action can finish between inspection and cancellation. A
            // stale-action failure should not prevent the subsequent clear.
            print("Ignoring stale \(name) during map mutation: \(error.localizedDescription)")
        }
    }

    private func performSDKOperation(named name: String, _ operation: @escaping () -> Void) throws {
        do {
            try ExceptionCatcher.catchException(operation)
        } catch {
            throw RPLidarControllerError.operationFailed(
                name: name,
                underlying: error
            )
        }
    }
    
    /// Toggles the map update engine to update the map. Use this to switch between maps in conjuction with mapLocalization.
    func setMapUpdate(_ mapUpdate:Bool) {
        do { try ExceptionCatcher.catchException { [weak self] in self?.rpSlamwarePlatformProtocol_object?.setMapUpdate(mapUpdate) } } catch {}
    }
    /// Turns the map localization engine on/off. Use this to switch between maps in conjunction with mapUpdate.
    func setMapLocalization(_ mapLocalization: Bool) {
        do { try ExceptionCatcher.catchException { [weak self] in self?.rpSlamwarePlatformProtocol_object?.setMapLocalization(mapLocalization) } } catch {}
    }
    
    /// Returns an array of available map types from Slamware
    var availableMaps: [NSNumber]? {
        var maps: [NSNumber]? = nil
        do { try ExceptionCatcher.catchException { [weak self] in maps = self?.rpSlamwarePlatformProtocol_object?.availableMaps() as? [NSNumber] } } catch {}
        return maps
    }
    /// Returns RPLidar pose of the robot, location and rotation
    var pose: RPPose? {
        var p: RPPose? = nil
        do { try ExceptionCatcher.catchException { [weak self] in p = self?.rpSlamwarePlatformProtocol_object?.pose() } } catch {}
        return p
    }
    
    func getPose() throws -> RPPose? {
        do {
            try ExceptionCatcher.catchException {
                // Simulate an Objective-C exception
                self.currentPose = self.rpSlamwarePlatformProtocol_object?.pose()
            }
        } catch {
            print("Caught Objective-C exception currentPose: \(error.localizedDescription)")
            throw NSError(domain: "RPLidar", code: 1, userInfo: [NSLocalizedDescriptionKey: "Operation failed due to get currentPose"])
        }
        return currentPose
    }
    /// Returns localization quality of the RPLidar. 0 the highest quality
    var localiationQuality: Int32? {
        var q: Int32 = 0
        do { try ExceptionCatcher.catchException { [weak self] in q = self?.rpSlamwarePlatformProtocol_object?.localizationQuality() ?? 0 } } catch {}
        return q
    }
    /// Returns the current location of the RPLidar
    var location: RPLocation? {
        var l: RPLocation? = nil
        do { try ExceptionCatcher.catchException { [weak self] in l = self?.rpSlamwarePlatformProtocol_object?.location() } } catch {}
        return l
    }
    
    func getLocation() throws -> RPLocation? {
        do {
            try ExceptionCatcher.catchException {
                // Simulate an Objective-C exception
                self.currentLocation = self.rpSlamwarePlatformProtocol_object?.location()
            }
        } catch {
            print("Caught Objective-C exception currentLocation: \(error.localizedDescription)")
            throw NSError(domain: "RPLidar", code: 1, userInfo: [NSLocalizedDescriptionKey: "Operation failed due to get currentLocation"])
        }
        return currentLocation
    }
    
    func performRiskyOperation() throws {
        // Assume this is an Objective-C method that can throw an NSException
        // For demonstration, we'll simulate it.
        
        do {
            try ExceptionCatcher.catchException {
                // Simulate an Objective-C exception
                NSException(name: NSExceptionName("SimulatedException"), reason: "Something went wrong in ObjC", userInfo: nil).raise()
            }
        } catch {
            print("Caught Objective-C exception as Swift Error: \(error.localizedDescription)")
            throw NSError(domain: "YourAppDomain", code: 1, userInfo: [NSLocalizedDescriptionKey: "Operation failed due to Objective-C exception"])
        }
    }

    /// Returns the network status of the RPLidar
    var networkStatus: [String: String]? {
        var status: [String: String]? = nil
        do {
            try ExceptionCatcher.catchException { [weak self] in
                status = self?.rpSlamwarePlatformProtocol_object?.getNetworkStatus() as? [String: String]
            }
        } catch {
            print("Caught Objective-C exception in networkStatus: \(error.localizedDescription)")
        }
        return status
    }
    /// Returns the composite map of the RPLidar
    var compositeMap: RPCompositeMap? {
        var map: RPCompositeMap? = nil
        do { try ExceptionCatcher.catchException { [weak self] in map = self?.rpSlamwarePlatformProtocol_object?.compositeMap() } } catch {}
        return map
    }
    /// Returns the status of the RPLidar
    var status: DiscoverStatus? {
        deviceManager?.getStatus(.BOTH)
    }
    
    /// Returns the RPMap of the known area
    var getMap: RPMap? {
        var map: RPMap? = nil
        do { 
            try ExceptionCatcher.catchException { [weak self] in
                if let rpKnownRect = self?.rpSlamwarePlatformProtocol_object?.getKnownArea(of: RPMapTypeBitmap8Bit, andMapKind: RPMapKindExploreMap) {
                    map = self?.rpSlamwarePlatformProtocol_object?.getMapWith(RPMapTypeBitmap8Bit, inArea: rpKnownRect, of: RPMapKindExploreMap)
                }
            } 
        } catch {}
        return map
    }
    
    func getCurrentMap() throws -> RPMap? {
        do {
            try ExceptionCatcher.catchException { [self] in
                // Simulate an Objective-C exception
                if let rpKnownRect = self.rpSlamwarePlatformProtocol_object?.getKnownArea(of: RPMapTypeBitmap8Bit, andMapKind: RPMapKindExploreMap) {
                    self.currentMap = self.rpSlamwarePlatformProtocol_object?.getMapWith(RPMapTypeBitmap8Bit, inArea: rpKnownRect, of: RPMapKindExploreMap)
                }
            }
        } catch {
            print("Caught Objective-C exception currentLocation: \(error.localizedDescription)")
            throw NSError(domain: "RPLidar", code: 1, userInfo: [NSLocalizedDescriptionKey: "Operation failed due to get currentMap"])
        }
        return currentMap
    }

    func getCompositeMap() throws -> RPCompositeMap? {
        do {
            try ExceptionCatcher.catchException { [self] in
                // Simulate an Objective-C exception
                self.currentCompositeMap = self.rpSlamwarePlatformProtocol_object?.compositeMap()
            }
        } catch {
            print("Caught Objective-C exception currentLocation: \(error.localizedDescription)")
            throw NSError(domain: "RPLidar", code: 1, userInfo: [NSLocalizedDescriptionKey: "Operation failed due to get currentCompositeMap"])
        }
        return currentCompositeMap
    }

    private func installMapForLocalization(
        _ map: RPMap,
        pose: RPPose,
        on platform: RPSlamwarePlatformProtocol
    ) throws {
        try performSDKOperation(named: "Pause map update for load") {
            platform.setMapUpdate(false)
        }
        try performSDKOperation(named: "Pause map localization for load") {
            platform.setMapLocalization(false)
        }
        try waitForMapModes(
            on: platform,
            mapUpdate: false,
            mapLocalization: false
        )
        try performSDKOperation(named: "Upload saved map") {
            platform.setMapWith(
                map,
                of: RPMapTypeBitmap8Bit,
                andMapKind: RPMapKindExploreMap
            )
        }
        try performSDKOperation(named: "Set saved map pose") {
            platform.setPose(pose)
        }
        try performSDKOperation(named: "Enable localization for loaded map") {
            platform.setMapLocalization(true)
        }
        try waitForMapModes(
            on: platform,
            mapUpdate: false,
            mapLocalization: true
        )
    }

    private func startRelocalization(
        on platform: RPSlamwarePlatformProtocol,
        in recoveryArea: RPRectangleF
    ) throws {
        var lastError: Error?

        // Mapper-only installations often cannot perform the SDK's default
        // base movement. Ask Slamware to match the current scan without
        // commanding the chassis first.
        do {
            let options = RPRecoverLocalizationOptions(
                maxReocverTime: NSNumber(value: 60_000),
                andRecoverLocalizationMovement: RPRecoverLocalizationMovementNoMove
            )
            try performSDKOperation(named: "Start stationary relocalization") {
                self.relocalizationAction = platform.recoverLocalization(
                    withCurrentArea: recoveryArea,
                    andRecoverLocalizationOptions: options
                )
            }
            if relocalizationAction != nil {
                return
            }
        } catch {
            lastError = error
            print("Stationary relocalization was rejected; trying the legacy action: \(error.localizedDescription)")
        }

        // The no-options overload is supported by older Slamware firmware and
        // is the form used in Slamtec's reference relocalization sample.
        do {
            try performSDKOperation(named: "Start legacy relocalization") {
                self.relocalizationAction = platform.recoverLocalization(recoveryArea)
            }
            if relocalizationAction != nil {
                return
            }
        } catch {
            lastError = error
        }

        // A restart or network transition can lose the response even though
        // the action was created. Adopt the device's action instead of issuing
        // a duplicate recovery request.
        do {
            var deviceAction: RPMoveActionProtocol?
            var deviceActionIsEmpty = true
            try performSDKOperation(named: "Check relocalization action") {
                deviceAction = platform.currentAction()
                deviceActionIsEmpty = deviceAction?.isEmpty() ?? true
            }
            if let deviceAction, !deviceActionIsEmpty {
                relocalizationAction = deviceAction
                return
            }
        } catch {
            lastError = error
        }

        throw RPLidarControllerError.operationFailed(
            name: "Start relocalization",
            underlying: lastError ?? NSError(
                domain: "RPLidar",
                code: 13,
                userInfo: [NSLocalizedDescriptionKey: "Slamware did not create a recovery action."]
            )
        )
    }
    
    /// Installs a saved map and seed pose, then starts Slamware's actual
    /// relocalization action. Map update deliberately remains off: Slamware
    /// uses that mode for localization against a known map, and it prevents a
    /// bad provisional pose from corrupting the map while recovery runs.
    func loadMapAndRecoverLocalization(_ map: RPMap, pose: RPPose) throws {
        guard let platform = rpSlamwarePlatformProtocol_object else {
            throw RPLidarControllerError.notConnected
        }

        let areaWidth = Float(map.dimension.width) * map.resolution.x
        let areaHeight = Float(map.dimension.height) * map.resolution.y
        guard areaWidth.isFinite,
              areaHeight.isFinite,
              areaWidth > 0,
              areaHeight > 0,
              map.origin.x.isFinite,
              map.origin.y.isFinite else {
            throw RPLidarControllerError.operationFailed(
                name: "Load map",
                underlying: NSError(
                    domain: "RPLidar",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "The saved map area is invalid."]
                )
            )
        }
        // In this generation of the Slamware SDK an empty rectangle means the
        // whole map. Passing the bitmap's exact bounds is rejected by some
        // Mapper firmware even though the map itself uploads successfully.
        let recoveryArea = RPRectangleF()

        if let action = relocalizationAction {
            cancelActionForMapMutation(action, named: "relocalization")
            relocalizationAction = nil
        }

        var deviceAction: RPMoveActionProtocol?
        do {
            try performSDKOperation(named: "Read current device action") {
                deviceAction = platform.currentAction()
            }
        } catch {
            print("Unable to inspect current action before map load: \(error.localizedDescription)")
        }
        if let deviceAction {
            cancelActionForMapMutation(deviceAction, named: "current device action")
        }

        try installMapForLocalization(map, pose: pose, on: platform)

        do {
            try startRelocalization(on: platform, in: recoveryArea)
        } catch {
            // Use the reset-map lesson as a last resort: a soft service restart
            // clears a wedged action state. The restart also clears the map, so
            // reconnect first and then install the saved map again before
            // retrying relocalization.
            print("Relocalization action failed; restarting SLAM services and retrying: \(error.localizedDescription)")
            let restartedPlatform = try restartSlamwareForMapReset(on: platform)
            try installMapForLocalization(map, pose: pose, on: restartedPlatform)
            try startRelocalization(on: restartedPlatform, in: recoveryArea)
        }

        guard relocalizationAction != nil else {
            throw RPLidarControllerError.operationFailed(
                name: "Start relocalization",
                underlying: NSError(
                    domain: "RPLidar",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Slamware did not create a recovery action."]
                )
            )
        }

        currentMap = map
        currentPose = pose
    }

    func relocalizationState() throws -> RPLidarRelocalizationState {
        guard let action = relocalizationAction else { return .idle }

        var actionStatus = RPActionStatusWaitingForStart
        var progress = 0.0
        do {
            try ExceptionCatcher.catchException {
                actionStatus = action.status()
                progress = action.progress()
            }
        } catch {
            throw RPLidarControllerError.operationFailed(
                name: "Read relocalization status",
                underlying: error
            )
        }

        switch actionStatus {
        case RPActionStatusWaitingForStart:
            return .waiting(progress: progress)
        case RPActionStatusRunning, RPActionStatusPaused:
            return .running(progress: progress)
        case RPActionStatusFinished:
            relocalizationAction = nil
            return .finished
        case RPActionStatusStopped:
            relocalizationAction = nil
            return .stopped
        case RPActionStatusError:
            relocalizationAction = nil
            return .failed
        default:
            return .running(progress: progress)
        }
    }
    
    /// RPLaserPoint Array returned
    var laserPoints: [RPLaserPoint]? {
        var points: [RPLaserPoint]? = nil
        do {
            try ExceptionCatcher.catchException { [weak self] in
                points = self?.rpSlamwarePlatformProtocol_object?.laserScan().laserPoints
            }
        } catch {}
        return points
    }
    
    func getLaserPoints() throws -> [RPLaserPoint]? {
        try getLaserScan()?.laserPoints
    }

    /// Returns the points together with the pose captured for that scan. Using
    /// this pose avoids rotating/translating fresh hits with a different pose
    /// fetched in a separate network request.
    func getLaserScan() throws -> RPLaserScan? {
        do {
            try ExceptionCatcher.catchException {
                let scan = self.rpSlamwarePlatformProtocol_object?.laserScan()
                self.currentLaserScan = scan
                self.currentLaserPoints = scan?.laserPoints
            }
        } catch {
            print("Caught Objective-C exception currentLaserScan: \(error.localizedDescription)")
            throw NSError(domain: "RPLidar", code: 1, userInfo: [NSLocalizedDescriptionKey: "Operation failed due to get currentLaserScan"])
        }
        return currentLaserScan
    }
}

extension RPLidarController: RPDiscoveryDelegate {
    func onStartDiscovery(_ discover: RPAbstractDiscover!) {
        print("onStartDiscovery \(String(describing: discover))")
    }
    
    func onStopDiscovery(_ discover: RPAbstractDiscover!) {
        print("onStopDiscovery \(String(describing: discover))")
    }
    
    func onDiscoveryStatusChanged(_ discover: RPAbstractDiscover!, with status: DiscoverStatus, withError error: String!) {
        print("onDiscoveryStatusChanged \(String(describing: discover))\n status = \(status)\n error = \(String(describing: error))")
    }
    
    func onDeviceFound(_ discover: RPAbstractDiscover!, with device: RPAbstractDevice!) {
        
        print("onDeviceFound \(String(describing: discover))\ndevice \(String(describing: device))")
    }
    
    
}
