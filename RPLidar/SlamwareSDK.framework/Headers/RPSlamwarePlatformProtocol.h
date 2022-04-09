//
//  RPSlamwarePlatformProtocol.h
//  uicommander
//
//  Created by Tony Huang on 4/11/16.
//  Copyright © 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RPSlamwareEnums.h"
#import "RPMap.h"
#import "RPRectangleF.h"
#import "RPPose.h"
#import "RPLocation.h"
#import "RPActionProtocol.h"
#import "RPMoveActionProtocol.h"
#import "RPSweepMoveActionProtocol.h"
#import "RPRectangleF.h"
#import "RPPath.h"
#import "RPLaserScan.h"
#import "RPLine.h"
#import "RPFirmwareUpdateInfo.h"
#import "RPFirmwareUpdateProgress.h"
#import "RPScheduleTask.h"
#import "RPHealthInfo.h"
#import "RPPowerStatus.h"
#import "RPMoveOption.h"
#import "RPRecoverLocalizationOptions.h"
#import "RPPointPDF.h"
#import "RPCompositeMap.h"
#import "RPImpactSensorInfo.h"
#import "RPImpactSensorValue.h"

@protocol RPSlamwarePlatformProtocol <NSObject>

//
// Connection Handling
//

/// Disconnect form the Platform */
- (void) disconnect;

//
// Device Info
//

/*!
    @brief Get device id
    @return an NSUUID of device id
 */
- (NSUUID* _Nullable) deviceId;

/*!
    @brief Get device manufacturer id
    @return An integer of manufacturer id
 */
- (int) manufacturerId;

/*!
    @brief Get device manufacturer name
    @return A string of manufacture name
 */
- (NSString* _Nullable) manufacturerName;

/*!
    @brief Get device model id
    @return An integer of model id
 */
- (int) modelId;

/*!
    @brief Get device model name
    @return A string of model name
 */
- (NSString* _Nullable) modelName;

/*!
    @brief Get device hardware version
    @return A string of hardware version
 */
- (NSString* _Nullable) hardwareVersion;

/*!
    @brief Get device software version
    @return A string of software version
 */
- (NSString* _Nullable) softwareVersion;

//
// Map APIs
//

/*!
    @brief Get available map types in Slamware
    @return A list of map type (please convert members to RPMapType enum)
 */
- (nonnull NSArray<NSNumber*>*) availableMaps;

/*!
    @brief Get map data from Slamware
    @param type The data type of the map
    @param rect Required area of the map
    @param kind The kind of the map
    @return The partial map object
 */
- (nonnull RPMap*) getMapWithMapType:(RPMapType)type inArea:(nonnull RPRectangleF*)rect ofMapKind:(RPMapKind)kind;

/*!
    @brief Upload map data to the Slamware (Notice: should be used with setPose, and with map update and localization stopped)
    @param map The map object
    @param type The data type of the map
    @param kind The kind of the map
 */
- (void) setMapWithMap:(nonnull RPMap*)map ofMapType:(RPMapType)type andMapKind:(RPMapKind)kind;

/*!
    @brief Get the known area of the map
    @param type The data type of the map
    @param kind The kind of the map
    @return The explored area of the map
 */
- (nonnull RPRectangleF*) getKnownAreaOfMapType:(RPMapType)type andMapKind:(RPMapKind)kind;

/// Clear current map
- (void) clearMap;

//
// Robot Pose
//

/*!
    @brief Get the position of robot in the map coordinate system
    @return The location of the robot
 */
- (nonnull RPLocation*) location;

/*!
    @brief Get the pose of the robot (including location and rotation)
    @return The pose of the robot
 */
- (nonnull RPPose*) pose;

/*!
    @brief Set the pose of the robot
    @param _pose The new pose of the robot
 */
- (void) setPose:(nonnull RPPose*)_pose;

/*!
 * @brief Get the position of robot home in the map coordinate system
 * @return
 */
- (nullable RPPose*) homePose;

//
// Mapping and Localization
//

/**
 * Get if the Slamware is doing localization
 * @return A boolean to indicate if the Slamware is doing localization
 */
- (BOOL) mapLocalization;

/**
 * Enable or disable localization
 * @param v A boolean to indicate if the Slamware should do localization
 */
