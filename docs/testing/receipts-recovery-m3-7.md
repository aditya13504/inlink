# M3.7 — Unified receipts and recovery

This milestone routes the persistent receipt queue over BLE or the internet
relay. BLE is preferred when the GATT session is ready. If a BLE receipt batch
fails, the same encrypted envelope can be submitted through the relay. If BLE
is unavailable, queued receipts can use the configured relay directly.

## Reliability behavior

- Receipt and receipt-ack records are persisted before transport attempts.
- The queue drains from the existing foreground delivery timer after restart
  recovery and when a transport is available.
- A receipt remains queued until an authenticated `receiptAck` arrives.
- A `receiptAck` is removed after BLE transport acceptance or relay acceptance.
  If it is lost, a repeated delivery receipt causes the peer to enqueue it again.
- Relay idempotency IDs are derived from the exact encoded envelope bytes.
  Retrying an identical HTTP submission reuses its ID; a freshly encrypted
  retry has a new ID and can be authenticated again after an earlier response
  or acknowledgement was lost.
- A relay queue acknowledgement only removes the relay's copy after the app's
  existing E2EE verification/decryption path accepts the envelope.
- Outgoing messages remain `IN_TRANSIT` after relay acceptance; only a matching
  authenticated end-to-end receipt can set `DELIVERED`.

## Limits and validation

This is foreground scheduling, not guaranteed background execution. Receipts
use the same bounded secure-storage queue as earlier milestones; it is not a
transactional encrypted database. Relay receipt routing requires the recipient
to poll the relay, and duplicate receipt envelopes can temporarily occupy relay
mailboxes until acknowledged or expired.

Added a deterministic relay envelope-ID unit test. Flutter/Dart analysis,
unit tests, mobile builds, and two-device end-to-end testing must still be run
on a configured Flutter host. Production requires protocol and cryptographic
review, server rate limiting/abuse controls, and platform-specific background
and battery testing.
