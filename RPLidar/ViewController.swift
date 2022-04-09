//
//  ViewController.swift
//  test
//
//  Created by ROB on 10/5/21.
//  Copyright © 2021 OrbitusRobotics. All rights reserved.
//

import UIKit
import SlamwareSDK

class ViewController: UIViewController {
    
    var deviceManager: RPDeviceManager?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        let x = 0b11111100 //252
        let y = 0b10101010 //125
        let z = 0b01010110 //86
        let result = x^y
        //print(result)
        
        deviceManager = RPDeviceManager.init(delegate: self)
        deviceManager?.start(.BOTH)
        let discoveryMode = deviceManager?.getMode()
        
        let rpSlamwarePlatformProtocol_object = deviceManager?.connect("192.168.11.1", withPort: 1445)
        //var options: [String: String] = [:]
        //options["ssid"] = "SUPA ROBONET";
        //options["password"] = "7!G3R&@7M"; // password length should surpass 8
        //options["ip"] = "192.168.11.101"; // do not use address from 192.168.11.1 to 192.168.11.100 (reserved for internal usage)
        //options["channel"] = "6";
        //rpSlamwarePlatformProtocol_object?.configureNetwork(with: RPNetworkModeAP, andOptions: options)
        //rpSlamwarePlatformProtocol_object?.configureNetwork(with: RPNetworkModeDHCPEnabled, andOptions: options)
        
        //let rpSlamwarePlatformProtocol_object = deviceManager?.connect("192.168.0.177", withPort: 1445)
        let isCharging = rpSlamwarePlatformProtocol_object?.batteryIsCharging()
        let deviceID = rpSlamwarePlatformProtocol_object?.deviceId()
        let networkStatus = rpSlamwarePlatformProtocol_object?.getNetworkStatus()
        let powerStatus = rpSlamwarePlatformProtocol_object?.getPowerStatus()
        
        let laserScan = rpSlamwarePlatformProtocol_object?.laserScan()
        let pose = rpSlamwarePlatformProtocol_object?.pose()
        let localizationQuality = rpSlamwarePlatformProtocol_object?.localizationQuality()
        let location = rpSlamwarePlatformProtocol_object?.location()
        
        if let laserPoints = laserScan?.laserPoints {
            for laserPoint in laserPoints {
                print("angle = \(laserPoint.angle)\tdistance =\(laserPoint.distance)\tisValid = \(laserPoint.valid)")
            }
        }
        
        if let status = deviceManager?.getStatus(.BOTH) {
            switch status {
            case .WORKING:
                print("discovery working")
            case .STOPPED:
                print("discovery stopped")
            case .ERROR:
                print("discovery error")
            @unknown default:
                print("unknown default error")
            }
        }
        if let location = location {
            print("location =  (\(location.x), \(location.y), \(location.z))")
        }
        if let pose = pose {
            print("pose = (\(pose.x()), \(pose.y()), \(pose.z())")
        }
        if let localizationQuality = localizationQuality {
            print("localizationQuality = \(localizationQuality)")
        }
        
    }


}

extension ViewController: RPDiscoveryDelegate {
    func onStartDiscovery(_ discover: RPAbstractDiscover!) {
        print("onStartDiscovery \(discover)")
    }
    
    func onStopDiscovery(_ discover: RPAbstractDiscover!) {
        print("onStopDiscovery \(discover)")
    }
    
    func onDiscoveryStatusChanged(_ discover: RPAbstractDiscover!, with status: DiscoverStatus, withError error: String!) {
        print("onDiscoveryStatusChanged \(discover)\n status = \(status)\n error = \(error)")
    }
    
    func onDeviceFound(_ discover: RPAbstractDiscover!, with device: RPAbstractDevice!) {
        print("onDeviceFound \(discover)\ndevice \(device)")
    }
    
    
}

