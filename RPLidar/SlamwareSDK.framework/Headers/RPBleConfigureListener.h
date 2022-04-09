//
//  RPBleConfigureListener.h
//  uicommander
//
//  Created by AlanLv on 5/9/16.
//  Copyright © 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

typedef NS_ENUM(NSInteger, RPBleError) {
    RPBleErrorBluetooth,
    RPBleErrorDisconnected,
    RPBleErrorInvalidDevice,
    RPBleErrorInvalidSsid,
    RPBleErrorInvalidPassword,
    RPBleErrorConfigurationFailed,
    RPBleErrorWifiConnectionFailed,
    RPBleErrorUnknown
};

@protocol RPBleConfigureListener <NSObject>

@required
- (void)onConfigureSuccess;

@required
- (void)onConfigureFailure:(RPBleError)error;

@end
