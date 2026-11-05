# ADR-004: First end-to-end encryption prototype

- Status: Prototype; security review required
- Date: 2026-10-09

## Decision

Use the Dart `cryptography` package and its Flutter platform integration for a
small, testable E2EE prototype:
- Ed25519 signing key for message-origin authentication.
- X25519 recipient public key plus a fresh ephemeral X25519 key per message.
- HKDF-SHA-256 for deriving a 256-bit message key from the DH shared secret.
- ChaCha20-Poly1305 for authenticated encryption.
- A versioned, explicitly encoded header used as associated data and as part of
  the signature input.
- Contacts must pin/verify the sender's Ed25519 public key out of band (for
  example, compare a fingerprint during QR exchange). An unverified key does
  not establish identity.

Package references:
- https://pub.dev/packages/cryptography
- https://pub.dev/packages/cryptography_flutter

## Security properties and limitations

This prototype provides confidentiality and tamper detection for a single
recipient, plus signature verification against a previously trusted signing
key. It does **not** yet provide forward secrecy against compromise of the
recipient's long-term X25519 private key, a Double Ratchet, replay prevention,
message expiry, persistent encrypted key storage, backup/recovery, multi-device
identity, group encryption, or metadata protection. The envelope's JSON/base64
wire representation is not yet integrated with the BLE fragmenter.

Do not use this prototype for sensitive or safety-critical communication.
Before release, obtain independent cryptographic review and test vectors.
Do not invent a custom handshake or claim Signal-protocol-level security.
