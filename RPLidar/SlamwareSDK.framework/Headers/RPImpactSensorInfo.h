//
// Created by Alan Lyu on 18/12/2017.
// Copyright (c) 2017 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RPPose.h"
#import "RPSlamwareEnums.h"

@interface RPImpactSensorInfo : NSObject

- (instancetype) initWithSensorId:(int)id andPose:(nonnull RPPose*)pose andImpactSensorType:(RPImpactSensorType)impactSensorType andSensorType:(RPSensorType)sensorType andRefreshFreq:(float)freq;
- (int) sensorId;
- (RPPose*) pose;
- (RPImpactSensorType) type;
- (RPSensorType) kind;
- (float) refreshFreq;

@end