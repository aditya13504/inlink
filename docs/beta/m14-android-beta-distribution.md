# Android Beta Distribution Runbook

## Before building

1. Use a clean checkout at a recorded commit.
2. Pin and record Flutter, Dart, Java, Android Gradle Plugin, and Android SDK versions.
3. Run `flutter pub get`, formatting checks, `flutter analyze`, `flutter test`, and the existing source
   validators.
4. Confirm Android application ID, version name, version code, minimum/target SDK, app label, and
   permissions against the approved release record.
5. Inspect the merged manifest and exported components. Document the privacy purpose of Bluetooth,
   nearby-device, and notification permissions where applicable.

## Build and inspect

From `app/` on a configured Android build host:

```bash
flutter build apk --release
# For Play Console distribution, build an app bundle if the project's Android setup supports it:
flutter build appbundle --release
```

These commands are instructions, not evidence that a build has passed. Inspect and test the actual
artifact before distributing it. Use the team's protected signing configuration; never put signing
secrets in source control or in the ZIP.

## Internal distribution

- Prefer a restricted internal-testing track or an access-controlled artifact channel.
- Invite only approved testers and record the artifact checksum, commit, version, and build date.
- Verify installation, update, uninstall, permission denial, BLE operation, relay operation, receipts,
  and restart recovery on supported physical devices.
- Share known issues and the beta limitations notice with every invitation.
- Revoke access or replace the build if a stop trigger is reached.

## Release evidence record

Record: commit SHA, artifact SHA-256, build environment, signing identity identifier (not its secret),
test run links, supported device/OS matrix, open issues, approver, and distribution track.
