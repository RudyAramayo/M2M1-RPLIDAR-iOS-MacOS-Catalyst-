//
// Created by AlanLv on 7/29/16.
// Copyright (c) 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface RPFirmwareUpdateInfo : NSObject

@property (strong, nonatomic) NSString* current;
@property (strong, nonatomic) NSString* latest;
@property (strong, nonatomic) NSString* releaseDate;
@property (strong, nonatomic) NSString* brief;

- (nonnull instancetype) init;

@end