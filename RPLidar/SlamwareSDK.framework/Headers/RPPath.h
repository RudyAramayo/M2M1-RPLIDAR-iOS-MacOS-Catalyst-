//
//  RPPath.h
//  uicommander
//
//  Created by Tony Huang on 4/11/16.
//  Copyright © 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RPLocation.h"

@interface RPPath : NSObject <NSCopying>

@property (nonatomic, nonnull, copy) NSArray<RPLocation*>* points;

- (nonnull instancetype) init;
- (nonnull instancetype) initWithPoints:(nonnull NSArray<RPLocation*>*)points;
- (nonnull id) copyWithZone:(nullable NSZone *)zone;

@end
