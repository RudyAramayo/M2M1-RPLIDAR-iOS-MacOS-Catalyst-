//
//  RPLidarPolarView.swift
//  RPLidar
//
//  Created by Rob Makina on 4/9/22.
//  Copyright © 2022 OrbitusRobotics. All rights reserved.
//

import UIKit
import SlamwareSDK

class RPLidarPolarView: UIView {
    
    var laserPoints: [RPLaserPoint] = []
    var zoomScale: Float = 100
    var map: RPMap?
    var currentLocation: RPLocation?
    
    func createBitmapContext(_ pixelsWide: Int, _ pixelsHigh: Int) -> CGContext? {
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * pixelsWide
        let bitsPerComponent = 8
        
        let byteCount = (bytesPerRow * pixelsHigh)
        
        let colorSpace = CGColorSpace(name: CGColorSpaceCreateDeviceRGB() as! CFString)
        
        let pixels = UnsafeMutablePointer<Pixel>.allocate(capacity:byteCount)
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        
        let context = CGContext(data: pixels, width: pixelsWide, height: pixelsHigh, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace!, bitmapInfo: bitmapInfo)
        
        return context
    }

    override func draw(_ rect: CGRect) {
        guard let currentContext: CGContext = UIGraphicsGetCurrentContext() else { return }
        let laserPointSize: CGFloat = 6.0
        let centerPoint = CGPoint(x: self.frame.size.width/2.0, y: self.frame.size.height/2.0)
        currentContext.setStrokeColor(UIColor.white.cgColor)
        currentContext.setFillColor(UIColor.red.cgColor)
        currentContext.setLineWidth(2)
        
        currentContext.addEllipse(in: CGRect(x:centerPoint.x, y: centerPoint.y, width:laserPointSize,height: laserPointSize))
        currentContext.drawPath(using: .fillStroke)
        
        if let map = map,
           let currentLocation = currentLocation {
            //print("x,y = \(currentLocation.x), \(currentLocation.y) -- map \(map.dimension.width), \(map.dimension.height) -- \(map.origin.x), \(map.origin.y) -- \(map.resolution.x), \(map.resolution.y) -- \(map.getArea().origin.x), \(map.getArea().origin.y) -- \(map.getArea().size.width), \(map.getArea().size.height)")
            let mapOriginX = map.origin.x //-8.69
            let mapOriginY = map.origin.y //-7.14
            let mapAreaWidth = map.getArea().size.width //11.2
            let mapAreaHeight = map.getArea().size.height //10.3
            
            let mapMinX = mapOriginX - mapAreaWidth // -8.69 - 11.2 = -19.8
            let mapMaxX = mapOriginX + mapAreaWidth // -8.69 + 11.2 = 2.6
            
            let mapMinY = mapOriginY - mapAreaHeight // -7.14 - 10.3 = -17.7
            let mapMaxY = mapOriginY + mapAreaHeight // -7.14 + 10.3 = 2.9
            
            //let magnitudeMapMinX = 0
            let magnitudeMapMaxX = mapMaxX - mapMinX // 2.6 - -19.8 = 22.4
            
            //let magnitudeMapMinY = 0
            let magnitudeMapMaxY = mapMaxY - mapMinY // 2.9 - -17.7 = 20.6
            
            //print("magMapMaxX = (0,\(magnitudeMapMaxX))")
            //print("magMapMaxY = (0,\(magnitudeMapMaxY))")
            
            let abs_currentPosDeltaX = (currentLocation.x - mapMinX) / magnitudeMapMaxX
            let abs_currentPosDeltaY = (currentLocation.y - mapMinY) / magnitudeMapMaxY
            
            //print("(magPosX/magPosY) = \(abs_currentPosDeltaX), \(abs_currentPosDeltaY)")
            
            let frameWidth = self.frame.size.width
            let frameHeight = self.frame.size.height
            
            let pixelX = Int(abs_currentPosDeltaX * Float(frameWidth))
            let pixelY = Int(abs_currentPosDeltaY * Float(frameHeight))
            
            currentContext.setStrokeColor(UIColor.red.cgColor)
            currentContext.setFillColor(UIColor.blue.cgColor)
            currentContext.setLineWidth(4)
            let sizeX_over2 = 30
            let sizeY_over2 = 30
            currentContext.addEllipse(in: CGRect(x:Int(frameWidth)-pixelX-sizeX_over2, y: /*Int(frameHeight)-*/pixelY-sizeY_over2, width: sizeX_over2, height: sizeY_over2))
            currentContext.drawPath(using: .fillStroke)
            
            //print("pixel = \(pixelX), \(pixelY)")
        }
        
        currentContext.setStrokeColor(UIColor.white.cgColor)
        currentContext.setFillColor(UIColor.red.cgColor)
        currentContext.setLineWidth(2)
        
        for laserPoint in laserPoints {
            if laserPoint.valid { //Skip invalid points for now
                let positionX = centerPoint.x
                let positionY = centerPoint.y
                let theta = laserPoint.angle + Float.pi//in Radians, 0 is center, right is +π and left is -π
                let distance = laserPoint.distance
                
                let x = CGFloat(sin(theta) * distance * zoomScale) + positionX
                let y = CGFloat(cos(theta) * distance * zoomScale) + positionY
            
                currentContext.addEllipse(in: CGRect(x:x, y: y, width:laserPointSize,height: laserPointSize))
                currentContext.drawPath(using: .fillStroke)
            }
        }
    }
}
