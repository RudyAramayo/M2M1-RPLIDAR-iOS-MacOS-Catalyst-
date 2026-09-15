import Foundation

enum RPLidarLaunchConfiguration {
    static let developmentModeDefaultsKey = "ROBDevelopmentMode"
    static let guiEnvironmentKey = "RPLIDAR_GUI"

    /// Only Mac launches have a menu for reopening a hidden map window.
    /// An iPhone/iPad must keep its map visible, including Release builds.
    static var supportsHeadless: Bool {
        ProcessInfo.processInfo.isMacCatalystApp || ProcessInfo.processInfo.isiOSAppOnMac
    }

    static func registerDefaults() {
        #if DEBUG
        let developmentModeDefault = true
        #else
        let developmentModeDefault = false
        #endif
        UserDefaults.standard.register(defaults: [
            developmentModeDefaultsKey: developmentModeDefault
        ])
    }

    static var developmentModeEnabled: Bool {
        registerDefaults()
        return UserDefaults.standard.bool(forKey: developmentModeDefaultsKey)
    }

    static func setDevelopmentModeEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: developmentModeDefaultsKey)
    }

    static var shouldShowGUI: Bool {
        shouldShowGUI(
            supportsHeadless: supportsHeadless,
            developmentModeEnabled: developmentModeEnabled,
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )
    }

    static func shouldShowGUI(
        supportsHeadless: Bool,
        developmentModeEnabled: Bool,
        arguments: [String],
        environment: [String: String]
    ) -> Bool {
        // Apply this before preferences or overrides: an old false default or
        // a shared Mac launch scheme must never leave a phone's screen empty.
        guard supportsHeadless else { return true }

        if arguments.contains("--rplidar-headless") { return false }
        if arguments.contains("--rplidar-gui") { return true }

        if let environmentValue = environment[guiEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
            if ["1", "true", "yes", "on"].contains(environmentValue) { return true }
            if ["0", "false", "no", "off"].contains(environmentValue) { return false }
        }
        return developmentModeEnabled
    }
}
