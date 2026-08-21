//
//  RPLidarController.swift
//  RPLidar
//
//  Created by Rob Makina on 4/9/22.
//  Copyright © 2022 OrbitusRobotics. All rights reserved.
//

import UIKit
import SlamwareSDK

class RPLidarController: NSObject {
    var connectionIP: String
    var deviceManager: RPDeviceManager?
    var rpSlamwarePlatformProtocol_object: RPSlamwarePlatformProtocol?
    
    var currentLocation: RPLocation?
    var currentPose: RPPose?
    var currentLaserScan: RPLaserScan?
    var currentLaserPoints: [RPLaserPoint]?
    var currentMap: RPMap?
    var currentCompositeMap: RPCompositeMap?
    
    init(ip: String) {
        connectionIP = ip
        super.init()
        deviceManager = RPDeviceManager.init(delegate: self)
        deviceManager?.start(.BOTH)
        rpSlamwarePlatformProtocol_object = deviceManager?.connect(connectionIP, withPort: 1445)
    }
    
    /// Clears the 8bit map that the lidar generates internalls
    func clearMap() {
        do {
            try ExceptionCatcher.catchException { [weak self] in
                self?.rpSlamwarePlatformProtocol_object?.clearMap()
            }
        } catch {
            print("Caught Objective-C exception in clearMap: \(error.localizedDescription)")
        }
    }
    
    /// Toggles the map update engine to update the map. Use this to switch between maps in conjuction with mapLocalization.
    func setMapUpdate(_ mapUpdate:Bool) {
        do { try ExceptionCatcher.catchException { [weak self] in self?.rpSlamwarePlatformProtocol_object?.setMapUpdate(mapUpdate) } } catch {}
    }
    /// Turns the map localization engine on/off. Use this to switch between maps in conjunction with mapUpdate.
    func setMapLocalization(_ mapLocalization: Bool) {
        do { try ExceptionCatcher.catchException { [weak self] in self?.rpSlamwarePlatformProtocol_object?.setMapLocalization(mapLocalization) } } catch {}
    }
    
    /// Returns an array of available map types from Slamware
    var availableMaps: [NSNumber]? {
        var maps: [NSNumber]? = nil
        do { try ExceptionCatcher.catchException { [weak self] in maps = self?.rpSlamwarePlatformProtocol_object?.availableMaps() as? [NSNumber] } } catch {}
        return maps
    }
    /// Returns RPLidar pose of the robot, location and rotation
    var pose: RPPose? {
        var p: RPPose? = nil
        do { try ExceptionCatcher.catchException { [weak self] in p = self?.rpSlamwarePlatformProtocol_object?.pose() } } catch {}
        return p
    }
    
    func getPose() throws -> RPPose? {
        do {
            try ExceptionCatcher.catchException {
                // Simulate an Objective-C exception
                self.currentPose = self.rpSlamwarePlatformProtocol_object?.pose()
            }
        } catch {
            print("Caught Objective-C exception currentPose: \(error.localizedDescription)")
            throw NSError(domain: "RPLidar", code: 1, userInfo: [NSLocalizedDescriptionKey: "Operation failed due to get currentPose"])
        }
        return currentPose
    }
    /// Returns localization quality of the RPLidar. 0 the highest quality
    var localiationQuality: Int32? {
        var q: Int32 = 0
        do { try ExceptionCatcher.catchException { [weak self] in q = self?.rpSlamwarePlatformProtocol_object?.localizationQuality() ?? 0 } } catch {}
        return q
    }
    /// Returns the current location of the RPLidar
    var location: RPLocation? {
        var l: RPLocation? = nil
        do { try ExceptionCatcher.catchException { [weak self] in l = self?.rpSlamwarePlatformProtocol_object?.location() } } catch {}
        return l
    }
    
