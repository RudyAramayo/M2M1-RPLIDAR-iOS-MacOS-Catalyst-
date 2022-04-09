//
//  RPHealthInfo.h
//  uicommander
//
//  Created by AlanLv on 8/18/16.
//  Copyright © 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RPHealthError.h"

@interface RPHealthInfo : NSObject

@property (nonatomic, assign) BOOL hasWarning;
@property (nonatomic, assign) BOOL hasError;
@property (nonatomic, assign) BOOL hasFatal;
@property (nonatomic, strong) NSArray<RPHealthError*> *errors;

@property (nonatomic, assign) BOOL hasSystemEmergencyStop;
@property (nonatomic, assign) BOOL hasLidarDisconnected;
@property (nonatomic, assign) BOOL hasSdpDisconnected;
//@property (nonatomic, assign) BOOL hasDepthCameraDisconnected;

- (instancetype) initWithWarning:(BOOL)warning
                        andError:(BOOL)error
                        andFatal:(BOOL)fatal
          andSystemEmergencyStop:(BOOL)stop
            andLidarDisconnected:(BOOL)lidar
              andSdpDisconnected:(BOOL)sdp
//      andDepthCameraDisconnected:(BOOL)depthCamera
                       andErrors:(NSArray<RPHealthError *>*)errors;

@end
