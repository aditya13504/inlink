# InLink M5 — Mesh Routing Core Closure

**Deliverable:** one integrated project archive containing the M4 baseline plus the
M5 routing core, tests, protocol contract, and acceptance documentation.

## Implemented

- Versioned strict JSON mesh packet with explicit size, ID, timestamp, TTL, and hop bounds.
- Opaque payload forwarding; no plaintext parsing in the routing layer.
- Flooding-style forwarding to eligible peers, excluding ingress/self and filtering invalid peer IDs.
- Route-key deduplication and conflicting-content detection.
- Hop-limit termination, bounded queue and seen cache, expiry cleanup.
- In-memory store-and-forward queue with per-peer attempt tracking and retry release on send failure.
- Locally originated packet API and explicit removal on authenticated application completion.
- Transport adapter interface for multi-peer transports, including per-peer attempt tracking and retry release after send failures.
- 25 Flutter unit tests covering validation, forwarding, loops, queue pressure, retries, expiry, malformed inputs, and transport adapter behavior (written but not executed in this environment).
- Protocol documentation and physical-device acceptance matrix.

## Validation status

The source and tests have been reviewed structurally, and the prior M4 relay regression
suite is still runnable. The environment does not contain Flutter or Dart, so M5 Dart
tests, analysis, formatting, and APK build could not be executed here. The included
Flutter CI workflow is configured to run them on a Flutter-enabled runner. ZIP integrity
and source-level checks are performed when packaging this milestone.

## Important limitations (not hidden)

1. The mesh queue and dedup cache are in-memory only; process restart loses queued work.
2. The current native Android BLE transport is oriented around one active peer and is
   not connected to the routing engine. No claim of live multi-hop radio delivery is made.
3. iOS Core Bluetooth and cross-platform mesh transport are not implemented.
4. The outer route metadata is not independently authenticated; the destination must
   run the inner E2EE verification and replay-protection pipeline.
5. BLE does not guarantee background execution or delivery. Physical-device range,
   reliability, battery, and reconnect tests are mandatory.
6. Independent cryptographic/security review is still required.

## Acceptance decision

M5 is **routing-core implementation-complete, device integration pending**. Do not
call the product multi-hop mesh-enabled or production-ready until a multi-peer native
transport, durable queue, Flutter CI, and physical-device acceptance tests pass.
