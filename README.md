# M2M1-RPLIDAR-iOS-MacOS-Catalyst-
M2M1 RPLidar by Slamware. Here is a working MacOSX Catalyst sample so that my Mac mini droid ROB can function with the lidar. Its a shame the library is not compiled for MacOSX arm64. There are Xcode complaints due to the usage of UIKit in the SlamwareSDK.framework. The only way around is to use MacOSX Catalyst to build the app and make it transmit data via the AutoNet. AutoNet is the automagic networking library that will instantly give you access to the nodes of the network with no hassle.

https://www.slamtec.com/en/Support#rplidar-mapper

Works for iOS as well. Will be used in my ROBOKit compilation of apps for the ROB droid.

