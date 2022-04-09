//
// Created by Alan Lyu on 21/12/2017.
// Copyright (c) 2017 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface RPImpactSensorValue : NSObject

@property (atomic) UInt32 time;
@property (atomic) float value;

- (instancetype)initWithTime:(UInt32)time value:(float)value;

@end