- (void) setMapLocalization:(BOOL)v;

/**
 * Get if the Slamware is updating map
 * @return A boolean to indicate if the Slamware is updating map
 */
- (BOOL) mapUpdate;

/**
 * Enable or disable map update
 * @param v A boolean to indicate if the Slamware should update map
 */
- (void) setMapUpdate:(BOOL)v;

/**
 * Get localization quality
 */
- (int) localizationQuality;

//
// Movement
//

/**
 * Make robot move to a series of points
 * @param locs The points to visit
 * @param appending A boolean to indicate if Slamware should clear current tasks or append these point to the visit list
 * @param isMilestone A boolean to indicate if Slamware should plan a route to the points or go directly to the point
 * @return The move action to manipulate this operation
 */
- (nullable id<RPMoveActionProtocol>) moveToLocations:(nonnull NSArray<RPLocation*>*)locs andAppendingToCurrentTask:(BOOL)appending andSetAsMilestones:(BOOL)isMilestone;

/**
 * Make robot move to a specific point
 * @param loc The point to visit
 * @param appending A boolean to indicate if Slamware should clear current tasks or append these point to the visit list
 * @param isMilestone A boolean to indicate if Slamware should plan a route to the points or go directly to the point
 * @return The move action to manipulate this operation
 */
- (nullable id<RPMoveActionProtocol>) moveToLocation:(nonnull RPLocation*)loc andAppendingToCurrentTask:(BOOL)appending andSetAsMilestones:(BOOL)isMilestone;

/**
 * Make robot move to a specific point
 * @param loc The point to visit
 * @param moveOption Move option
 * @param yaw Yaw
 * @return The move action to manipulate this operation
 */
- (nullable id<RPMoveActionProtocol>) moveToLocation:(nonnull RPLocation*)loc withMoveOption:(RPMoveOption*)moveOption andYaw:(float)yaw;

/**
 * Make robot move to a series of points
 * @param locs The points to visit
 * @param moveOption Move topion
 * @param yaw Yaw
 * @return The move action to manipulate this operation
 */
- (nullable id<RPMoveActionProtocol>) moveToLocations:(nonnull NSArray<RPLocation*>*)locs withMoveOption:(RPMoveOption*)moveOption andYaw:(float)yaw;

/**
 * Manual control robot's movement (notice: this action will not do any obstacle avoidance).
 * You have to invoke this API repeat to keep the robot move, and call MoveAction.cancel() to
 * stop the movement in time, or the robot will stop after a period of last moveBy call.
 * @param direction Which type of movement you want the robot do
 * @return The move action to manipulate this operation
 */
- (nullable id<RPMoveActionProtocol>) moveBy:(RPMoveDirection)direction;

/**
 * Manual control robot's movement (notice: this action will not do any obstacle avoidance)
 * You have to invoke this API repeat to keep the robot move, and call MoveAction.cancel() to
 * stop the movement in time, or the robot will stop after a period of last moveBy call.
 * This interface is usually used by the trackball.
 * @param theta The relative yaw difference according to the current robot yaw
 * @param moveOption Move option
 * @return The move action to manipulate this operation
 */
- (nullable id<RPMoveActionProtocol>) moveBy:(float)theta withMoveOption:(RPMoveOption*)moveOption;

/**
 * Make robot rotate a specific pose
 * @param orientation Required pose
 * @return The move action to manipulate this operation
 */
- (nullable id<RPMoveActionProtocol>) rotateToOrientation:(nonnull RPRotation*)orientation;

/**
 * Make robot rotate a specific angle (differential)
 * @param offset The rad the robot required to rotate
 * @return The move action to manipulate this operation
 */
- (nullable id<RPMoveActionProtocol>) rotateBy:(nonnull RPRotation*)offset;

//
// Current Action
//

/**
 * Get robot current action
 */
- (nullable id<RPMoveActionProtocol>) currentAction;

//
// Path Finding
//

/**
 * Search a path in the map from robot's current position to the required location
 * @param location The target location
 * @return A path from robot's current location to the target location
 */
- (nonnull RPPath*) searchPathToLocation:(nonnull RPLocation*)location;

//
// Power Management
//

/**
 * Get the left percentage of the battery (from 0 ~ 100)
 * @return The battery percentage
 */
