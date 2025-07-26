//
//  RPLidarViewController.swift
//  test
//
//  Created by ROB on 10/5/21.
//  Copyright © 2021 OrbitusRobotics. All rights reserved.
//
import UIKit
import SlamwareSDK

class RPLidarViewController: UIViewController {
    
    var rpLidar: RPLidarController = RPLidarController(ip: "192.168.11.1")
    var autoNetClient: AutoNetClient = AutoNetClient(service: "_roboNet._tcp")
    let distance_filter: Float = 1.0
    let angleFilter: Float = 0.50

    var currentMap: RPMap?
    
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
        rpLidarImageView.transform = CGAffineTransformMakeScale(1.0, -1.0)
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
    static let kLidarPulseFrequency = 0.15
    static let kMapPulseFrequency = 0.5
    static let kMapLocalStorageFrequency = 10.0
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        Timer.scheduledTimer(timeInterval: 0, target: self, selector: #selector(loadCurrentMap), userInfo: nil, repeats: false)
        Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(appStartup), userInfo: nil, repeats: false)
    }
    
    @objc func appStartup() {
        Timer.scheduledTimer(timeInterval: RPLidarViewController.kLidarPulseFrequency, target: self, selector: #selector(lidarPulse), userInfo: nil, repeats: true)
        Timer.scheduledTimer(timeInterval: RPLidarViewController.kMapPulseFrequency, target: self, selector: #selector(mapPulse), userInfo: nil, repeats: true)
        Timer.scheduledTimer(timeInterval: RPLidarViewController.kMapLocalStorageFrequency, target: self, selector: #selector(mapStorage), userInfo: nil, repeats: true)
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
                var filteredLaserPoints: [RPLaserPoint] = []
                
                for laserPoint in laserPoints {
                    if laserPoint.valid &&
                        laserPoint.distance < self.distance_filter &&
                        ((laserPoint.angle < self.angleFilter  &&
                          laserPoint.angle > -self.angleFilter) || (laserPoint.angle > Float.pi - self.angleFilter  &&
                                                                    laserPoint.angle < Float.pi) || (laserPoint.angle < -Float.pi + self.angleFilter  &&
                                                                                                     laserPoint.angle > -Float.pi)) {
                        filteredLaserPoints.append(laserPoint)
                        dataString += "\(laserPoint.distance):\(laserPoint.angle)\n"
                    }
                }
                
                self.rpLidarPolarView.laserPoints = filteredLaserPoints
                DispatchQueue.main.async {
                    self.rpLidarPolarView.setNeedsDisplay()
                }
                
            }
            
            let messageDict = ["message":dataString,
                               "sender":"rpLidar"]
            do {
                let data = try NSKeyedArchiver.archivedData(withRootObject: messageDict, requiringSecureCoding: false)
                //self.autoNetClient.send(data: data)
                //print("sent")
            } catch {
                print("Error archiving messageDict: \(error.localizedDescription)")
            }            
        }
    }
                 
    @objc func mapPulse() {
        
        DispatchQueue.global(qos: .userInteractive).async {
            if let map = self.rpLidar.getMap {
                self.currentMap = map
                let data = map.data
                let width = map.dimension.width
                let height = map.dimension.height
                //print("origin = \(map.origin.x), \(map.origin.y)    dim = \(width), \(height)")
                let imageData = UnsafeMutablePointer<Pixel>.allocate(capacity: Int(width * height))
                
                let dataBytes = data.bytes
                let image = self.mask(from: dataBytes, dataWidth: width, dataHeight: height)
                DispatchQueue.main.async {
                    self.rpLidarImageView.image = image
                    if let yaw = self.rpLidar.pose?.yaw(),
                       let location = self.rpLidar.location {
                        let polarViewWidth = self.rpLidarPolarView.frame.size.width
                        let polarViewHeight = self.rpLidarPolarView.frame.size.height
                        
                        let x_min = map.origin.x - map.getArea().size.width / 2
                        let x_max = map.origin.x + map.getArea().size.width / 2
                        let y_min = map.origin.y - map.getArea().size.height / 2
                        let y_max = map.origin.y + map.getArea().size.height / 2
                        print("x_min \(x_min) x_max \(x_max) y_min \(y_min) y_max \(y_max)")
                        
                        let delta_x = x_max - x_min
                        let delta_y = y_max - y_min
                        print("delta_x \(delta_x) delta_y \(delta_y)")
                        
                        let delta_loc_x = location.x - x_min
                        let delta_loc_y = location.y - y_min
                        print("delta_loc_x \(delta_loc_x) delta_loc_y \(delta_loc_y)")
                        
                        let rotationTransform = CGAffineTransformMakeRotation(Double(yaw) - .pi / 2)
                        let translationTransform = CGAffineTransformMakeTranslation(460, -40)
                        print("x,y = \(location.x), \(location.y) -- map \(map.dimension.width), \(map.dimension.height) -- \(map.origin.x), \(map.origin.y) -- \(map.resolution.x), \(map.resolution.y) -- \(map.getArea().origin.x), \(map.getArea().origin.y) -- \(map.getArea().size.width), \(map.getArea().size.height)")
                        
                        let transform = CGAffineTransformConcat(rotationTransform, translationTransform)
                        let scaleTransfor = CGAffineTransformMakeScale(1.0, -1.0)
                        //self.rpLidarImageView.transform = CGAffineTransformConcat(scaleTransfor, transform)
                        self.rpLidarPolarView.transform = CGAffineTransformMakeTranslation(460, -40)
                    }
                }
            }
        }
    }
    
    @objc func mapStorage() {
        storeMap(with: "HOME")
    }
    
    @objc func loadCurrentMap() {
        restoreMap(with: "HOME")
    }
    
    func storeMap(with locationName: String) {
        if let map = currentMap,
         let pose = self.rpLidar.pose {
            let current_robotMap = ROBOMap(
                origin: CGPoint(x: Double(map.origin.x), y: Double(map.origin.y)),
                dimension: CGSize(width: Double(map.dimension.width), height: Double(map.dimension.height)),
                resolution: CGPoint(x: Double(map.resolution.x), y: Double(map.resolution.y)),
                timestamp: map.timestamp,
                data: map.data,
                poseLocationX: Double(pose.location.x),
                poseLocationY: Double(pose.location.y),
                poseLocationZ: Double(pose.location.z),
                poseYaw: Double(pose.rotation.yaw),
                posePitch: Double(pose.rotation.pitch),
                poseRoll: Double(pose.rotation.roll)
            )
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            
            do {
                let encodedData = try encoder.encode(current_robotMap)
                //let jsonString = String(data: encodedData, encoding: .utf8)
                //print("rpmap: \(jsonString ?? "Couldn't convert to JSON string")")
                //let fileURL = mapsDirectory.appendingPathComponent("\(locationName).json")
                //try encodedData.write(to: fileURL)
                //UserDefaults.standard.set(encodedData, forKey: "\(locationName).rpmap")
                RPAppKitController.shared.writeMapToFile(location: locationName, data: encodedData)
            } catch {
                print("failed to encode: \(error)")
            }
        }
    }
    
    func restoreMap(with locationName: String) {
        //if let data = UserDefaults.standard.data(forKey: "\(locationName).rpmap") {
        if let data = RPAppKitController.shared.loadMap(locationName) {
            let decoder = JSONDecoder()
            do {
                let map = try decoder.decode(ROBOMap.self, from: data)
                let rpMap = RPMap(origin: RPPointF(x: Float(map.origin.x), andY: Float(map.origin.y)),
                                  andDimension: RPSize(width: Int32(map.dimension.width), andHeight: Int32(map.dimension.height)),
                                  andResolution: RPPointF(x: Float(map.resolution.x), andY: Float(map.resolution.y)),
                                  andTimestamp: map.timestamp,
                                  andData: map.data)
                
                self.rpLidar.setMap(
                    rpMap,
                    pose: RPPose(
                        x: Float(map.poseLocationX),
                        andY: Float(map.poseLocationY),
                        andZ: Float(map.poseLocationZ),
                        andYaw: Float(map.poseYaw),
                        andPitch: Float(map.posePitch),
                        andRoll: Float(map.poseRoll)
                    )
                )
            } catch {
                print("failed to restore map \(error)")
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

//if let origin = RPPointF(x: 0, andY: 0),
//let dimension = RPSize(width: 0, andHeight: 0),
//let resolution = RPPointF(x: 0, andY: 0) {
//    let timestamp = Int()
//    let data = Data()

struct ROBOMap: Codable {
    var origin: CGPoint
    let dimension: CGSize
    let resolution: CGPoint
    let timestamp: Int
    let data: Data
    
    let poseLocationX: Double
    let poseLocationY: Double
    let poseLocationZ: Double
    let poseYaw: Double
    let posePitch: Double
    let poseRoll: Double
}

