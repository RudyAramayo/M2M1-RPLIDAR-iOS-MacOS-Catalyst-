//
//  RPRotation.h
//  uicommander
//
//  Created by Tony Huang on 4/11/16.
//  Copyright © 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface RPRotation : NSObject<NSCopying>

@property (atomic) float yaw;
@property (atomic) float pitch;
@property (atomic) float roll;

- (instancetype) init;
- (instancetype) initWithYaw:(float)y;
- (instancetype) initWithYaw:(float)y andPitch:(float)p andRoll:(float)r;
- (id) copyWithZone:(NSZone *)zone;

@end
