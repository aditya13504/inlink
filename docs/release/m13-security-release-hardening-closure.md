# M13 Closure — Security & Release Hardening

## Delivered in source

- Updated `SECURITY.md` to reflect the current experimental architecture and a private-reporting
  workflow, without claiming an audit or production readiness.
- Added a security baseline and explicit production release blockers.
- Added `scripts/validate_m13_security.py` to check required guardrails, workflow permissions,
  source-control exclusions, and the release-gate language.
- Extended relay CI with source baseline checks, Bandit static analysis, and dependency advisory
  scanning through `pip-audit`.
- Kept existing relay tests and Flutter checks in place.

## Verification status

The closure is only complete for the source package and checks that can run in the available
environment. Record fresh test output with each release candidate.

- Relay pytest: run locally / CI.
- M11, M12, M13 source validators: run locally / CI.
- Python compileall: run locally / CI.
- Swift syntax parse and plist XML parse: syntax/config checks only, not an iOS app build.
- Flutter analyze/tests and Android APK build: require Flutter/Dart/Android toolchain and must pass
  in CI.
- iOS build: requires a complete Xcode project/workspace and macOS runner; not supplied by this
  milestone.
- Physical BLE, authenticated receipt, relay fallback, restart, and multi-peer mesh scenarios:
  require devices and remain mandatory acceptance gates.
- Independent security/cryptography review: not performed by this package.

## Release decision

**No production or public-beta security approval is implied.** M13 provides better repeatability
and clearer release gates; it does not close the outstanding platform, device, operational, or
independent-review requirements.
