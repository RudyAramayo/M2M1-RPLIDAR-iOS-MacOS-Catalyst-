//
// Created by Alan Lyu on 18/12/2017.
// Copyright (c) 2017 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface RPMetaData : NSObject<NSCopying>

@property (strong, nonatomic) NSMutableDictionary<NSString*, NSString*>* dict;

- (nonnull instancetype) init;
- (nonnull instancetype) initWithData:(nonnull NSDictionary<NSString*, NSString*>*)data;
- (id)copyWithZone:(nullable NSZone *)zone;

@end