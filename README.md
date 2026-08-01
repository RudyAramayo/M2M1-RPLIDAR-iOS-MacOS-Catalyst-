# M2M1-RPLIDAR-iOS-MacOS-Catalyst-
M2M1 RPLidar by Slamware. Here is a working MacOSX Catalyst sample so that my Mac mini droid ROB can function with the lidar. Its a shame the library is not compiled for MacOSX arm64. There are Xcode complaints due to the usage of UIKit in the SlamwareSDK.framework. The only way around is to use MacOSX Catalyst to build the app and make it transmit data via the AutoNet. AutoNet is the automagic networking library that will instantly give you access to the nodes of the network with no hassle.

https://www.slamtec.com/en/Support#rplidar-mapper

## Secure Cerebro publishing

RPLidar now discovers only `_robctl._udp` and publishes typed frame-7 telemetry
over the same TLS 1.3 QUIC transport used by Cerebro. The Cerebro certificate is
pinned and a reciprocal HMAC pairing proof completes before any scan or map is
sent. There is no automatic plaintext or `_roboNet._tcp` fallback.

1. In Cerebro, issue a new per-device credential with role
   `lidarPublisher`. Do not reuse the ROBController/operator credential.
2. Launch RPLidar, select **Pair RPLidar…**, and paste the complete `ROBCTL2:`
   code. It is stored in this app's Keychain and is never logged.
3. Confirm the overlay reads **authenticated / Lidar publisher** before relying
   on the feed.
4. Revoke the device in Cerebro when retiring or replacing it. **Forget Local
   Pairing** only removes this app's local Keychain copy; it is not revocation.

The bundled SlamwareSDK framework contains iPhoneOS armv7/arm64 slices and
imports UIKit. The project builds for iOS and can run on supported Apple-silicon
Macs as an iPad/iPhone app, but it is not a native macOS or true Mac Catalyst
binary. A native/Catalyst deployment requires a SlamwareSDK build containing
the corresponding platform slice.

Works for iOS as well. Will be used in my ROBOKit compilation of apps for the ROB droid.

<img width="1316" height="835" alt="Screenshot 2025-07-30 at 8 02 28 PM" src="https://github.com/user-attachments/assets/32139d18-d4d5-4338-9a7e-6af155fedcb8" />
