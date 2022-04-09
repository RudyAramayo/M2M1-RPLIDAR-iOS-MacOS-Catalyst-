//
//  RPActionProtocol.h
//  uicommander
//
//  Created by Tony Huang on 4/11/16.
//  Copyright © 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RPSlamwareEnums.h"

@protocol RPActionProtocol <NSObject>
- (RPActionStatus) status;
- (double) progress;
- (void) cancel;
- (RPActionStatus) waitUntilDone;
- (BOOL) isEmpty;
- (unsigned int) actionId;
- (NSString*) actionName;
@end
