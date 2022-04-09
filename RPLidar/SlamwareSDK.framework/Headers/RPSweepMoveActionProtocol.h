//
//  RPSweepMoveActionProtocol.h
//  uicommander
//
//  Created by Tony Huang on 4/11/16.
//  Copyright © 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RPMoveActionProtocol.h"
#import "RPMap.h"
#import "RPSlamwareEnums.h"
#import "RPRectangleF.h"

@protocol RPSweepMoveActionProtocol <RPMoveActionProtocol>

- (NSArray<NSNumber *> *)getAvailableSweepMaps;
- (RPMap *)getSweepMap:(RPMapType)type withArea:(RPRectangleF *)area;
- (RPRectangleF *)getSweepMapArea:(RPMapType)type;

@end
