# M2M1-RPLIDAR-iOS-MacOS-Catalyst-
M2M1 RPLidar by Slamware. Here is a working MacOSX Catalyst sample so that my Mac mini droid ROB can function with the lidar. Its a shame the library is not compiled for MacOSX arm64. There are Xcode complaints due to the usage of UIKit in the SlamwareSDK.framework. The only way around is to use MacOSX Catalyst to build the app and make it transmit data via the AutoNet. AutoNet is the automagic networking library that will instantly give you access to the nodes of the network with no hassle.

https://www.slamtec.com/en/Support#rplidar-mapper

## Secure Cerebro publishing

RPLidar now discovers only `_robctl._udp` and publishes compact binary scans to
Cerebro. On the same Mac, scan bytes prefer a protected local Unix-domain IPC
socket; authenticated TLS 1.3 QUIC remains connected and takes over
automatically whenever local delivery is unavailable. The Cerebro certificate
is pinned and a reciprocal HMAC pairing proof completes before publishing.
Full occupancy/composite maps stay local and are never sent over ROBControl.
There is no automatic plaintext or `_roboNet._tcp` fallback.

1. In Cerebro, issue a new per-device credential with role
   `lidarPublisher`. Do not reuse the ROBController/operator credential.
2. Launch RPLidar, select **Pair RPLidar…**, and paste the complete `ROBCTL2:`
   code. It is stored in this app's Keychain and is never logged.
3. Confirm the overlay reads **authenticated / Lidar publisher** before relying
   on the feed.
4. Revoke the device in Cerebro when retiring or replacing it. **Forget Local
   Pairing** only removes this app's local Keychain copy; it is not revocation.

If Cerebro reports that it replaced or migrated its server certificate, every
RPLidar credential that pinned the previous certificate must be re-enrolled.
In Cerebro, revoke the old RPLidar entry and issue a fresh **Lidar Publisher**
code. In RPLidar, choose **Replace Pairing…** and paste the new code. Certificate
pin or explicit credential rejection now stops automatic retries and displays
**re-pair required** instead of remaining indefinitely at **reconnecting**.

`ROB_CONTROL_PAIRING_SECRET` remains available as a startup-only developer
bootstrap when this app has never had a Keychain credential. A stored Keychain
code is always authoritative, and either **Replace Pairing…** or **Forget Local
Pairing** permanently disables environment bootstrap. An old Xcode
launch-scheme value therefore cannot restore or overwrite a credential later.

## Map controls

- **Save Map…** captures the current bitmap map and droid pose together and
  exports a `.robomap` file with the system file picker.
- **Load Map…** validates a `.robomap`, installs the map and saved pose while
  mapping/localization are paused, and then runs Slamware relocalization over
  the saved map. Keep the area clear because the droid may move or rotate.
- A loaded map stays locked against updates for localization accuracy. Use
  **Reset Map** to cancel recovery, clear the active map, and resume live
  mapping. Saved files are not deleted by a reset.

## Headless passthrough and development GUI

The lidar connection, polling, authenticated frame-7 publishing, reconnects,
and periodic map storage are owned by a UI-independent passthrough service.
Opening or dismissing the GUI therefore does not start or stop the lidar feed.

Wire scans use the fixed-layout `RLS1` format: a 68-byte pose/identity header
plus four bytes per valid return (millimeters and angle). A 720-point scan is
2,948 bytes and roughly 14.7 KB/s at 5 Hz before transport overhead. Both local
IPC and QUIC allow one send in flight and retain only the newest pending scan,
preventing a slow receiver or Wi-Fi link from creating a stale ordered-stream
backlog.

### Same-Mac local transport

RPLidar and Cerebro share the App Group
`group.com.orbitusrobotics.rob`. Cerebro owns
`rplidar-cerebro-v1.sock` in that group container and RPLidar reconnects to it
in the background. A ready local connection receives the exact `RLS1` payload
without using an IP interface. A missing endpoint falls through to QUIC
immediately; an asynchronous local-send failure forwards the newest
undelivered sample to QUIC and keeps using the network until local IPC returns.

Cerebro resolves the embedded device UUID against its server-owned pairing
registry and verifies a 32-byte HMAC-SHA256 made with that publisher's existing
pairing secret for every local sample. It then applies the same role,
revocation, sequence, freshness, and rate checks as the network path. Enable
`group.com.orbitusrobotics.rob` for both app identifiers in the Apple Developer
portal and regenerate their provisioning profiles. If the App Group container
cannot be opened, QUIC remains the safe default.

The pairing overlay shows the live publishing route: green **LOCAL IPC • FAST**
means scans use the same-Mac socket, orange **QUIC FALLBACK** means scans use
the authenticated network path while local IPC reconnects, and red
**DISCONNECTED** means neither transport is currently ready. When local IPC is
active, the badge also reports whether QUIC standby is ready or reconnecting.

This project cannot call Mach-service NSXPC directly because SlamwareSDK makes
it an iPhoneOS/Designed-for-iPad target and those XPC APIs are unavailable on
iOS. The App Group Unix socket is the supported low-overhead local IPC path for
the shipping target. True NSXPC would require a native macOS or Mac Catalyst
SlamwareSDK binary first.

- Debug builds register `ROBDevelopmentMode` as enabled and open the map GUI,
  matching Cerebro's development-mode behavior.
- Release builds register Development Mode as disabled and keep the
  storyboard-managed window hidden while the passthrough service continues.
- The **RPLidar** menu always offers **Open RPLidar Map**, even when Development
  Mode is disabled. Its checkmarked **Development Mode** item controls only
  whether the map opens automatically on future launches.
- `--rplidar-gui` and `--rplidar-headless` override that default. The
  `RPLIDAR_GUI` environment variable accepts `1`/`true` or `0`/`false` as an
  alternate override.

Headless means the UIKit map-rendering view is torn down before it receives
lidar snapshots; the tracked window remains available for the explicit menu
command. This remains an iOS app, so iOS can still suspend its process after it
enters the background; it is not an unrestricted system daemon.

The GUI now uses ROBController's `ROBOpenStreetMapView` as its live main map:
OpenStreetMap tiles, the ROB location, lidar returns, occupancy imagery, and the
selected destination share one surface. Tap the map to select a point, use
**Search destination** for Nominatim place search, or open **Destinations…** to
review the persistent **Recent Destinations** table. Rows can be deleted and
the history can be cleared. These are local diagnostic selections. RPLidar
retains its restricted `lidarPublisher` credential and does not send
operator/navigation commands.

The bundled SlamwareSDK framework contains iPhoneOS armv7/arm64 slices and
imports UIKit. The project builds for iOS and can run on supported Apple-silicon
Macs as an iPad/iPhone app, but it is not a native macOS or true Mac Catalyst
binary. A native/Catalyst deployment requires a SlamwareSDK build containing
the corresponding platform slice.

Works for iOS as well. Will be used in my ROBOKit compilation of apps for the ROB droid.

<img width="1316" height="835" alt="Screenshot 2025-07-30 at 8 02 28 PM" src="https://github.com/user-attachments/assets/32139d18-d4d5-4338-9a7e-6af155fedcb8" />
