//
//  RPPose.h
//  uicommander
//
//  Created by Tony Huang on 4/11/16.
//  Copyright © 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RPLocation.h"
#import "RPRotation.h"

@interface RPPose : NSObject<NSCopying>

@property (nonatomic, nonnull, copy) RPLocation* location;
@property (nonatomic, nonnull, copy) RPRotation* rotation;

- (nonnull instancetype) init;
- (nonnull instancetype) initWithLocation:(nonnull RPLocation*)loc;
- (nonnull instancetype) initWithRotation:(nonnull RPRotation*)rot;
- (nonnull instancetype) initWithLocation:(nonnull RPLocation*)loc andRotation:(nonnull RPRotation*)rot;
- (nonnull instancetype) initWithX:(float)x andY:(float)y andZ:(float)z andYaw:(float)yaw andPitch:(float)pitch andRoll:(float)roll;
- (nonnull id) copyWithZone:(nullable NSZone *)zone;

- (float) x;
- (void) setX:(float)v;

- (float) y;
- (void) setY:(float)v;

- (float) z;
- (void) setZ:(float)v;

- (float) yaw;
- (void) setYaw:(float)v;

- (float) pitch;
- (void) setPitch:(float)v;

- (float) roll;
- (void) setRoll:(float)v;

@end
