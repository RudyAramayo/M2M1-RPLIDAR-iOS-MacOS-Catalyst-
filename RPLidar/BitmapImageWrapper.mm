//
//  BitmapImageWrapper.m
//  RPLidar
//
//  Created by Rob Makina on 9/30/23.
//  Copyright © 2023 OrbitusRobotics. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BitmapImageWrapper.h"
#import "BitmapImage.hpp"
@implementation HelloWorldWrapper
- (NSString *) sayHello {
    HelloWorld helloWorld;
    std::string helloWorldMessage = helloWorld.sayHello();
    return [NSString
            stringWithCString:helloWorldMessage.c_str()
            encoding:NSUTF8StringEncoding];
}
@end
