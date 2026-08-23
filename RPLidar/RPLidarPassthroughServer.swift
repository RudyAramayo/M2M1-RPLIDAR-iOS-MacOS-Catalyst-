//
//  RPLidarPassthroughServer.swift
//  RPLidar
//
//  Owns the hardware and authenticated Cerebro telemetry path independently
//  of UIKit so production launches can run without constructing the map UI.
//

import Foundation
import SlamwareSDK

struct RPLidarScanSnapshot {
    let location: RPLocation?
    let pose: RPPose?
    let laserPoints: [RPLidarScanPoint]
}

struct RPLidarMapSnapshot {
    let map: RPMap
    let compositeMap: RPCompositeMap?
}

protocol RPLidarPassthroughServerDelegate: AnyObject {
    func passthroughServer(
        _ server: RPLidarPassthroughServer,
        didReceive scan: RPLidarScanSnapshot
    )

    func passthroughServer(
        _ server: RPLidarPassthroughServer,
        didReceive map: RPLidarMapSnapshot
    )
}

final class RPLidarPassthroughServer {
    static let shared = RPLidarPassthroughServer()

    static let lidarPulseFrequency: TimeInterval = 0.20
    static let mapPulseFrequency: TimeInterval = 5.0
    static let mapLocalStorageFrequency: TimeInterval = 30.0

    let operationQueue = DispatchQueue(label: "com.orbitusrobotics.rplidar.passthrough")
    let autoNetClient = AutoNetClient(service: AutoNetClient.defaultService)
    private lazy var localIPCClient = ROBLidarLocalIPCClient(
        deliveryDidFail: { [weak self] envelope in
            guard let scanData = ROBLidarLocalIPCEnvelope.scanData(from: envelope) else { return }
            self?.autoNetClient.publishLidarTelemetry(scanData)
        }
    )

    weak var delegate: RPLidarPassthroughServerDelegate? {
        didSet { deliverLatestSnapshots() }
    }

    private(set) var lidar: RPLidarController?

    private let stateLock = NSLock()
    private let telemetrySequenceStore = ROBLidarTelemetrySequenceStore.shared
    private var timers: [DispatchSourceTimer] = []
    private var started = false
    private var isReconnecting = false
    private var reconnectScheduled = false
    private var publisherDeviceID: UUID?
    private var localIPCSharedSecret: Data?
    private var latestScan: RPLidarScanSnapshot?
    private var latestMap: RPLidarMapSnapshot?
    private var latestPose: RPPose?

    private init() {}

    func start() {
        stateLock.lock()
        guard !started else {
            stateLock.unlock()
            return
        }
        started = true
        stateLock.unlock()

        localIPCClient.start()
        autoNetClient.start()
        refreshPublisherIdentity()
        installTimers()
        operationQueue.async { [weak self] in
            self?.reconnectLocked()
        }
        print("RPLidar passthrough server started")
    }

    func stop() {
        stateLock.lock()
        guard started else {
            stateLock.unlock()
            return
        }
        started = false
        let activeTimers = timers
        timers.removeAll()
        stateLock.unlock()

        activeTimers.forEach { $0.cancel() }
        localIPCClient.stop()
        autoNetClient.stop()
        operationQueue.async { [weak self] in
            self?.lidar = nil
            self?.latestScan = nil
            self?.latestMap = nil
            self?.latestPose = nil
        }
    }

    func refreshPublisherIdentity() {
        let credential = try? ROBControlPairing.clientAuthenticationMaterial()
        operationQueue.async { [weak self] in
            self?.publisherDeviceID = credential?.controllerID
            self?.localIPCSharedSecret = credential?.sharedSecret
        }
    }

    func requestReconnect() {
        operationQueue.async { [weak self] in
            guard let self else { return }
            self.lidar = nil
            self.reconnectLocked()
        }
    }

    func requestMapRefresh() {
        operationQueue.async { [weak self] in
            self?.mapPulseLocked()
        }
    }

