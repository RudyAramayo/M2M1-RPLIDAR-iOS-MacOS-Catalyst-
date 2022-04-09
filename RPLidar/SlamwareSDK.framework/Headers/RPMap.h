//
//  RPMap.h
//  uicommander
//
//  Created by Tony Huang on 4/11/16.
//  Copyright © 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RPPointF.h"
#import "RPSize.h"

@class RPRectangleF;

@interface RPMap : NSObject<NSCopying>

@property (nonatomic, nonnull, copy) RPPointF* origin;
@property (nonatomic, nonnull, copy) RPSize* dimension;
@property (nonatomic, nonnull, copy) RPPointF* resolution;
@property (atomic) long timestamp;
@property (nonatomic, nonnull, copy) NSData* data;

- (nonnull instancetype) initWithOrigin:(nonnull RPPointF*)_origin
                   andDimension:(nonnull RPSize*)_dimension
                  andResolution:(nonnull RPPointF*)_resolution
                   andTimestamp:(long)_timestamp
                        andData:(nonnull NSData*)_data;

- (nonnull instancetype) initWithOrigin:(nonnull RPPointF*)_origin
                   andDimension:(nonnull RPSize*)_dimension
                  andResolution:(nonnull RPPointF*)_resolution
                        andData:(nonnull NSData*)_data;

- (nonnull RPRectangleF *)getMapArea;

- (nonnull id) copyWithZone:(nullable NSZone *)zone;

@end
