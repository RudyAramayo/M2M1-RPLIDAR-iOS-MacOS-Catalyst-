//
// Created by Alan Lyu on 18/12/2017.
// Copyright (c) 2017 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RPSlamwareEnums.h"

@interface RPRecoverLocalizationOptions : NSObject

@property (strong, nonatomic, nullable) NSNumber *maxRecoverTimeInMilliSeconds;
@property (atomic) RPRecoverLocalizationMovement recoverMovementType;

- (nonnull instancetype) init;
- (nonnull instancetype) initWithMaxReocverTime:(nullable NSNumber*)timeInMillis andRecoverLocalizationMovement:(RPRecoverLocalizationMovement)type;

@end
