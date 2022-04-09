//
// Created by Alan Lyu on 18/12/2017.
// Copyright (c) 2017 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RPMetaData.h"
#import "RPMapLayer.h"

@interface RPCompositeMap : NSObject<NSCopying>

@property (strong, nonatomic) RPMetaData* mapMetaData;
@property (strong, nonatomic) NSArray<id<RPMapLayer>>* maps;

- (nonnull instancetype) init;
- (instancetype)initWithMapMetaData:(RPMetaData *)mapMetaData maps:(NSArray<id<RPMapLayer>>*)maps;
- (id)copyWithZone:(nullable NSZone *)zone;

@end