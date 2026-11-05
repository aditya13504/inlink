# M4.12 — Flutter verification pipeline

## Changes

- CI now records `flutter doctor -v`, checks Dart formatting, runs static analysis,
  runs unit/widget tests with expanded output, and builds the Android debug APK.
- Successful CI runs upload `app/build/app/outputs/flutter-apk/app-debug.apk` as
  the `inlink-android-debug` artifact for seven days.
- `scripts/verify_flutter.sh` runs the same local verification sequence and stops
  immediately if a step fails or Flutter is missing.

## How to verify locally

From the repository root:

```bash
./scripts/verify_flutter.sh
```

Requirements: Flutter stable, Dart bundled with Flutter, Android SDK/platform tools,
and Android build dependencies accepted/configured.

## What counts as verified

- A green workflow run proves formatting, analyzer, Flutter tests, and debug APK
  build passed for that commit and CI toolchain.
- A debug APK build does not prove BLE behavior on physical devices.
- Physical Android device tests and an independent cryptographic/security review
  remain release gates.

## Current environment result

This working environment does not have `flutter` or `dart` on PATH, so the Flutter
unit tests, analyzer, and APK build could not be executed here. The CI workflow and
local script are prepared for execution in a configured environment; they are not
claimed to have passed.
