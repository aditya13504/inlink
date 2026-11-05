# M11 Native Mesh Integration Test Plan

## Automated checks on a Flutter-enabled host

From `app/`:

```bash
dart format lib test
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Expected: no analyzer errors, all unit/widget tests pass, Android debug APK builds. These commands were **not run** in the packaging environment because Flutter/Dart and Gradle are unavailable.

From `relay/`:

```bash
python -m compileall -q relay
python -m pytest -q tests
```

Expected: relay source compiles and the existing relay suite passes. These are supporting regressions checks, not validation of the Dart mesh implementation.

## Physical-device test matrix

| Case | Setup | Expected result |
|---|---|---|
| Trusted peer | Two devices have imported and verified each other's identity | Bilateral challenge/proof exchange binds node IDs to current BLE addresses |
| Untrusted peer | Third device is not a verified contact | Proof is rejected; no node/address binding |
| Stale challenge | Delay proof beyond challenge lifetime | Proof rejected; no binding |
| Replayed proof | Replay an already consumed proof | Proof rejected; no binding |
| Conflicting binding | Attempt to bind one address to a second node ID | Fail closed; no overwrite |
| Disconnect | Disconnect a bound peer | Address binding and partial transfers cleared |
| Fragmented control | Deliver challenge/proof over multiple BLE frames | Reassembled control payload processed once |
| Malformed frame | Invalid header, fragment fields, oversized control | Frame ignored/rejected; no routing |
| Two-node message | Send through authenticated direct peer | Durable queued state then authenticated receipt-driven delivered state |
| Store and forward | Three peers with a viable route | Intermediate forwards opaque encrypted packet; destination receipt required |
| No route | Destination is not reachable | Message remains queued/retryable or expires; never claims delivery |
| Process restart | Kill process with pending packet | Durable route restored; retries are safe and duplicate-resistant |
| UI lifecycle | Open and close mesh conversations repeatedly | No duplicate subscriptions, disposed streams, or divergent repositories |

## Safety assertions

- BLE discovery alone must never create a trusted contact or node binding.
- Do not log challenge/proof payloads, private keys, decrypted messages, or complete encrypted envelopes.
- A successful `sendBleFrameToPeer` return is not an end-to-end delivery receipt.
- No global-delivery claim is valid without a physical path through connected peers or a configured relay.
