//
// Created by AlanLv on 4/12/16.
// Copyright (c) 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CoreBluetooth/CoreBluetooth.h"
#import "RPAbstractDevice.h"


@interface RPBleDevice : RPAbstractDevice

@property (strong, nonatomic) CBPeripheral *peripheral;

- (BOOL)canBeFoundWith:(DiscoveryMode)mode;

@end