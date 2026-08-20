//
//  ExceptionCatcher.m
//  RPLidar
//
//  Created by Rob Makina on 7/26/25.
//  Copyright © 2025 OrbitusRobotics. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ExceptionCatcher.h"

@implementation ExceptionCatcher

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
