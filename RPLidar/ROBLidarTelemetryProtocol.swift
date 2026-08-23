//
//  ROBLidarTelemetryProtocol.swift
//  RPLidar
//
//  Role-scoped telemetry carried only in ROBControl frame type 7.
//

import CryptoKit
import Foundation
import Network

struct ROBLidarWirePoint: Equatable, Sendable {
    let distanceMeters: Float
    let angleRadians: Float
}

/// Compact, fixed-layout scan payload for ROBControl frame type 7.
///
/// All integers and Float32 bit patterns use network byte order. The 68-byte
/// header is followed by `pointCount` four-byte samples: UInt16 millimeters and
/// UInt16 angle turns. Map rasters are deliberately not part of this protocol.
struct ROBLidarScanFrame: Equatable, Sendable {
    static let formatVersion: UInt8 = 1
    static let headerLength = 68
    static let pointStride = 4
    static let minimumPointCount = 8
    static let maximumPointCount = 8_192
    static let maximumEncodedBytes = headerLength + maximumPointCount * pointStride
    static let maximumMessageAgeMilliseconds: UInt64 = 2_000
    static let maximumFutureSkewMilliseconds: UInt64 = 5_000

    private static let magic = Data([0x52, 0x4C, 0x53, 0x31]) // RLS1
    private static let minimumDistanceMeters: Float = 0.03
    private static let maximumDistanceMeters: Float = 30
    private static let maximumAbsolutePositionMeters: Float = 1_000_000
    private static let radiansPerAngleUnit = Float.pi * 2 / 65_536

    let deviceID: UUID
    let sequence: UInt64
    let sentAtMilliseconds: UInt64
    let x: Float
    let y: Float
    let z: Float
    let yaw: Float
    let pitch: Float
    let roll: Float
    let points: [ROBLidarWirePoint]

    func validationError(
        authenticatedDeviceID: UUID,
        lastAcceptedSequence: UInt64,
        nowMilliseconds: UInt64
    ) -> String? {
        guard deviceID == authenticatedDeviceID else {
            return "device ID does not match authenticated peer"
        }
        guard sequence > 0, sequence > lastAcceptedSequence else {
            return "sequence is missing or not increasing"
        }
        guard sentAtMilliseconds > 0 else { return "timestamp is missing" }
        if sentAtMilliseconds > nowMilliseconds {
            guard sentAtMilliseconds - nowMilliseconds <= Self.maximumFutureSkewMilliseconds else {
                return "timestamp is too far in the future"
            }
        } else if nowMilliseconds - sentAtMilliseconds > Self.maximumMessageAgeMilliseconds {
            return "telemetry is stale"
        }
        let poseValues = [x, y, z, yaw, pitch, roll]
        guard poseValues.allSatisfy(\.isFinite),
              abs(x) <= Self.maximumAbsolutePositionMeters,
              abs(y) <= Self.maximumAbsolutePositionMeters,
              abs(z) <= Self.maximumAbsolutePositionMeters else {
            return "pose contains an invalid value"
        }
        guard (Self.minimumPointCount ... Self.maximumPointCount).contains(points.count) else {
            return "point count is outside the supported range"
        }
        guard points.allSatisfy({ point in
            point.distanceMeters.isFinite
                && (Self.minimumDistanceMeters ... Self.maximumDistanceMeters).contains(point.distanceMeters)
                && point.angleRadians.isFinite
        }) else {
            return "scan contains an invalid point"
        }
        return nil
    }

    func encoded() throws -> Data {
        let previous = sequence > 0 ? sequence - 1 : 0
        if let error = validationError(
            authenticatedDeviceID: deviceID,
            lastAcceptedSequence: previous,
            nowMilliseconds: sentAtMilliseconds
        ) {
            throw ROBLidarTelemetryEncodingError.invalid(error)
        }

        var data = Data(capacity: Self.headerLength + points.count * Self.pointStride)
        data.append(Self.magic)
        data.append(Self.formatVersion)
        data.append(0) // flags
        Self.append(UInt16(Self.headerLength), to: &data)
        data.append(Self.bytes(for: deviceID))
        Self.append(sequence, to: &data)
        Self.append(sentAtMilliseconds, to: &data)
        for value in [x, y, z, yaw, pitch, roll] {
            Self.append(value.bitPattern, to: &data)
        }
        Self.append(UInt16(points.count), to: &data)
        Self.append(UInt16(0), to: &data) // reserved
        for point in points {
            let millimeters = UInt16((point.distanceMeters * 1_000).rounded())
            let normalized = Self.normalizedAngle(point.angleRadians)
            let rawAngle = Int((normalized / Self.radiansPerAngleUnit).rounded()) & 0xFFFF
            Self.append(millimeters, to: &data)
            Self.append(UInt16(rawAngle), to: &data)
        }
        return data
    }