    /// Must be called from operationQueue after the hardware map is reset so
    /// a newly attached GUI or storage pulse cannot observe the old map.
    func invalidateSnapshotsAfterMapReset() {
        dispatchPrecondition(condition: .onQueue(operationQueue))
        latestScan = nil
        latestMap = nil
        latestPose = nil
    }

    func detach(_ candidate: RPLidarPassthroughServerDelegate) {
        if delegate === candidate {
            delegate = nil
        }
    }

    private var isStarted: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return started
    }

    private func installTimers() {
        let scanTimer = DispatchSource.makeTimerSource(queue: operationQueue)
        scanTimer.schedule(
            deadline: .now() + 1,
            repeating: Self.lidarPulseFrequency,
            leeway: .milliseconds(25)
        )
        scanTimer.setEventHandler { [weak self] in
            self?.lidarPulseLocked()
        }

        let mapTimer = DispatchSource.makeTimerSource(queue: operationQueue)
        mapTimer.schedule(
            deadline: .now() + 2,
            repeating: Self.mapPulseFrequency,
            leeway: .milliseconds(150)
        )
        mapTimer.setEventHandler { [weak self] in
            self?.mapPulseLocked()
        }

        let storageTimer = DispatchSource.makeTimerSource(queue: operationQueue)
        storageTimer.schedule(
            deadline: .now() + Self.mapLocalStorageFrequency,
            repeating: Self.mapLocalStorageFrequency,
            leeway: .seconds(1)
        )
        storageTimer.setEventHandler { [weak self] in
            self?.storeLatestMapLocked()
        }

        stateLock.lock()
        timers = [scanTimer, mapTimer, storageTimer]
        stateLock.unlock()
        scanTimer.resume()
        mapTimer.resume()
        storageTimer.resume()
    }

    private func reconnectLocked() {
        dispatchPrecondition(condition: .onQueue(operationQueue))
        guard isStarted, !isReconnecting else { return }
        if lidar != nil { return }

        isReconnecting = true
        reconnectScheduled = false
        defer { isReconnecting = false }

        var connectedLidar: RPLidarController?
        do {
            try ExceptionCatcher.catchException {
                connectedLidar = RPLidarController(ip: "192.168.11.1")
            }
        } catch {
            print("RPLidar connection failed: \(error.localizedDescription)")
        }

        guard let connectedLidar else {
            scheduleReconnectLocked()
            return
        }
        lidar = connectedLidar
        print("RPLidar passthrough connected to 192.168.11.1:1445")
    }

    private func scheduleReconnectLocked() {
        dispatchPrecondition(condition: .onQueue(operationQueue))
        guard isStarted, !reconnectScheduled else { return }
        reconnectScheduled = true
        operationQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.reconnectScheduled = false
            self.reconnectLocked()
        }
    }

    private func lidarPulseLocked() {
        dispatchPrecondition(condition: .onQueue(operationQueue))
        guard isStarted else { return }
        guard let lidar else {
            reconnectLocked()
            return
        }

        do {
            guard let scan = try lidar.getLaserScan() else { return }
            let pose: RPPose?
            if let scanPose = scan.pose {
                pose = scanPose
            } else {
                pose = try lidar.getPose()
            }
            let location: RPLocation?
            if let poseLocation = pose?.location {
                location = poseLocation
            } else {
                location = try lidar.getLocation()
            }
            latestPose = pose

            var renderedPoints: [RPLidarScanPoint] = []
            var wirePoints: [ROBLidarWirePoint] = []
            renderedPoints.reserveCapacity(scan.laserPoints.count)
            wirePoints.reserveCapacity(scan.laserPoints.count)
            for laserPoint in scan.laserPoints where laserPoint.valid {
                renderedPoints.append(
                    RPLidarScanPoint(
                        distance: CGFloat(laserPoint.distance),
                        angle: CGFloat(laserPoint.angle)
                    )
                )
                wirePoints.append(
                    ROBLidarWirePoint(
                        distanceMeters: Float(laserPoint.distance),
                        angleRadians: Float(laserPoint.angle)
                    )
                )
            }

            let snapshot = RPLidarScanSnapshot(
                location: location,
                pose: pose,
                laserPoints: renderedPoints
            )
            latestScan = snapshot
            publishScanLocked(location: location, pose: pose, points: wirePoints)
            deliver(scan: snapshot)
        } catch {
            print("RPLidar scan passthrough failed: \(error.localizedDescription)")
            self.lidar = nil
            scheduleReconnectLocked()
        }
    }

    private func mapPulseLocked() {
        dispatchPrecondition(condition: .onQueue(operationQueue))
        guard isStarted else { return }
        guard let lidar else {
            reconnectLocked()
            return
        }

        do {
            let compositeMap = try? lidar.getCompositeMap()
            guard let map = try lidar.getCurrentMap() else { return }
            let snapshot = RPLidarMapSnapshot(map: map, compositeMap: compositeMap ?? nil)
            latestMap = snapshot
            deliver(map: snapshot)
        } catch {
            print("RPLidar map passthrough failed: \(error.localizedDescription)")
            self.lidar = nil
            scheduleReconnectLocked()
        }
    }

    private func publishScanLocked(
        location: RPLocation?,
        pose: RPPose?,
        points: [ROBLidarWirePoint]
    ) {
        guard let deviceID = publisherDeviceID,
              let sequence = telemetrySequenceStore.next(deviceID: deviceID) else {
            return
        }
        let frame = ROBLidarScanFrame(
            deviceID: deviceID,
            sequence: sequence,
            sentAtMilliseconds: Self.currentMilliseconds(),
            x: Float(location?.x ?? 0),
            y: Float(location?.y ?? 0),
            z: Float(location?.z ?? 0),
            yaw: Float(pose?.yaw() ?? 0),
            pitch: Float(pose?.pitch() ?? 0),
            roll: Float(pose?.roll() ?? 0),
            points: points
        )
        do {
            let data = try frame.encoded()
            if let localIPCSharedSecret,
               let envelope = ROBLidarLocalIPCEnvelope.seal(
                   scanData: data,
                   sharedSecret: localIPCSharedSecret
               ),
               localIPCClient.sendLatestIfReady(envelope) {
                return
            } else {
                autoNetClient.publishLidarTelemetry(data)
            }
        } catch {
            print("RPLidar scan was not published: \(error.localizedDescription)")
        }
    }

    private func storeLatestMapLocked() {
        dispatchPrecondition(condition: .onQueue(operationQueue))
        guard isStarted else { return }
        guard let map = latestMap?.map,
              let pose = latestPose ?? (try? lidar?.getPose()),
              let lidar else {
            return
        }
        let locationName: String
        if let networkStatus = lidar.networkStatus,
           let ssid = networkStatus["ssid"],
           !ssid.isEmpty {
            locationName = ssid
        } else {
            locationName = "HOME"
        }
        do {
            let data = try ROBOMap(map: map, pose: pose).encoded()
            RPAppKitController.shared.writeMapToFile(location: locationName, data: data)
        } catch {
            print("RPLidar automatic map storage failed: \(error.localizedDescription)")
        }
    }

    private func deliver(scan: RPLidarScanSnapshot) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.passthroughServer(self, didReceive: scan)
        }
    }

    private func deliver(map: RPLidarMapSnapshot) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.passthroughServer(self, didReceive: map)
        }
    }

    private func deliverLatestSnapshots() {
        operationQueue.async { [weak self] in
            guard let self else { return }
            if let latestScan = self.latestScan {
                self.deliver(scan: latestScan)
            }
            if let latestMap = self.latestMap {
                self.deliver(map: latestMap)
            }
        }
    }

    private static func currentMilliseconds() -> UInt64 {
        UInt64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
    }
}
