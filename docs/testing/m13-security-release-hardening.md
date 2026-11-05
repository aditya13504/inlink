# M13 Test Plan — Security & Release Hardening

Run from the repository root:

```bash
python scripts/validate_m11_source.py
python scripts/validate_m12_source.py
python scripts/validate_m13_security.py
python -m compileall -q relay
python -m pytest -q relay/tests
```

On a configured Flutter host:

```bash
cd app
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --reporter expanded
flutter build apk --debug
```

Security CI additionally runs Bandit and `pip-audit` against relay dependencies.

## Manual / environment-dependent gates

- Run CI from a clean checkout and inspect the exact workflow revision and logs.
- Build and install Android on at least two supported devices; verify discovery, authenticated
  peer binding, frame transfer, receipt verification, reconnect, restart, and duplicate handling.
- Create and validate the iOS Xcode project on macOS; build on supported iOS versions.
- Test Android-to-iOS and iOS-to-Android BLE sessions, including disconnect, radio off/on,
  background/foreground, payload boundary, and malformed frame cases.
- Verify relay TLS, reverse-proxy body/time limits, rate limiting, database permissions, backups,
  expiry cleanup, log redaction, and abuse response in a deployment-like environment.
- Obtain an independent review of protocol canonicalization, key lifecycle, replay handling,
  cryptographic composition, and downgrade behavior.

A green source validator is not evidence that these manual gates passed.
