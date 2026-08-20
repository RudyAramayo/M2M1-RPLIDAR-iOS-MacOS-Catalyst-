//
//  RPLidarViewController.swift
//  test
//
//  Created by ROB on 10/5/21.
//  Copyright © 2021 OrbitusRobotics. All rights reserved.
//
import UIKit
import Network
import SlamwareSDK

class RPLidarViewController: UIViewController {
    
    var isReconnecting: Bool = false
    
    static let kLidarPulseFrequency = 0.20
    static let kMapPulseFrequency = 5.0
    static let kMapLocalStorageFrequency = 30.0
    
    var rpLidar: RPLidarController?
    private let autoNetClient = AutoNetClient(service: AutoNetClient.defaultService)
    private let telemetrySequenceStore = ROBLidarTelemetrySequenceStore.shared
    private var publisherDeviceID: UUID?
    private var runtimeTimers: [Timer] = []
    private var transportStatusTimer: Timer?
    private let transportStatusLabel = UILabel()
    private let pairButton = UIButton(type: .system)
    private let forgetPairingButton = UIButton(type: .system)
    let distance_filter: Float = 1.0
    let angleFilter: Float = 0.50
    
    private var queue = DispatchQueue(label: "lidar.queue")
    
    var currentLocation: RPLocation?
    var currentMap: RPMap?
    var currentCompositeMap: RPCompositeMap?
    var currentPose: RPPose?
    var currentLaserPoints: [RPLaserPoint]?
    
    @IBOutlet var rpLidarImageView: UIImageView!
    @IBOutlet var rpLidarPolarView: RPLidarPolarView!
    @IBOutlet var locationLabel: UILabel!
    @IBOutlet var rotationLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //-----
        // Unit test usage of obj-c exception catching which is not the same as swift exception catching
        //try? rpLidar.performRiskyOperation()
        //-----
        let destinationHost = NWEndpoint.Host("192.168.11.1")
        let destinationPort = NWEndpoint.Port(rawValue: 1445)!
        let destinationEndpoint = NWEndpoint.hostPort(host: destinationHost, port: destinationPort)
        //-----
        //tcp connection to the RPLidar itself
        let connection = NWConnection(to: destinationEndpoint, using: .tcp)
        //udp connection to the RPLidar itself
        //let connection = NWConnection(to: destinationEndpoint, using: .udp)
        //-----
        
