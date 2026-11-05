# Android BLE M1 experiment

## Scope

This change adds an experimental Android BLE advertiser/scanner, GATT service,
frame write/notify path, runtime permission handling, and Flutter method/event
channels. It is **not production-ready** and has not been compiled or tested on
physical devices in this environment.

Only synthetic test frames should be sent. BLE framing is not encryption,
authentication, replay protection, or reliable delivery.

## Flutter API

`NativeNetworkTransport` exposes:
- `startBle()`
- `stopBle()`
- `sendBleFrame(Uint8List frame)`
- `events`, a broadcast stream of native event maps

Expected events include `started`, `scanning`, `advertising`, `peerFound`,
`peerConnected`, `readyToSend`, `frameReceived`, `frameSent`,
`peerDisconnected`, `permissionDenied`, `error`, and `stopped`.

The native channel names are `inlink/network` and `inlink/network-events`. The client requests ATT MTU 247 before service discovery because the v1 frame can be 194 bytes; actual negotiated MTU depends on both devices.

## Important repository limitation

The starter repository currently contains only selected native source files; it
does not contain a complete generated Flutter Android project (Gradle wrapper,
Gradle build files, resources, and full iOS project). Run `flutter create .`
from the `app/` directory only after backing up existing files, or generate a
clean Flutter project and merge these source files carefully. Do not overwrite
the existing `lib/` or native implementation.

The manifest included here is a template to merge into the manifest generated
by Flutter. Its launcher icon and themes refer to standard generated resources.

## Local setup

1. Install Flutter SDK and Android Studio/Android SDK.
2. Generate/complete the Flutter platform scaffolding as described above.
3. Merge `app/android/app/src/main/AndroidManifest.xml` into the generated manifest.
4. From `app/`, run:
   ```bash
   flutter pub get
   flutter analyze
   flutter test
   flutter build apk --debug
   ```
5. Install the debug build on two Android phones. Grant requested Bluetooth
   permissions, turn Bluetooth on, tap the app's BLE start action (the current
   scaffold UI does not yet provide this control), and inspect logs/events.
6. Exercise a one-frame transfer in each direction using synthetic bytes.
   Record phone models, Android versions, RSSI, connection time, payload size,
   failures, and reconnection behavior.

## Known prototype limitations

- The app UI is not yet wired to expose start/stop/send controls.
- It attempts one outgoing GATT connection at a time and is not a mesh router.
- It does not implement transfer fragmentation/reassembly, retry queues, pairing,
  identity, encryption, receipts, relay infrastructure, or background service.
- BLE advertising and scanning behavior varies by vendor and OS version.
- iOS support is not implemented by this change.
- Android background operation is not guaranteed.
- Treat all incoming bytes as untrusted. The eventual message layer must
  authenticate frames and enforce quotas before routing or storing them.
