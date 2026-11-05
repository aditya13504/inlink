# E2EE prototype: development notes

## Included

- In-memory Ed25519 signing identity and X25519 encryption identity.
- Public identity bundle and short SHA-256 fingerprint.
- One-recipient envelope with ephemeral X25519 DH, HKDF-SHA-256,
  ChaCha20-Poly1305 AEAD, and Ed25519 signature.
- Strict envelope field lengths and version check.
- Tests for round-trip decryption, wrong trusted sender, wrong recipient,
  tampered ciphertext, and empty plaintext.

## Run on the developer machine

From `app/`:
```powershell
flutter pub get
flutter analyze
flutter test
```

These commands have not been run by the code-generation environment. If any
compile/test errors occur, fix them before adding persistent keys or integrating
this with BLE.

## Critical security notes

- Keys are generated in memory and are lost when the app restarts.
- The public-key fingerprint must be verified with the contact; a key delivered
  by an untrusted relay without verification can be substituted.
- There is no forward secrecy after compromise of a recipient's long-term
  encryption key. A future version needs a reviewed ratcheting protocol rather
  than an improvised one.
- No persistent key storage, replay cache, durable outbox, or BLE envelope
  fragmentation is included.
- Do not send real private data with this prototype.
