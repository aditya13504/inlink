# InLink Mesh Routing Protocol v1 (experimental)

**Purpose:** bounded store-and-forward flooding of an opaque E2EE envelope over
short-range peer links. This is a routing envelope, not a replacement for the
inner authenticated message envelope.

## Wire format

UTF-8 JSON object with exactly these fields:

| Field | Type | Rule |
|---|---|---|
| `protocol_version` | integer | exactly `1` |
| `message_id` | string | 16–64 URL-safe characters |
| `origin_node_id` | string | 16–64 URL-safe characters |
| `destination_node_id` | string | 16–64 URL-safe characters; must differ from origin |
| `created_at` | integer | Unix epoch seconds; no more than 5 minutes in the future |
| `expires_at` | integer | future timestamp, at most 7 days after creation |
| `hop_limit` | integer | 1–8 |
| `hop_count` | integer | 0–`hop_limit`; number of intermediate forwarding operations already applied |
| `opaque_envelope` | string | non-empty encoded E2EE envelope, maximum 15 KiB UTF-8 |

Maximum encoded routing packet is 16 KiB to fit the current BLE frame-transfer limit. Unknown/missing fields, wrong types,
unsupported versions, invalid IDs, expired packets, overlong TTLs, and invalid
hop counters are rejected. The packet is intentionally strict so v1 has one
unambiguous representation at the application layer.

## Forwarding behavior

1. A sender first creates and signs/encrypts the normal E2EE message. Mesh routing
   receives only that opaque envelope.
2. Each node checks the routing packet bounds and expiry, then deduplicates on
   `(origin_node_id, message_id)`.
3. If the destination is this node, it returns the inner envelope to the existing
   verified-message pipeline. It must not display plaintext until that pipeline
   authenticates and decrypts it.
4. Otherwise, a node whose `hop_count` has reached `hop_limit` drops the packet.
   A node below the limit increments `hop_count`, queues the packet, and offers it
   to eligible connected neighbors other than the ingress peer and itself.
5. The bounded seen cache suppresses loops and duplicates. A repeated route key
   with changed immutable content is rejected as a conflicting duplicate.
6. A transport adapter marks a peer attempted only after local transport
   acceptance. On transport failure it clears that attempt to permit retry.
   Local transport acceptance is not remote delivery.
7. Queue entries remain pending until explicit application-level completion,
   cancellation, or expiry. Completion must be based on authenticated evidence,
   not merely successful radio writes.

## Resource bounds

- Maximum forwarding queue: 256 packets per engine by default.
- Maximum seen/replay entries: 4,096 by default.
- Maximum hop limit: 8.
- Maximum envelope payload: 15 KiB.
- Maximum routing packet: 16 KiB.
- Maximum message lifetime: 7 days.
- Expired entries are purged; overflow rejects new packets instead of silently
  evicting an unexpired accepted packet.

## Security and privacy boundaries

- Intermediate nodes can see origin/destination identifiers, message ID, timing,
  expiry, hop counters, payload size, and link-layer metadata.
- The outer routing envelope is not independently authenticated. A malicious peer
  can spoof route metadata or inject junk; the destination's inner E2EE signature,
  recipient binding, replay protection, and receipt checks remain mandatory.
- The in-memory routing queue and seen cache do **not** survive process death.
  Do not describe this as durable store-and-forward until a SQLCipher-backed
  persistence adapter and restart recovery tests are added.
- The current Android BLE implementation is single-peer-oriented. This routing
  core is not yet wired to a native multi-peer connection manager. The included
  multi-hop behavior is validated at the pure routing-core level only.
- BLE advertisements/connections do not provide anonymous routing or guaranteed
  background delivery. This is not an anonymity network.
- Do not use this experimental mesh implementation for sensitive communication.

## Versioning

Any change to field meaning, canonicalization, hop semantics, expiry, or unknown
field handling requires a new protocol version and test vectors. Never silently
interpret a v1 packet as a newer version.
