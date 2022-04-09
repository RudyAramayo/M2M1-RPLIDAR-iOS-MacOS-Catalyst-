//
//  RPRobotHealthError.h
//  uicommander
//
//  Created by AlanLv on 8/18/16.
//  Copyright © 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RPSlamwareEnums.h"


@interface RPHealthError : NSObject

@property (nonatomic, assign) int errorId;
@property (nonatomic, assign) BaseErrorLevel errorLevel;
@property (nonatomic, assign) BaseErrorComponent errorComponent;
@property (nonatomic, assign) int componentErrorCode;
@property (nonatomic, assign) int errorCode;
@property (nonatomic, strong) NSString *errorMessage;

@property (nonatomic, assign) BaseComponentErrorType componentErrorType;
@property (nonatomic, assign) int componentErrorDeviceId;

- (instancetype) initWithId:(int)id
              andErrorLevel:(BaseErrorLevel)level
          andErrorComponent:(BaseErrorComponent)component
           andComponentCode:(int)componentCode
               andErrorCode:(int)errorCode
                 andMessage:(NSString*)message
      andComponentErrorType:(BaseComponentErrorType)componentType
                andDeviceId:(int)deviceId;

@end
