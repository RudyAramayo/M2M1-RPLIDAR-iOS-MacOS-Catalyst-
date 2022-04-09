//
// Created by AlanLv on 4/27/16.
// Copyright (c) 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface RPPoint : NSObject<NSCopying>

@property (atomic) int x;
@property (atomic) int y;

- (instancetype) init;
- (instancetype) initWithX:(int)x andY:(int)y;
- (id) copyWithZone:(NSZone *)zone;

@end