//
// Created by Alan Lyu on 19/12/2017.
// Copyright (c) 2017 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RPMapLayer.h"
#import "RPLocation.h"
#import "RPSize.h"
#import "RPPointF.h"

@interface RPGridMapLayer : NSObject<RPMapLayer>

@property (strong, nonatomic) RPLocation *origin;
@property (strong, nonatomic) RPSize *dimension;
@property (strong, nonatomic) RPPointF *resolution;
@property (strong, nonatomic) NSData *mapData;

- (nonnull instancetype) initWithMetaData:(RPMetaData *)metaData andName:(NSString *)name andUsage:(NSString *)usage andOrigin:(RPLocation*)origin andDimension:(RPSize*)dimension andResolution:(RPPointF*)resolution andMapData:(NSData*)data;

@end