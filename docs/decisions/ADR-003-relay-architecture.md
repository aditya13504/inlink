# ADR-003: Relay Architecture

Status: Provisional.

## Decision
Begin with a small, independently deployable relay service that forwards opaque encrypted envelopes. Avoid a mandatory central identity authority.

## Consequences
- Relays may observe some routing metadata.
- Quotas, expiry and abuse handling are required.
- Users need a documented relay configuration and trust model.
- Bridge nodes are deferred until the delivery protocol is stable.
