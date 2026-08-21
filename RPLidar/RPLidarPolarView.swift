//
//  RPLidarPolarView.swift
//  RPLidar
//
//  Created by Rob Makina on 4/9/22.
//  Copyright © 2022 OrbitusRobotics. All rights reserved.
//

import UIKit

class RPLidarPolarView: UIView {
    var laserPoints: [RPLidarScanPoint] = []
    var mapFrame: RPLidarMapFrame?
    var robotPose: RPLidarPose2D?

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(),
              let mapFrame,
              let robotPose else { return }

        let transform = RPLidarMapTransform(map: mapFrame, viewBounds: bounds)
        context.saveGState()
        context.clip(to: transform.renderRect)

        context.setFillColor(UIColor.systemRed.withAlphaComponent(0.9).cgColor)
        let laserPointDiameter: CGFloat = 3
        let laserPointRadius = laserPointDiameter / 2
        for laserPoint in laserPoints
        where laserPoint.distance.isFinite && laserPoint.angle.isFinite && laserPoint.distance > 0 {
            let point = transform.viewPoint(for: laserPoint, at: robotPose)
            context.fillEllipse(in: CGRect(
                x: point.x - laserPointRadius,
                y: point.y - laserPointRadius,
                width: laserPointDiameter,
                height: laserPointDiameter
            ))
        }

        drawRobot(robotPose, with: transform, in: context)
        context.restoreGState()
    }

    private func drawRobot(
        _ pose: RPLidarPose2D,
        with transform: RPLidarMapTransform,
        in context: CGContext
    ) {
        let center = transform.viewPoint(forWorldPoint: pose.location)
        let headingPoint = transform.viewPoint(
            forWorldPoint: CGPoint(
                x: pose.location.x + cos(pose.yaw),
                y: pose.location.y + sin(pose.yaw)
            )
        )
        let deltaX = headingPoint.x - center.x
        let deltaY = headingPoint.y - center.y
        let length = max(hypot(deltaX, deltaY), 0.000_1)
        let direction = CGPoint(x: deltaX / length, y: deltaY / length)

        context.setStrokeColor(UIColor.systemRed.cgColor)
        context.setLineWidth(3)
        context.move(to: center)
        context.addLine(to: CGPoint(
            x: center.x + direction.x * 20,
            y: center.y + direction.y * 20
        ))
        context.strokePath()

        let robotDiameter: CGFloat = 18
        let robotRect = CGRect(
            x: center.x - robotDiameter / 2,
            y: center.y - robotDiameter / 2,
            width: robotDiameter,
            height: robotDiameter
        )
        context.setFillColor(UIColor.systemBlue.cgColor)
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(2)
        context.addEllipse(in: robotRect)
        context.drawPath(using: .fillStroke)
    }
}
