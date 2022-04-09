//
// Created by Alan Lyu on 2018/6/27.
// Copyright (c) 2018 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "RPMapLayer.h"
#import "RPCompositePose.h"

@interface RPPoseMapLayer : NSObject<RPMapLayer>

@property (strong, nonatomic) NSMutableDictionary<NSString*, RPCompositePose*>* poses;

- (nonnull instancetype) initWithMetaData:(RPMetaData*)data andName:(NSString*)name andUsage:(NSString*)usage andPoses:(NSMutableDictionary<NSString*, RPCompositePose*>*)pose;

@end