    static func decode(_ data: Data) throws -> ROBLidarScanFrame {
        guard data.count >= headerLength, data.count <= maximumEncodedBytes else {
            throw ROBLidarTelemetryEncodingError.oversized
        }
        let bytes = [UInt8](data)
        guard Data(bytes[0..<4]) == magic,
              bytes[4] == formatVersion,
              bytes[5] == 0,
              Int(readUInt16(bytes, at: 6)) == headerLength,
              let deviceID = uuid(from: bytes[8..<24]) else {
            throw ROBLidarTelemetryEncodingError.invalid("unsupported binary header")
        }
        let pointCount = Int(readUInt16(bytes, at: 64))
        guard readUInt16(bytes, at: 66) == 0,
              (minimumPointCount ... maximumPointCount).contains(pointCount),
              data.count == headerLength + pointCount * pointStride else {
            throw ROBLidarTelemetryEncodingError.invalid("length or point count is invalid")
        }

        let frame = ROBLidarScanFrame(
            deviceID: deviceID,
            sequence: readUInt64(bytes, at: 24),
            sentAtMilliseconds: readUInt64(bytes, at: 32),
            x: Float(bitPattern: readUInt32(bytes, at: 40)),
            y: Float(bitPattern: readUInt32(bytes, at: 44)),
            z: Float(bitPattern: readUInt32(bytes, at: 48)),
            yaw: Float(bitPattern: readUInt32(bytes, at: 52)),
            pitch: Float(bitPattern: readUInt32(bytes, at: 56)),
            roll: Float(bitPattern: readUInt32(bytes, at: 60)),
            points: stride(from: headerLength, to: data.count, by: pointStride).map { offset in
                let distance = Float(readUInt16(bytes, at: offset)) / 1_000
                var angle = Float(readUInt16(bytes, at: offset + 2)) * radiansPerAngleUnit
                if angle > .pi { angle -= .pi * 2 }
                return ROBLidarWirePoint(distanceMeters: distance, angleRadians: angle)
            }
        )
        let previous = frame.sequence > 0 ? frame.sequence - 1 : 0
        if let error = frame.validationError(
            authenticatedDeviceID: frame.deviceID,
            lastAcceptedSequence: previous,
            nowMilliseconds: frame.sentAtMilliseconds
        ) {
            throw ROBLidarTelemetryEncodingError.invalid(error)
        }
        return frame
    }

    private static func normalizedAngle(_ angle: Float) -> Float {
        var result = angle.truncatingRemainder(dividingBy: .pi * 2)
        if result < 0 { result += .pi * 2 }
        return result
    }

    private static func bytes(for identifier: UUID) -> Data {
        var value = identifier.uuid
        return withUnsafeBytes(of: &value) { Data($0) }
    }

    private static func uuid(from bytes: ArraySlice<UInt8>) -> UUID? {
        guard bytes.count == 16 else { return nil }
        var value: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        _ = withUnsafeMutableBytes(of: &value) { destination in
            Data(bytes).copyBytes(to: destination)
        }
        return UUID(uuid: value)
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private static func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }

    private static func readUInt64(_ bytes: [UInt8], at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for byte in bytes[offset ..< offset + 8] {
            value = (value << 8) | UInt64(byte)
        }
        return value
    }
}

enum ROBLidarTelemetryEncodingError: LocalizedError {
    case invalid(String)
    case oversized

    var errorDescription: String? {
        switch self {
        case .invalid(let detail):
            return "Invalid RPLidar scan: \(detail)."
        case .oversized:
            return "RPLidar scan is outside the compact binary frame bounds."
        }
    }
}

enum ROBLidarLocalIPC {
    static let applicationGroupIdentifier = "group.com.orbitusrobotics.rob"
    static let socketFileName = "rplidar-cerebro-v1.sock"
    static let maximumSocketPathBytes = 103

