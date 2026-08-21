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
}

struct RPLidarPose2D {
    let location: CGPoint
    let yaw: CGFloat
}

struct RPLidarScanPoint {
    let distance: CGFloat
    let angle: CGFloat
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
