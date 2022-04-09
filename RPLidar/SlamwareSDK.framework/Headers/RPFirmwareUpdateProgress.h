//
// Created by AlanLv on 7/29/16.
// Copyright (c) 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface RPFirmwareUpdateProgress : NSObject

@property (atomic) unsigned int currentStep;
@property (atomic) unsigned int totalSteps;
@property (atomic) unsigned int currentStepProgress;
@property (strong, nonatomic) NSString* currentStepName;

- (nonnull instancetype) init;

@end