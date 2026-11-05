# Identity persistence and contact verification

## Included

- `IdentityVault`: stores identity private-key material with `flutter_secure_storage`.
- `loadOrCreateIdentity`: avoids silently generating a new identity on each launch.
- Public contact bundle parsing and fingerprint computation.
- Explicit fingerprint confirmation before a contact is marked verified.
- Saved verified-contact records and tests for serialization/verification.

## Developer checks

Run from `app/`:
```powershell
flutter pub get
flutter analyze
flutter test
```
The code generator has not run these commands. Resolve dependency/API or lint
issues before using this code.

## Contact verification flow

1. User A exports the public bundle only; private identity material must never be shared.
2. User B imports the bundle and sees its fingerprint.
3. Both users compare the fingerprint over a separate trusted channel, in person
   or by a channel they already trust.
4. Only after the comparison should the user call `verifyFingerprint` and save
   the returned `VerifiedInLinkContact`.
5. An unverified imported bundle must not be used to authenticate a sender.

The short fingerprint is for convenient comparison, not a replacement for a
formal key transparency system. Never accept a contact automatically just
because the bundle arrived through BLE, a QR code, or a relay.

## Limitations

- No QR scanner/generator or contact-management UI yet.
- The code stores key bytes in OS-backed secure storage but does not implement
  hardware-bound keys, backup/recovery, biometric gating, key rotation, or
  multi-device sync.
- Existing encrypted messages may become unreadable if identity keys are deleted.
- Independent security review remains mandatory before release.
