# M7 — Authenticated Mesh Ingress Test Plan

## Automated tests authored

- Stable node ID derivation from the same public identity keys.
- Valid signature proof for a fresh challenge.
- BLE address binding occurs only after the trusted keys and signature verify.
- Unknown contacts do not get bound.
- Replayed/consumed challenge is rejected.
- Malformed or oversized proof is rejected.
- Existing relay regression suite remains part of the release check.

## Required before release

1. Run `flutter pub get`, `dart format app/lib app/test`, `flutter analyze`, and
   `flutter test` on a Flutter-enabled host.
2. Build the Android debug APK with the supported Android SDK.
3. On two physical Android devices, run challenge/proof in both directions and
   verify both node/address bindings.
4. Tamper with a signature, node ID, challenge, public key and JSON field set;
   each must fail closed without binding.
5. Verify a packet addressed to the local node is decrypted only after sender
   contact pinning, signature validation, authenticated decryption and replay
   checks.
6. Verify a relay node can forward opaque envelopes without possessing the
   recipient private key.
7. Disconnect during fragment transfer, reconnect, and verify incomplete
   assemblies are discarded and complete packets are deduplicated.
8. Validate battery use, Android permission denial/revocation, process death,
   and background/foreground transitions.

Flutter and Android toolchain results must be recorded from an actual CI or
developer machine. Source-only review is not a substitute for device tests.
