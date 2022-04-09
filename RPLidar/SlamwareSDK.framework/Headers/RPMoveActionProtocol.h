//
//  RPMoveActionProtocol.h
//  uicommander
//
//  Created by Tony Huang on 4/11/16.
//  Copyright © 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RPActionProtocol.h"
#import "RPPath.h"

@protocol RPMoveActionProtocol <RPActionProtocol>
- (RPPath*) remainingPath;
- (RPPath*) remainingMilestones;
@end
