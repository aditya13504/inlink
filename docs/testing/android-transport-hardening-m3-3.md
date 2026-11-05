# M3.3 — Android transport hardening

## Changes in this milestone

### Native Android GATT sender
- Native frame sends now enter a bounded FIFO queue (maximum 128 queued frames).
- A client-side GATT write is not reported as complete until `onCharacteristicWrite` returns success/failure.
- Server-side notifications are serialized and completed from `onNotificationSent`.
- Queue entries fail explicitly when BLE stops or a peer disconnects; the caller receives an error and can retry the whole encrypted envelope using the M3.1 delivery queue.
- The server selects one connected GATT peer for each notification in this single-peer experiment instead of broadcasting the same frame to every connected device.
- The sender reports `readyToSend` only after the client CCCD write succeeds, or after the remote client enables server notifications.
- CCCD writes accept only valid enable/disable values at offset zero.

### Flutter transport
- Complete frame batches are serialized so fragments from separate messages/receipts do not interleave.
- A failed batch does not poison the sender queue.
- Closing/restarting the BLE session invalidates queued batches from the old session.
- Retry and receipt queues drain only after GATT readiness, not merely after the scan/advertising start request succeeds.
- Peer disconnect/stop clears partial fragment assemblies and closes the current sender session.

### Reassembly limits
- Partial transfers remain bounded by concurrent-transfer count and age.
- A total buffered-payload byte budget is enforced across concurrent partial transfers.
- Explicit `clear()`, `activeTransfers`, and `bufferedBytes` support lifecycle cleanup and diagnostics.
- A backwards-moving clock expires inconsistent partials rather than retaining them indefinitely.

## Semantics

A successful native frame callback means the Android GATT operation reported success for that frame. It does **not** mean the remote app reassembled or authenticated the message. Only the existing authenticated receipt can set a message to `DELIVERED`.

If a connection drops mid-envelope, some frames may already have arrived. The receiver's bounded reassembler drops partial state on its observed disconnect; the sender retries the entire encrypted envelope with a fresh transfer ID and envelope. Application-level message IDs and recipient-side duplicate handling are still required.

## Validation plan

Run from `app/` on a machine with Flutter and Android SDK installed:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Then test with two physical Android devices:
1. Start BLE on both; verify `readyToSend` only appears after GATT subscription is ready.
2. Send short and near-maximum-size encrypted envelopes. Verify fragments for different messages do not interleave.
3. Disconnect Bluetooth during the first, middle, and last fragment of a message. Confirm sender never reports `DELIVERED` without a valid receipt.
4. Reconnect and verify the whole envelope is retried and the recipient displays one application message.
5. Queue a receipt while the peer is offline; reconnect and verify it transmits and the acknowledgement flow completes.
6. Stress with malformed frames, missing fragments, conflicting fragment counts, repeated fragments, and multiple partial transfer IDs. Confirm bounded memory and no crash.
7. Stop BLE during an active send and confirm pending native method calls fail rather than hanging or being reported as successful.

## Validation status

Source-level changes and package-file checks only. Flutter analysis/tests, Kotlin/Gradle compilation, and physical-device tests have not been run in this environment. The Android implementation remains experimental and single-peer; iOS Core Bluetooth and robust multi-peer mesh are not implemented.
