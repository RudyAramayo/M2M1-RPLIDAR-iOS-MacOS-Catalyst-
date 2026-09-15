// Test-only stand-in for the iOS SDK, allowing the native exception boundary
// to run on macOS. This directory is not in the app target's include paths.
#import <Foundation/Foundation.h>

@protocol RPSlamwarePlatformProtocol <NSObject>
- (void)disconnect;
@end

@interface RPDeviceManager : NSObject
+ (id<RPSlamwarePlatformProtocol>)connect:(NSString *)host withPort:(int)port;
@end