    static func socketURL(fileManager: FileManager = .default) -> URL? {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["ROB_LIDAR_IPC_SOCKET"],
           !override.isEmpty {
            let url = URL(fileURLWithPath: override).standardizedFileURL
            return url.path.utf8.count <= maximumSocketPathBytes ? url : nil
        }
        #endif
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: applicationGroupIdentifier
        ) else { return nil }
        let url = container.appendingPathComponent(socketFileName, isDirectory: false)
        return url.path.utf8.count <= maximumSocketPathBytes ? url : nil
    }

    static func parameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = 2
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.allowLocalEndpointReuse = true
        parameters.defaultProtocolStack.applicationProtocols.insert(
            NWProtocolFramer.Options(definition: ROBLidarLocalIPCFramer.definition),
            at: 0
        )
        return parameters
    }

    static func contentContext() -> NWConnection.ContentContext {
        let message = NWProtocolFramer.Message(definition: ROBLidarLocalIPCFramer.definition)
        return NWConnection.ContentContext(
            identifier: "ROBLidarLocalIPC.Scan",
            metadata: [message]
        )
    }
}

enum ROBLidarLocalIPCEnvelope {
    static let authenticationCodeLength = 32
    static let maximumEncodedBytes = ROBLidarScanFrame.maximumEncodedBytes
        + authenticationCodeLength
    private static let authenticationDomain = Data("ROB-LIDAR-LOCAL-IPC-V1\0".utf8)

    static func seal(scanData: Data, sharedSecret: Data) -> Data? {
        guard sharedSecret.count == 32,
              (try? ROBLidarScanFrame.decode(scanData)) != nil else { return nil }
        var authenticatedData = authenticationDomain
        authenticatedData.append(scanData)
        let authenticationCode = Data(
            HMAC<SHA256>.authenticationCode(
                for: authenticatedData,
                using: SymmetricKey(data: sharedSecret)
            )
        )
        var envelope = scanData
        envelope.append(authenticationCode)
        return envelope
    }

    static func scanData(from envelope: Data) -> Data? {
        guard envelope.count >= ROBLidarLocalIPCHeader.minimumPayloadLength,
              envelope.count <= maximumEncodedBytes else { return nil }
        return envelope.dropLast(authenticationCodeLength)
    }

    static func open(_ envelope: Data, sharedSecret: Data) -> Data? {
        guard sharedSecret.count == 32,
              let scanData = scanData(from: envelope) else { return nil }
        let authenticationCode = envelope.suffix(authenticationCodeLength)
        var authenticatedData = authenticationDomain
        authenticatedData.append(scanData)
        guard HMAC<SHA256>.isValidAuthenticationCode(
            authenticationCode,
            authenticating: authenticatedData,
            using: SymmetricKey(data: sharedSecret)
        ) else { return nil }
        return scanData
    }
}

final class ROBLidarLocalIPCFramer: NWProtocolFramerImplementation {
    static let definition = NWProtocolFramer.Definition(implementation: ROBLidarLocalIPCFramer.self)
    static var label: String { "ROBLidarLocalIPC" }

    required init(framer: NWProtocolFramer.Instance) {}
    func start(framer: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult { .ready }
    func wakeup(framer: NWProtocolFramer.Instance) {}
    func stop(framer: NWProtocolFramer.Instance) -> Bool { true }
    func cleanup(framer: NWProtocolFramer.Instance) {}

    func handleOutput(
        framer: NWProtocolFramer.Instance,
        message: NWProtocolFramer.Message,
        messageLength: Int,
        isComplete: Bool
    ) {
        guard isComplete,
              (ROBLidarLocalIPCHeader.minimumPayloadLength ... ROBLidarLocalIPCEnvelope.maximumEncodedBytes)
                .contains(messageLength) else {
            framer.markFailed(error: NWError.posix(.EMSGSIZE))
            return
        }
        framer.writeOutput(data: ROBLidarLocalIPCHeader(payloadLength: UInt32(messageLength)).encoded)
        do {
            try framer.writeOutputNoCopy(length: messageLength)
        } catch {
            framer.markFailed(error: NWError.posix(.EIO))
        }
    }

    func handleInput(framer: NWProtocolFramer.Instance) -> Int {
        while true {
            var header: ROBLidarLocalIPCHeader?
            let parsed = framer.parseInput(
                minimumIncompleteLength: ROBLidarLocalIPCHeader.encodedLength,
                maximumLength: ROBLidarLocalIPCHeader.encodedLength
            ) { buffer, _ in
                guard let buffer,
                      buffer.count >= ROBLidarLocalIPCHeader.encodedLength else { return 0 }
                header = ROBLidarLocalIPCHeader(buffer)
                return ROBLidarLocalIPCHeader.encodedLength
            }
            guard parsed else { return ROBLidarLocalIPCHeader.encodedLength }
            guard let header else {
                framer.markFailed(error: NWError.posix(.EPROTO))
                return 0
            }
            let message = NWProtocolFramer.Message(definition: Self.definition)
            if !framer.deliverInputNoCopy(
                length: Int(header.payloadLength),
                message: message,
                isComplete: true
            ) {
                return 0
            }
        }
    }
}

private struct ROBLidarLocalIPCHeader {
    static let magic: UInt32 = 0x524C_4950 // RLIP
    static let encodedLength = 8
    static let minimumPayloadLength = ROBLidarScanFrame.headerLength
        + ROBLidarScanFrame.minimumPointCount * ROBLidarScanFrame.pointStride
        + ROBLidarLocalIPCEnvelope.authenticationCodeLength

