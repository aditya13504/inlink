# M4.7 — Android BLE permission lifecycle and device validation

## Source hardening

The Android method-channel handler now rejects a second `startBle` call while a
runtime Bluetooth permission request is already pending, instead of overwriting
the first method result and potentially leaving its Dart future unresolved.
Permission success is rechecked against the current permission state. If the
activity is destroyed while the prompt is open, the pending result receives an
explicit error.

This is source-level hardening only. Android compilation and device behavior
have not been verified in the packaging environment.

## Two-device setup

- Install the same debug build on two physical Android devices.
- Use Android 12+ (API 31+) on at least one device; ideally test both devices on
  Android 12+ and repeat on Android 11 or lower if those versions are supported.
- Keep the devices unlocked for initial foreground testing.
- Enable Bluetooth on both devices and accept the requested permissions.
- Keep logs free of private keys, plaintext messages, and other sensitive data.

## Required test cases

| ID | Procedure | Pass condition |
|---|---|---|
| AND-01 | Start BLE with permissions already granted | Method call completes; started/scanning/advertising events appear |
| AND-02 | Start BLE without permissions | Permission prompt appears and one result completes |
| AND-03 | Trigger a second start call while permission prompt is pending | Second call fails explicitly; first call remains resolvable |
| AND-04 | Deny one requested permission | Dart receives `ble_permission_denied`; no false started state |
| AND-05 | Destroy/recreate activity while permission prompt is open | Pending call is completed with an explicit error |
| AND-06 | Bluetooth disabled | Clear `bluetooth_disabled` error |
| AND-07 | Two devices scan/advertise in foreground | Peer-found and connection events are visible on the expected side |
| AND-08 | Send a frame larger than 194 bytes | Rejected before native BLE transfer |
| AND-09 | Disconnect during frame transfer | Active/queued transfer fails clearly; app does not claim message delivery |
| AND-10 | Stop BLE | Scan, advertising and GATT resources are closed |
| AND-11 | Revoke permissions in Settings and restart BLE | A new permission flow occurs; no crash |
| AND-12 | Repeat 20 connect/disconnect cycles | No stuck connection, unbounded queue growth, or false delivery receipt |

## Build and test

```bash
cd app
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

Then install the APK on two devices and execute AND-01 through AND-12. Capture
Android logs and record device model, OS/API level, build hash, result, and any
error code. Do not treat relay server tests as evidence of BLE hardware success.

## Status

- [x] Guard against multiple overlapping BLE permission prompts.
- [x] Recheck permissions after the runtime permission callback.
- [x] Fail a pending start call explicitly if the activity is destroyed.
- [x] Add a repeatable Android device acceptance matrix.
- [ ] Run Flutter analysis/tests and Android build in CI.
- [ ] Complete two-device hardware validation.
