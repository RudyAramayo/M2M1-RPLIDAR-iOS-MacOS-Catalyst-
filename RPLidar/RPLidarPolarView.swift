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
            
            let mapMinX = Float(map.origin.x)
            let mapMinY = Float(map.origin.y)
            let mapAreaWidth = Float(map.getArea().size.width)
            let mapAreaHeight = Float(map.getArea().size.height)
            
            let proportionalX = (currentLocation.x - mapMinX) / mapAreaWidth
            let proportionalY = (currentLocation.y - mapMinY) / mapAreaHeight
            
            let imageRatio = CGFloat(map.dimension.width) / CGFloat(map.dimension.height)
            let viewRatio = self.bounds.width / self.bounds.height
            
            var renderRect = self.bounds
            if imageRatio > viewRatio {
                renderRect.size.height = self.bounds.width / imageRatio
                renderRect.origin.y = (self.bounds.height - renderRect.height) / 2
            } else {
                renderRect.size.width = self.bounds.height * imageRatio
                renderRect.origin.x = (self.bounds.width - renderRect.width) / 2
            }
            
            let pixelX = renderRect.origin.x + renderRect.width * CGFloat(proportionalX)
            let pixelY = renderRect.origin.y + renderRect.height * CGFloat(1.0 - proportionalY)
            
            currentContext.setStrokeColor(UIColor.red.cgColor)
            currentContext.setFillColor(UIColor.blue.cgColor)
            currentContext.setLineWidth(4)
            let sizeX_over2: CGFloat = 15.0
            let sizeY_over2: CGFloat = 15.0
            currentContext.addEllipse(in: CGRect(x: pixelX - sizeX_over2, y: pixelY - sizeY_over2, width: sizeX_over2 * 2, height: sizeY_over2 * 2))
            currentContext.drawPath(using: .fillStroke)
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