    let payloadLength: UInt32

    init(payloadLength: UInt32) {
        self.payloadLength = payloadLength
    }

    init?(_ buffer: UnsafeMutableRawBufferPointer) {
        guard buffer.count >= Self.encodedLength,
              Self.readUInt32(buffer, at: 0) == Self.magic else { return nil }
        let payloadLength = Self.readUInt32(buffer, at: 4)
        guard (UInt32(Self.minimumPayloadLength) ... UInt32(ROBLidarLocalIPCEnvelope.maximumEncodedBytes))
            .contains(payloadLength) else { return nil }
        self.payloadLength = payloadLength
    }

    var encoded: Data {
        Data([
            UInt8((Self.magic >> 24) & 0xFF),
            UInt8((Self.magic >> 16) & 0xFF),
            UInt8((Self.magic >> 8) & 0xFF),
            UInt8(Self.magic & 0xFF),
            UInt8((payloadLength >> 24) & 0xFF),
            UInt8((payloadLength >> 16) & 0xFF),
            UInt8((payloadLength >> 8) & 0xFF),
            UInt8(payloadLength & 0xFF),
        ])
    }

    private static func readUInt32(_ buffer: UnsafeMutableRawBufferPointer, at offset: Int) -> UInt32 {
        (UInt32(buffer[offset]) << 24)
            | (UInt32(buffer[offset + 1]) << 16)
            | (UInt32(buffer[offset + 2]) << 8)
            | UInt32(buffer[offset + 3])
    }
}

final class ROBLidarLocalIPCClient {
    private let queue = DispatchQueue(label: "com.orbitusrobotics.rplidar.local-ipc.client")
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let socketURL: URL?
    private let stateDidChange: ((Bool) -> Void)?
    private let deliveryDidFail: ((Data) -> Void)?
    private var connection: NWConnection?
    private var reconnectWorkItem: DispatchWorkItem?
    private var explicitlyStopped = true
    private var ready = false
    private var sendInFlight = false
    private var inFlightScan: Data?
    private var pendingLatestScan: Data?

    init(
        socketURL: URL? = ROBLidarLocalIPC.socketURL(),
        stateDidChange: ((Bool) -> Void)? = nil,
        deliveryDidFail: ((Data) -> Void)? = nil
    ) {
        self.socketURL = socketURL
        self.stateDidChange = stateDidChange
        self.deliveryDidFail = deliveryDidFail
        queue.setSpecific(key: queueKey, value: 1)
    }

    func start() {
        performOnQueue { [weak self] in
            guard let self else { return }
            self.explicitlyStopped = false
            self.connectLocked()
        }
    }

    func stop() {
        performOnQueue { [weak self] in
            guard let self else { return }
            self.explicitlyStopped = true
            self.reconnectWorkItem?.cancel()
            self.reconnectWorkItem = nil
            self.setReadyLocked(false)
            self.pendingLatestScan = nil
            self.sendInFlight = false
            self.inFlightScan = nil
            self.connection?.stateUpdateHandler = nil
            self.connection?.cancel()
            self.connection = nil
        }
    }

    /// Returns true only when this sample was accepted by the local path.
    /// Callers send through QUIC when false.
    func sendLatestIfReady(_ data: Data) -> Bool {
        guard data.count <= ROBLidarLocalIPCEnvelope.maximumEncodedBytes else { return false }
        return performOnQueue {
            guard ready, connection != nil, !explicitlyStopped else { return false }
            pendingLatestScan = data
            flushLatestLocked()
            return true
        }
    }

