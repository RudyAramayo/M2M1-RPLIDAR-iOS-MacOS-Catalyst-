//
// Created by AlanLv on 4/27/16.
// Copyright (c) 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "RPPoint.h"
#import "RPSize.h"


@interface RPRectangle : NSObject<NSCopying>

@property (nonatomic, nonnull, copy) RPPoint* origin;
@property (nonatomic, nonnull, copy) RPSize* size;

- (instancetype) init;
- (instancetype) initWithOrigin:(nonnull RPPoint*)theOrigin andSize:(nonnull RPSize*)theSize;
- (int) left;
- (int) top;
- (int) right;
- (int) bottom;
- (BOOL) empty;
- (void) unionOf:(RPRectangle *)dest;
- (void) intersectionOf:(RPRectangle *)dest;
- (int) area;
- (id) copyWithZone:(NSZone *)zone;

@end