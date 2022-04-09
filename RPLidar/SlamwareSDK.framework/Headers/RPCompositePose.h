//
// Created by Alan Lyu on 2018/6/27.
// Copyright (c) 2018 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "RPPose.h"
#import "RPMetaData.h"

@interface RPCompositePose : NSObject

@property (strong, nonatomic) NSString* name;
@property (strong, nonatomic) NSMutableArray<NSString*>* tags;
@property (strong, nonatomic) RPPose* pose;
@property (strong, nonatomic) RPMetaData* metaData;
@property (atomic) char flags;

- (nonnull instancetype) initWithName:(NSString*)name andTags:(NSMutableArray<NSString*>*)tags andPose:(RPPose*)pose andMeta:(RPMetaData*)meta andFlags:(char)flags;

@end