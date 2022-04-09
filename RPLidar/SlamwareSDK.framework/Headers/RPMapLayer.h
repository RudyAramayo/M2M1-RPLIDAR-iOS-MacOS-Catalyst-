//
// Created by Alan Lyu on 18/12/2017.
// Copyright (c) 2017 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#include "RPMetaData.h"
#import "RPSlamwareEnums.h"

@protocol RPMapLayer

@property (strong, nonatomic) RPMetaData *mapMetaData;
@property (strong, nonatomic) NSString *name;
@property (strong, nonatomic) NSString *usage;

- (RPMapLayerType) type;

@end
