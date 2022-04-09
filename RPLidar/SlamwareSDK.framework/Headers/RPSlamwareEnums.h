//
//  RPSlamwareEnums.h
//  uicommander
//
//  Created by Tony Huang on 4/11/16.
//  Copyright © 2016 Shanghai Slamtec Co., Ltd. All rights reserved.
//

#pragma once

/// The data type of map
typedef enum {
    /// The map is a bitmap whose cells are 8bit signed integers
    RPMapTypeBitmap8Bit
} RPMapType;

/// The usage of the map
typedef enum {
    /// The map is an exploring map built by SLAM algorithm
    RPMapKindExploreMap = 0,

    /// The map is a sweep map containing metadata for sweep operation
    RPMapKindSweepMap = 10
} RPMapKind;

/// Action status
typedef enum {
    /// The action has been created but waiting for start
    RPActionStatusWaitingForStart,

    /// The action is running
    RPActionStatusRunning,

    /// The action is finished successfully
    RPActionStatusFinished,

    /// The action has been paused
    RPActionStatusPaused,

    /// The action has been stopped
    RPActionStatusStopped,

    /// The action has met some error
    RPActionStatusError
} RPActionStatus;

/// Different ways to discover Slamware-based devices
typedef enum {
    /// Discover device by BLE
    RPDiscoveryModeBle,

    /// Discover device by mDNS
    RPDiscoveryModeMdns
} RPDiscoveryMode;

/// Different modes to restart Slamware Core module
typedef enum {
    /// Fast, soft restart
    RPRestartModeSoft,

    /// Slow, cleaner restart
    RPRestartModeHard
} RPRestartMode;

/// Manual control operations
typedef enum {
    /// Make robot move forward
    RPMoveDirectionForward,

    /// Make robot move backward
    RPMoveDirectionBackward,

    /// Make robot turn right
    RPMoveDirectionTurnRight,

    /// Make robot turn left
    RPMoveDirectionTurnLeft
} RPMoveDirection;

// ArtifactUsage
typedef enum {
    // Virtual wall
    RPArtifactUsageVirtualWall,

    // Virtual track
    RPArtifactUsageVirtualTrack
} RPArtifactUsage;

// RPSleepMode
typedef enum {
    // for legacy base
    RPSleepModeUnknown,

    // Slamware is not sleeping
    RPSleepModeAwake,

    // Slamware is waking up
    RPSleepModeWakingUp,

    // Slamware is asleep
    RPSleepModeAsleep
} RPSleepMode;

// RPDockingStatus
typedef enum {
    RPDockingStatusUnknown,

    RPDockingStatusOnDock,

    RPDockingStatusNotOnDock
} RPDockingStatus;

// NetworkMode
typedef enum {
    RPNetworkModeAP,
    RPNetworkModeStation,
    RPNetworkModeWifiDisabled,
    RPNetworkModeDHCPDisabled,
    RPNetworkModeDHCPEnabled
} RPNetworkMode;

// ImpactSensorType
typedef enum {
    RPImpactSensorTypeDigital,
    RPImpactSensorTypeAnalog
} RPImpactSensorType;

// SensorType
typedef enum {
    RPSensorTypeBumper,
    RPSensorTypeCliff,
    RPSensorTypeSonar,
    RPSensorTypeDepthCamera,
    RPSensorTypeWallSensor,
    RPSensorTypeUnknown
} RPSensorType;

// MoveOptionFlag
typedef NS_OPTIONS(NSInteger, RPMoveOptionFlag) {
    RPMoveOptionFlagNone = 0,
    RPMoveOptionFlagAppending = 1,
    RPMoveOptionFlagMilestone = 2,
    RPMoveOptionFlagNoSmooth = 4,
    RPMoveOptionFlagKeyPoints = 8,
    RPMoveOptionFlagPrecise = 16,
    RPMoveOptionFlagWithYaw = 32,
    RPMoveOptionFlagReturnUnreachableDirectly = 64
};

// RecoverLocalizationMovement
typedef enum {
    RPRecoverLocalizationMovementUnknown,
    RPRecoverLocalizationMovementNoMove,
    RPRecoverLocalizationMovementRotateOnly,
    RPRecoverLocalizationMovementAny,
    RPRecoverLocalizationNone,
} RPRecoverLocalizationMovement;

// MapLayerType
typedef enum {
    RPMapLayerTypeGridMap,
    RPMapLayerTypeLineMap,
    RPMapLayerTypePointsMap,
    RPMapLayerTypePoseMap
} RPMapLayerType;

// base error level
typedef NS_ENUM(NSInteger, BaseErrorLevel) {
    BaseErrorLevelHealthy,
    BaseErrorLevelWarn,
    BaseErrorLevelError,
    BaseErrorLevelFatal,
    BaseErrorLevelUnknown = 255
};

// base error component
typedef NS_ENUM(NSInteger, BaseErrorComponent) {
    BaseErrorComponentUser,
    BaseErrorComponentSystem,
    BaseErrorComponentPower,
    BaseErrorComponentMotion,
    BaseErrorComponentSensor,
    BaseErrorComponentUnknown = 255
};

// Base Component Error Type
typedef NS_ENUM(NSInteger, BaseComponentErrorType) {
    BaseComponentErrorTypeUnknown = -1,

    // User
    BaseComponentErrorTypeUser = (1024 * 1),

    // System
    BaseComponentErrorTypeSystemNone = (1024 * 2),
    BaseCompoenntErrorTypeSystemEmergencyStop,
    BaseComponentErrorTypeSystemTemperatureHigh,
    BaseComponentErrorTypeSystemTemperatureLow,
    BaseComponentErrorTypeSystemWatchDogOverFlow,
    BaseComponentErrorTypeSystemCtrlBusDisconnected,
    BaseComponentErrorTypeSystemSlamwareRebooted,
    BaseComponentErrorTypeSystemBrakeReleased,
    BaseComponentErrorTypeSystemSlamwareRelocalizationFailed,

    // Power
    BaseComponentErrorTypePowerNone = (1024 * 3),
    BaseComponentErrorTypePowerControllerDown,
    BaseComponentErrorTypePowerPowerLow,
    BaseComponenterrorTypePowerOverCurrent,

    // Motion
    BaseComponentErrorTypeMotionNone = (1024 * 4),
    BaseComponentErrorTypeMotionControllerDown,
    BaseComponentErrorTypeMotionMotorAlarm,
    BaseComponentErrorTypeMotionMotorDown,
    BaseComponentErrorTypeMotionOdometryDown,
    BaseComponentErrorTypeMotionBrushStall,
    BaseComponentErrorTypeMotionBlowerStall,

    // Sensor
    BaseComponentErrorTypeSensorNone = (1024 * 5),
    BaseComponentErrorTypeSensorControllerDown,
    BaseComponentErrorTypeSensorBumperDown,
    BaseComponentErrorTypeSensorCliffDown,
    BaseComponentErrorTypeSensorSonarDown,
    BaseComponentErrorTypeSensorDustbinBlock,
    BaseComponentErrorTypeSensorDustbinGone,
    BaseComponentErrorTypeSensorWallIrDown,
    BaseComponentErrorTypeSensorMagTapeTriggered,
    BaseComponentErrorTypeSensorMagSelfTestFailed,
    BaseComponentErrorTypeSensorIMUDown
};

#define kRPSlamwareSystemParameterRobotSpeed @"base.max_moving_speed"
#define kRPSlamwareSystemParameterRobotSpeedHigh @"high"
#define kRPSlamwareSystemParameterRobotSpeedMedium @"medium"
#define kRPSlamwareSystemParameterRobotSpeedLow @"low"
