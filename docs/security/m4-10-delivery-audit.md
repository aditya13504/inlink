# M4.10 — End-to-end delivery audit

## Audit findings addressed

1. **Receipt lookup was not conversation-scoped.** The previous lookup selected the first local message with a matching application ID, then checked the sender. Since the database's uniqueness key is peer + direction + ID, IDs are only unique within that scope. Receipt lookup now filters by outgoing direction and authenticated sender fingerprint before digest validation and status mutation.
2. **Receipt fields lacked strict structural validation.** Delivery receipts and receipt acknowledgements now validate message ID length/characters and the SHA-256 base64url digest format before using the values to locate local state.

## Invariants

- Transport acceptance (`BLE write`, `GATT notification`, relay `accepted`/`duplicate`) is not delivery.
- A message becomes `delivered` only after an encrypted envelope has been authenticated/decrypted from a verified contact and its receipt matches the local identity, sender, message ID, and digest of an envelope actually sent.
- A receipt acknowledgement only removes a queued receipt when sender, target identity, message ID, and digest match.
- Message IDs are scoped to a verified contact; lookup must use that scope.
- Repeated or stale receipts must not cause another contact's message to be marked delivered.
- Unknown or malformed receipt fields must fail closed.

## Validation plan

1. Unit test receipt message-ID and digest shape validation.
2. Send the same application message ID under two different contact fingerprints in a repository fixture; a receipt from contact A must never mutate contact B's record.
3. Test valid receipt, wrong sender, wrong target fingerprint, unknown message ID, unknown envelope digest, malformed digest, and duplicate receipt.
4. Interrupt a multi-frame transfer before final fragment; verify no receipt is generated.
5. Restart after relay acceptance but before recipient receipt; verify the message remains `inTransit`/queued, not delivered.
6. Deliver a delayed valid receipt after retry/reconnect; verify it may confirm delivery only when its digest is in the message's sent-envelope digest history.
7. Confirm transport callbacks alone never set `delivered`.

## Status and limits

The source changes and test cases are added in this milestone. Relay tests and source-level checks can run here, but Flutter tests, SQLCipher-backed repository tests, Android/iOS builds, and physical two-device tests require a configured Flutter toolchain and devices. Independent security review remains required before public beta.
