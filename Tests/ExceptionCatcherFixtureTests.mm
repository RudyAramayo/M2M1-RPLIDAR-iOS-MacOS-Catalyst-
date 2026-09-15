// clang++ -fobjc-arc -fobjc-arc-exceptions -fblocks -std=c++17 -I Tests/Support -I RPLidar -framework Foundation RPLidar/ExceptionCatcher.mm Tests/ExceptionCatcherFixtureTests.mm -o /tmp/rplidar-exception-tests
#import "ExceptionCatcher.h"
#import <SlamwareSDK/SlamwareSDK.h>
#include <stdexcept>

@interface FixturePlatform : NSObject <RPSlamwarePlatformProtocol>
@property BOOL disconnected;
@end

@implementation FixturePlatform
- (void)disconnect { self.disconnected = YES; }
@end

@implementation RPDeviceManager
+ (id<RPSlamwarePlatformProtocol>)connect:(NSString *)host withPort:(int)port {
    if ([host isEqualToString:@"objc"]) {
        [NSException raise:@"ConnectionFailException" format:@"Device went offline after the probe"];
    }
    if ([host isEqualToString:@"cpp"]) {
        throw std::runtime_error("SDK connection failure");
    }
    if ([host isEqualToString:@"unknown"]) { throw 42; }
    if ([host isEqualToString:@"nil"]) { return nil; }
    return [FixturePlatform new];
}
@end

static void expect(BOOL condition, NSString *message) {
    if (!condition) { throw std::runtime_error(message.UTF8String); }
}

int main() {
    @autoreleasepool {
        for (NSString *host in @[@"objc", @"cpp", @"unknown", @"nil"]) {
            NSError *error = nil;
            id platform = [ExceptionCatcher connectToHost:host port:1445 error:&error];
            expect(platform == nil && error != nil, @"SDK failure escaped the native boundary");
            expect(error.localizedDescription.length > 0, @"SDK failure lost its error message");
            if ([host isEqualToString:@"objc"]) {
                expect([error.localizedDescription isEqualToString:@"Device went offline after the probe"], @"Objective-C exception reason was lost");
            }
            if ([host isEqualToString:@"cpp"]) {
                expect([error.localizedDescription isEqualToString:@"SDK connection failure"], @"C++ exception reason was lost");
            }
        }
        NSError *error = nil;
        FixturePlatform *platform = (FixturePlatform *)[ExceptionCatcher connectToHost:@"ready" port:1445 error:&error];
        expect(platform != nil && error == nil, @"Successful connection was rejected");
        expect([ExceptionCatcher disconnectPlatform:platform error:&error] && platform.disconnected, @"Platform was not disconnected");

        expect(![ExceptionCatcher catchException:^{ throw std::runtime_error("poll failed"); } error:&error], @"Generic C++ failure escaped");
        expect(![ExceptionCatcher catchException:^{ [NSException raise:@"ScanFailure" format:@"poll failed"]; } error:&error], @"Generic Objective-C failure escaped");
        expect([ExceptionCatcher catchException:^{} error:nil], @"Successful SDK operation was rejected");
        puts("RPLidar native exception fixtures passed");
    }
}
