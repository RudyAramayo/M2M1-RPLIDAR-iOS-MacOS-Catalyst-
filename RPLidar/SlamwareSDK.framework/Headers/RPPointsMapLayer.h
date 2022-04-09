//
// Created by Alan Lyu on 19/12/2017.
// Copyright (c) 2017 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RPMapLayer.h"
#import "RPPointPDF.h"

@interface RPPointsMapLayer : NSObject<RPMapLayer>

@property (nonnull, nonatomic) NSMutableArray<RPPointPDF*>* points;

- (nonnull instancetype) initWithMetaData:(RPMetaData*)data andName:(NSString*)name andUsage:(NSString*)usage andPoints:(NSArray<RPPointPDF*>*)points;

@end