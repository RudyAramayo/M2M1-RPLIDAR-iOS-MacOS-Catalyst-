import Foundation
import Network
import Security

enum FixtureFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

@main
struct ROBLidarTelemetryProtocolFixtureTests {
    static func main() throws {
        try credentialRoleFixtures()
        try certificateMigrationFixtures()
        try telemetryFixtures()
        try sequenceFixtures()
        try localIPCFixtures()
        try transportRouteFixtures()
        guard DataMessageType.lidarTelemetry.rawValue == 7 else {
            throw FixtureFailure.failed("Lidar telemetry did not retain frame kind 7")
        }
        print("RPLidar v2 role and telemetry fixtures passed")
    }

    private static func credentialRoleFixtures() throws {
        let lidarCredential = credential(role: .lidarPublisher)
        try ROBControlPairing.validatePublisherCredential(lidarCredential)

        do {
            try ROBControlPairing.validatePublisherCredential(
                credential(role: .operatorController)
            )
            throw FixtureFailure.failed("RPLidar accepted an operator-controller credential")
        } catch AutoNetTransportError.roleMismatch(let expected, let actual) {
            guard expected == .lidarPublisher, actual == .operatorController else {
                throw FixtureFailure.failed("Credential role mismatch reported the wrong roles")
            }
        }

        do {
            try ROBControlPairing.validatePublisherCredential(credential(role: nil))
            throw FixtureFailure.failed("RPLidar accepted a legacy credential without a role")
        } catch AutoNetTransportError.roleMismatch {
            // Missing roles intentionally decode as legacy operator authority.
        }

        let encoded = try JSONEncoder().encode(lidarCredential)
        let decoded = try JSONDecoder().decode(ROBControlCredential.self, from: encoded)
        guard decoded == lidarCredential,
              decoded.role == .lidarPublisher,
              decoded.deviceName == "Fixture RPLidar" else {
            throw FixtureFailure.failed("Role-scoped credential did not round-trip")
        }

        let controlCharacterName = credential(
            role: .lidarPublisher,
            deviceName: "Fixture\nRPLidar"
        )
        guard !controlCharacterName.isValid else {
            throw FixtureFailure.failed("Credential accepted control characters in deviceName")
        }
    }

