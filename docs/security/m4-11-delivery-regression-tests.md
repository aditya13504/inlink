# M4.11 — Delivery and transport regression tests

## Regression found and fixed

The legacy-message fallback ID is `in-` plus `base64UrlEncode(SHA256(envelope))`.
Dart's base64url encoding includes a trailing `=` for a 32-byte SHA-256 digest.
The M4.10 message-ID validator rejected `=`, so a valid receipt for a legacy
fallback ID could be rejected. The validator now allows at most one terminal
padding character while still rejecting embedded or repeated padding.

## Added tests

- Accept generated hex IDs and padded base64url fallback IDs.
- Reject empty, oversized, delimiter-bearing, embedded-padding, and repeated-padding IDs.
- Reject malformed receipt digests.
- Conflicting duplicate BLE fragments discard the partial transfer and release buffered bytes.
- Conflicting fragment counts discard the partial transfer and release buffered bytes.

## Existing invariants retained

- The receipt is processed only after envelope authentication/decryption.
- Receipt lookup is scoped to the authenticated sender and outgoing direction.
- A receipt must target the local identity and match a sent-envelope digest.
- Transport acceptance never transitions a message to delivered.
- Partial BLE transfers are bounded and are cleared on disconnect/recovery.

## Validation still required

Run `flutter test`, `flutter analyze`, and the Android build on a configured Flutter
toolchain. Exercise receipt delivery and BLE reconnect scenarios on two physical
devices. Relay unit tests do not validate Dart behavior or Android BLE callbacks.