    private func connectLocked() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !explicitlyStopped, connection == nil, let socketURL else { return }
        let candidate = NWConnection(
            to: .unix(path: socketURL.path),
            using: ROBLidarLocalIPC.parameters()
        )
        connection = candidate
        candidate.stateUpdateHandler = { [weak self, weak candidate] state in
            guard let self, let candidate, self.connection === candidate else { return }
            switch state {
            case .ready:
                self.reconnectWorkItem?.cancel()
                self.reconnectWorkItem = nil
                self.setReadyLocked(true)
                self.flushLatestLocked()
            case .waiting, .failed:
                self.disconnectAndRetryLocked(candidate)
            case .cancelled:
                self.disconnectAndRetryLocked(candidate)
            case .setup, .preparing:
                self.setReadyLocked(false)
            @unknown default:
                self.disconnectAndRetryLocked(candidate)
            }
        }
        candidate.start(queue: queue)
    }

    private func flushLatestLocked() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard ready, !sendInFlight,
              let connection,
              let data = pendingLatestScan else { return }
        pendingLatestScan = nil
        sendInFlight = true
        inFlightScan = data
        connection.send(
            content: data,
            contentContext: ROBLidarLocalIPC.contentContext(),
            isComplete: true,
            completion: .contentProcessed { [weak self, weak connection] error in
                guard let self, let connection else { return }
                self.performOnQueue {
                    guard self.connection === connection else { return }
                    self.sendInFlight = false
                    self.inFlightScan = nil
                    if error != nil {
                        self.disconnectAndRetryLocked(connection, failedScan: data)
                    } else {
                        self.flushLatestLocked()
                    }
                }
            }
        )
    }

    private func disconnectAndRetryLocked(_ candidate: NWConnection, failedScan: Data? = nil) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard connection === candidate else { return }
        let latestUndeliveredScan = pendingLatestScan ?? failedScan ?? inFlightScan
        candidate.stateUpdateHandler = nil
        candidate.cancel()
        connection = nil
        sendInFlight = false
        inFlightScan = nil
        pendingLatestScan = nil
        setReadyLocked(false)
        if !explicitlyStopped, let latestUndeliveredScan {
            deliveryDidFail?(latestUndeliveredScan)
        }
        guard !explicitlyStopped, reconnectWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reconnectWorkItem = nil
            self.connectLocked()
        }
        reconnectWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.75, execute: workItem)
    }

    private func setReadyLocked(_ value: Bool) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard ready != value else { return }
        ready = value
        stateDidChange?(value)
    }

    private func performOnQueue<T>(_ operation: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return operation()
        }
        return queue.sync(execute: operation)
    }
}

final class ROBLidarLocalIPCServer {
    private let queue = DispatchQueue(label: "com.orbitusrobotics.cerebro.local-ipc.server")
    private let socketURL: URL?
    private let receiveScan: (Data) -> Void
    private let stateDidChange: ((Bool) -> Void)?
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    init(
        socketURL: URL? = ROBLidarLocalIPC.socketURL(),
        stateDidChange: ((Bool) -> Void)? = nil,
        receiveScan: @escaping (Data) -> Void
    ) {
        self.socketURL = socketURL
        self.stateDidChange = stateDidChange
        self.receiveScan = receiveScan
    }

    func start() {
        queue.async { [weak self] in
            self?.startLocked()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopLocked(removeSocket: true)
        }
    }

