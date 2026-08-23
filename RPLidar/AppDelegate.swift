//
//  AppDelegate.swift
//  test
//
//  Created by ROB on 10/5/21.
//  Copyright © 2021 OrbitusRobotics. All rights reserved.
//

import UIKit

enum RPLidarLaunchConfiguration {
    static let developmentModeDefaultsKey = "ROBDevelopmentMode"
    static let guiEnvironmentKey = "RPLIDAR_GUI"

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
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--rplidar-headless") { return false }
        if arguments.contains("--rplidar-gui") { return true }

        if let environmentValue = ProcessInfo.processInfo.environment[guiEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
            if ["1", "true", "yes", "on"].contains(environmentValue) { return true }
            if ["0", "false", "no", "off"].contains(environmentValue) { return false }
        }
        return developmentModeEnabled
    }
}

private final class RPLidarHeadlessViewController: UIViewController {
    override func loadView() {
        let placeholderView = UIView(frame: .zero)
        placeholderView.backgroundColor = .clear
        view = placeholderView
    }
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    private static let rplidarMenuIdentifier = UIMenu.Identifier(
        "com.orbitusrobotics.rplidar.menu"
    )


    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if let pluginsURL = Bundle.main.builtInPlugInsURL {
            let rpAppKitControllerPluginURL = pluginsURL.appendingPathComponent("RPAppKitController.bundle")
            Bundle(path: rpAppKitControllerPluginURL.path)?.load()
            
//            //-------
//            // UnitTests for writing to disk
//            if let data = "Data".data(using: .utf8) {
//                RPAppKitController.shared.writeMapToFile(location: "HOME", data: data)
//            }
//            let maps = RPAppKitController.shared.allMaps()
//            print("maps \(maps)")
//            
//            if let data = RPAppKitController.shared.loadMap("HOME") {
//                let mapData = String(data: data, encoding: .utf8)
//                print("mapData = \(mapData ?? "")")
//            }
//            //--------
        }

        RPLidarLaunchConfiguration.registerDefaults()
        RPLidarPassthroughServer.shared.start()

        if RPLidarLaunchConfiguration.shouldShowGUI {
            // This target runs on the Mac as an iPad app. UIKit must create and
            // track its window from UIMainStoryboardFile; a manually allocated
            // UIWindow is treated as untracked and produces an empty host window.
            guard let applicationWindow = window,
                  applicationWindow.rootViewController != nil else {
                assertionFailure("UIKit did not load the main RPLidar storyboard")
                return false
            }
            applicationWindow.makeKeyAndVisible()
            print("RPLidar development GUI enabled")
        } else {
            // Retain UIKit's tracked window so the map can be opened later
            // from the menu without enabling Development Mode. UIKit requires
            // every application window to keep a root controller through the
            // end of launch, even when that window is hidden.
            guard let applicationWindow = window else {
                assertionFailure("UIKit did not create the RPLidar application window")
                return false
            }
            applicationWindow.rootViewController = RPLidarHeadlessViewController()
            applicationWindow.isHidden = true
            print("RPLidar running as a headless lidar passthrough server")
        }

        return true
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .main else { return }

        let openMap = UIAction(
            title: "Open RPLidar Map",
            image: UIImage(systemName: "map")
        ) { [weak self] _ in
            self?.showRPLidarMap()
        }
        let developmentMode = UIAction(
            title: "Development Mode",
            image: UIImage(systemName: "hammer"),
            state: RPLidarLaunchConfiguration.developmentModeEnabled ? .on : .off
        ) { [weak self] _ in
            guard self != nil else { return }
            let enabled = !RPLidarLaunchConfiguration.developmentModeEnabled
            RPLidarLaunchConfiguration.setDevelopmentModeEnabled(enabled)
            UIMenuSystem.main.setNeedsRebuild()
        }
        let menu = UIMenu(
            title: "RPLidar",
            image: nil,
            identifier: Self.rplidarMenuIdentifier,
            options: [],
            children: [openMap, developmentMode]
        )

        if builder.menu(for: Self.rplidarMenuIdentifier) != nil {
            builder.replace(menu: Self.rplidarMenuIdentifier, with: menu)
        } else {
            builder.insertSibling(menu, afterMenu: .view)
        }
    }

    private func showRPLidarMap() {
        guard let applicationWindow = window else {
            assertionFailure("UIKit's tracked RPLidar window is unavailable")
            return
        }
        if applicationWindow.rootViewController == nil
            || applicationWindow.rootViewController is RPLidarHeadlessViewController {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            guard let rootViewController = storyboard.instantiateInitialViewController() else {
                assertionFailure("Main.storyboard has no initial RPLidar view controller")
                return
            }
            applicationWindow.rootViewController = rootViewController
        }
        applicationWindow.isHidden = false
        applicationWindow.makeKeyAndVisible()
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        RPLidarPassthroughServer.shared.stop()
    }


}
