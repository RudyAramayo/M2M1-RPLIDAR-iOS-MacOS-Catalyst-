//
//  RPSize.h
//  uicommander
//
//  Created by Tony Huang on 4/11/16.
//  Copyright © 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface RPSize : NSObject<NSCopying>

@property (atomic) int width;
@property (atomic) int height;

- (instancetype) init;
- (instancetype) initWithWidth:(int)_width andHeight:(int)_height;
- (id) copyWithZone:(NSZone *)zone;

@end
