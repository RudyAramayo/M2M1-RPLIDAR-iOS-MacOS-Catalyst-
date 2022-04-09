//
//  RPPointF.h
//  uicommander
//
//  Created by Tony Huang on 4/11/16.
//  Copyright © 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface RPPointF : NSObject<NSCopying>

@property (atomic) float x;
@property (atomic) float y;

- (instancetype) init;
- (instancetype) initWithX:(float)x andY:(float)y;
- (id) copyWithZone:(NSZone *)zone;

@end
