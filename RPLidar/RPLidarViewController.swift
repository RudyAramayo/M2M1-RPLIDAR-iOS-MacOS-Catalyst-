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
        var dataString = ""
        if let location = rpLidar.location {
            locationLabel.text = "x: \(location.x)  y: \(location.y)  z: \(location.z)"
            dataString += "\(location.x):\(location.y):\(location.z)\n"
        } else {
            dataString += "0:0:0\n"
        }
        if let pose = rpLidar.pose {
            rotationLabel.text = "yaw: \(pose.yaw())  pitch: \(pose.pitch())  roll: \(pose.roll())"
            dataString += "\(pose.yaw()):\(pose.pitch()):\(pose.roll())\n"
        } else {
            dataString += "0:0:0\n"
        }
        if let laserPoints = rpLidar.laserPoints {
            rpLidarPolarView.laserPoints = laserPoints
            rpLidarPolarView.setNeedsDisplay()
            
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
            autoNetClient.send(data: data)
            print("sent")
        } catch {
            print("Error archiving messageDict: \(error.localizedDescription)")
        }
        
//
//        bool saveToBmp(const char * filename, Map map)
//        {
//            std::string finalFilename = filename;
//            finalFilename += ".bmp";
//
//            bitmap_image mapBitmap(map.getMapDimension().x(), map.getMapDimension().y());
//
//            for (size_t posY = 0; posY < map.getMapDimension().y(); ++posY)
//            {
//                for (size_t posX = 0; posX < map.getMapDimension().x(); ++posX)
//                {
//                    rpos::system::types::_u8 cellValue = ((wow)128U) + map.getMapData()[posX + (map.getMapDimension().y()-posY-1) * map.getMapDimension().x()];
//                    mapBitmap.set_pixel(posX, posY, cellValue, cellValue, cellValue);
//                }
//            }
//            mapBitmap.save_image(finalFilename);
//            return true;
//        }
        
        
        
        if let map = rpLidar.getMap {

            
            let data = map.data
            let width = map.dimension.width
            let height = map.dimension.height
            
            let imageData = UnsafeMutablePointer<Pixel>.allocate(capacity: Int(width * height))
            let pixels = UnsafeMutableBufferPointer<Pixel>(start: imageData, count: Int(width * height))
            
            
             //Example of traversing the pixels
            for y in 0 ..< height {
                for x in 0 ..< width {
                    let index = y * width + x
                    let pixel = pixels[Int(index)]
                    if pixel.red > 0 && pixel.green > 0 && pixel.blue > 0 {
                        print("\(pixel.red), \(pixel.green), \(pixel.blue)")
                    }
                }
            }
            
            var colorSpace = CGColorSpaceCreateDeviceRGB()
            
            var bitmapInfo: UInt32 = CGBitmapInfo.byteOrder32Big.rawValue
            
            let bytesPerRow = width * 4
            
            bitmapInfo |= CGImageAlphaInfo.premultipliedLast.rawValue & CGBitmapInfo.alphaInfoMask.rawValue
            
            if let context = CGContext(
                data: pixels.baseAddress,
                width: Int(width),
                height: Int(height),
                bitsPerComponent: 8,
                bytesPerRow: Int(bytesPerRow),
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                releaseCallback: nil,
                releaseInfo: nil
            ),
               let newCGImage = context.makeImage(){
                //rpLidarImageView.image = UIImage(cgImage: newCGImage)
                rpLidarImageView.image = UIImage(data: data)
            }
            
        }
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
