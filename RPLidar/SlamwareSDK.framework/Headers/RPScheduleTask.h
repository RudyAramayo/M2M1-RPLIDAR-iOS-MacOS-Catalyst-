//
// Created by AlanLv on 8/3/16.
// Copyright (c) 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface RPScheduleTask : NSObject

@property (atomic, assign) int id;
@property (atomic, assign) int hour;
@property (atomic, assign) int minute;
@property (atomic, assign) int year;
@property (atomic, assign) int month;
@property (atomic, assign) int day;
@property (atomic, assign) int maxDuration;
@property (atomic, assign) BOOL enabled;
@property (atomic, assign) int weekRepeat;
@property (nonatomic, strong) NSString* task;

- (nonnull instancetype) init;

@end