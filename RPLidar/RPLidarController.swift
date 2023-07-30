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
    /// Returns localization quality of the RPLidar. 0 the highest quality
    var localiationQuality: Int32? {
        rpSlamwarePlatformProtocol_object?.localizationQuality()
    }
    /// Returns the current location of the RPLidar
    var location: RPLocation? {
        rpSlamwarePlatformProtocol_object?.location()
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
