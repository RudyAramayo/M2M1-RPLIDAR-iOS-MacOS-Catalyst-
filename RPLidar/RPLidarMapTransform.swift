//
//  RPLidarMapTransform.swift
//  RPLidar
//
//  Shared map/pose/scan geometry. Slamware coordinates use a right-handed
//  world frame while UIKit view coordinates increase downward.
//

import Foundation
import CoreGraphics

struct RPLidarMapFrame {
    let origin: CGPoint
    let worldSize: CGSize
    let pixelDimensions: CGSize

    init?(
        origin: CGPoint,
        pixelDimensions: CGSize,
        resolution: CGSize
    ) {
        let values = [
            origin.x, origin.y,
            pixelDimensions.width, pixelDimensions.height,
            resolution.width, resolution.height
        ]
        guard values.allSatisfy(\.isFinite),
              pixelDimensions.width > 0,
              pixelDimensions.height > 0,
              resolution.width > 0,
              resolution.height > 0 else {
            return nil
        }

        self.origin = origin
        self.pixelDimensions = pixelDimensions
        self.worldSize = CGSize(
            width: pixelDimensions.width * resolution.width,
            height: pixelDimensions.height * resolution.height
        )
    }

    func aspectFitRect(in bounds: CGRect) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }

        let scale = min(
            bounds.width / pixelDimensions.width,
            bounds.height / pixelDimensions.height
        )
        let size = CGSize(
            width: pixelDimensions.width * scale,
            height: pixelDimensions.height * scale
        )
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// The displayed raster is already flipped to image rows (top to bottom),
    /// as in the SDK's samples/map2bmp/src/main.cpp.
    func worldPoint(forImageUnitPoint point: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + point.x * worldSize.width,
                y: origin.y + (1 - point.y) * worldSize.height)
    }
}

struct RPLidarPose2D {
    let location: CGPoint
    let yaw: CGFloat
}

struct RPLidarScanPoint {
    let distance: CGFloat
    let angle: CGFloat
}

/// One map-to-geographic transform for the bitmap, scan and heading. Slamware
/// uses +X at yaw zero and counterclockwise radians, not compass bearings.
/// Calibration rotates the entire SLAM frame clockwise on the geographic map.
struct RPLidarGeographicTransform {
    let pose: RPLidarPose2D
    let clockwiseRotation: CGFloat
    let scale: CGFloat

    func offset(forWorldPoint point: CGPoint) -> CGPoint {
        offset(forMapVector: CGPoint(x: point.x - pose.location.x,
                                    y: point.y - pose.location.y))
    }

    func offset(forMapVector vector: CGPoint) -> CGPoint {
        let c = cos(clockwiseRotation)
        let s = sin(clockwiseRotation)
        // x = east, y = north, in metres relative to ROB's geographic anchor.
        return CGPoint(x: (c * vector.x + s * vector.y) * scale,
                       y: (-s * vector.x + c * vector.y) * scale)
    }

    func offset(for scan: RPLidarScanPoint) -> CGPoint {
        let angle = pose.yaw + scan.angle
        return offset(forMapVector: CGPoint(x: cos(angle) * scan.distance,
                                           y: sin(angle) * scan.distance))
    }

    var headingVector: CGPoint {
        offset(forMapVector: CGPoint(x: cos(pose.yaw), y: sin(pose.yaw)))
    }
}

@objc(ROBLidarPoseTelemetry)
public final class ROBLidarPoseTelemetry: NSObject {
    @objc public let x: Double
    @objc public let y: Double
    @objc public let z: Double
    @objc public let yaw: Double
    @objc public let pitch: Double
    @objc public let roll: Double

    public init?(x: Double, y: Double, z: Double, yaw: Double, pitch: Double, roll: Double) {
        guard [x, y, z, yaw, pitch, roll].allSatisfy(\.isFinite) else { return nil }
        self.x = x
        self.y = y
        self.z = z
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
    }

