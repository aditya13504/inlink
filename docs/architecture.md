# Architecture — Initial

## Layers

1. Flutter presentation: screens, user actions, accessibility, status.
2. Application services: conversations, local repositories, outbox and delivery state.
3. Protocol/security: message envelope, validation, identity and cryptographic-library adapters.
4. Network engine: peer discovery, transport selection, retry, deduplication and routing.
5. Platform adapters: Kotlin/Android and Swift/iOS APIs.
6. Optional community infrastructure: encrypted envelope relay and later bridge nodes.

## Initial stack

- Flutter/Dart for shared UI and application orchestration.
- Kotlin for Android-specific network integration.
- Swift for iOS-specific network integration.
- SQLite with a reviewed encrypted-storage approach before sensitive production data is stored.
- A maintained cryptographic library selected after a documented compatibility/security review.
- A small relay service after the direct-link and message lifecycle are proven.

## Boundary rule

Flutter UI must not own radio scanning or cryptographic primitives. The app talks to a transport-neutral interface; platform adapters report capabilities and errors. The protocol must not depend on a UI framework.

## Platform reality

Android and iOS differ in background execution and radio APIs. Define a shared product contract but allow different platform implementations. Do not promise continuous background mesh availability on every device.

## Delivery lifecycle

QUEUED -> IN_TRANSIT -> DELIVERED
                 -> QUEUED (retryable failure)
QUEUED/IN_TRANSIT -> EXPIRED or FAILED

Only an authenticated recipient receipt can produce DELIVERED. A transport or relay acknowledgement is not recipient delivery.

## Current scaffold

`NetworkTransport` is a transport-neutral interface. `FakeNetworkTransport` supports development before native BLE is ready. The native method channels are placeholders and do not currently scan or exchange BLE packets.