        connection.pathUpdateHandler = { path in
            switch path.status {
            case .satisfied:
                print("Path to destination is available")
                self.reconnect()
                //self.rpLidar = RPLidarController(ip: "192.168.11.1")
                if let status = self.rpLidar?.status {
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
                
            case .unsatisfied:
                print("Path to destination is not available")
            case .requiresConnection:
                print("Path to destination needs a connection attempt")
            @unknown default:
                print("Unknown path status")
            }
            
            // Access properties like path.usesInterfaceType, path.isExpensive, etc.
        }
        connection.start(queue: .global())
        
        
        autoNetClient.start()
        installTransportControls()
        refreshPublisherIdentity()
        refreshTransportStatus()
        transportStatusTimer = Timer.scheduledTimer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(refreshTransportStatus),
            userInfo: nil,
            repeats: true
        )
        rpLidarImageView.transform = CGAffineTransformMakeScale(1.0, -1.0)
    }

    deinit {
        transportStatusTimer?.invalidate()
        runtimeTimers.forEach { $0.invalidate() }
        autoNetClient.stop()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        Timer.scheduledTimer(timeInterval: 0, target: self, selector: #selector(loadCurrentMap), userInfo: nil, repeats: false)
        Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(appStartup), userInfo: nil, repeats: false)
    }
    
    @objc func appStartup() {
        guard runtimeTimers.isEmpty else { return }
        runtimeTimers = [
            Timer.scheduledTimer(timeInterval: RPLidarViewController.kLidarPulseFrequency, target: self, selector: #selector(lidarPulse), userInfo: nil, repeats: true),
            Timer.scheduledTimer(timeInterval: RPLidarViewController.kMapPulseFrequency, target: self, selector: #selector(mapPulse), userInfo: nil, repeats: true),
            Timer.scheduledTimer(timeInterval: RPLidarViewController.kMapLocalStorageFrequency, target: self, selector: #selector(mapStorage), userInfo: nil, repeats: true)
        ]
    }
    
    @IBAction func clearMapAction() {
        rpLidar?.clearMap()
    }
    
    @IBAction func zoomAction(sender: UISlider) {
        rpLidarPolarView.zoomScale = sender.value
        rpLidarPolarView.setNeedsDisplay()
    }
    
    @objc func lidarPulse() {
        //DispatchQueue.global(qos: .userInteractive).async {
        queue.async {
            do {
                var dataString = ""
                if let location = try self.rpLidar?.getLocation() {
                    self.currentLocation = location
                    DispatchQueue.main.async {
                        self.locationLabel.text = "x: \(location.x)  y: \(location.y)  z: \(location.z)"
                    }
                    dataString += "\(location.x):\(location.y):\(location.z)\n"
                } else {
                    dataString += "0:0:0\n"
                }
                if let pose = try self.rpLidar?.getPose() {
                    self.currentPose = pose
                    DispatchQueue.main.async {
                        self.rotationLabel.text = "yaw: \(pose.yaw())  pitch: \(pose.pitch())  roll: \(pose.roll())"
                    }
                    dataString += "\(pose.yaw()):\(pose.pitch()):\(pose.roll())\n"
                } else {
                    dataString += "0:0:0\n"
                }
                if let laserPoints = try self.rpLidar?.getLaserPoints() {
                    self.currentLaserPoints = laserPoints
                    var filteredLaserPoints: [RPLaserPoint] = []
                    
                    for laserPoint in laserPoints {
                        if laserPoint.valid
                            //&&
                            //laserPoint.distance < self.distance_filter &&
                            //((laserPoint.angle < self.angleFilter  &&
                            //  laserPoint.angle > -self.angleFilter) || (laserPoint.angle > Float.pi - self.angleFilter  &&
                            //                                            laserPoint.angle < Float.pi) || (laserPoint.angle < -Float.pi + self.angleFilter  &&
                            //                                                                             laserPoint.angle > -Float.pi))
                        {
                            filteredLaserPoints.append(laserPoint)
                            dataString += "\(laserPoint.distance):\(laserPoint.angle)\n"
                        }
                    }
                    
                    self.rpLidarPolarView.laserPoints = filteredLaserPoints
                    self.rpLidarPolarView.map = self.currentMap
                    self.rpLidarPolarView.currentLocation = self.currentLocation
                    
                    DispatchQueue.main.async {
                        self.rpLidarPolarView.setNeedsDisplay()
                    }
                    
                    self.publishScan(dataString)
                }
            } catch {
                print("RPLidar error \(error.localizedDescription)")
                self.reconnect()
            }
        }
    }
    
    
    @objc func mapPulse() {
        
        //DispatchQueue.global(qos: .userInteractive).async {
        queue.async {
            do {
                if let compositeMap = try self.rpLidar?.getCompositeMap() {
                    self.currentCompositeMap = compositeMap
                    
                    if let mapMetaDataDict = compositeMap.mapMetaData.dict {
                        print("mapMetaDataDict = \(mapMetaDataDict)")
                    }
                    
                    if let mapData = compositeMap.maps {
                        for map in mapData {
                            if let mapLayerDict = map.mapMetaData.dict {
                                print("mapLayerDict = \(mapLayerDict)")
                            }
                        }
                    }
                }
                if let map = try self.rpLidar?.getCurrentMap() {
                    self.currentMap = map
                    let data = map.data
                    let width = map.dimension.width
                    let height = map.dimension.height
                    print("origin = \(map.origin.x), \(map.origin.y)    dim = \(width), \(height)")
                    //let imageData = UnsafeMutablePointer<Pixel>.allocate(capacity: Int(width * height))
                    //Send the laser points to the network if the option has been enabled
                    //-------
                    self.publishMap(
                        data: map.data,
                        width: Int(map.dimension.width),
                        height: Int(map.dimension.height)
                    )
                    //-------
                    
                    let dataBytes = data.bytes
                    let image = self.mask(from: dataBytes, dataWidth: width, dataHeight: height)
                    DispatchQueue.main.async {
                        self.rpLidarImageView.image = image
                        //
                        do {
                            if let yaw = try self.rpLidar?.getPose()?.yaw(),
                               let location = try self.rpLidar?.getLocation() {
                                //                        let polarViewWidth = self.rpLidarPolarView.frame.size.width
                                //                        let polarViewHeight = self.rpLidarPolarView.frame.size.height
                                //
                                //                        let x_min = map.origin.x - map.getArea().size.width / 2
                                //                        let x_max = map.origin.x + map.getArea().size.width / 2
                                //                        let y_min = map.origin.y - map.getArea().size.height / 2
                                //                        let y_max = map.origin.y + map.getArea().size.height / 2
                                //                        print("x_min \(x_min) x_max \(x_max) y_min \(y_min) y_max \(y_max)")
                                //
                                //                        let delta_x = x_max - x_min
                                //                        let delta_y = y_max - y_min
                                //                        print("delta_x \(delta_x) delta_y \(delta_y)")
                                //
                                //                        let delta_loc_x = location.x - x_min
                                //                        let delta_loc_y = location.y - y_min
                                //                        print("delta_loc_x \(delta_loc_x) delta_loc_y \(delta_loc_y)")
                                //
                                //                        let rotationTransform = CGAffineTransformMakeRotation(Double(yaw) - .pi / 2)
                                //                        let translationTransform = CGAffineTransformMakeTranslation(460, -40)
                                //print("x,y = \(location.x), \(location.y) -- map \(map.dimension.width), \(map.dimension.height) -- \(map.origin.x), \(map.origin.y) -- \(map.resolution.x), \(map.resolution.y) -- \(map.getArea().origin.x), \(map.getArea().origin.y) -- \(map.getArea().size.width), \(map.getArea().size.height)")
                                //
                                //                        let transform = CGAffineTransformConcat(rotationTransform, translationTransform)
                                //                        let scaleTransfor = CGAffineTransformMakeScale(1.0, -1.0)
                                //                        //self.rpLidarImageView.transform = CGAffineTransformConcat(scaleTransfor, transform)
                                //                        self.rpLidarPolarView.transform = CGAffineTransformMakeTranslation(460, -40)
                            }
                        } catch {
                            print("error = \(error)")
                        }
                    }
                }
            } catch {
                print("RPLidar getCurrentMap error \(error)")
                self.reconnect()
            }
        }
    }
    
    func reconnect() {
        guard isReconnecting == false else {
            print("Already attempting to reconnect")
            return
        }
        
        isReconnecting = true
        
        do {
            try ExceptionCatcher.catchException {
                // Simulate an Objective-C exception
                print("RPLidarController(ip: \"192.168.11.1\")")
                self.rpLidar = nil
                self.rpLidar = RPLidarController(ip: "192.168.11.1")
                self.isReconnecting = false
            }
        } catch {
            print("Caught Objective-C exception reconnect: \(error.localizedDescription) -- Attempting to recoonect")
            self.isReconnecting = false
            self.queue.asyncAfter(deadline: .now() + 0.5, execute: {
                self.reconnect()
            })
        }
    }

    private func publishScan(_ payload: String) {
        guard let deviceID = publisherDeviceID,
              let sequence = telemetrySequenceStore.next(deviceID: deviceID) else {
            return
        }
        let message = ROBLidarTelemetryMessage.scan(
            deviceID: deviceID,
            sequence: sequence,
            sentAtMilliseconds: Self.currentMilliseconds(),
            payload: payload
        )
        do {
            autoNetClient.publishLidarTelemetry(try message.encoded())
        } catch {
            print("RPLidar scan was not published: \(error.localizedDescription)")
        }
    }

    private func publishMap(data: Data, width: Int, height: Int) {
        guard let deviceID = publisherDeviceID,
              let sequence = telemetrySequenceStore.next(deviceID: deviceID) else {
            return
        }
        let message = ROBLidarTelemetryMessage.map(
            deviceID: deviceID,
            sequence: sequence,
            sentAtMilliseconds: Self.currentMilliseconds(),
            data: data,
            width: width,
            height: height
        )
        do {
            autoNetClient.publishLidarTelemetry(try message.encoded())
        } catch {
            print("RPLidar map was not published: \(error.localizedDescription)")
        }
    }

    private static func currentMilliseconds() -> UInt64 {
        UInt64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
    }

    private func installTransportControls() {
        transportStatusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        transportStatusLabel.textAlignment = .center
        transportStatusLabel.numberOfLines = 2

        pairButton.setTitle("Pair RPLidar…", for: .normal)
        pairButton.addTarget(self, action: #selector(showPairingPrompt), for: .touchUpInside)

        forgetPairingButton.setTitle("Forget Local Pairing", for: .normal)
        forgetPairingButton.addTarget(self, action: #selector(confirmForgetPairing), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            transportStatusLabel,
            pairButton,
            forgetPairingButton
        ])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 6
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stack.backgroundColor = UIColor.black.withAlphaComponent(0.62)
        stack.layer.cornerRadius = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 210)
        ])
    }

    private func refreshPublisherIdentity() {
        let deviceID = autoNetClient.publisherDeviceID
        queue.async { [weak self] in
            self?.publisherDeviceID = deviceID
        }
    }

    @objc private func refreshTransportStatus() {
        let paired = autoNetClient.isPairingConfigured
        let stored = autoNetClient.hasStoredPairing
        let connected = autoNetClient.isConnected
        if autoNetClient.pairingNeedsReplacement {
            transportStatusLabel.text = "Cerebro: re-pair required\nCertificate or code rejected"
            transportStatusLabel.textColor = .systemRed
        } else if paired && connected {
            transportStatusLabel.text = "Cerebro: authenticated\nRole: Lidar publisher"
            transportStatusLabel.textColor = .systemGreen
        } else if paired {
            transportStatusLabel.text = "Cerebro: reconnecting\nRole: Lidar publisher"
            transportStatusLabel.textColor = .systemYellow
        } else if stored {
            transportStatusLabel.text = "Cerebro: pairing invalid\nReplace or forget pairing"
            transportStatusLabel.textColor = .systemRed
        } else {
            transportStatusLabel.text = "Cerebro: not paired\nPublishing disabled"
            transportStatusLabel.textColor = .systemRed
        }
        pairButton.setTitle(stored ? "Replace Pairing…" : "Pair RPLidar…", for: .normal)
        forgetPairingButton.isEnabled = stored
    }

    @objc private func showPairingPrompt() {
        let alert = UIAlertController(
            title: "Pair RPLidar with Cerebro",
            message: "In Cerebro, issue a new credential with the Lidar Publisher role, then paste the complete ROBCTL2 code here. Operator-controller credentials are rejected.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = AutoNetClient.pairingCodeFormat
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.spellCheckingType = .no
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Pair", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let code = alert?.textFields?.first?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !code.isEmpty else {
                self.presentTransportNotice(
                    title: "Pairing code required",
                    message: "Paste the complete ROBCTL2 code issued by Cerebro."
                )
                return
            }
            var error: NSError?
            guard self.autoNetClient.installPairingCode(code, error: &error) else {
                self.presentTransportNotice(
                    title: "Pairing rejected",
                    message: error?.localizedDescription ?? "Cerebro pairing credential was invalid."
                )
                return
            }
            self.refreshPublisherIdentity()
            self.refreshTransportStatus()
        })
        present(alert, animated: true)
    }

    @objc private func confirmForgetPairing() {
        let alert = UIAlertController(
            title: "Forget local pairing?",
            message: "This removes the credential from this app. To revoke it for every copy, revoke the device in Cerebro.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Forget", style: .destructive) { [weak self] _ in
            guard let self else { return }
            var error: NSError?
            guard self.autoNetClient.removePairingCode(&error) else {
                self.presentTransportNotice(
                    title: "Unable to forget pairing",
                    message: error?.localizedDescription ?? "The local Keychain entry could not be removed."
                )
                return
            }
            self.refreshPublisherIdentity()
            self.refreshTransportStatus()
        })
        present(alert, animated: true)
    }

    private func presentTransportNotice(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    func getCurrentLocationName() -> String {
        if let networkStatus = rpLidar?.networkStatus,
           let ssid = networkStatus["ssid"], !ssid.isEmpty {
            return ssid
        }
        return "HOME"
    }
    
    @objc func mapStorage() {
        storeMap(with: getCurrentLocationName())
    }
    
    @objc func loadCurrentMap() {
        let locationName = getCurrentLocationName()
        restoreMap(with: locationName)
        // Optionally trigger recover localization after loading the map
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.rpLidar?.recoverLocalization()
        }
    }
    
    func storeMap(with locationName: String) {
        if let map = currentMap,
           let pose = currentPose {
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
                
                self.rpLidar?.setMap(
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
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue),
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
