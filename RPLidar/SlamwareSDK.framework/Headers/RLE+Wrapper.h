//
//  RLE.h
//  uicommander
//
//  Created by AlanLv on 6/29/16.
//  Copyright © 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface RLEWrapper : NSObject

+ (NSData*)encode:(NSData*)data;
+ (NSData*)decode:(NSData*)data;

@end