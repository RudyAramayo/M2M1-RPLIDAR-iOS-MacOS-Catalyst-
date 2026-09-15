//
//  ExceptionCatcher.h
//  RPLidar
//
//  Created by Rob Makina on 7/26/25.
//  Copyright © 2025 OrbitusRobotics. All rights reserved.
//

#ifndef ExceptionCatcher_h
#define ExceptionCatcher_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol RPSlamwarePlatformProtocol;

@interface ExceptionCatcher : NSObject

+ (BOOL)catchException:(void(^_Nonnull)(void))tryBlock error:(__autoreleasing NSError *_Nullable*_Nullable)error;

// Keep the throwing SDK call entirely in Objective-C++, so a failed connect
// never unwinds a Swift initializer or leaves its captured controller alive.
+ (nullable id<RPSlamwarePlatformProtocol>)connectToHost:(NSString *)host
                                                  port:(int)port
                                                 error:(NSError *_Nullable*_Nullable)error;

+ (BOOL)disconnectPlatform:(id<RPSlamwarePlatformProtocol>)platform
                     error:(NSError *_Nullable*_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif /* ExceptionCatcher_h */
