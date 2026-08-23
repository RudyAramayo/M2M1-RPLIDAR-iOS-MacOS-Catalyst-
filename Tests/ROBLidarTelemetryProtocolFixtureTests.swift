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
        let scan = ROBLidarTelemetryMessage.scan(
            deviceID: deviceID,
            sequence: 41,
            sentAtMilliseconds: now,
            payload: "0:0:0\n0:0:0\n0.25:0.1\n"
        )
        guard scan.validationError(
            authenticatedDeviceID: deviceID,
            lastAcceptedSequence: 40,
            nowMilliseconds: now
        ) == nil else {
            throw FixtureFailure.failed("Valid scan failed validation")
        }
        let decodedScan = try ROBLidarTelemetryMessage.decode(scan.encoded())
        guard decodedScan.schemaVersion == 1,
              decodedScan.networkProbeVersion == 1,
              decodedScan.kind == .scan,
              decodedScan.deviceID == deviceID,
              decodedScan.sequence == 41,
              decodedScan.scanPayload == scan.scanPayload,
              decodedScan.mapData == nil else {
            throw FixtureFailure.failed("Scan telemetry did not round-trip")
        }
        var legacyObject = try JSONSerialization.jsonObject(with: scan.encoded()) as! [String: Any]
        legacyObject.removeValue(forKey: "networkProbeVersion")
        let legacyScan = try ROBLidarTelemetryMessage.decode(
            JSONSerialization.data(withJSONObject: legacyObject)
        )
        guard legacyScan.networkProbeVersion == nil,
              legacyScan.validationError(
                authenticatedDeviceID: deviceID,
                lastAcceptedSequence: 40,
                nowMilliseconds: now
              ) == nil else {
            throw FixtureFailure.failed("Pre-probe telemetry lost backward compatibility")
        }
        let unsupportedProbe = ROBLidarTelemetryMessage(
            kind: .scan,
            deviceID: deviceID,
            sequence: 42,
            sentAtMilliseconds: now,
            scanPayload: "0:0:0\n0:0:0\n0.25:0.1\n",
            networkProbeVersion: 2
        )
        guard unsupportedProbe.validationError(
            authenticatedDeviceID: deviceID,
            lastAcceptedSequence: 41,
            nowMilliseconds: now
        ) == "unsupported network probe version" else {
            throw FixtureFailure.failed("Unsupported network probe capability was accepted")
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

        let map = ROBLidarTelemetryMessage.map(
            deviceID: deviceID,
            sequence: 42,
            sentAtMilliseconds: now,
            data: Data([0, 1, 2, 3]),
            width: 2,
            height: 2
        )
        guard map.validationError(
            authenticatedDeviceID: deviceID,
            lastAcceptedSequence: 41,
            nowMilliseconds: now
        ) == nil else {
            throw FixtureFailure.failed("Valid map failed validation")
        }
        let decodedMap = try ROBLidarTelemetryMessage.decode(map.encoded())
        guard decodedMap.kind == .map,
              decodedMap.mapData == Data([0, 1, 2, 3]),
              decodedMap.mapWidth == 2,
              decodedMap.mapHeight == 2,
              decodedMap.scanPayload == nil else {
            throw FixtureFailure.failed("Map telemetry did not round-trip")
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
