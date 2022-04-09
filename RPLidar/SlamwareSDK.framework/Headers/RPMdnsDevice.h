//
// Created by AlanLv on 4/12/16.
// Copyright (c) 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RPAbstractDevice.h"


@interface RPMdnsDevice : RPAbstractDevice

@property (strong, nonatomic) NSString *addr;
@property (nonatomic) int port;

- (BOOL)canBeFoundWith:(DiscoveryMode)mode;

@end