- (int) batteryPercentage;

/**
 * Get if the battery is charging
 * @return A boolean to indicate if the battery is charging
 */
- (BOOL) batteryIsCharging;

/**
 * Get if the robot is _connected with a outlet
 * @return A boolean to indicate if the robot is _connected to the charger
 */
- (BOOL) dcIsConnected;

//
// System Versions
//

/**
 * Get the version of Slamware
 * @return The version string of the Slamware
 */
- (nonnull NSString*) slamwareVersion;

/**
 * Get the version of Slamware SDK
 * @return The version string of the Slamware SDK
 */
- (nonnull NSString*) sdkVersion;

//
// Laser Scan
//

/**
 * Get the most recent LASER scan
 * @return The most recent LASER scan
 */
- (nonnull RPLaserScan*) laserScan;

//
// Virtual Walls
//

/**
 * Get existing virtual walls
 * @return A list of existing virtual walls
 */
- (nonnull NSArray<RPLine*>*) walls;

/**
 * Add a virtual wall to Slamware
 * @param wall The virtual wall to add
 */
- (void) addWall:(nonnull RPLine*)wall;

/**
 * Add a set of virtual walls to Slamware
 * @param walls Virtual walls to add
 */
- (void) addWalls:(nonnull NSArray<RPLine*>*)walls;

/**
 * Remove specific virtual wall
 * @param wallId The id to the virtual wall to remove
 */
- (void) clearWallById:(NSInteger)wallId;

/**
 * Remove all virtual walls from Slamware
 */
- (void) clearWalls;

//
// Sweep
//

/**
 * Make robot to start sweep (Notice: This method is only available on Slamware Core Vacuum Robot Edition)
 * @return The sweep move action to manipulate this operation
 */
- (nullable id<RPSweepMoveActionProtocol>) startSweep;

/**
 * Make robot to sweep a particular area (Notice: This method is only available on Slamware Core Vacuum Robot Edition)
 * @return The sweep move action to manipulate this operation
 */
- (nullable id<RPSweepMoveActionProtocol>) sweepSpot:(nonnull RPLocation *)location;

//
// Auto Home
//

/**
 * Make robot go back to the charging base (Notice: This method is only available on robots which support auto home feature)
 * @return The move action to manipulate this operation
 */
- (nullable id<RPMoveActionProtocol>) goHome;

//
// Module operations
//

/**
 * Restart the Slamware module
 * @param mode The mode to restart Slamware module
 */
- (void) restartModuleWithMode:(RPRestartMode)mode;

//
// System parameters
//

/**
 * Set system parameter
 * @param name The parameter to set
 * @param value The value you want to set
 */
- (void) setSystemParameterNamed:(nonnull NSString*)name withValue:(nonnull NSString*)value;

/**
 * Get system parameter
 * @param name The parameter to get
 * @return The current value of the parameter
 */
- (nonnull NSString*) valueOfSystemParameterNamed:(nonnull NSString*)name;

//
// Firmware update
//

/**
 * Get firmware update info
 * @return firmware update info
 */
- (RPFirmwareUpdateInfo *) getFirmwareUpdateInfo;

/**
 * Start firmware update
 */
- (void) startFirmwareUpdate;

/**
 * Get firmware update progress
 * @return firmware update progress
 */
- (RPFirmwareUpdateProgress *) getFirmwareUpdateProgress;

//
// Schedule task
//

/**
 * Get scheduled task
 * @return an NSArray of RPScheduleTask
 */
- (NSArray<RPScheduleTask *> *) getScheduledTasks;

/**
 * Add a schedule task
 * @param task the schedule task to add
 * @return YES for adding successfully, NO for adding failing
 */
- (BOOL) addScheduledTask:(RPScheduleTask *)task;

/**
 * Get a specific schedule task
 * @param id the id of the schedule task
 * @return the schedule task
 */
- (RPScheduleTask *) getScheduledTaskWithId:(int)id;

/**
 * Update a schedule task
 * @param task the schedule task to add
 * @return the updated schedule task
 */
- (RPScheduleTask *) updateScheduledTask:(RPScheduleTask *)task;

/**
 * Delete a schedule task
 * @param id the deleting schedule task id
 * @return YES for deleting successfully, NO for deleting failing
 */
