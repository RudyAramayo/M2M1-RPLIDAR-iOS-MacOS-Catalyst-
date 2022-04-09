//
//  RPLaserPoint.h
//  uicommander
//
//  Created by Tony Huang on 4/11/16.
//  Copyright © 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface RPLaserPoint : NSObject<NSCopying>

@property (atomic) float distance;
@property (atomic) float angle;
@property (atomic) BOOL valid;

- (instancetype) init;
- (instancetype) initWithDistance:(float)dist andAngle:(float)ang;
- (instancetype) initWithDistance:(float)dist andAngle:(float)ang andValid:(BOOL)isValid;
- (id) copyWithZone:(NSZone *)zone;

@end
