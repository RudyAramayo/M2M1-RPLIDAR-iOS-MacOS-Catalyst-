//
//  RPSizeF.h
//  uicommander
//
//  Created by Tony Huang on 4/11/16.
//  Copyright © 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface RPSizeF : NSObject<NSCopying>

@property (atomic) float width;
@property (atomic) float height;

- (instancetype) init;
- (instancetype) initWithWidth:(float)_width andHeight:(float)_height;
- (id) copyWithZone:(NSZone *)zone;

@end
