//
// Created by Alan Lyu on 27/02/2017.
// Copyright (c) 2017 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RPSlamwareEnums.h"

@interface RPPowerStatus : NSObject

@property (atomic, assign) BOOL isDCConnected;
@property (atomic, assign) RPDockingStatus dockingStatus;
@property (atomic, assign) BOOL isCharging;
@property (atomic, assign) int batterPercentage;
@property (atomic, assign) RPSleepMode sleepMode;

- (instancetype) initWithDCConnected:(BOOL)dcConnected andDockingStatus:(RPDockingStatus)dockingStatus andCharging:(BOOL)charging andBatteryPercentage:(int)batterPercentage andSleepMode:(RPSleepMode)sleepMode;

@end