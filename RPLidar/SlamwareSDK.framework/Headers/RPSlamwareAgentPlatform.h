//
//  RPSlamwareCorePlatform.h
//  uicommander
//
//  Created by Tony Huang on 4/11/16.
//  Copyright © 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RPSlamwarePlatformProtocol.h"

@interface RPSlamwareAgentPlatform : NSObject<RPSlamwarePlatformProtocol> {
}

+ (nonnull instancetype) platformByConnectToHost:(nonnull NSString*)host andPort:(int)port;
+ (nonnull instancetype) platformByConnectToHost:(nonnull NSString*)host;

//
// Connection Handling
//

- (void) disconnect;

//
// Map APIs
//

- (nonnull NSArray<NSNumber*>*) availableMaps;
- (nonnull RPMap*) getMapWithMapType:(RPMapType)type inArea:(nonnull RPRectangleF*)rect ofMapKind:(RPMapKind)kind;
- (void) setMapWithMap:(nonnull RPMap*)map ofMapType:(RPMapType)type andMapKind:(RPMapKind)kind;
- (nonnull RPRectangleF*) getKnownAreaOfMapType:(RPMapType)type andMapKind:(RPMapKind)kind;
- (void) clearMap;

//
// Robot Pose
//

- (nonnull RPLocation*) location;
- (nonnull RPPose*) pose;
- (void) setPose:(nonnull RPPose*)_pose;
- (nullable RPPose*) homePose;

//
// Mapping and Localization
//

- (BOOL) mapLocalization;
- (void) setMapLocalization:(BOOL)v;
- (BOOL) mapUpdate;
- (void) setMapUpdate:(BOOL)v;
- (int) localizationQuality;

//
// Movement
//

- (nullable id<RPMoveActionProtocol>) moveToLocations:(nonnull NSArray<RPLocation*>*)locs andAppendingToCurrentTask:(BOOL)appending andSetAsMilestones:(BOOL)isMilestone;
- (nullable id<RPMoveActionProtocol>) moveToLocation:(nonnull RPLocation*)loc andAppendingToCurrentTask:(BOOL)appending andSetAsMilestones:(BOOL)isMilestone;
- (nullable id<RPMoveActionProtocol>) moveToLocation:(nonnull RPLocation*)loc withMoveOption:(RPMoveOption*)moveOption andYaw:(float)yaw;
- (nullable id<RPMoveActionProtocol>) moveToLocations:(nonnull NSArray<RPLocation*>*)locs withMoveOption:(RPMoveOption*)moveOption andYaw:(float)yaw;
- (nullable id<RPMoveActionProtocol>) moveBy:(RPMoveDirection)direction;
- (nullable id<RPMoveActionProtocol>) moveBy:(float)theta withMoveOption:(RPMoveOption*)moveOption;
- (nullable id<RPMoveActionProtocol>) rotateToOrientation:(nonnull RPRotation*)orientation;
- (nullable id<RPMoveActionProtocol>) rotateBy:(nonnull RPRotation*)offset;

//
// Current action
//

- (nullable id<RPMoveActionProtocol>) currentAction;

//
// Path Finding
//

- (nonnull RPPath*) searchPathToLocation:(nonnull RPLocation*)location;

//
// Power Management
//

- (int) batteryPercentage;
- (BOOL) batteryIsCharging;
- (BOOL) dcIsConnected;

//
// System Versions
//

- (nonnull NSString*) slamwareVersion;
- (nonnull NSString*) sdkVersion;

//
// Laser Scan
//

- (nonnull RPLaserScan*) laserScan;

//
// Virtual Walls
//

- (nonnull NSArray<RPLine*>*) walls;
- (void) addWall:(nonnull RPLine*)wall;
- (void) addWalls:(nonnull NSArray<RPLine*>*)walls;
- (void) clearWallById:(NSInteger)wallId;
- (void) clearWalls;

//
// Sweep
//

- (nullable id<RPSweepMoveActionProtocol>) startSweep;
- (nullable id<RPSweepMoveActionProtocol>) sweepSpot:(RPLocation *)location;

//
// Auto Home
//

- (nullable id<RPMoveActionProtocol>) goHome;

//
// Module operations
//

- (void) restartModuleWithMode:(RPRestartMode)mode;

//
// System parameters
//

- (void) setSystemParameterNamed:(nonnull NSString*)name withValue:(nonnull NSString*)value;
- (nonnull NSString*) valueOfSystemParameterNamed:(nonnull NSString*)name;

//
// read / write stcm
//

- (nullable RPCompositeMap*) readCompositeMap:(nonnull NSString*)filePath;
- (nullable NSString*) saveCompositeMap:(nonnull RPCompositeMap*)map andFilePath:(nonnull NSString*)filePath;

@end
