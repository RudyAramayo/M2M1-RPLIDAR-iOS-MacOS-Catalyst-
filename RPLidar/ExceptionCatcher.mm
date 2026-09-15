//
//  ExceptionCatcher.mm
//  RPLidar
//
//  Created by Rob Makina on 7/26/25.
//  Copyright © 2025 OrbitusRobotics. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ExceptionCatcher.h"
#import <SlamwareSDK/SlamwareSDK.h>
#include <exception>

@implementation ExceptionCatcher

+ (id<RPSlamwarePlatformProtocol>)connectToHost:(NSString *)host
                                          port:(int)port
                                         error:(NSError **)error {
    try {
        @try {
            // A known IP needs no discovery manager, Bonjour browser, or BLE
            // scan. Creating those on every retry leaked sockets and threads.
            id<RPSlamwarePlatformProtocol> platform = [RPDeviceManager connect:host withPort:port];
            if (!platform && error) {
                *error = [NSError errorWithDomain:@"RPLidarConnection" code:1 userInfo:@{
                    NSLocalizedDescriptionKey: @"Slamware did not return a connected platform."
                }];
            }
            return platform;
        } @catch (NSException *exception) {
            if (error) {
                *error = [NSError errorWithDomain:exception.name code:0 userInfo:@{
                    NSLocalizedDescriptionKey: exception.reason ?: exception.name
                }];
            }
        }
    } catch (const std::exception &exception) {
        if (error) {
            *error = [NSError errorWithDomain:@"RPLidarSDKException" code:2 userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithUTF8String:exception.what()] ?: @"Slamware connection failed."
            }];
        }
    } catch (...) {
        if (error) {
            *error = [NSError errorWithDomain:@"RPLidarSDKException" code:3 userInfo:@{
                NSLocalizedDescriptionKey: @"Slamware connection failed with an unknown exception."
            }];
        }
    }
    return nil;
}

+ (BOOL)disconnectPlatform:(id<RPSlamwarePlatformProtocol>)platform error:(NSError **)error {
    return [self catchException:^{ [platform disconnect]; } error:error];
}

+ (BOOL)catchException:(void (^)(void))tryBlock error:(__autoreleasing NSError * _Nullable *)error {
    @try {
        tryBlock();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            *error = [[NSError alloc] initWithDomain:exception.name code:0 userInfo:exception.userInfo];
        }
        return NO;
    } @catch (id exception) {
        if (error) {
            *error = [[NSError alloc] initWithDomain:@"UnknownObjCException" code:-1 userInfo:nil];
        }
        return NO;
    } @catch (...) {
        if (error) {
            *error = [[NSError alloc] initWithDomain:@"UnknownCPlusPlusException" code:-2 userInfo:nil];
        }
        return NO;
    }
}

@end
