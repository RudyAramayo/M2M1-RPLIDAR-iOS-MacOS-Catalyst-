//
// Created by Alan Lyu on 19/12/2017.
// Copyright (c) 2017 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RPMapLayer.h"
#import "RPCompositeLine.h"

@interface RPLineMapLayer : NSObject<RPMapLayer>

@property (nonatomic) NSMutableDictionary<NSString*, RPCompositeLine*>* lines;

- (nonnull instancetype) initWithMetaData:(RPMetaData *)data andName:(NSString*)name andUsage:(NSString*)usage andLines:(NSDictionary<NSString*, RPCompositeLine*>*)lines;

@end