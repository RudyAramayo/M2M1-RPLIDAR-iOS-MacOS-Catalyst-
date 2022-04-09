//
//  RPDeviceManager+Connect.h
//  uicommander
//
//  Created by AlanLv on 6/30/16.
//  Copyright © 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <SlamwareSDK/SlamwareSDK.h>

@interface RPDeviceManager (Connect)

+ (nonnull id<RPSlamwarePlatformProtocol>)connect:(nonnull NSString *)host withPort:(int)port;
+ (nonnull id<RPSlamwarePlatformProtocol>)connect:(nonnull RPMdnsDevice *)device;

@end
