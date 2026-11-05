# M12 Closure — Cross-Platform Transport and Reliability

## Delivered in this source package

- Added a CoreBluetooth transport implementation in `app/ios/Runner/AppDelegate.swift`, using the same InLink service and characteristic UUIDs as Android.
- The iOS transport implements the existing method-channel contract: `getCapabilities`, `startBle`, `stopBle`, `getConnectedPeers`, `sendBleFrame`, and `sendBleFrameToPeer`.
- iOS can operate as both a BLE central and peripheral: scan for the InLink service, connect, discover the frame characteristic, subscribe to notifications, advertise the local service, accept writes, and notify subscribed peers.
- Added bounded outgoing frame queueing, targeted sends, connection cleanup, send failure on disconnect/stop, radio-state error reporting, and MTU-size checks.
- Added Bluetooth usage descriptions to `Info.plist`.
- Added Dart method-channel contract tests for shared event stream, platform capability parsing, connected peer enumeration, targeted send bytes, and frame-size rejection.
- Added this milestone's transport interoperability contract, test matrix, and release tracker updates.

## Cross-platform contract

- Service UUID: `9F3A1000-7B4D-4F3C-9A12-2F6E1A000001`.
- Frame characteristic UUID: `9F3A1001-7B4D-4F3C-9A12-2F6E1A000001`.
- A transport handle is local to that device and connection. It is not an InLink identity. The signed challenge/proof handshake and pinned contact verification remain mandatory.
- A successful native send result means local GATT write/notification acceptance, not end-to-end delivery. Only the authenticated recipient receipt may set a message to delivered.
- The iOS native implementation uses a UUID handle from CoreBluetooth rather than a MAC address. The mesh directory deliberately treats both as opaque local handles.

## Validation performed here

- Swift frontend syntax parsing passed for `AppDelegate.swift` using `swiftc -frontend -parse`.
- M12 source-contract checks are included in `scripts/validate_m12_source.py`.
- Python relay source compilation and existing relay tests are run during packaging.

## Validation not performed

- Flutter/Dart SDK is unavailable in the packaging environment. `dart format`, `flutter pub get`, `flutter analyze`, `flutter test`, and Flutter platform builds were not run.
- The current repository's `app/ios` directory contains only `Runner/AppDelegate.swift` and `Runner/Info.plist`; a complete generated Xcode project/workspace and CocoaPods scaffold are absent. Therefore this archive includes the iOS native transport source but cannot be built as an iOS app until the normal Flutter iOS project scaffold is generated and the source is integrated.
- Swift parsing is not the same as type-checking against the iOS SDK or Flutter framework.
- No physical iPhone/Android interoperability test was possible.
- iOS background BLE behavior, device MTU negotiation, reconnect, battery use, and three-peer limits are unverified.
- No iOS BLE background modes are enabled by default. This avoids implying reliable background operation before product and battery testing.

## Required acceptance gates

1. On a macOS host, generate/restore the Flutter iOS project scaffold, integrate the Runner files, run `flutter pub get`, `flutter analyze`, `flutter test`, and `flutter build ios --no-codesign`.
2. Build Android debug and iOS app from the same source revision.
3. Test Android-to-iOS and iOS-to-Android short frames, fragmented message envelopes, disconnects, permission denial, Bluetooth power-off/on, and reconnect.
4. Confirm native peer handles differ across platforms but each local handle is bound only after the signed proof matches a previously verified contact.
5. Confirm GATT send acceptance never triggers a delivered state without an authenticated recipient receipt.
6. Test a three-device topology, simultaneous peers, send queue saturation, and app lifecycle transitions.
7. Review privacy disclosures and background behavior before enabling iOS background modes or claiming continuous mesh availability.
