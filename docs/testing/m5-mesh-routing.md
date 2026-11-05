# M5 — Mesh routing verification and acceptance

## Automated unit tests

`app/test/mesh_routing_engine_test.dart` and `app/test/mesh_transport_adapter_test.dart` cover:

- strict packet JSON and exact field set;
- version, ID, hop counter, timestamp, TTL, payload and packet-size validation;
- multi-hop forwarding with unchanged opaque payload;
- destination delivery without plaintext inspection at intermediate nodes;
- duplicate and loop suppression, including hop-count changes;
- conflicting immutable content under a reused route key;
- hop-limit termination;
- bounded queue refusal without evicting accepted packets;
- retrying a queued packet when a neighbor becomes available;
- per-peer attempt tracking and retry after transport failure;
- locally originated packets, duplicate IDs, and queue bounds;
- expiry cleanup, bounded seen-cache behavior, and invalid ingress/neighbor IDs;
- adapter sends to connected peers, excludes ingress peers, and retries failed local sends.

Run on a configured Flutter stable SDK:

```bash
cd app
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --reporter expanded
flutter build apk --debug
```

## Required physical-device acceptance matrix

| Scenario | Setup | Expected result |
|---|---|---|
| Direct | A can reach B | B receives packet and verifies inner E2EE envelope |
| One relay | A–B–C, no A–C link | B forwards once toward C; C can authenticate/decrypt |
| Loop | A–B–C–A topology | Duplicate route key is not forwarded repeatedly |
| Alternate neighbor | B first has no outbound peer, then C appears | Pending packet becomes available for C |
| Interrupted send | Transport fails mid-packet | Attempt is released and retry remains possible |
| TTL | Hold packet beyond expiry | It is purged and not forwarded |
| Hop cap | Build a path longer than configured hop limit | Packet stops at the cap |
| Malformed peer | Invalid ID or malformed route packet | Reject before enqueue |
| Conflicting duplicate | Same origin/message ID, different payload | Reject as conflicting duplicate |
| Restart | Kill and restart process with pending packet | Current implementation loses the in-memory queue; this is a known unmet gate, not a pass |
| Receipt | Deliver message but delay authenticated receipt | Queue remains pending until app-level completion |

## Honest status

The pure routing core and its test cases are included. Flutter tests, static analysis,
APK compilation, and physical multi-device tests were not run in the authoring
environment because Flutter/Dart and BLE-capable devices were unavailable. The
current Android native transport is not a multi-peer mesh transport, and the queue
is memory-only. Those are explicit limitations of this M5 routing-core milestone.
