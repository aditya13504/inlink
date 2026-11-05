# iOS Beta / TestFlight Runbook

## Readiness blocker

The M12/M13 project snapshot contains iOS native source and `Info.plist`, but the archive closure
records that a complete generated Xcode project/workspace and Podfile are not present. Therefore
this runbook is a checklist, **not a claim that TestFlight distribution is currently possible**.
First create and review a complete Flutter iOS project scaffold, preserve the native CoreBluetooth
implementation and channel contracts, and validate it on a supported macOS/Xcode host.

## Once the project is buildable

1. Pin and record macOS, Xcode, Flutter, Dart, CocoaPods, and iOS deployment-target versions.
2. Confirm bundle identifier, version/build numbers, entitlements, usage descriptions, background
   modes (only if actually required and justified), privacy manifest requirements, and signing setup.
3. Run Flutter format/analyzer/tests and build the iOS app on macOS.
4. Validate signing, archive export, install, launch, permission denial, foreground/background behavior,
   BLE discovery and transfer, reconnect, authenticated receipts, and relay behavior on physical iOS
   devices.
5. Upload the signed build to App Store Connect using the team's authorized credentials.
6. Complete required beta app information, privacy disclosures, export-compliance answers, tester
   notes, and review requirements truthfully.
7. Start with internal TestFlight testers; expand only after review of test results and issues.

## Do not

- Commit certificates, private keys, provisioning profiles, API keys, or App Store Connect tokens.
- Claim iOS support until a real device build and the required transport acceptance tests pass.
- Enable background modes or collect diagnostics without a documented purpose and platform review.
