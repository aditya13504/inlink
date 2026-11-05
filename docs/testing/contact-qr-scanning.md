# M2.4 — QR contact import and key-change warnings

## Implemented in source
- `mobile_scanner` camera-based QR scanner returns the raw QR payload only.
- The payload is parsed as an InLink public identity bundle before use.
- QR scanning does **not** verify a person or automatically trust a key.
- Users must compare the full displayed fingerprint through a separate trusted channel.
- Same display name + different fingerprint triggers a warning. The existing contact is not replaced; users must cancel or use a different name for a separately verified identity.
- Android declares `CAMERA`; the scanner plugin handles its runtime permission request.
- iOS requires `NSCameraUsageDescription`. This repository currently lacks a complete Xcode Runner project; merge the included key into the generated Runner `Info.plist` if regenerating platform scaffolding.

## Manual verification
1. Run `flutter pub get`, `flutter analyze`, and `flutter test` from `app/`.
2. Run on a physical Android phone and grant camera access.
3. On a second device, open **Your pseudonymous identity** and scan its QR from the first device.
4. Confirm the imported fingerprint is shown and that no contact is saved until the fingerprint is independently confirmed.
5. Enter a wrong fingerprint and confirm save fails.
6. Add a verified contact, then try importing a different key under the same display name. Confirm the warning appears and the original record remains unchanged.
7. Deny camera permission and verify the user can cancel and use paste-import instead.

## Security notes
- QR codes contain public keys only. Do not put private key material, account tokens, or message content in the QR payload.
- A fingerprint match only helps authenticate a key when the comparison channel is independently trusted.
- The current fingerprint is 64 bits (8 SHA-256 bytes), which is suitable only for this prototype; increase it to at least 128 bits before production and update the display/verification UX.
- This remains a prototype. No Flutter dependency resolution, analyzer, test suite, platform build, or device test was executed while preparing this change.