    var pose2D: RPLidarPose2D {
        RPLidarPose2D(location: CGPoint(x: x, y: y), yaw: yaw)
    }

    @objc public var positionText: String {
        String(format: "X: %.3f  Y: %.3f  Z: %.3f m", x, y, z)
    }

    @objc public var rotationText: String {
        String(format: "Yaw: %.1f°  Pitch: %.1f°  Roll: %.1f°",
               yaw * 180 / .pi, pitch * 180 / .pi, roll * 180 / .pi)
    }
}

/// The controller-compatible archive carries metres and radians. Do not guess
/// angle units from magnitude: a small degree angle is indistinguishable from
/// radians, and a valid unwrapped radian yaw can exceed 2π.
@objc(ROBLidarDisplayScan)
public final class ROBLidarDisplayScan: NSObject {
    @objc public let pose: ROBLidarPoseTelemetry
    @objc public let points: [String]

    @objc public init?(message: String) {
        let lines = message.components(separatedBy: "\n")
        guard lines.count >= 2 else { return nil }
        let values = lines.prefix(2).flatMap { $0.components(separatedBy: ":") }
        guard lines[0].components(separatedBy: ":").count == 3,
              lines[1].components(separatedBy: ":").count == 3 else { return nil }
        let numbers = values.compactMap(Double.init)
        guard numbers.count == 6,
              let pose = ROBLidarPoseTelemetry(x: numbers[0], y: numbers[1], z: numbers[2],
                                               yaw: numbers[3], pitch: numbers[4], roll: numbers[5])
        else { return nil }
        self.pose = pose
        self.points = Array(lines.dropFirst(2).filter { !$0.isEmpty })
    }
}

struct RPLidarMapTransform {
    let map: RPLidarMapFrame
    let renderRect: CGRect

    init(map: RPLidarMapFrame, viewBounds: CGRect) {
        self.map = map
        self.renderRect = map.aspectFitRect(in: viewBounds)
    }

    /// Converts a point in Slamware's map coordinate system to the matching
    /// point in the aspect-fit bitmap rect.
    func viewPoint(forWorldPoint point: CGPoint) -> CGPoint {
        let normalizedX = (point.x - map.origin.x) / map.worldSize.width
        let normalizedY = (point.y - map.origin.y) / map.worldSize.height

        return CGPoint(
            x: renderRect.minX + normalizedX * renderRect.width,
            y: renderRect.maxY - normalizedY * renderRect.height
        )
    }

    /// Laser angles and pose yaw are right-handed headings in radians. Adding
    /// them rotates a scan-local hit into the map frame before translation.
    func worldPoint(for scanPoint: RPLidarScanPoint, at pose: RPLidarPose2D) -> CGPoint {
        let heading = pose.yaw + scanPoint.angle
        return CGPoint(
            x: pose.location.x + cos(heading) * scanPoint.distance,
            y: pose.location.y + sin(heading) * scanPoint.distance
        )
    }

    func viewPoint(for scanPoint: RPLidarScanPoint, at pose: RPLidarPose2D) -> CGPoint {
        viewPoint(forWorldPoint: worldPoint(for: scanPoint, at: pose))
    }
}

enum RPLidarMapRaster {
    /// Slamware map cells are signed 8-bit occupancy values stored in bytes.
    /// Raw row zero is the map's bottom row; image row zero is the top row.
    static func displayBytes(from rawBytes: [UInt8], width: Int, height: Int) -> [UInt8]? {
        guard width > 0, height > 0 else { return nil }
        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, rawBytes.count >= pixelCount else { return nil }

        var result = [UInt8](repeating: 0, count: pixelCount)
        for displayY in 0 ..< height {
            let sourceY = height - displayY - 1
            for x in 0 ..< width {
                let sourceIndex = x + sourceY * width
                let destinationIndex = x + displayY * width
                result[destinationIndex] = rawBytes[sourceIndex] &+ 128
            }
        }
        return result
    }
}
