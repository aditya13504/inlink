# M3.9 — Integration reliability and device validation gate

M3.9 adds additional server-side integration tests and a concrete two-device
release gate. Physical-device validation has **not** been performed by this
build environment; the checklist below is for execution on the developer's
devices and must be recorded with device/OS/app build versions.

## Added automated relay tests

- Recipient mailbox quota rejects additional pending messages when full.
- Strict request models reject unexpected fields instead of silently accepting
  ambiguous payloads.
- A signed acknowledgement with the wrong envelope digest cannot remove a
  queued message.
- Repeated acknowledgement after a lost response is safe and returns `not_found`
  once the original queued copy has already been removed.

Existing tests also cover encrypted-envelope forwarding, recipient polling,
submission idempotency, conflicting message IDs, signature rejection, expiry,
oversized payloads, stale timestamps, and recipient key proof-of-possession.

## Two-device test matrix

Record each row as PASS/FAIL and capture app logs without plaintext or private
keys. Use two Android devices initially; repeat iOS cases after an iOS build
exists.

| Scenario | Procedure | Required result |
|---|---|---|
| Verified identity | Exchange identity QR/fingerprint and verify both sides | Both contacts show verified fingerprints |
| BLE direct message | Send a unique message while BLE is ready | One visible message; sender waits for authenticated receipt |
| Relay-only message | Stop BLE on both devices; configure reachable HTTPS relay | Recipient polls, decrypts, stores one message and acknowledges relay copy |
| BLE to relay fallback | Drop BLE during a queued send while relay is reachable | Message remains queued/in transit until a valid receipt; no false `DELIVERED` |
| Relay outage | Disable server/network during submission | Message remains queued; failure is visible and retry is bounded |
| Lost submit response | Allow server to accept a message, then interrupt sender before response | Retrying same exact envelope is idempotent |
| Lost relay ack response | Interrupt recipient after server accepts relay ack | Repeated ack is safe; no duplicate visible message |
| Lost E2EE receipt | Drop receipt traffic, then retry message | Fresh envelope retry lets recipient re-issue receipt; eventual `DELIVERED` only after authenticated receipt |
| App restart | Queue a message, kill and reopen app | Queue metadata survives and due work resumes in foreground |
| Expiry | Keep recipient offline past expiry | Message becomes `EXPIRED`; it is not sent afterward |
| Tampered envelope | Change envelope bytes or digest in test tooling | Reject; never display plaintext |
| Duplicate delivery | Deliver same application message ID through both transports | Exactly one visible message |

## Commands on a configured development machine

From `inlink-foundation/app`:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Run the relay tests from `inlink-foundation/relay`:

```bash
python -m pip install -r requirements.txt
python -m pytest -q tests
```

The current environment does not have Flutter/Dart or physical Android/iOS devices
available, so this milestone does not claim those checks have passed. Relay
server tests can be run here; mobile builds and the device matrix are release
gates before public beta.

## Exit criteria before beta

- All Flutter tests and analyzer checks pass.
- Android build and iOS build succeed on their supported hosts.
- Two-device BLE and relay message/receipt cycles pass repeatedly.
- No duplicate visible messages after retries, transport switching, or restart.
- No message becomes `DELIVERED` without a valid authenticated receipt.
- TLS, rate limiting, abuse controls, database backup/retention policy, threat
  model review, and independent cryptographic/security review are complete.


## M4.0 note

The local repository now serializes add/update mutations and scopes deduplication to contact fingerprint, direction, and message ID. This change is source-reviewed but not yet validated by Flutter tests in this environment. See `docs/security/m4-beta-threat-model.md` for release blockers.
