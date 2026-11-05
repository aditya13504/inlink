# M8 Closure — Application Messaging Orchestration

## Included

- A single application service coordinates startup recovery, outbound text
  encryption, mesh queueing, ingress events, text validation and retries.
- Outbound text is wrapped in a versioned application payload and encrypted for
  a previously verified contact before entering the mesh router.
- Inbound text is surfaced only after the existing ingress pipeline opens the
  signed E2EE envelope and replay protection accepts it.
- Recipient delivery receipts are signed by the recipient identity, encrypted
  back to the sender, and verified against the expected trusted contact before
  a message is marked delivered.
- Local BLE send acceptance is never represented as end-to-end delivery.
- Application-level payload limits (8 KiB UTF-8 text ceiling to leave room for E2EE/base64/routing overhead) and metadata consistency checks are applied.

## Known gaps (must not be represented as completed)

- The current pending receipt map is in memory. Persist outgoing message state
  and pending receipt expectations in the app's encrypted message database before
  a release so app restart cannot forget a sent-but-not-yet-receipted message.
- The chat UI and app lifecycle still need to instantiate the service and map
  events into durable conversation records.
- Receipt transport over an intermittent mesh needs two-device and multi-hop
  validation; retries and duplicate receipts need integration coverage.
- The existing E2EE envelope is a prototype design and has not received an
  independent cryptographic audit or a forward-secure ratchet.
- The M7 handshake test suite and all Flutter tests must be run on a Flutter SDK
  host; Android compile and physical-device tests are required.
- iOS native BLE transport is not included in M8.

## Release gates

1. `dart format app/lib app/test`
2. `flutter pub get`, `flutter analyze`, `flutter test`
3. Android debug build and two-device handshake/send/receipt tests
4. Test offline queueing, process death, reconnect, replayed receipt, forged
   receipt, wrong-recipient receipt and oversized payload.
5. Review persistent sent-message state before beta.
