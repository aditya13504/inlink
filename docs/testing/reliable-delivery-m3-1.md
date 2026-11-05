# M3.1 reliable delivery verification

## Current behavior

- Outgoing message records are persisted before any BLE attempt.
- Message records store a stable application message ID, expiry, retry count, last attempt, and next attempt.
- The app retries queued/in-transit messages while it is running, BLE is active, and the selected conversation matches the queued recipient. Mobile operating systems may suspend the app; this is not an always-on background worker.
- Each attempt uses a fresh E2EE envelope while preserving the application message ID. The recipient stores a message once by application ID but can issue a new receipt for a retransmitted envelope.
- A receipt is itself encrypted to the sender and signed by the recipient's existing Ed25519 identity through the E2EE envelope. It contains the message ID, SHA-256 digest of the exact delivered envelope, recipient identity fingerprint, and timestamp.
- The sender sets `delivered` only after the incoming receipt envelope passes verified-contact checks and the message ID, envelope digest, and recipient identity all match.
- Messages expire after seven days and stop retrying after eight attempts. Retry delay is exponential, capped at 30 minutes, and randomized with jitter.

## Manual test plan (two Android devices)

1. Install the same development build on two devices. Create identities and exchange public contact bundles out of band; compare the full 128-bit fingerprints before saving contacts.
2. Open the same verified conversation on both devices and start BLE on both.
3. Send a short text from A to B. On A, verify status is initially `queued` or `inTransit`, never `delivered` merely because the Android API accepted frames.
4. On B, verify the plaintext appears only after envelope signature verification and authenticated decryption. Confirm B sends a receipt when the BLE return path is available.
5. On A, verify the status becomes `delivered` only after the receipt is received and matched.
6. Temporarily disconnect BLE or stop the peer, queue a message, then restore the connection. Verify attempts increment and the retry delay increases. Do not wait for background delivery while the OS has suspended the app.
7. Close/reopen the app and confirm retry metadata is restored. Test expired records by setting an old `expiresAtUtc` in a development fixture; the app should mark them `expired` and not send them.
8. Deliver a retry of the same application message ID with a fresh envelope. Verify B does not create a second visible message and can return a receipt for the latest envelope.
9. Try a receipt with the wrong sender identity, recipient fingerprint, message ID, or envelope digest in a development test. It must not mark the message delivered.

## Validation status

The automated unit tests are added but have **not** been run in this environment because Flutter/Dart are not installed here. Android compilation and all two-device checks remain pending. Receipt sending currently uses the active BLE path immediately; receipts are not yet persisted as an independent return queue. The secure-storage JSON message repository is a bounded prototype, not a production encrypted database.
