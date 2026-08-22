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
    /// Unlike map upload, Slamware documents clearMap as a direct operation;
    /// disabling mapping/localization first can produce OperationFailException
    /// on some firmware versions.
    func resetMap() throws {
        guard let platform = rpSlamwarePlatformProtocol_object else {
            throw RPLidarControllerError.notConnected
        }

        if let action = relocalizationAction {
            do {
                try performSDKOperation(named: "Cancel relocalization") {
                    action.cancel()
                }
                try performSDKOperation(named: "Wait for relocalization cancellation") {
                    _ = action.waitUntilDone()
                }
            } catch {
                // A recovery action can finish between the status poll and
                // cancel call. That stale-action failure must not block reset.
                print("Ignoring relocalization cancellation during reset: \(error.localizedDescription)")
            }
            relocalizationAction = nil
        }

        try performSDKOperation(named: "Clear map") {
            platform.clearMap()
        }
        currentMap = nil
        currentCompositeMap = nil

        try performSDKOperation(named: "Enable map update") {
            platform.setMapUpdate(true)
        }
        try performSDKOperation(named: "Enable map localization") {
            platform.setMapLocalization(true)
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
              let areaOrigin = RPPointF(x: map.origin.x, andY: map.origin.y),
              let areaSize = RPSizeF(
                width: areaWidth,
                andHeight: areaHeight
              ) else {
            throw RPLidarControllerError.operationFailed(
                name: "Load map",
                underlying: NSError(
                    domain: "RPLidar",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "The saved map area is invalid."]
                )
            )
        }
        let recoveryArea = RPRectangleF(origin: areaOrigin, andSize: areaSize)

        do {
            try ExceptionCatcher.catchException {
                self.relocalizationAction?.cancel()
                self.relocalizationAction = nil
                platform.setMapUpdate(false)
                platform.setMapLocalization(false)
                platform.setMapWith(
                    map,
                    of: RPMapTypeBitmap8Bit,
                    andMapKind: RPMapKindExploreMap
                )
                platform.setPose(pose)
                platform.setMapLocalization(true)
                self.relocalizationAction = platform.recoverLocalization(recoveryArea)
            }
        } catch {
            // Leave update disabled after a failed load so an uncertain pose
            // cannot modify the map. A reset explicitly restores mapping mode.
            throw RPLidarControllerError.operationFailed(
                name: "Load map and relocalize",
                underlying: error
            )
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
