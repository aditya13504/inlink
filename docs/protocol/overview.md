# InLink Protocol — Draft 0

Status: conceptual draft, not suitable for production implementation yet.

## Design goals
- Transport-neutral message envelope.
- Versioned and bounded packet format.
- End-to-end encrypted message content.
- Authenticated delivery receipts.
- Duplicate suppression and expiry.
- Forward-compatible optional fields.

## Layers
- Identity: public-key references and contact verification.
- Message: opaque conversation reference, unique ID, expiry and encrypted payload.
- Delivery: acknowledgement, retry and deduplication semantics.
- Transport: BLE/local transport or internet relay.
- Relay: queue quotas, expiry and abuse controls.

## Important distinction
A session-encryption protocol is not automatically a complete asynchronous end-to-end messaging protocol. Select and integrate a maintained library with a reviewed security model. Do not invent encryption or key-ratcheting algorithms.

## Before implementation
Specify canonical serialization, field lengths, key identifiers, signature/AEAD binding, replay window, error handling, unknown-field handling, protocol negotiation, fragmentation, maximum payload sizes and cross-platform test vectors.
