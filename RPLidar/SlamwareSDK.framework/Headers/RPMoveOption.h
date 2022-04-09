//
// Created by Alan Lyu on 18/12/2017.
// Copyright (c) 2017 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RPSlamwareEnums.h"

@interface RPMoveOption : NSObject<NSCopying>

@property (atomic) RPMoveOptionFlag flag;
@property (strong, nonatomic) NSNumber *speedRatio;

- (nonnull instancetype) init;
- (nonnull instancetype)initWittMoveOption:(RPMoveOptionFlag)flag andSpeedRatio:(NSNumber*)ratio;
- (nonnull id) copyWithZone:(nullable NSZone*) zone;

@end