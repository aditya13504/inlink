# M4.6 — CI integration gates

## What changed

- Flutter CI now runs `flutter build apk --debug` after dependency resolution,
  formatting, static analysis, and Flutter tests.
- A separate relay workflow installs the pinned-range Python dependencies and
  runs the relay test suite on pushes and pull requests.
- Both workflows use read-only repository permissions where specified and run
  on hosted Ubuntu runners.

## What a green CI run will establish

- Dart sources meet the configured formatter/analyzer gates.
- Flutter unit/widget tests pass in the CI Flutter environment.
- The Android debug APK can be assembled in CI.
- Relay server tests pass in a clean Python environment.

## What CI does not establish

- Successful installation or BLE behavior on a physical Android device.
- iOS compilation or iOS background BLE behavior.
- Production security certification, cryptographic protocol audit, or battery
  performance.
- That the configured external relay is deployed or reachable.
- Successful end-to-end delivery between two actual app installations.

## First-run instructions

Push this archive's source to a Git repository and open the repository's
Actions tab. Wait for both **Flutter checks** and **Relay checks**. If either
workflow fails, treat its log as a blocking integration defect; do not describe
the milestone as build-verified until the jobs pass. The packaging environment
does not have Flutter or Dart, so these workflows have been authored but not
executed here.
