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
    var currentLaserPoints: [RPLaserPoint]?
    var currentMap: RPMap?
    
    init(ip: String) {
        connectionIP = ip
        super.init()
        deviceManager = RPDeviceManager.init(delegate: self)
        deviceManager?.start(.BOTH)
        rpSlamwarePlatformProtocol_object = deviceManager?.connect(connectionIP, withPort: 1445)
    }
    
    /// Clears the 8bit map that the lidar generates internalls
    func clearMap() {
        rpSlamwarePlatformProtocol_object?.clearMap()
    }
    
    /// Toggles the map update engine to update the map. Use this to switch between maps in conjuction with mapLocalization.
    func setMapUpdate(_ mapUpdate:Bool) {
        rpSlamwarePlatformProtocol_object?.setMapUpdate(mapUpdate)
    }
    /// Turns the map localization engine on/off. Use this to switch between maps in conjunction with mapUpdate.
    func setMapLocalization(_ mapLocalization: Bool) {
        rpSlamwarePlatformProtocol_object?.setMapLocalization(mapLocalization)
    }
    
    /// Returns an array of available map types from Slamware
    var availableMaps: [NSNumber]? {
        rpSlamwarePlatformProtocol_object?.availableMaps()
    }
    /// Returns RPLidar pose of the robot, location and rotation
    var pose: RPPose? {
        rpSlamwarePlatformProtocol_object?.pose()
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
        rpSlamwarePlatformProtocol_object?.localizationQuality()
    }
    /// Returns the current location of the RPLidar
    var location: RPLocation? {
        rpSlamwarePlatformProtocol_object?.location()
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
        rpSlamwarePlatformProtocol_object?.getNetworkStatus()
    }
    /// Returns the composite map of the RPLidar
    var compositeMap: RPCompositeMap? {
        rpSlamwarePlatformProtocol_object?.compositeMap()
    }
    /// Returns the status of the RPLidar
    var status: DiscoverStatus? {
        deviceManager?.getStatus(.BOTH)
    }
    
    /// Returns the RPMap of the known area
    var getMap: RPMap? {
        if let rpKnownRect = rpSlamwarePlatformProtocol_object?.getKnownArea(of: RPMapTypeBitmap8Bit, andMapKind: RPMapKindExploreMap) {
            return rpSlamwarePlatformProtocol_object?.getMapWith(RPMapTypeBitmap8Bit, inArea: rpKnownRect, of: RPMapKindExploreMap)
        }
        return nil
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
            throw NSError(domain: "RPLidar", code: 1, userInfo: [NSLocalizedDescriptionKey: "Operation failed due to get currentLocation"])
        }
        return currentMap
    }

    
    func setMap(_ map: RPMap?, pose: RPPose?) {
        if let map = map,
           let pose = pose {
            rpSlamwarePlatformProtocol_object?.setMapUpdate(false)
            rpSlamwarePlatformProtocol_object?.setMapLocalization(false)
            
            rpSlamwarePlatformProtocol_object?.setPose(pose)
            rpSlamwarePlatformProtocol_object?.setMapWith(map, of: RPMapTypeBitmap8Bit, andMapKind: RPMapKindExploreMap)
            
            rpSlamwarePlatformProtocol_object?.setMapUpdate(true)
            rpSlamwarePlatformProtocol_object?.setMapLocalization(true)
        }
    }
    
    /// RPLaserPoint Array returned
    var laserPoints: [RPLaserPoint]? {
        let laserScan = rpSlamwarePlatformProtocol_object?.laserScan()
        return laserScan?.laserPoints
        //---------
        //DEBUG PRINT OUT LASER POINT ARRAY
        //if let laserPoints = laserScan?.laserPoints {
        //    for laserPoint in laserPoints {
        //        print("angle = \(laserPoint.angle)\tdistance =\(laserPoint.distance)\tisValid = \(laserPoint.valid)")
        //    }
        //}
        //---------
    }
    
    func getLaserPoints() throws -> [RPLaserPoint]? {
        do {
            try ExceptionCatcher.catchException {
                // Simulate an Objective-C exception
                self.currentLaserPoints = self.rpSlamwarePlatformProtocol_object?.laserScan().laserPoints
            }
        } catch {
            print("Caught Objective-C exception currentLaserPoints: \(error.localizedDescription)")
            throw NSError(domain: "RPLidar", code: 1, userInfo: [NSLocalizedDescriptionKey: "Operation failed due to get currentLaserPoints"])
        }
        return currentLaserPoints
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
