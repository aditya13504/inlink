# M6 closure — Durable Mesh Queue and Multi-Peer Android BLE

## Included

- SQLCipher durable mesh queue and secure-storage key management.
- Transactional queue operations, strict packet validation on recovery, expiry pruning, deduplication, persisted peer-attempt state, and safe retry reset after process recovery.
- Mesh engine restoration API and durable router coordinator.
- Android bounded multi-peer GATT client sessions, target-peer send API, connected-peer listing, and native Flutter method-channel wrappers.
- Fragmenting native mesh peer transport plus explicit verified node-ID-to-BLE-address directory.
- Restoration and directory tests, protocol and device-validation docs.

## Acceptance status

| Area | Status |
|---|---|
| Source files and docs present | Complete in package |
| Relay regression tests | Must be rerun for this package |
| Flutter unit tests/analyze | Not run: Flutter/Dart unavailable in authoring environment |
| Android compile | Not run: Android SDK/Gradle environment not verified |
| Multi-device BLE validation | Pending physical devices |
| E2EE authenticated identity handshake integration | Pending; directory API requires caller to bind only after successful authentication |
| End-to-end receipt-driven queue removal | Coordinator API present; caller integration and device verification pending |

## Important limitations

- Three outbound client connections are the configured cap; actual platform support may be lower. The operating system may also impose limits on inbound GATT peers.
- Native BLE addresses are mutable/ephemeral transport handles and are not trusted identity.
- The native event stream exposes received frames and a per-peer reassembly helper is included; routing and E2EE verification must still be wired by the caller.
- Foreground Android behavior only; no guarantee of reliable background mesh, iOS mesh, or global connectivity without a route.
- No cryptographic audit or independent security review has been performed.

**Disposition:** M6 source implementation package delivered; Android device validation and final application integration remain release gates. Do not label this build production-ready.
