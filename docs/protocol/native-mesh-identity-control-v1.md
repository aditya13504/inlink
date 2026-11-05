# Native Mesh Identity Control Channel v1

## Purpose

This control channel authenticates an already-connected BLE transport address against an identity the user previously verified. It does not establish trust from discovery alone and does not replace end-to-end message encryption.

## Framing

Control messages are UTF-8 JSON, encoded into the existing version-1 `BleFrame` fragmentation format. The reassembled control message is limited to 2,048 bytes. The receiver rejects unknown fields and malformed frame encodings.

### Challenge

```json
{"version":1,"kind":"challenge","challenge":"<canonical-base64url-32-byte-nonce>"}
```

The challenge creator retains the challenge locally for at most two minutes and consumes it on verification attempt. A challenge is not accepted as a node identity or proof of trust.

### Proof wrapper

```json
{"version":1,"kind":"proof","proof":"<MeshIdentityHandshake signed proof JSON>"}
```

The signed proof includes the challenge, deterministic pseudonymous node ID, signing public key, encryption public key, and Ed25519 signature over the domain-separated canonical proof fields. The verifier checks the challenge is outstanding and unexpired, checks the deterministic node ID, verifies the signature, and matches both public keys and fingerprint against an existing verified contact before binding the current BLE address.

## Mutual exchange

Both sides independently send a fresh challenge when a link becomes ready. A side responds to a received challenge only if it has already initiated its own challenge on that address. Each side verifies the other side's proof against a previously verified contact before binding the address. A proof contains public identity keys and a signature; those keys are public material, so this exchange does not provide identity concealment from a connected radio peer.

## State handling

- One outstanding local challenge per transport address in the manager.
- Duplicate readiness events do not start multiple simultaneous challenges.
- Disconnect clears the address binding, challenge state, and partial control reassembly for that address.
- A malformed, expired, replayed, conflicting, or untrusted proof is rejected without binding.
- BLE address is never serialized as a stable node ID or used for routing.
- Control messages may be observed by the BLE peer and are not a substitute for privacy against radio-level traffic analysis.

## Limitations

The implementation uses the existing Android GATT transport and its single serialized frame queue. Physical-device interoperability, GATT role asymmetry, background restrictions, reconnect behavior, and simultaneous peer load must be validated on supported Android versions. iOS support is not included in v1.
