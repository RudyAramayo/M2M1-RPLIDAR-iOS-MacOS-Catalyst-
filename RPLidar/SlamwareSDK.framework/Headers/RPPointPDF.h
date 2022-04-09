//
// Created by Alan Lyu on 18/12/2017.
// Copyright (c) 2017 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>

@class RPLocation;


@interface RPPointPDF : NSObject<NSCopying>

@property (atomic) int id;
@property (strong, nonatomic) RPLocation* loc;
@property (atomic) float circularErrorProbability;
@property (strong, nonatomic) NSArray<NSString*>* tags;

- (nonnull instancetype) initWithId:(int)id andLocation:(nonnull RPLocation*)location andCircularErrorProbability:(float)probability andTags:(nonnull NSArray<NSString*>*)tags;

@end