# M11 Closure — Native Multi-Peer Mesh Integration

## Delivered

- Added `NativeMeshHandshakeManager`, a bounded, fragmented control channel over the existing Android BLE frame transport. Each side issues a fresh challenge and returns a signed identity proof.
- The manager binds a BLE transport address to a stable InLink node ID only after `MeshIdentityHandshake.verifyAndBind` validates the fresh challenge, signature, deterministic node ID, and matching previously verified contact keys/fingerprint.
- Control payloads are size-limited, require exact v1 field sets, use the existing strict frame decoder/reassembler, and fail closed on malformed, expired, replayed, untrusted, or conflicting proofs. Error handling deliberately avoids logging control payloads or identity material.
- Added `NativeMeshRuntime`, which composes the identity vault, shared SQLCipher conversation repository, verified-message service, durable mesh queue/router, targeted native multi-peer transport, authenticated ingress, and mesh application service.
- Added `NativeMeshConversationsRoute` and wired the Android Conversations entry point to it. The runtime is explicitly disposed with the route. The same `LocalMessageRepository` instance is shared by the chat UI and mesh message store.
- Native BLE is **not** auto-started by this route. The user must start BLE explicitly from the home screen and grant platform permissions.
- Updated adapter comments and added protocol and physical-device acceptance documentation.

## Security boundaries

- A BLE address is a temporary transport handle, never a cryptographic identity.
- Only contacts already verified and stored by InLink can bind to a mesh node ID. Unknown peers cannot become trusted through radio discovery alone. The handshake proof contains public identity keys and may be visible to a connected peer; this version does not conceal identity from radio peers.
- A successful GATT write means only local transport acceptance. The UI must not show `delivered` until the authenticated recipient receipt is verified.
- Mesh packets remain end-to-end encrypted; intermediate nodes can observe timing, packet size, and transport metadata.
- This remains an experimental messaging protocol. It does not implement a Double Ratchet, forward secrecy per message, group messaging, metadata protection, audited key transparency, or a production-grade background execution strategy.
- Android multi-peer BLE is bounded and OS/device dependent. iOS native BLE multi-peer mesh integration is not implemented in this milestone.

## Validation status

- Source archive integrity and Python relay tests are checked during packaging.
- Flutter/Dart SDK is not installed in the packaging environment, so `dart format`, `flutter analyze`, `flutter test`, and Android Gradle compilation cannot be truthfully reported as passed.
- No physical Android device pair was available here. Live BLE discovery, bilateral challenge/proof exchange, fragmentation, reconnect behavior, receipt processing, and multi-hop delivery remain device acceptance gates.

## Required acceptance before calling this beta-ready

1. On two Android devices, import each other's verified contact identity through the existing trusted contact flow.
2. Start BLE on both devices and open Conversations on both. Confirm the fresh bilateral challenge/proof exchange binds only the expected contact keys to each current BLE address.
3. Repeat with an untrusted third device. It must not appear as a bound peer and must not be able to submit a valid mesh packet as a trusted origin.
4. Exchange short and maximum-supported text messages in both directions; interrupt Bluetooth during fragmented sends and confirm retries do not falsely report delivery.
5. Confirm only a valid, signed, encrypted recipient receipt transitions an outgoing mesh message to `delivered`.
6. Force-stop/restart the app and verify pending route metadata is restored from SQLCipher without plaintext message content in the mesh queue.
7. Test three devices with A and C not directly connected but both linked to B. Confirm store-and-forward behavior only when a usable route exists.
8. Test permission denial, Bluetooth disabled, disconnect/reconnect, stale challenge, replayed proof, malformed frames, and route disposal.
9. Run `dart format lib test`, `flutter pub get`, `flutter analyze`, `flutter test`, and Android debug build on a Flutter-enabled host.
