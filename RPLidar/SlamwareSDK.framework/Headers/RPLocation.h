//
//  RPLocation.h
//  uicommander
//
//  Created by Tony Huang on 4/11/16.
//  Copyright © 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface RPLocation : NSObject<NSCopying>

@property (atomic) float x;
@property (atomic) float y;
@property (atomic) float z;

- (nonnull instancetype) init;
- (nonnull instancetype) initWithX:(float)x andY:(float)y andZ:(float)z;
- (nonnull id) copyWithZone:(nullable NSZone*) zone;

@end
