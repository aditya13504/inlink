# InLink Mesh Identity Handshake v1

## Goal and trust model

Bind a temporary Android BLE transport address to a stable pseudonymous InLink
node ID only after the peer proves possession of a trusted Ed25519 signing key.
A BLE address is never an identity. The handshake does not automatically trust
unknown contacts and does not replace out-of-band fingerprint verification.

## Node ID

`node_id = base64url_no_padding(SHA-256(domain || signing_public_key || encryption_public_key))`

The domain is the fixed byte string `InLink-Mesh-HSK-v1\\0`. Both public keys
are 32 bytes. Node IDs are stable for the same key pair and contain no phone
number or account identifier.

## Challenge and proof

1. The verifier creates 32 cryptographically random bytes and tracks the
   base64url challenge for at most two minutes.
2. The claimant signs a canonical JSON object with exactly these fields:
   `version`, `challenge`, `node_id`, `signing_key`, `encryption_key`.
3. The proof includes those fields and `signature`; encoded input is capped at
   2 KiB and public keys/signature have strict lengths.
4. The verifier consumes the challenge, checks expiry and canonical encoding,
   derives the node ID, matches both keys to an already verified contact,
   verifies the Ed25519 signature, then and only then binds the BLE address.
5. Challenges are single-use and bounded to 256 outstanding entries.

The signature covers a fixed domain separator followed by UTF-8 JSON generated
from the fields in the defined insertion order. Implementations must preserve
the field order when generating canonical bytes. Unknown fields are rejected.

## Limitations and deployment notes

- Run this exchange in both directions to authenticate both peers mutually.
- The challenge-response proves key possession but is not a key exchange, a
  ratchet, or forward secrecy. E2EE envelopes still require their existing
  signature and authenticated decryption checks.
- The trusted contact list must originate from the existing user-verified
  fingerprint flow; never auto-approve a contact based on radio discovery.
- The implementation currently keeps outstanding challenges in memory, which
  is appropriate for short-lived handshakes but means process death restarts
  the exchange.
- Do not use BLE MAC addresses as persistent contact IDs.