    private static func certificateMigrationFixtures() throws {
        let robotID = UUID(uuidString: "b3d5723a-f350-41aa-80b9-f26af02dc7a1")!
        let controllerID = UUID(uuidString: "a09fd941-ac67-420b-97e3-64aed9d90cdb")!
        let replacementFingerprint = Data((0..<32).map(UInt8.init))
        let replacementSecret = Data((32..<64).map(UInt8.init))
        let payload: [String: Any] = [
            "version": 2,
            "robotID": robotID.uuidString,
            "controllerID": controllerID.uuidString,
            "serviceType": ROBControlPairing.serviceType,
            "applicationProtocol": ROBControlPairing.applicationProtocol,
            "certificateSHA256": replacementFingerprint.base64EncodedString(),
            "sharedSecret": replacementSecret.base64EncodedString(),
            "role": ROBControlPeerRole.lidarPublisher.rawValue,
            "deviceName": "Migration Fixture RPLidar",
            "issuedAtMilliseconds": 2_000_000,
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let replacementCode = "ROBCTL2:\(payloadData.base64EncodedString())"
        let decoded = try ROBControlPairing.decodePairingCode(replacementCode)
        guard decoded.robotID == robotID,
              decoded.controllerID == controllerID,
              decoded.certificateSHA256 == replacementFingerprint,
              decoded.sharedSecret == replacementSecret,
              decoded.effectiveRole == .lidarPublisher else {
            throw FixtureFailure.failed("Fresh Cerebro replacement code did not decode")
        }

        let stored = credential(role: .lidarPublisher)
        let storedBootstrap = try ROBControlPairing.environmentBootstrapCredential(
            storedCredential: stored,
            environmentCode: replacementCode,
            bootstrapAllowed: true
        )
        guard storedBootstrap == nil else {
            throw FixtureFailure.failed("Environment code overrode the Keychain credential")
        }

        let bootstrapped = try ROBControlPairing.environmentBootstrapCredential(
            storedCredential: nil,
            environmentCode: replacementCode,
            bootstrapAllowed: true
        )
        guard bootstrapped == decoded else {
            throw FixtureFailure.failed("One-time environment bootstrap did not select its credential")
        }

        let disabledBootstrap = try ROBControlPairing.environmentBootstrapCredential(
            storedCredential: nil,
            environmentCode: replacementCode,
            bootstrapAllowed: false
        )
        guard disabledBootstrap == nil else {
            throw FixtureFailure.failed("Explicit Pair or Forget did not disable environment bootstrap")
        }

        guard ROBControlPairing.requiresPairingReplacement(
                after: AutoNetTransportError.credentialRejected
              ),
              ROBControlPairing.requiresPairingReplacement(
                after: NWError.tls(errSSLPeerHandshakeFail)
              ),
              !ROBControlPairing.requiresPairingReplacement(
                after: AutoNetTransportError.pairingRequired
              ) else {
            throw FixtureFailure.failed("Certificate or credential rejection was not classified")
        }
    }

    private static func telemetryFixtures() throws {
        let deviceID = UUID()
        let now: UInt64 = 2_000_000
        let points = (0..<8).map {
            ROBLidarWirePoint(
                distanceMeters: 0.4 + Float($0) * 0.01,
                angleRadians: -0.4 + Float($0) * 0.1
            )
        }
        let scan = ROBLidarScanFrame(
            deviceID: deviceID,
            sequence: 41,
            sentAtMilliseconds: now,
            x: 1.25,
            y: -0.75,
            z: 0.1,
            yaw: 0.2,
            pitch: -0.1,
            roll: 0.05,
            points: points
        )
        guard scan.validationError(
            authenticatedDeviceID: deviceID,
            lastAcceptedSequence: 40,
            nowMilliseconds: now
        ) == nil else {
            throw FixtureFailure.failed("Valid scan failed validation")
        }
        let encodedScan = try scan.encoded()
        let decodedScan = try ROBLidarScanFrame.decode(encodedScan)
        guard encodedScan.count == ROBLidarScanFrame.headerLength
                + points.count * ROBLidarScanFrame.pointStride,
              Data(encodedScan.prefix(4)) == Data([0x52, 0x4C, 0x53, 0x31]),
              decodedScan.deviceID == deviceID,
              decodedScan.sequence == 41,
              decodedScan.x == scan.x,
              decodedScan.y == scan.y,
              decodedScan.points.count == points.count,
              zip(decodedScan.points, points).allSatisfy({ decoded, original in
                  abs(decoded.distanceMeters - original.distanceMeters) <= 0.0006
                      && abs(decoded.angleRadians - original.angleRadians) <= 0.0001
              }) else {
            throw FixtureFailure.failed("Scan telemetry did not round-trip")
        }
        guard scan.validationError(
                authenticatedDeviceID: UUID(),
                lastAcceptedSequence: 40,
                nowMilliseconds: now
              ) == "device ID does not match authenticated peer",
              scan.validationError(
                authenticatedDeviceID: deviceID,
                lastAcceptedSequence: 41,
                nowMilliseconds: now
              ) == "sequence is missing or not increasing",
              scan.validationError(
                authenticatedDeviceID: deviceID,
                lastAcceptedSequence: 40,
                nowMilliseconds: now + 2_001
              ) == "telemetry is stale",
              scan.validationError(
                authenticatedDeviceID: deviceID,
                lastAcceptedSequence: 40,
                nowMilliseconds: now - 5_001
              ) == "timestamp is too far in the future" else {
            throw FixtureFailure.failed("Scan identity, sequence, or freshness checks failed")
        }

        let tooFewPoints = ROBLidarScanFrame(
            deviceID: deviceID,
            sequence: 42,
            sentAtMilliseconds: now,
            x: 0,
            y: 0,
            z: 0,
            yaw: 0,
            pitch: 0,
            roll: 0,
            points: Array(points.prefix(7))
        )
        guard tooFewPoints.validationError(
            authenticatedDeviceID: deviceID,
            lastAcceptedSequence: 41,
            nowMilliseconds: now
        ) == "point count is outside the supported range" else {
            throw FixtureFailure.failed("Undersized scan was accepted")
        }

        var unsupportedHeader = encodedScan
        unsupportedHeader[5] = 1
        do {
            _ = try ROBLidarScanFrame.decode(unsupportedHeader)
            throw FixtureFailure.failed("Unsupported binary scan flags were accepted")
        } catch ROBLidarTelemetryEncodingError.invalid {
            // Expected: reserved header flags are strict for version 1.
        }
        do {
            _ = try ROBLidarScanFrame.decode(encodedScan + Data([0]))
            throw FixtureFailure.failed("Binary scan with trailing data was accepted")
        } catch ROBLidarTelemetryEncodingError.invalid {
            // Expected: the payload size must exactly match the point count.
        }
        do {
            _ = try ROBLidarScanFrame.decode(Data("{\"kind\":\"scan\"}".utf8))
            throw FixtureFailure.failed("Removed JSON telemetry schema was still accepted")
        } catch {
            // Expected: no compatibility decoder exists.
        }
    }

    private static func sequenceFixtures() throws {
        let suiteName = "ROBLidarTelemetryProtocolFixtureTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw FixtureFailure.failed("Could not create isolated UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let deviceID = UUID()
        let firstStore = ROBLidarTelemetrySequenceStore(defaults: defaults)
        guard firstStore.next(deviceID: deviceID) == 1,
              firstStore.next(deviceID: deviceID) == 2 else {
            throw FixtureFailure.failed("Telemetry sequence was not increasing")
        }
        let prior = firstStore.next(deviceID: deviceID)!
        let reloadedStore = ROBLidarTelemetrySequenceStore(defaults: defaults)
        guard let reloaded = reloadedStore.next(deviceID: deviceID), reloaded > prior else {
            throw FixtureFailure.failed("Telemetry sequence high-watermark did not persist")
        }
    }

    private static func localIPCFixtures() throws {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let socketURL = URL(fileURLWithPath: "/tmp/rob-lidar-\(suffix).sock")
        let unavailableURL = URL(fileURLWithPath: "/tmp/rob-lidar-missing-\(suffix).sock")
        defer {
            try? FileManager.default.removeItem(at: socketURL)
            try? FileManager.default.removeItem(at: unavailableURL)
        }

        let serverReady = DispatchSemaphore(value: 0)
        let clientReady = DispatchSemaphore(value: 0)
        let scanReceived = DispatchSemaphore(value: 0)
        let receivedLock = NSLock()
        var receivedData: Data?
        let server = ROBLidarLocalIPCServer(
            socketURL: socketURL,
            stateDidChange: { ready in
                if ready { serverReady.signal() }
            },
            receiveScan: { data in
                receivedLock.lock()
                receivedData = data
                receivedLock.unlock()
                scanReceived.signal()
            }
        )
        let client = ROBLidarLocalIPCClient(
            socketURL: socketURL,
            stateDidChange: { ready in
                if ready { clientReady.signal() }
            }
        )
        defer {
            client.stop()
            server.stop()
        }

        server.start()
        guard serverReady.wait(timeout: .now() + 3) == .success else {
            throw FixtureFailure.failed("Local IPC server did not become ready")
        }
        client.start()
        guard clientReady.wait(timeout: .now() + 3) == .success else {
            throw FixtureFailure.failed("Local IPC client did not become ready")
        }

        let scan = ROBLidarScanFrame(
            deviceID: UUID(),
            sequence: 1,
            sentAtMilliseconds: UInt64(Date().timeIntervalSince1970 * 1_000),
            x: 0,
            y: 0,
            z: 0,
            yaw: 0,
            pitch: 0,
            roll: 0,
            points: (0..<ROBLidarScanFrame.minimumPointCount).map { index in
                ROBLidarWirePoint(
                    distanceMeters: 0.5 + Float(index) * 0.01,
                    angleRadians: Float(index) * 0.1
                )
            }
        )
        let encoded = try scan.encoded()
        let sharedSecret = Data(repeating: 0xA5, count: 32)
        guard let envelope = ROBLidarLocalIPCEnvelope.seal(
            scanData: encoded,
            sharedSecret: sharedSecret
        ) else {
            throw FixtureFailure.failed("Local IPC could not authenticate a valid scan")
        }
        guard envelope.count == encoded.count + ROBLidarLocalIPCEnvelope.authenticationCodeLength,
              ROBLidarLocalIPCEnvelope.open(
                envelope,
                sharedSecret: sharedSecret
              ) == encoded else {
            throw FixtureFailure.failed("Local IPC authenticated envelope did not round-trip")
        }
        var tamperedEnvelope = envelope
        tamperedEnvelope[tamperedEnvelope.startIndex] ^= 0x01
        guard ROBLidarLocalIPCEnvelope.open(
            tamperedEnvelope,
            sharedSecret: sharedSecret
        ) == nil else {
            throw FixtureFailure.failed("Local IPC accepted a tampered scan")
        }
        guard client.sendLatestIfReady(envelope) else {
            throw FixtureFailure.failed("Ready local IPC client rejected a scan")
        }
        guard scanReceived.wait(timeout: .now() + 3) == .success else {
            throw FixtureFailure.failed("Local IPC scan did not reach the server")
        }
        receivedLock.lock()
        let delivered = receivedData
        receivedLock.unlock()
        guard delivered == envelope else {
            throw FixtureFailure.failed("Local IPC changed the authenticated scan envelope")
        }

        let unavailableClient = ROBLidarLocalIPCClient(socketURL: unavailableURL)
        unavailableClient.start()
        guard !unavailableClient.sendLatestIfReady(envelope) else {
            unavailableClient.stop()
            throw FixtureFailure.failed("Unavailable local IPC path suppressed network fallback")
        }
        unavailableClient.stop()
    }

    private static func transportRouteFixtures() throws {
        guard ROBLidarTelemetryTransportRoute.resolve(
                publishingEnabled: true,
                localIPCReady: true,
                quicReady: true
              ) == .localIPC,
              ROBLidarTelemetryTransportRoute.resolve(
                publishingEnabled: true,
                localIPCReady: false,
                quicReady: true
              ) == .quicFallback,
              ROBLidarTelemetryTransportRoute.resolve(
                publishingEnabled: true,
                localIPCReady: false,
                quicReady: false
              ) == .disconnected,
              ROBLidarTelemetryTransportRoute.resolve(
                publishingEnabled: false,
                localIPCReady: true,
                quicReady: true
              ) == .publishingDisabled else {
            throw FixtureFailure.failed("Telemetry transport route precedence changed")
        }
    }

    private static func credential(
        role: ROBControlPeerRole?,
        deviceName: String = "Fixture RPLidar"
    ) -> ROBControlCredential {
        ROBControlCredential(
            version: 2,
            robotID: UUID(),
            controllerID: UUID(),
            serviceType: ROBControlPairing.serviceType,
            applicationProtocol: ROBControlPairing.applicationProtocol,
            certificateSHA256: Data(repeating: 0x11, count: 32),
            sharedSecret: Data(repeating: 0x22, count: 32),
            role: role,
            deviceName: deviceName,
            issuedAtMilliseconds: 1_999_000
        )
    }
}
