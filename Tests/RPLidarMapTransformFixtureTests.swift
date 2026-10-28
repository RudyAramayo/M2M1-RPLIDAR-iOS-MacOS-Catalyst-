import Foundation
import CoreGraphics

enum RPLidarMapTransformFixtureFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

@main
struct RPLidarMapTransformFixtureTests {
    static func main() throws {
        try mapToViewFixtures()
        try scanToWorldFixtures()
        try geographicAlignmentFixtures()
        try telemetryFixtures()
        try rasterFixtures()
        print("RPLidar map transform fixtures passed")
    }

    private static func mapToViewFixtures() throws {
        guard let map = RPLidarMapFrame(
            origin: CGPoint(x: -10, y: -5),
            pixelDimensions: CGSize(width: 200, height: 100),
            resolution: CGSize(width: 0.1, height: 0.1)
        ) else {
            throw RPLidarMapTransformFixtureFailure.failed("Valid map frame was rejected")
        }

        let transform = RPLidarMapTransform(
            map: map,
            viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100)
        )
        try assertRect(
            transform.renderRect,
            equals: CGRect(x: 0, y: 25, width: 100, height: 50),
            message: "Aspect-fit map rectangle was incorrect"
        )
        try assertPoint(
            transform.viewPoint(forWorldPoint: CGPoint(x: -10, y: -5)),
            equals: CGPoint(x: 0, y: 75),
            message: "Map origin did not land on the bitmap's lower-left pixel"
        )
        try assertPoint(
            transform.viewPoint(forWorldPoint: CGPoint(x: 10, y: 5)),
            equals: CGPoint(x: 100, y: 25),
            message: "Map maximum did not land on the bitmap's upper-right pixel"
        )
        try assertPoint(
            transform.viewPoint(forWorldPoint: CGPoint(x: 0, y: 0)),
            equals: CGPoint(x: 50, y: 50),
            message: "Map center did not land on the bitmap center"
        )
    }

    private static func scanToWorldFixtures() throws {
        guard let map = RPLidarMapFrame(
            origin: .zero,
            pixelDimensions: CGSize(width: 100, height: 100),
            resolution: CGSize(width: 0.1, height: 0.1)
        ) else {
            throw RPLidarMapTransformFixtureFailure.failed("Valid square map was rejected")
        }

        let transform = RPLidarMapTransform(
            map: map,
            viewBounds: CGRect(x: 0, y: 0, width: 200, height: 200)
        )
        let pose = RPLidarPose2D(
            location: CGPoint(x: 2, y: 3),
            yaw: .pi / 2
        )

        try assertPoint(
            transform.worldPoint(
                for: RPLidarScanPoint(distance: 2, angle: 0),
                at: pose
            ),
            equals: CGPoint(x: 2, y: 5),
            message: "Robot yaw was not applied to a forward scan hit"
        )
        try assertPoint(
            transform.worldPoint(
                for: RPLidarScanPoint(distance: 2, angle: .pi / 2),
                at: pose
            ),
            equals: CGPoint(x: 0, y: 3),
            message: "Laser angle and robot yaw were not composed"
        )
        try assertPoint(
            transform.viewPoint(
                for: RPLidarScanPoint(distance: 2, angle: 0),
                at: pose
            ),
            equals: CGPoint(x: 40, y: 100),
            message: "Scan hit did not use the same world-to-map transform as the robot"
        )
    }

    private static func geographicAlignmentFixtures() throws {
        let map = RPLidarMapFrame(origin: CGPoint(x: -7, y: -11),
                                  pixelDimensions: CGSize(width: 400, height: 600),
                                  resolution: CGSize(width: 0.05, height: 0.05))!
        let wall = CGPoint(x: 4, y: 6)
        let bitmapPoint = CGPoint(x: (wall.x - map.origin.x) / map.worldSize.width,
                                  y: 1 - (wall.y - map.origin.y) / map.worldSize.height)
        for position in [CGPoint(x: 2, y: 3), CGPoint(x: -2, y: 1)] {
            let dx = wall.x - position.x, dy = wall.y - position.y
            for yaw: CGFloat in [0, .pi / 2, -.pi / 3, 3 * .pi] {
                for rotation: CGFloat in [0, -.pi / 4, .pi / 2] {
                    let transform = RPLidarGeographicTransform(
                        pose: RPLidarPose2D(location: position, yaw: yaw),
                        clockwiseRotation: rotation, scale: 0.6)
                    let hit = RPLidarScanPoint(distance: hypot(dx, dy), angle: atan2(dy, dx) - yaw)
                    try assertPoint(transform.offset(for: hit),
                                    equals: transform.offset(forWorldPoint: map.worldPoint(forImageUnitPoint: bitmapPoint)),
                                    message: "Scan and bitmap wall separated as ROB moved/turned or calibration changed")
                    // Independent compass projection: SDK yaw increases CCW.
                    let expected = CGPoint(x: cos(rotation) * dx + sin(rotation) * dy,
                                           y: -sin(rotation) * dx + cos(rotation) * dy)
                    try assertPoint(transform.offset(for: hit),
                                    equals: CGPoint(x: expected.x * 0.6, y: expected.y * 0.6),
                                    message: "SDK axes became clockwise compass axes")
                }
            }
        }
        let north = RPLidarGeographicTransform(pose: RPLidarPose2D(location: .zero, yaw: .pi / 2),
                                               clockwiseRotation: 0, scale: 1)
        try assertPoint(north.headingVector, equals: CGPoint(x: 0, y: 1), message: "Positive yaw must point north")
        try assertPoint(map.worldPoint(forImageUnitPoint: .zero), equals: CGPoint(x: -7, y: 19),
                        message: "Bitmap top-left must retain map origin and upper Y")
    }

    private static func telemetryFixtures() throws {
        let scan = ROBLidarDisplayScan(message: "1.5:-2:0\n1.5707963267948966:0.17453292519943295:-0.5235987755982988\n2:0\n")!
        guard scan.pose.positionText == "X: 1.500  Y: -2.000  Z: 0.000 m",
              scan.pose.rotationText == "Yaw: 90.0°  Pitch: 10.0°  Roll: -30.0°",
              scan.points == ["2:0"] else {
            throw RPLidarMapTransformFixtureFailure.failed("Pose units, axes or scan headers were lost")
        }
        for invalid in ["", "1:2:3", "1:2:3\n1:2", "bad:2:3\n1:2:3", "1:2:3\nnan:0:0", "inf:2:3\n0:0:0"] {
            guard ROBLidarDisplayScan(message: invalid) == nil else {
                throw RPLidarMapTransformFixtureFailure.failed("Invalid pose was displayed as a real zero pose")
            }
        }
        let unwrapped = ROBLidarDisplayScan(message: "0:0:0\n9.42477796076938:0:0")!
        guard abs(unwrapped.pose.yaw - 3 * .pi) < 0.000001 else {
            throw RPLidarMapTransformFixtureFailure.failed("Unwrapped radians were guessed to be degrees")
        }
    }

    private static func rasterFixtures() throws {
        let raw: [UInt8] = [0x00, 0x7f, 0x81, 0xff]
        guard RPLidarMapRaster.displayBytes(from: raw, width: 2, height: 2)
                == [0x01, 0x7f, 0x80, 0xff] else {
            throw RPLidarMapTransformFixtureFailure.failed(
                "Signed map cells were not biased and vertically oriented like the SDK bitmap sample"
            )
        }
        guard RPLidarMapRaster.displayBytes(from: [0], width: 2, height: 2) == nil else {
            throw RPLidarMapTransformFixtureFailure.failed("Undersized map data was accepted")
        }
    }

    private static func assertPoint(
        _ actual: CGPoint,
        equals expected: CGPoint,
        message: String
    ) throws {
        guard approximatelyEqual(actual.x, expected.x),
              approximatelyEqual(actual.y, expected.y) else {
            throw RPLidarMapTransformFixtureFailure.failed(
                "\(message): got \(actual), expected \(expected)"
            )
        }
    }

    private static func assertRect(
        _ actual: CGRect,
        equals expected: CGRect,
        message: String
    ) throws {
        guard approximatelyEqual(actual.minX, expected.minX),
              approximatelyEqual(actual.minY, expected.minY),
              approximatelyEqual(actual.width, expected.width),
              approximatelyEqual(actual.height, expected.height) else {
            throw RPLidarMapTransformFixtureFailure.failed(
                "\(message): got \(actual), expected \(expected)"
            )
        }
    }

    private static func approximatelyEqual(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < 0.000_01
    }
}
