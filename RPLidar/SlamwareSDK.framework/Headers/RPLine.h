//
//  RPLine.h
//  uicommander
//
//  Created by Tony Huang on 4/11/16.
//  Copyright © 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RPPointF.h"

@interface RPLine : NSObject<NSCopying>

@property (nonatomic, nonnull, copy) RPPointF* startPoint;
@property (nonatomic, nonnull, copy) RPPointF* endPoint;
@property (atomic) int lineId;

- (nonnull instancetype) initWithStartPoint:(nonnull RPPointF*)start andEndPoint:(nonnull RPPointF*)end;
- (nonnull instancetype) initWithStartPoint:(nonnull RPPointF*)start andEndPoint:(nonnull RPPointF*)end andLineId:(int)lindId;
- (nonnull id) copyWithZone:(nullable NSZone *)zone;

@end