- (BOOL) deleteScheduledTaskWithId:(int)id;

/**
 * get robot health
 * @return RPHealthInfo
 */
- (RPHealthInfo *) getRobotHealth;

/**
 * Clear an error
 * @param errorCode: errorCode in RPHealthError
 */
- (void) clearRobotHealth:(int)errorCode;

/**
     * configure network
     * @param mode NetworkMode. see NetworkMode class.
     * @param options network configuration
     * @return success or failure
 */
- (BOOL) configureNetworkWithMode:(RPNetworkMode)mode andOptions:(nonnull NSDictionary<NSString*, NSString*>*)options;

/**
 * Get network status
 * @return network status
 */
- (nonnull NSDictionary<NSString*, NSString*>*) getNetworkStatus;

/**
 * get lines
 * @param usage line usage
 * @return an array of RPLine.
 */
- (NSArray<RPLine*>*) getLines:(RPArtifactUsage)usage;

/**
 * Add a line
 * @param usage line usage
 * @param line RPLine
 * @return success of failure
 */
- (BOOL) addLine:(RPArtifactUsage)usage withLine:(RPLine*)line;

/**
 * Add lines
 * @param usage line usage
 * @param lines an array of RPLine
 * @return success or failure
 */
- (BOOL) addLines:(RPArtifactUsage)usage withLines:(NSArray<RPLine*>*)lines;

/**
 * Remove a specific line
 * @param usage line usage
 * @param lineId the line id
 * @return success or failure
 */
- (BOOL) removeLineById:(RPArtifactUsage)usage withLineId:(NSInteger)lineId;

/**
 * Clear lines
 * @param usage line usage
 * @return success or failure
 */
- (BOOL) clearLines:(RPArtifactUsage)usage;

/**
 * Recover localization
 * @param area Current area
 * @return RPMoveActionProtocol
 */
- (id<RPMoveActionProtocol>) recoverLocalization:(RPRectangleF *)area;

/**
 * Recover localization
 * @param area Current area
 * @param opts Recover localization options
 * @return IMoveAction
 */
- (nullable id<RPMoveActionProtocol>) recoverLocalizationWithCurrentArea:(RPRectangleF*)area andRecoverLocalizationOptions:(RPRecoverLocalizationOptions*)options;

/**
 * Get power status
 * @return PowerStatus
 */
- (RPPowerStatus *) getPowerStatus;

/**
 * Wake up slamware
 */
- (void) wakeUp;

/**
 * Get aux location
 * @return Aux Location
 */
- (nonnull RPPointPDF*) auxLocation;

//
// CompositeMap
//

/**
 * get composite map
 * @return composite map
 */
- (nonnull RPCompositeMap*) compositeMap;

/**
 * set composite map
 * @param mapData composite map
 * @param pose robot pose
 */
- (void) setCompositeMapWithMapData:(nonnull RPCompositeMap*)mapData andPose:(nonnull RPPose*)pose;

//
// sensors
//

/**
 * get list of info of sensors
 * @return List of ImpactSensorInfo
 */
- (NSArray<RPImpactSensorInfo*>*) sensors;

/**
 * get sensor values
 * @return Map of Sensor ID and ImpactSensorValue
 */
- (NSDictionary<NSNumber*, RPImpactSensorValue*>*) sensorValues;

/**
 * get sensor value by given id
 * @param sensorId Integer
 * @return ImpactSensorValue
 */
- (nullable RPImpactSensorValue*) sensorValueById:(NSNumber*)sensorId;

/**
 * read composite map from a stcm file
 * @param filePath Must be an app-container file path.
 * @return RPCompositeMap if read succeeds, return an RPCompositeMap object. if fails, return nil.
 */
- (nullable RPCompositeMap*)readCompositeMap:(nonnull NSString*)filePath;

/**
 * save composite map to a specific file path
 * @param mapData RPCompositeMap
 * @param filePath must be an app-container file path.
 * @return NSString if read succeeds, return nil. if fails, the NSString object represents the failure reason.
 */
- (nullable NSString*)saveCompositeMap:(nonnull RPCompositeMap *)mapData andFilePath:(nonnull NSString*)filePath;

@end
