# M8 Application Integration Test Matrix

| Scenario | Expected result |
|---|---|
| Send to previously verified contact | E2EE envelope persisted before transport attempts |
| No connected peers | Message remains queued; not marked delivered |
| Native send accepted | Still awaiting authenticated recipient receipt |
| Destination opens valid envelope | Text event emitted and receipt generated |
| Invalid sender signature / unknown sender | No text event and no receipt |
| Duplicate E2EE envelope | Replay guard rejects; no second text event |
| Forged or wrong-signer receipt | Receipt rejected; message remains pending |
| Valid signed receipt from expected recipient | Delivered event emitted; durable route removed |
| Malformed app payload / unknown kind | Rejected without exposing ciphertext |
| App restart | Durable mesh routes restore; receipt expectation persistence remains a release gap |

Run with two physical Android devices and a controlled three-node relay topology.
Capture state transitions, not plaintext or keys. Never log envelope content,
private keys, QR payloads, or message text in release diagnostics.
