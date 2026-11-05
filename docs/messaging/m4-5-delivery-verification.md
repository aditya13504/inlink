# M4.5 — End-to-end delivery verification

## Added automated relay-path test

`relay/tests/test_relay.py` now exercises a complete relay mailbox lifecycle:
1. Sender signs and submits an opaque encrypted envelope.
2. Recipient polls but does not acknowledge, simulating a temporary processing failure.
3. A second signed poll still returns the queued message.
4. Recipient acknowledges the exact envelope digest with a signed request.
5. A subsequent poll returns an empty mailbox.

This verifies relay queue retention and authenticated acknowledgement semantics.
It does **not** prove that the Flutter app successfully decrypts the envelope or
that BLE works between physical devices.

## Two-device acceptance matrix

| Scenario | Required pass condition |
|---|---|
| BLE direct send | Recipient authenticates and decrypts message; sender sees delivered only after valid receipt |
| BLE interruption | Message remains queued/in transit; bounded retry resumes when link returns |
| Relay fallback | Message can be polled after accepted relay submit; no false delivered status on HTTP 202 |
| Relay processing delay | Polling without ack does not remove the queued message |
| Invalid receipt/digest | Sender does not mark delivered; relay message remains until valid ack |
| App restart | Queued messages and retry metadata persist across process restart |
| Duplicate transport delivery | One visible message per peer/direction/application message ID |
| Offline recipient | Sender remains queued/in transit until authenticated recipient receipt |
| Expiry | Expired message is not retried indefinitely and state is surfaced clearly |
| Network return | Retry drain resumes without requiring manual screen navigation |

## Manual test record template

For each run record: app commit/archive version, Android/iOS version, device
models, transport (BLE/relay), timestamps, message ID, envelope digest, expected
state transitions, actual state transitions, and logs with secrets/keys removed.

## Run relay tests

```bash
cd relay
python -m pytest -q tests
```

## Current limitations

Flutter and Dart are not installed in the packaging environment. No Flutter
analysis/tests/build or real-device BLE/relay-fallback tests have been run.
Do not treat this milestone as mobile end-to-end certification; it strengthens
only the executable relay server test coverage and documents the remaining
device acceptance criteria.
