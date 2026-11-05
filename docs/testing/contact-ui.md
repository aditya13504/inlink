# Identity and contact UI (M2.3)

## Included UI
- Identity & contacts page accessible from the main app toolbar.
- QR code display for the public identity bundle only.
- Public bundle JSON import.
- Fingerprint display and explicit out-of-band fingerprint confirmation.
- Verified contact list and remove action.

## Not yet included
- QR scanning with camera permissions.
- A cryptographically designed QR payload expiry/signature or URI scheme.
- Secure export/import workflow for private keys (private keys must not be exported to contacts).
- Contact key-change warnings, revocation, multi-device identity, or a full messaging UI.

## Validate
From `app/` run `flutter pub get`, `flutter analyze`, `flutter test`, then build
on Android and iOS. These checks have not been run by the code-generation environment.
The `qr_flutter` dependency is used only to render the public bundle QR code.
