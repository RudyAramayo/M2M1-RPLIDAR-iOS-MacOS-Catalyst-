//
// Created by AlanLv on 4/12/16.
// Copyright (c) 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RPAbstractDevice.h"

@class RPAbstractDiscover;
@class RPAbstractDevice;

typedef NS_ENUM(NSInteger, DiscoverStatus) {
    STOPPED,
    WORKING,
    ERROR
};

@protocol RPDiscoveryDelegate <NSObject>

@required
- (void)onStartDiscovery:(RPAbstractDiscover *)discover;

@required
- (void)onStopDiscovery:(RPAbstractDiscover *)discover;

@required
- (void)onDiscoveryStatusChanged:(RPAbstractDiscover *)discover withStatus:(DiscoverStatus)status withError:(NSString *)error;

@required
- (void)onDeviceFound:(RPAbstractDiscover *)discover withDevice:(RPAbstractDevice *)device;

@end

@interface RPAbstractDiscover : NSObject

- (DiscoverStatus)getStatus:(DiscoveryMode)mode;

- (void)start:(DiscoveryMode)mode;

- (void)stop:(DiscoveryMode)mode;

- (DiscoveryMode)getMode;

@end