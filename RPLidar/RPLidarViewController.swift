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
    
    @IBOutlet var rpLidarImageView: UIImageView!
    @IBOutlet var rpLidarPolarView: RPLidarPolarView!
    @IBOutlet var locationLabel: UILabel!
    @IBOutlet var rotationLabel: UILabel!
    
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
    static let kLidarPulseFrequency = 0.1
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        Timer.scheduledTimer(timeInterval: RPLidarViewController.kLidarPulseFrequency, target: self, selector: #selector(lidarPulse), userInfo: nil, repeats: true)
    }
    
    @IBAction func zoomAction(sender: UISlider) {
        rpLidarPolarView.zoomScale = sender.value
        rpLidarPolarView.setNeedsDisplay()
    }
    
    @objc func lidarPulse() {
        
        DispatchQueue.global(qos: .userInteractive).async {
            var dataString = ""
            if let location = self.rpLidar.location {
                DispatchQueue.main.async {
                    self.locationLabel.text = "x: \(location.x)  y: \(location.y)  z: \(location.z)"
                }
                dataString += "\(location.x):\(location.y):\(location.z)\n"
            } else {
                dataString += "0:0:0\n"
            }
            if let pose = self.rpLidar.pose {
                DispatchQueue.main.async {
                    self.rotationLabel.text = "yaw: \(pose.yaw())  pitch: \(pose.pitch())  roll: \(pose.roll())"
                }
                dataString += "\(pose.yaw()):\(pose.pitch()):\(pose.roll())\n"
            } else {
                dataString += "0:0:0\n"
            }
            if let laserPoints = self.rpLidar.laserPoints {
                self.rpLidarPolarView.laserPoints = laserPoints
                DispatchQueue.main.async {
                    self.rpLidarPolarView.setNeedsDisplay()
                }
                
                
                for laserPoint in laserPoints {
                    if laserPoint.valid {
                        dataString += "\(laserPoint.distance):\(laserPoint.angle)\n"
                    }
                }
            }
            
            let messageDict = ["message":dataString,
                               "sender":"rpLidar"]
            do {
                let data = try NSKeyedArchiver.archivedData(withRootObject: messageDict, requiringSecureCoding: false)
                self.autoNetClient.send(data: data)
                //print("sent")
            } catch {
                print("Error archiving messageDict: \(error.localizedDescription)")
            }
            
        }
        
        //rpLidar.clearMap()
        if let map = rpLidar.getMap {

            let data = map.data
            let width = map.dimension.width
            let height = map.dimension.height
            
            let imageData = UnsafeMutablePointer<Pixel>.allocate(capacity: Int(width * height))
            
            let dataBytes = data.bytes
            let image = mask(from: dataBytes, dataWidth: width, dataHeight: height)
            DispatchQueue.main.async {
                self.rpLidarImageView.image = image
            }
            
        }
    }
                 
    func mask(from data: [UInt8], dataWidth: Int32, dataHeight: Int32) -> UIImage? {
        guard data.count >= 8 else {
            print("data too small")
            return nil
        }

        let width  = Int(dataWidth)
        let height = Int(dataHeight)

        let colorSpace = CGColorSpaceCreateDeviceGray()

        guard
            data.count >= width * height,
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: colorSpace, bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
            let buffer = context.data?.bindMemory(to: UInt8.self, capacity: width * height)
        else {
            return nil
        }

        for index in 0 ..< width * height {
            buffer[index] = data[index]
        }

        return context.makeImage().flatMap { UIImage(cgImage: $0) }
    }
}

extension RPLidarViewController: AutoNetClientDataDelegate {
    func didReceiveData(_ data: NSData) {
        //Parse incomming commands here...
    }
}


public struct Pixel {
    public var value: UInt32
    
    public var red: UInt8 {
        get {
            return UInt8(value & 0xFF)
        } set {
            value = UInt32(newValue) | (value & 0xFFFFFF00)
        }
    }
    
    public var green: UInt8 {
        get {
            return UInt8((value >> 8) & 0xFF)
        } set {
            value = (UInt32(newValue) << 8) | (value & 0xFFFF00FF)
        }
    }
    
    public var blue: UInt8 {
        get {
            return UInt8((value >> 16) & 0xFF)
        } set {
            value = (UInt32(newValue) << 16) | (value & 0xFF00FFFF)
        }
    }
    
    public var alpha: UInt8 {
        get {
            return UInt8((value >> 24) & 0xFF)
        } set {
            value = (UInt32(newValue) << 24) | (value & 0x00FFFFFF)
        }
    }
}

extension Data {
    var bytes: [UInt8] {
        return [UInt8](self)
    }
}

extension Array where Element == UInt8 {
    var data: Data {
        return Data(self)
    }
}
