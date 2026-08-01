//
//  ROBLidarTelemetryProtocol.swift
//  RPLidar
//
//  Role-scoped telemetry carried only in ROBControl frame type 7.
//

import Foundation

struct ROBLidarTelemetryMessage: Codable, Equatable {
    enum Kind: String, Codable {
        case scan
        case map
    }

    static let currentSchemaVersion = 1
    static let maximumScanPayloadBytes = 1_048_576
    static let maximumMapDataBytes = 3_100_000
    static let maximumMapDimension = 16_384
    static let maximumMessageAgeMilliseconds: UInt64 = 2_000
    static let maximumFutureSkewMilliseconds: UInt64 = 5_000
    static let maximumEncodedBytes = 4 * 1024 * 1024

    let schemaVersion: Int
    let kind: Kind
    let messageID: UUID
    let deviceID: UUID
    let sequence: UInt64
    let sentAtMilliseconds: UInt64
    let scanPayload: String?
    let mapData: Data?
    let mapWidth: Int?
    let mapHeight: Int?

    init(
        schemaVersion: Int = ROBLidarTelemetryMessage.currentSchemaVersion,
        kind: Kind,
        messageID: UUID = UUID(),
        deviceID: UUID,
        sequence: UInt64,
        sentAtMilliseconds: UInt64,
        scanPayload: String? = nil,
        mapData: Data? = nil,
        mapWidth: Int? = nil,
        mapHeight: Int? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.messageID = messageID
        self.deviceID = deviceID
        self.sequence = sequence
        self.sentAtMilliseconds = sentAtMilliseconds
        self.scanPayload = scanPayload
        self.mapData = mapData
        self.mapWidth = mapWidth
        self.mapHeight = mapHeight
    }

    func validationError(
        authenticatedDeviceID: UUID,
        lastAcceptedSequence: UInt64,
        nowMilliseconds: UInt64
    ) -> String? {
        guard schemaVersion == Self.currentSchemaVersion else {
            return "unsupported schema version"
        }
        guard deviceID == authenticatedDeviceID else {
            return "device ID does not match authenticated peer"
        }
        guard sequence > 0, sequence > lastAcceptedSequence else {
            return "sequence is missing or not increasing"
        }
        guard sentAtMilliseconds > 0 else {
            return "timestamp is missing"
        }
        if sentAtMilliseconds > nowMilliseconds {
            guard sentAtMilliseconds - nowMilliseconds <= Self.maximumFutureSkewMilliseconds else {
                return "timestamp is too far in the future"
            }
        } else if nowMilliseconds - sentAtMilliseconds > Self.maximumMessageAgeMilliseconds {
            return "telemetry is stale"
        }

        switch kind {
        case .scan:
            guard let scanPayload,
                  !scanPayload.isEmpty,
                  scanPayload.lengthOfBytes(using: .utf8) <= Self.maximumScanPayloadBytes,
                  mapData == nil, mapWidth == nil, mapHeight == nil else {
                return "scan payload is missing, oversized, or mixed with map data"
            }
        case .map:
            guard scanPayload == nil,
                  let mapData, !mapData.isEmpty,
                  mapData.count <= Self.maximumMapDataBytes,
                  let mapWidth, let mapHeight,
                  (1...Self.maximumMapDimension).contains(mapWidth),
                  (1...Self.maximumMapDimension).contains(mapHeight) else {
                return "map payload or dimensions are invalid"
            }
            let (cellCount, overflow) = mapWidth.multipliedReportingOverflow(by: mapHeight)
            guard !overflow, mapData.count >= cellCount else {
                return "map data is smaller than its dimensions"
            }
        }
        return nil
    }
}

enum ROBLidarTelemetryEncodingError: LocalizedError {
    case invalid(String)
    case oversized

    var errorDescription: String? {
        switch self {
        case .invalid(let detail):
            return "Invalid RPLidar telemetry: \(detail)."
        case .oversized:
            return "Encoded RPLidar telemetry exceeds the 4 MiB ROBControl frame limit."
        }
    }
}

extension ROBLidarTelemetryMessage {
    static func scan(
        deviceID: UUID,
        sequence: UInt64,
        sentAtMilliseconds: UInt64,
        payload: String,
        messageID: UUID = UUID()
    ) -> ROBLidarTelemetryMessage {
        ROBLidarTelemetryMessage(
            kind: .scan,
            messageID: messageID,
            deviceID: deviceID,
            sequence: sequence,
            sentAtMilliseconds: sentAtMilliseconds,
            scanPayload: payload
        )
    }

    static func map(
        deviceID: UUID,
        sequence: UInt64,
        sentAtMilliseconds: UInt64,
        data: Data,
        width: Int,
        height: Int,
        messageID: UUID = UUID()
    ) -> ROBLidarTelemetryMessage {
        ROBLidarTelemetryMessage(
            kind: .map,
            messageID: messageID,
            deviceID: deviceID,
            sequence: sequence,
            sentAtMilliseconds: sentAtMilliseconds,
            mapData: data,
            mapWidth: width,
            mapHeight: height
        )
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
        let data = try JSONEncoder().encode(self)
        guard data.count <= Self.maximumEncodedBytes else {
            throw ROBLidarTelemetryEncodingError.oversized
        }
        return data
    }

    static func decode(_ data: Data) throws -> ROBLidarTelemetryMessage {
        guard data.count <= maximumEncodedBytes else {
            throw ROBLidarTelemetryEncodingError.oversized
        }
        return try JSONDecoder().decode(ROBLidarTelemetryMessage.self, from: data)
    }
}

/// A persisted sequence shared by scans and maps. The transport also has its
/// own per-connection frame sequence; this publisher sequence lets Cerebro
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
