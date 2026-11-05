# Milestone 6 — Durable Mesh Queue and Multi-Peer Android BLE

## What this milestone adds

- A separate SQLCipher-backed mesh queue with a random 256-bit key held in platform secure storage.
- Transactional enqueue, route-key deduplication, immutable-content conflict detection, bounded capacity (maximum 256), expiry pruning, and attempted-peer persistence. Attempts are reset on process recovery because local BLE acceptance is not an end-to-end receipt.
- Startup restoration into the in-memory routing engine with strict packet validation.
- Android GATT support for up to three outbound client connections plus the platform's connected inbound GATT peers; targeted frame sends are addressed to a current BLE transport handle.
- A Flutter adapter that maps authenticated InLink node IDs to current BLE addresses, fragments opaque mesh packets with the existing BLE frame format, and sends fragments sequentially.
- Tests for queue restoration behavior and verified peer directory validation.

## Security boundaries

- BLE addresses are transport handles, **not** identities. `VerifiedBlePeerDirectory.bindAfterAuthentication` must only be called after the app has completed a cryptographically authenticated identity handshake. This milestone does not implement that handshake.
- The routing layer forwards only opaque E2EE envelopes. Intermediate relays do not decrypt message content.
- Native write/notification acceptance is only local transport acceptance, not recipient delivery. Remove a durable route only after authenticated application-level completion (for example, the existing verified receipt flow).
- SQLCipher protects queue data at rest, but the queue key must remain recoverable from platform secure storage. If that key is lost, the encrypted queue is not recoverable; the app must report that condition rather than silently create a replacement database.
- This is an experimental foreground transport. Android OS limits, radio collisions, vendor GATT behavior, and background execution can interrupt connections. No always-on mesh guarantee is made.

## Current integration boundary

The native method channel exposes `getConnectedPeers`, `sendBleFrameToPeer`, and the existing receive event stream. `NativeMeshPeerTransport` expects a verified node-ID/address directory. The caller must bind identities after authenticated contact verification, process incoming `frameReceived` events through `MessageFrameReassembler`, decode the completed packet, and invoke the E2EE verification/delivery pipeline. The full receive-to-chat flow is not enabled automatically by this milestone.

## Validation gates

1. Run `flutter pub get`, `dart format app/lib app/test`, `flutter analyze`, and `flutter test` on a Flutter-enabled machine.
2. Build Android debug and release variants with the repository's supported Android SDK/JDK.
3. Test at least four physical Android phones in a star topology; test outbound peer cap, multiple inbound peers, targeted sends, fragmentation/reassembly, disconnects during fragments, and duplicate fragments.
4. Kill/restart the app and confirm pending packets and attempted-peer metadata recover from SQLCipher.
5. Verify that a forged BLE address cannot be bound to a node without the E2EE identity handshake.
6. Test authenticated receipt removal and expiry cleanup, including a process kill between local transport acceptance and queue metadata update.

Until these gates pass, treat M6 as implementation-complete at source level but device verification pending—not as production-ready.
