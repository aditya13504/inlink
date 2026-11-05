# M3.5 — Flutter relay client integration

## Added

- `app/lib/core/network/relay/relay_client.dart` implements relay API v1 submission, signed mailbox polling, and signed queue acknowledgement.
- Conversation UI has a relay URL field plus **Send queued** and **Poll relay** actions.
- Non-loopback endpoints must use HTTPS. Plain HTTP is accepted only for loopback development (`localhost`, `127.0.0.1`, or `::1`).
- The client verifies the returned envelope digest and size, then the conversation handler checks that the envelope's signing key hashes to the relay's claimed sender ID.
- Polled envelopes use the same verified-contact, E2EE signature/decryption, replay-protection, local persistence and authenticated delivery-receipt flow as BLE. The relay queue copy is acknowledged only after the envelope processing path returns success.
- Relay acceptance does not change a local message to `DELIVERED`. The existing encrypted recipient receipt remains the end-to-end delivery signal.

## Local development

1. Start the relay using the instructions in [`../../relay/README.md`](../../relay/README.md).
2. Run the Flutter app on a device that can reach the relay host.
3. Enter the relay URL in the conversation screen. Use `http://127.0.0.1:8000` only when the app and relay share the same host/network namespace; for a physical phone, use a reachable development host address and configure HTTPS rather than assuming the phone's localhost is the computer.
4. Choose a verified contact and press **Send queued** to submit unexpired outgoing envelopes. Submissions are idempotent, so retrying the action will not enqueue the same message twice.
5. On the recipient device, enter the same relay endpoint and press **Poll relay**. Envelopes from unverified contacts or envelopes that fail E2EE/replay checks are not acknowledged and remain queued until expiry.

## Current limitations

- This is manually triggered relay transport, not an automatic background service. No durable automatic retry scheduler or connectivity-aware BLE/relay routing is implemented yet.
- The relay URL is not persisted by the UI.
- A replayed envelope whose first processing succeeded but whose relay acknowledgement failed can be rejected by replay protection on a later poll and remain in the queue until expiry; robust idempotent inbound acknowledgement needs a transactional accepted-envelope ledger.
- iOS transport, real network/device integration, and Flutter SDK validation remain outstanding. Do not expose the prototype relay publicly without TLS, abuse controls, rate limits, nonce replay controls, operational monitoring, and independent security review.
