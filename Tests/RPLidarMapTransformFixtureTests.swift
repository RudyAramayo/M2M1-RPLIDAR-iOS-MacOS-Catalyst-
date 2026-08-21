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
