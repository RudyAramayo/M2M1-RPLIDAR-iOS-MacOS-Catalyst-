//
//  RPLidarViewController.swift
//  test
//
//  Created by ROB on 10/5/21.
//  Copyright © 2021 OrbitusRobotics. All rights reserved.
//

import UIKit

class RPLidarViewController: UIViewController {
    
    var rpLidar: RPLidarController = RPLidarController(ip: "192.168.11.1")
    var autoNetClient: AutoNetClient = AutoNetClient(service: "_roboNet._tcp")
    
    @IBAction func clearMapAction() {
        rpLidar.clearMap()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        autoNetClient.dataDelegate = self
        autoNetClient.start()
        
        if let status = rpLidar.status {
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
    }

}

extension RPLidarViewController: AutoNetClientDataDelegate {
    func didReceiveData(_ data: NSData) {
        //Parse incomming commands here...
    }
}
