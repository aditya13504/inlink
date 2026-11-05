# M12 Cross-Platform Transport Test Matrix

## Automated checks

From `app/` on a Flutter-enabled host:

```bash
dart format lib test
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

On macOS after the iOS Runner project is generated and integrated:

```bash
flutter build ios --no-codesign
```

The source package was not built with Flutter because Flutter/Dart are unavailable here. The Swift file was syntax-parsed only, not type-checked against iOS frameworks.

## Device matrix

| Scenario | Android ↔ Android | Android ↔ iOS | iOS ↔ iOS |
|---|---|---|---|
| Discovery and connection | Required | Required | Required |
| Bidirectional frame transfer | Required | Required | Required |
| 194-byte frame / negotiated MTU | Required | Required | Required |
| Verified-contact handshake | Required | Required | Required |
| Fragmented E2EE envelope | Required | Required | Required |
| Authenticated recipient receipt | Required | Required | Required |
| Disconnect during write | Required | Required | Required |
| Bluetooth off/on recovery | Required | Required | Required |
| Permission denial and re-enable | Required | Required | Required |
| Three connected peers | Required | Required | Required |
| Background/screen lock | Measure and document | Measure and document | Measure and document |

## Acceptance invariants

- No peer is trusted because it was discovered or connected.
- Transport handles are opaque, per-platform identifiers and must not be serialized as permanent identity.
- Native frame transfer success is not message delivery.
- Unsupported platform capabilities must be reported as false; the UI must retain the existing non-mesh path when native capability discovery fails.
- Queue overflow and MTU errors fail explicitly; they must not silently truncate or reinterpret frames.
- iOS background operation is not guaranteed and is not enabled by this milestone.