    func getLocation() throws -> RPLocation? {
        do {
            try ExceptionCatcher.catchException {
                // Simulate an Objective-C exception
                self.currentLocation = self.rpSlamwarePlatformProtocol_object?.location()
            }
        } catch {
            print("Caught Objective-C exception currentLocation: \(error.localizedDescription)")
            throw NSError(domain: "RPLidar", code: 1, userInfo: [NSLocalizedDescriptionKey: "Operation failed due to get currentLocation"])
        }
        return currentLocation
    }
    
    func performRiskyOperation() throws {
        // Assume this is an Objective-C method that can throw an NSException
        // For demonstration, we'll simulate it.
        
        do {
            try ExceptionCatcher.catchException {
                // Simulate an Objective-C exception
                NSException(name: NSExceptionName("SimulatedException"), reason: "Something went wrong in ObjC", userInfo: nil).raise()
            }
        } catch {
            print("Caught Objective-C exception as Swift Error: \(error.localizedDescription)")
            throw NSError(domain: "YourAppDomain", code: 1, userInfo: [NSLocalizedDescriptionKey: "Operation failed due to Objective-C exception"])
        }
    }

    /// Returns the network status of the RPLidar
    var networkStatus: [String: String]? {
        var status: [String: String]? = nil
        do {
            try ExceptionCatcher.catchException { [weak self] in
                status = self?.rpSlamwarePlatformProtocol_object?.getNetworkStatus() as? [String: String]
            }
        } catch {
            print("Caught Objective-C exception in networkStatus: \(error.localizedDescription)")
        }
        return status
    }
    /// Returns the composite map of the RPLidar
    var compositeMap: RPCompositeMap? {
        var map: RPCompositeMap? = nil
        do { try ExceptionCatcher.catchException { [weak self] in map = self?.rpSlamwarePlatformProtocol_object?.compositeMap() } } catch {}
        return map
    }
    /// Returns the status of the RPLidar
    var status: DiscoverStatus? {
        deviceManager?.getStatus(.BOTH)
    }
    
    /// Returns the RPMap of the known area
    var getMap: RPMap? {
        var map: RPMap? = nil
        do { 
            try ExceptionCatcher.catchException { [weak self] in
                if let rpKnownRect = self?.rpSlamwarePlatformProtocol_object?.getKnownArea(of: RPMapTypeBitmap8Bit, andMapKind: RPMapKindExploreMap) {
                    map = self?.rpSlamwarePlatformProtocol_object?.getMapWith(RPMapTypeBitmap8Bit, inArea: rpKnownRect, of: RPMapKindExploreMap)
                }
            } 
        } catch {}
        return map
    }
    
    func getCurrentMap() throws -> RPMap? {
        do {
            try ExceptionCatcher.catchException { [self] in
                // Simulate an Objective-C exception
                if let rpKnownRect = self.rpSlamwarePlatformProtocol_object?.getKnownArea(of: RPMapTypeBitmap8Bit, andMapKind: RPMapKindExploreMap) {
                    self.currentMap = self.rpSlamwarePlatformProtocol_object?.getMapWith(RPMapTypeBitmap8Bit, inArea: rpKnownRect, of: RPMapKindExploreMap)
                }
            }
        } catch {
            print("Caught Objective-C exception currentLocation: \(error.localizedDescription)")
            throw NSError(domain: "RPLidar", code: 1, userInfo: [NSLocalizedDescriptionKey: "Operation failed due to get currentMap"])
        }
        return currentMap
    }

    func getCompositeMap() throws -> RPCompositeMap? {
        do {
            try ExceptionCatcher.catchException { [self] in
                // Simulate an Objective-C exception
                self.currentCompositeMap = self.rpSlamwarePlatformProtocol_object?.compositeMap()
            }
        } catch {
            print("Caught Objective-C exception currentLocation: \(error.localizedDescription)")
            throw NSError(domain: "RPLidar", code: 1, userInfo: [NSLocalizedDescriptionKey: "Operation failed due to get currentCompositeMap"])
        }
        return currentCompositeMap
    }
    
