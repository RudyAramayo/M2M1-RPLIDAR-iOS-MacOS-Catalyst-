//
//  RPRectangleF.h
//  uicommander
//
//  Created by Tony Huang on 4/11/16.
//  Copyright © 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RPPointF.h"
#import "RPSizeF.h"

@interface RPRectangleF : NSObject<NSCopying>

@property (nonatomic, nonnull, copy) RPPointF* origin;
@property (nonatomic, nonnull, copy) RPSizeF* size;

- (nonnull instancetype) init;
- (nonnull instancetype) initWithOrigin:(nonnull RPPointF*)origin andSize:(nonnull RPSizeF*)size;
- (float) left;
- (float) top;
- (float) right;
- (float) bottom;
- (BOOL) empty;
- (void) unionOf:(nonnull RPRectangleF *)dest;
- (void) intersectionOf:(nonnull RPRectangleF *)dest;
- (float) area;
- (nonnull id) copyWithZone:(nullable NSZone *)zone;

@end
