//
// Created by AlanLv on 4/12/16.
// Copyright (c) 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, DiscoveryMode) {
    DiscoveryModeBLE,
    DiscoveryModeMDNS,
    DiscoveryModeBOTH
};

@interface RPAbstractDevice : NSObject

@property (nonatomic) int manufactureId;
@property (nonatomic) int modelId;
@property (strong, nonatomic) NSString *manufactureName;
@property (strong, nonatomic) NSString *modelName;
@property (strong, nonatomic) NSString *hardwareVersion;
@property (strong, nonatomic) NSString *softwareVersion;
@property (strong, nonatomic) NSString *serialNumber;
@property (strong, nonatomic) NSUUID *deviceId;
@property (strong, nonatomic) NSString *deviceName;

- (BOOL)canBeFoundWith:(DiscoveryMode)mode;

@end