    func setMap(_ map: RPMap?, pose: RPPose?) {
        if let map = map,
           let pose = pose {
            do {
                try ExceptionCatcher.catchException { [weak self] in
                    self?.rpSlamwarePlatformProtocol_object?.setMapUpdate(false)
                    self?.rpSlamwarePlatformProtocol_object?.setMapLocalization(false)
                    
                    self?.rpSlamwarePlatformProtocol_object?.setMapWith(map, of: RPMapTypeBitmap8Bit, andMapKind: RPMapKindExploreMap)
                    self?.rpSlamwarePlatformProtocol_object?.setPose(pose)
                    
                    self?.rpSlamwarePlatformProtocol_object?.setMapUpdate(true)
                    self?.rpSlamwarePlatformProtocol_object?.setMapLocalization(true)
                }
            } catch {
                print("Caught Objective-C exception in setMap: \(error.localizedDescription)")
            }
        }
    }
    
    func recoverLocalization(in area: CGRect? = nil) {
        do {
            try ExceptionCatcher.catchException { [weak self] in
                if let area = area {
                    let originX = Float(area.origin.x)
                    let originY = Float(area.origin.y)
                    let width = Float(area.width)
                    let height = Float(area.height)
                    
                    if let origin = RPPointF(x: originX, andY: originY),
                       let size = RPSizeF(width: width, andHeight: height) {
                        let rpArea = RPRectangleF(origin: origin, andSize: size)
                        self?.rpSlamwarePlatformProtocol_object?.recoverLocalization(rpArea)
                    }
                } else {
                    if let rpKnownRect = self?.rpSlamwarePlatformProtocol_object?.getKnownArea(of: RPMapTypeBitmap8Bit, andMapKind: RPMapKindExploreMap) {
                        self?.rpSlamwarePlatformProtocol_object?.recoverLocalization(rpKnownRect)
                    }
                }
            }
        } catch {
            print("Caught Objective-C exception in recoverLocalization: \(error.localizedDescription)")
        }
    }
    
    /// RPLaserPoint Array returned
    var laserPoints: [RPLaserPoint]? {
        var points: [RPLaserPoint]? = nil
        do {
            try ExceptionCatcher.catchException { [weak self] in
                points = self?.rpSlamwarePlatformProtocol_object?.laserScan().laserPoints
            }
        } catch {}
        return points
    }
    
    func getLaserPoints() throws -> [RPLaserPoint]? {
        try getLaserScan()?.laserPoints
    }

    /// Returns the points together with the pose captured for that scan. Using
    /// this pose avoids rotating/translating fresh hits with a different pose
    /// fetched in a separate network request.
    func getLaserScan() throws -> RPLaserScan? {
        do {
            try ExceptionCatcher.catchException {
                let scan = self.rpSlamwarePlatformProtocol_object?.laserScan()
                self.currentLaserScan = scan
                self.currentLaserPoints = scan?.laserPoints
            }
        } catch {
            print("Caught Objective-C exception currentLaserScan: \(error.localizedDescription)")
            throw NSError(domain: "RPLidar", code: 1, userInfo: [NSLocalizedDescriptionKey: "Operation failed due to get currentLaserScan"])
        }
        return currentLaserScan
    }
}

extension RPLidarController: RPDiscoveryDelegate {
    func onStartDiscovery(_ discover: RPAbstractDiscover!) {
        print("onStartDiscovery \(String(describing: discover))")
    }
    
    func onStopDiscovery(_ discover: RPAbstractDiscover!) {
        print("onStopDiscovery \(String(describing: discover))")
    }
    
    func onDiscoveryStatusChanged(_ discover: RPAbstractDiscover!, with status: DiscoverStatus, withError error: String!) {
        print("onDiscoveryStatusChanged \(String(describing: discover))\n status = \(status)\n error = \(String(describing: error))")
    }
    
    func onDeviceFound(_ discover: RPAbstractDiscover!, with device: RPAbstractDevice!) {
        
        print("onDeviceFound \(String(describing: discover))\ndevice \(String(describing: device))")
    }
    
    
}
