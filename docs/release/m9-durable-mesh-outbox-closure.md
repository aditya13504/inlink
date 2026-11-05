# M9 Closure — Durable Mesh Outbox and Conversation State

## Delivered in this package

- Added a message-store contract and adapter over the existing SQLCipher
  conversation repository.
- Outgoing mesh messages are tagged with a transport namespace and persisted with their encrypted envelope and local
  conversation text before routing or transport attempts.
- Startup restores pending receipt expectations from the durable conversation
  store and re-creates missing route-queue entries where possible.
- Incoming text is saved before a recipient delivery receipt is generated.
  Storage failure rejects the inbound message and prevents an acknowledgement.
- A delivery receipt must match an unexpired outgoing record and the exact
  pinned recipient fingerprint before it can mark the record delivered.
- Added tests for pending outbox restoration, inbound idempotence and durable
  delivered-state updates.
- Changed message-history eviction to remove terminal records first and reject
  a new write rather than silently evicting queued/in-transit/failed messages.

## Still required

- The Flutter/Dart SDK was not available in the build environment; the new Dart
  tests, analyzer and Android build have not been executed here.
- M10 adds an optional dependency-injected mesh UI path and lifecycle integration.
  The default app composition still does not construct the service because stable
  multi-peer native transport and authenticated identity binding remain gates.
- The existing mesh native transport and identity handshake still require
  physical-device multi-peer tests; iOS BLE remains unimplemented.
- Legacy migration retention policy should be validated with a large fixture
  containing more pending messages than the configured history limit.
- Independent cryptographic review and full two-device / three-node delivery
  testing remain release gates.

## Validation required on a Flutter-enabled host

1. `dart format app/lib app/test`
2. `cd app && flutter pub get && flutter analyze && flutter test`
3. Android debug build and physical-device test
4. Kill the app between conversation persistence and route persistence; verify
   startup reconstructs the route and receipt expectation.
5. Test invalid receipt signer, expired receipt, wrong contact fingerprint,
   duplicate inbound message, full outbox and encrypted database reopen.
