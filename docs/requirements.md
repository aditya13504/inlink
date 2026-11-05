# Requirements — Initial Baseline

IDs are stable references for implementation and tests.

## Identity
- ID-01 (P0): Generate a local pseudonymous identity without requiring phone/email.
- ID-02 (P0): Keep display name separate from cryptographic identity.
- ID-03 (P0): Support contact exchange through a QR/shareable card in a later MVP increment.
- ID-04 (P0): Provide a way to verify a contact key out-of-band.
- ID-05 (P1): Define key rotation and recovery before production.

## Messaging
- MSG-01 (P0): One-to-one text messages.
- MSG-02 (P0): Persist outgoing messages before transmission.
- MSG-03 (P0): Distinguish queued, in-transit, delivered, expired and failed.
- MSG-04 (P0): Suppress duplicate user-visible messages.
- MSG-05 (P0): Resume delivery after normal app restart.
- MSG-06 (P0): Apply message expiry and bounded storage.
- MSG-07 (P1): Store-and-forward relaying.
- MSG-08 (P1): Group messaging with defined group key management.

## Networking
- NET-01 (P0): Discover nearby compatible peers using supported platform APIs.
- NET-02 (P0): Authenticate peers and secure sessions before sensitive traffic.
- NET-03 (P0): Internet relay for global delivery.
- NET-04 (P0): Shared protocol across Android, iOS and relay implementations.
- NET-05 (P0): Recover from network changes without silently losing queued messages.
- NET-06 (P1): Multi-hop relaying with loop prevention and hop limits.
- NET-07 (P1): Independently operated relay instances.
- NET-08 (P2): Dedicated bridge nodes.

## Security and privacy
- PRV-01: End-to-end encryption for private message contents.
- PRV-02: Encrypted local storage and OS-protected key material.
- PRV-03: Minimize metadata and diagnostic collection.
- PRV-04: Block and mute controls.
- SEC-01: No custom cryptographic algorithms.
- SEC-02: Treat every peer, packet and relay as untrusted.
- SEC-03: Bound packet sizes, queues, retries and relay resource usage.

## Initial measurable goals
Targets must be tested under documented device/radio conditions:
- Direct-link test suite: target at least 95% successful delivery in a defined repeatable test environment.
- Retry/reconnect suite: zero duplicate user-visible messages.
- Persistence: no outgoing message acknowledged as durably queued is lost after a normal app restart.
- Production gate: no unresolved critical/high-severity security findings in security-critical paths.
