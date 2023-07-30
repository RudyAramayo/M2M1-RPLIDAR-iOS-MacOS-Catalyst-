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
        
        /*let width  = 200
        let height = 300
        let boundingBox = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        let context = createBitmapContext(width, height)
        
        let data = context!.data
        
        let pixels = UnsafeMutablePointer<Pixel>(data!)
        var n = 0
        for j in 0 ..< height {
            for i in 0 ..< width {
                pixels[n] = 0 //B
                n = n+1
                pixels[n] = 255 //G
                n = n+1
                pixels[n] = 0 //R
                n = n+1
                pixels[n] = 255 //A
                n = n+1
            }
        }
        let image = context!.makeImage()
        if let currentContext: CGContext = UIGraphicsGetCurrentContext() {
            UIImage(cgImage:image!).pngData()
            currentContext.draw(image!, in: boundingBox)
        }*/
    }
}