    private func startLocked() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard listener == nil, let socketURL else {
            stateDidChange?(false)
            return
        }
        do {
            try removeStaleSocketIfNeeded(at: socketURL)
            let parameters = ROBLidarLocalIPC.parameters()
            parameters.requiredLocalEndpoint = .unix(path: socketURL.path)
            let candidate = try NWListener(using: parameters)
            listener = candidate
            candidate.newConnectionHandler = { [weak self] connection in
                self?.acceptLocked(connection)
            }
            candidate.stateUpdateHandler = { [weak self, weak candidate] state in
                guard let self, let candidate, self.listener === candidate else { return }
                switch state {
                case .ready:
                    self.stateDidChange?(true)
                case .failed:
                    self.stopLocked(removeSocket: true)
                case .cancelled:
                    self.stateDidChange?(false)
                default:
                    break
                }
            }
            candidate.start(queue: queue)
        } catch {
            listener = nil
            stateDidChange?(false)
        }
    }

    private func acceptLocked(_ connection: NWConnection) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard connections.count < 4 else {
            connection.cancel()
            return
        }
        let identifier = ObjectIdentifier(connection)
        connections[identifier] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                self.receiveNextLocked(on: connection)
            case .failed, .cancelled:
                self.connections.removeValue(forKey: identifier)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveNextLocked(on connection: NWConnection) {
        dispatchPrecondition(condition: .onQueue(queue))
        let identifier = ObjectIdentifier(connection)
        guard connections[identifier] === connection else { return }
        connection.receiveMessage { [weak self, weak connection] data, _, _, error in
            guard let self, let connection,
                  self.connections[identifier] === connection else { return }
            guard error == nil,
                  let data,
                  let scanData = ROBLidarLocalIPCEnvelope.scanData(from: data),
                  (try? ROBLidarScanFrame.decode(scanData)) != nil else {
                self.connections.removeValue(forKey: identifier)
                connection.cancel()
                return
            }
            self.receiveScan(data)
            self.receiveNextLocked(on: connection)
        }
    }

    private func stopLocked(removeSocket: Bool) {
        dispatchPrecondition(condition: .onQueue(queue))
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        for connection in connections.values {
            connection.stateUpdateHandler = nil
            connection.cancel()
        }
        connections.removeAll()
        if removeSocket, let socketURL {
            try? removeSocketIfPresent(at: socketURL)
        }
        stateDidChange?(false)
    }

    private func removeStaleSocketIfNeeded(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let values = try url.resourceValues(forKeys: [.fileResourceTypeKey])
        guard values.fileResourceType == .socket else {
            throw CocoaError(.fileWriteFileExists)
        }
        try FileManager.default.removeItem(at: url)
    }

    private func removeSocketIfPresent(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let values = try url.resourceValues(forKeys: [.fileResourceTypeKey])
        guard values.fileResourceType == .socket else { return }
        try FileManager.default.removeItem(at: url)
    }
}

enum ROBLidarTelemetryTransportRoute: Equatable {
    case localIPC
    case quicFallback
    case disconnected
    case publishingDisabled

    static func resolve(
        publishingEnabled: Bool,
        localIPCReady: Bool,
        quicReady: Bool
    ) -> Self {
        guard publishingEnabled else { return .publishingDisabled }
        if localIPCReady { return .localIPC }
        if quicReady { return .quicFallback }
        return .disconnected
    }
}

/// A persisted scan sequence. The transport also has its own per-connection
/// frame sequence; this publisher sequence lets Cerebro
/// reject stale application messages independently, including after reconnect.
final class ROBLidarTelemetrySequenceStore {
    static let shared = ROBLidarTelemetrySequenceStore()

    private struct Reservation {
        var nextValue: UInt64
        let highWatermark: UInt64
    }

    /// Serializes high-watermark reservations across store instances in this
    /// process. A reserved value is never reused; an app restart may skip the
    /// unused tail of the previous block, which is safe for replay protection.
    private static let persistenceLock = NSLock()
    private static let reservationSize: UInt64 = 4_096

    private let defaults: UserDefaults
    private let lock = NSLock()
    private let keyPrefix = "ROBCTL2.RPLidarTelemetrySequence."
    private var reservations: [UUID: Reservation] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func next(deviceID: UUID) -> UInt64? {
        lock.lock()
        defer { lock.unlock() }

        if var reservation = reservations[deviceID] {
            let value = reservation.nextValue
            if value == reservation.highWatermark {
                reservations.removeValue(forKey: deviceID)
            } else {
                reservation.nextValue = value + 1
                reservations[deviceID] = reservation
            }
            return value
        }

        Self.persistenceLock.lock()
        defer { Self.persistenceLock.unlock() }

        let key = keyPrefix + deviceID.uuidString.lowercased()
        let previous = defaults.string(forKey: key).flatMap(UInt64.init) ?? 0
        guard previous < UInt64.max else { return nil }
        let reservedCount = min(Self.reservationSize, UInt64.max - previous)
        let highWatermark = previous + reservedCount
        defaults.set(String(highWatermark), forKey: key)
        _ = defaults.synchronize()

        let first = previous + 1
        if first < highWatermark {
            reservations[deviceID] = Reservation(
                nextValue: first + 1,
                highWatermark: highWatermark
            )
        }
        return first
    }
}
