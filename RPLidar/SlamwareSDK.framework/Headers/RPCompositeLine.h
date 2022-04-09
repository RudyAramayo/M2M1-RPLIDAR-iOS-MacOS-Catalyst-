//
// Created by Alan Lyu on 19/12/2017.
// Copyright (c) 2017 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RPPointF.h"
#import "RPMetaData.h"

@interface RPCompositeLine : NSObject

@property (strong, nonatomic) NSString* name;
@property (strong, nonatomic) RPPointF *start;
@property (strong, nonatomic) RPPointF *end;
@property (strong, nonatomic) RPMetaData *metaData;

- (nonnull instancetype)initWithName:(NSString *)name andStart:(RPPointF *)start andEnd:(RPPointF *)end andMetaData:(RPMetaData *)data;

@end