//
//  RPDeviceManager.h
//  uicommander
//
//  Created by Tony Huang on 4/11/16.
//  Copyright © 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RPAbstractDiscover.h"
#import "RPAbstractDevice.h"
#import "RPMdnsDevice.h"

@class RPAbstractDevice;
@class RPBleWifiInfo;
@protocol RPBleConfigureListener;
@protocol RPDiscoveryDelegate;
@protocol RPSlamwarePlatformProtocol;

@interface RPDeviceManager : RPAbstractDiscover

- (nonnull id)initWithDelegate:(nonnull id<RPDiscoveryDelegate>)aDelegate;

// connect device
- (nonnull id<RPSlamwarePlatformProtocol>)connect:(nonnull NSString *)host withPort:(int)port;
- (nonnull id<RPSlamwarePlatformProtocol>)connect:(nonnull RPMdnsDevice *)device;

// peer
- (void)pair:(nonnull RPAbstractDevice *)aDevice withWifiInfo:(nonnull RPBleWifiInfo *)aWifiInfo withListenter:(nonnull id<RPBleConfigureListener>)aListener;
- (void)stopPair;

@end
