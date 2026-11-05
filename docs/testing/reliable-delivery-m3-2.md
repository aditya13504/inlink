# M3.2 receipt durability and delivery hardening

## What changed

- Added a bounded OS-backed `DeliveryReceiptQueue` that persists receipt and receipt-ack records before attempting BLE transmission.
- Receipts wait for a live BLE path and are retried with bounded exponential backoff while the app is running. Queue entries expire after seven days and the queue is bounded to 200 records.
- A receiver keeps a delivery receipt until it receives an authenticated `receiptAck`. The sender creates that acknowledgement only after validating the original receipt against the verified contact, the intended local identity, the stable application message ID, and a digest of an envelope actually sent for that message.
- Receipt acknowledgements are encrypted to the verified contact. The acknowledgement is removed from the local queue after local BLE acceptance; if it is lost, the recipient retries its receipt and the sender creates the acknowledgement again.
- Outgoing message records now preserve a bounded history of sent envelope digests. This allows a delayed receipt for an earlier retry to be validated even if a newer envelope has since been sent.
- Message records migrate from versions 1 and 2 to version 3 without discarding the previous fields. Legacy records begin with an empty digest history; the current envelope digest remains a fallback match.
- Inbound application payloads are serialized through the existing inbound chain. Duplicate receipt and acknowledgement handling is idempotent.

## Delivery guarantees and limits

This is **at-least-once receipt transmission**, not exactly-once delivery. Message IDs and envelope digests allow duplicate receipts to be handled safely. There is no acknowledgement-of-acknowledgement: an ack queue item is removed after the local BLE stack accepts its frames, and a repeated receipt triggers a replacement ack if needed.

The queue only drains while the app is running, BLE is active, and the contact is loaded. Mobile operating systems can suspend the app. This is not a background service and does not guarantee delivery while the app is terminated or suspended. The secure-storage JSON queues are bounded prototypes, not production databases.

## Validation

Added unit tests for receipt/ack serialization and message-record version 3 digest-history persistence plus version 2 migration. Flutter tests, static analysis, Android build, and physical-device tests were not run in this environment because the Flutter/Dart toolchain and test devices are unavailable.

## Manual two-device test

1. On device A, send a message to verified contact B while BLE is active.
2. Confirm B receives the plaintext only after E2EE validation, then confirm B's receipt is persisted before BLE send.
3. Disconnect B immediately after the receipt is queued. Reconnect and verify the receipt queue drains.
4. Confirm A marks the message delivered only after validating the receipt and then sends a receipt acknowledgement.
5. Confirm B removes its queued receipt only after the authenticated acknowledgement is received.
6. Simulate a lost acknowledgement: allow B to resend its receipt; verify A safely reprocesses it and emits a new acknowledgement.
7. Retry the original message so it has a new envelope. Deliver a delayed receipt for the earlier envelope and confirm A accepts it only if that digest exists in the message's persisted sent-envelope history.
8. Restart both apps and verify pending receipt metadata is restored. Then verify expiry and queue-cap behavior using test fixtures.
