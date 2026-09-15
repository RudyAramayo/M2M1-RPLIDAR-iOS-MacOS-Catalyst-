// swiftc RPLidar/RPLidarLaunchConfiguration.swift Tests/RPLidarLaunchConfigurationFixtureTests.swift -o /tmp/rplidar-launch-tests
import Foundation

enum LaunchFixtureFailure: Error {
    case failed(String)
}

@main
struct RPLidarLaunchConfigurationFixtureTests {
    static func main() throws {
        // These include the fresh Release install and an existing install
        // whose saved Mac/development preferences previously hid the window.
        for developmentMode in [false, true] {
            for arguments in [[], ["--rplidar-headless"], ["--rplidar-gui"], ["--rplidar-gui", "--rplidar-headless"]] {
                for environment in [[:], ["RPLIDAR_GUI": "0"], ["RPLIDAR_GUI": "false"], ["RPLIDAR_GUI": "true"]] {
                    try expect(
                        RPLidarLaunchConfiguration.shouldShowGUI(
                            supportsHeadless: false,
                            developmentModeEnabled: developmentMode,
                            arguments: arguments,
                            environment: environment
                        ),
                        "An iPhone/iPad launch hid its only window"
                    )
                }
            }
        }

        try expect(!macGUI(developmentMode: false), "Mac Release default stopped supporting headless mode")
        try expect(macGUI(developmentMode: true), "Mac development default hid its GUI")
        try expect(macGUI(developmentMode: false, arguments: ["--rplidar-gui"]), "Mac GUI override was ignored")
        try expect(!macGUI(developmentMode: true, arguments: ["--rplidar-headless"]), "Mac headless override was ignored")
        try expect(macGUI(developmentMode: false, environment: ["RPLIDAR_GUI": " YES \n"]), "Mac GUI environment override was ignored")
        try expect(!macGUI(developmentMode: true, environment: ["RPLIDAR_GUI": "off"]), "Mac headless environment override was ignored")
        try expect(macGUI(developmentMode: true, environment: ["RPLIDAR_GUI": "invalid"]), "Invalid environment value did not use the Mac preference")
        try expect(macGUI(developmentMode: false, arguments: ["--rplidar-gui"], environment: ["RPLIDAR_GUI": "false"]), "Environment took precedence over a Mac launch argument")
        try expect(!macGUI(developmentMode: true, arguments: ["--rplidar-gui", "--rplidar-headless"]), "Mac conflicting-argument precedence changed")
        print("RPLidar launch fixtures passed: iOS always visible; Mac headless controls preserved")
    }

    private static func macGUI(
        developmentMode: Bool,
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) -> Bool {
        RPLidarLaunchConfiguration.shouldShowGUI(
            supportsHeadless: true,
            developmentModeEnabled: developmentMode,
            arguments: arguments,
            environment: environment
        )
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw LaunchFixtureFailure.failed(message) }
    }
}
