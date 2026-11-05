# M2.5 — Verified contact and encrypted-message integration

## Implemented source
- Fingerprints now display 128 bits (16 SHA-256 bytes) in both local and imported identity flows.
- Saved contact records validate fingerprint format and key lengths on load.
- `VerifiedMessageService.sealToVerifiedContact` accepts a verified contact object and uses its encryption public key.
- `VerifiedMessageService.openFromVerifiedContact` pins the sender signing key to the verified contact, validates the envelope signature and recipient key through the existing envelope implementation, then decrypts.
- `ReplayProtectionStore` persists SHA-256 identifiers for accepted envelope bytes in OS-backed secure storage, bounded to 4,096 recent identifiers by default.
- The replay identifier is recorded only after successful authentication/decryption.

## Integration notes
This service is an API foundation; the current app does not yet have a conversation composer, message database, or inbound delivery pipeline wired to it. Inbound message processing must be serialized to avoid concurrent check/record races. The bounded cache means very old messages may be replayable after their identifiers are evicted. These are explicit prototype limitations.

## Validation checklist
From `app/`:
1. `flutter pub get`
2. `flutter analyze`
3. `flutter test`
4. `flutter build apk --debug`
5. Test on two physical devices: create identities, verify each other's 128-bit fingerprints independently, send an envelope using the service, receive/decrypt with the verified contact, and reject a repeated envelope.
6. Verify a forged sender key and wrong recipient are rejected.
7. Inspect platform secure storage/backup settings before production release.

## Security warning
The existing envelope scheme uses ephemeral X25519 per message but does not provide a Double Ratchet, forward secrecy after recipient long-term private-key compromise, multi-device sessions, key transparency, or a reviewed protocol implementation. Do not deploy as production E2EE without adopting a well-reviewed protocol/library and independent security review.
