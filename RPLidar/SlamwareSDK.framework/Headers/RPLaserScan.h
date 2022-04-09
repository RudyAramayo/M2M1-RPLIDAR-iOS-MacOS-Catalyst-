//
//  RPLaserScan.h
//  uicommander
//
//  Created by Tony Huang on 4/11/16.
//  Copyright © 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RPLaserPoint.h"
#import "RPPose.h"

@interface RPLaserScan : NSObject<NSCopying>

@property (nonatomic, nonnull, copy) NSArray<RPLaserPoint*>* laserPoints;
@property (nonatomic, nullable, copy) RPPose* pose;

- (instancetype) initWithLaserPoints:(nonnull NSArray<RPLaserPoint*>*) laserPoints;
- (instancetype) initWithLaserPoints:(nonnull NSArray<RPLaserPoint*>*) laserPoints andPose:(nullable RPPose*)pose;
- (id) copyWithZone:(NSZone *)zone;

@end
