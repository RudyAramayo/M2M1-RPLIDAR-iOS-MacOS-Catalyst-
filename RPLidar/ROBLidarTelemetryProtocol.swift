//
//  ROBLidarTelemetryProtocol.swift
//  RPLidar
//
//  Role-scoped telemetry carried only in ROBControl frame type 7.
//

import Foundation

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
