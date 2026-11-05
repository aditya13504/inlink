> Historical snapshot: this page records the original M3.0 integration. For current retry, receipt, queue, and transport-hardening behavior, read `reliable-delivery-m3-1.md`, `reliable-delivery-m3-2.md`, and `android-transport-hardening-m3-3.md`.

# M3 — BLE encrypted-envelope transport integration

## Included in source
- `MessageFrameTransfer` fragments an already-encrypted envelope into the existing versioned BLE frames.
- `MessageFrameReassembler` accepts out-of-order fragments, tolerates identical duplicates, rejects conflicting fragments/counts, limits concurrent partial transfers and expires stale partial transfers.
- Conversations screen can start/stop native BLE and send a queued/failed encrypted envelope frame-by-frame.
- Incoming frames are reassembled, parsed as an encrypted envelope, matched to a locally verified sender signing key, and decrypted through `VerifiedMessageService`. Unverified senders and invalid/replayed envelopes are rejected.
- Outgoing status changes to `IN_TRANSIT` only after Android accepts every frame; a send failure marks the message `FAILED`.

## Do not misinterpret status
Android accepting a GATT write/notification is not proof of radio delivery, remote reassembly, successful decryption, or user receipt. There is no authenticated application-level acknowledgement yet. Do not mark sender-side messages `DELIVERED` until a signed/authenticated recipient receipt protocol is implemented.

## Known limitations
- Native Android implementation supports an experimental single client GATT connection plus server notifications. It is not a robust multi-peer mesh.
- The existing native BLE sender's accepted callback is not a per-frame remote acknowledgement; no end-to-end retry protocol exists.
- BLE frames are unauthenticated until the complete envelope is authenticated. Reassembly limits memory but still requires real-device stress testing.
- Reassembly is in-memory only; incomplete transfers are discarded on a detected disconnect/stop and otherwise expire after the configured age.
- Internet relay and multi-hop routing are not implemented. Delivery receipts and retry queues exist in later milestones, but they are foreground-only prototypes.
- Current encrypted-message envelope is still a prototype; use a reviewed E2EE protocol/library before production.
- Flutter/Dart analyzer, tests, APK build, and physical-device tests were not run in the generation environment.

## Validation
1. Run `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build apk --debug`.
2. On two physical Android devices, verify fingerprints in person/out-of-band.
3. Start BLE on both; wait for `peerConnected`/`readyToSend`.
4. Send a short and a long encrypted message; verify complete plaintext appears only on the intended verified peer.
5. Re-import/re-send the same envelope and verify replay rejection.
6. Turn off Bluetooth mid-transfer and confirm sender status is not `DELIVERED`.
7. Verify unknown sender, corrupted frame, missing fragment and malformed envelope are rejected without crashing.
