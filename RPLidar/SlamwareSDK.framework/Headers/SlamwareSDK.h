//
//  SlamwareSDK.h
//  SlamwareSDK
//
//  Created by Tony Huang on 4/11/16.
//  Copyright © 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>

//! Project version number for SlamwareSDK.
FOUNDATION_EXPORT double SlamwareSDKVersionNumber;

//! Project version string for SlamwareSDK.
FOUNDATION_EXPORT const unsigned char SlamwareSDKVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <SlamwareSDK/PublicHeader.h>
#import "RPSlamwareEnums.h"
#import "RPActionProtocol.h"
#import "RPMoveActionProtocol.h"
#import "RPPath.h"
#import "RPLocation.h"
#import "RPLaserScan.h"
#import "RPSizeF.h"
#import "RPSize.h"
#import "RPRotation.h"
#import "RPRectangleF.h"
#import "RPRectangle.h"
#import "RPPose.h"
#import "RPMap.h"
#import "RPLaserPoint.h"
#import "RPSweepMoveActionProtocol.h"
#import "RPLine.h"
#import "RPAbstractDevice.h"
#import "RPMdnsDevice.h"
#import "RPBleDevice.h"
#import "RPPointF.h"
#import "RPPoint.h"
#import "RPAbstractDiscover.h"
#import "RPBleWifiInfo.h"
#import "RPBleConfigureListener.h"
#import "RPDeviceManager.h"
#import "RPSlamwarePlatformProtocol.h"
#import "RLE+Wrapper.h"
#import "RPDeviceManager+Connect.h"
#import "RPFirmwareUpdateInfo.h"
#import "RPFirmwareUpdateProgress.h"
#import "RPScheduleTask.h"
#import "RPHealthError.h"
#import "RPHealthInfo.h"
#import "RPPowerStatus.h"
#import "RPCompositeLine.h"
#import "RPCompositeMap.h"
#import "RPGridMapLayer.h"
#import "RPImpactSensorInfo.h"
#import "RPImpactSensorValue.h"
#import "RPLineMapLayer.h"
#import "RPMapLayer.h"
#import "RPMetaData.h"
#import "RPMoveOption.h"
#import "RPPointPDF.h"
#import "RPPointsMapLayer.h"
#import "RPRecoverLocalizationOptions.h"
#import "RPCompositePose.h"
#import "RPPoseMapLayer.h"
