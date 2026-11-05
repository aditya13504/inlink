## Milestone 12 — Cross-platform transport and reliability

**Package status:** iOS CoreBluetooth transport source, shared transport contract, lifecycle/queue handling, and Dart method-channel tests added. iOS project scaffolding, Flutter compilation, and physical-device validation remain pending. See [`docs/release/m12-cross-platform-transport-closure.md`](release/m12-cross-platform-transport-closure.md).

- Added iOS central/peripheral BLE transport using the same GATT service and frame characteristic UUIDs as Android.
- Added explicit Bluetooth usage descriptions, bounded sends, peer-specific sends, connection cleanup, and radio-state handling.
- Added transport contract tests and cross-platform acceptance matrix.
- The repository does not yet contain a complete generated Xcode project; source syntax parsing is not a substitute for an iOS build or device test.

## Milestone 11 — Native multi-peer mesh integration

**Package status:** runtime composition and challenge/proof control channel implemented in source; Flutter compilation, Android build, and physical-device acceptance pending. See [`docs/release/m11-native-mesh-integration-closure.md`](release/m11-native-mesh-integration-closure.md).

- The Android Conversations route now creates one shared runtime graph for the durable mesh queue, native multi-peer transport, authenticated ingress, and SQLCipher conversation store.
- A bilateral challenge/proof exchange binds BLE transport addresses only to previously verified contact identities. Public identity keys are not secret and are not concealed from a connected radio peer.
- The native event stream is cached/shared so the UI, handshake manager, and packet receiver can all observe native events without replacing each other's platform event sink.
- BLE is not auto-started; live delivery is not claimed until physical-device acceptance passes. iOS native mesh remains unimplemented.

## Milestone 10 — Chat UI and mesh lifecycle integration

**Package status:** UI/lifecycle integration seam delivered; default transport composition and runtime validation pending. See [`docs/release/m10-chat-ui-mesh-lifecycle-closure.md`](release/m10-chat-ui-mesh-lifecycle-closure.md).

- `ConversationsPage` accepts an optional `MeshApplicationService`, starts it, subscribes to delivery/recovery events, refreshes durable history and disposes the injected service.
- The mesh send action is distinct from legacy BLE/relay sending and is disabled until a configured service is injected.
- The default app still does not construct the service because the native multi-peer transport and authenticated node-ID binding are not yet proven.

## Milestone 6 — Durable mesh queue and multi-peer Android BLE

**Package status:** source implementation delivered; runtime validation pending. See [`docs/release/m6-durable-mesh-transport-closure.md`](release/m6-durable-mesh-transport-closure.md).

- SQLCipher-backed bounded durable queue, startup restoration, peer-attempt persistence, expiry cleanup, and immutable duplicate detection.
- Android bounded multi-peer GATT connections and targeted peer sends; Flutter native adapter fragments mesh packets and requires authenticated identity-to-address mapping.
- Incoming frame reassembly and authenticated identity handshake are still caller integration gates. BLE addresses must never be treated as node identities.
- Flutter tests/analyze and Android build were not run in the authoring environment; physical multi-device tests remain required.

# Milestone Tracker

## Milestone 5 — Mesh routing core status

**Deliverable:** integrated package with the M5 routing core, tests, protocol contract,
and acceptance matrix in [`docs/release/m5-mesh-routing-closure.md`](release/m5-mesh-routing-closure.md).

**Disposition:** routing-core implementation-complete, device integration pending.
The route queue and seen cache are in-memory only; the current Android transport is
single-peer-oriented and is not wired to this routing engine. Flutter analysis/tests,
Android build, and physical-device tests have not been run in this environment.

## Milestone 4 — Integrated hardening status

**Implementation package:** consolidated into one release candidate; see
[`docs/release/m4-integrated-closure.md`](release/m4-integrated-closure.md).

**Current disposition:** implementation-complete, verification-pending. Relay tests
run in this environment; Flutter/Dart compilation, Android build, physical-device
testing, and independent security review have not been completed here. Historical
M4.0–M4.13 headings below record implementation history, not separate user-facing
deliverables. Do not label the app production-ready or beta-approved until the
integrated acceptance gates pass.

## M0 — Foundation
- [x] Create requirements and architecture baseline
- [x] Add initial threat model and protocol draft
- [x] Add Flutter source scaffold and native method-channel placeholders
- [x] Add initial tests and CI workflow
- [ ] Run `flutter pub get`, `flutter analyze`, `flutter test`
- [ ] Verify Android build locally
- [ ] Verify iOS build on macOS/Xcode

## M1 — Direct-link experiment
- [ ] Confirm target Android/iOS device matrix
- [x] Add Android BLE permission declarations and runtime request path (device verification pending)
- [x] Add experimental Android BLE discovery/advertising/GATT source (compile + device verification pending)
- [ ] Implement iOS Core Bluetooth discovery and advertising
- [x] Define interoperable packet framing and maximum payload (Dart codec + v1 spec; native integration pending)
- [ ] Exchange non-sensitive test packets between physical devices
- [ ] Record range, latency, disconnect and reconnection observations
- [ ] Document platform-specific background limits

Do not mark any unchecked item complete without evidence from a test run.


## M1 implementation notes (2026-10-09)
- Added an Android native GATT service with a write characteristic and notification path.
- Added Flutter method calls `startBle`, `stopBle`, `sendBleFrame`, plus an event stream.
- Added Android BLE permission declarations and runtime permission request handling.
- **Not verified:** this repository lacks complete generated Gradle/platform scaffolding; no Flutter analysis, Android build, emulator test, or physical-device test was run here.
- Next: complete/verify Flutter Android project scaffolding, compile and fix issues, add UI controls, test two Android phones, then implement iOS Core Bluetooth.

- [x] Add Flutter BLE start/stop/test-frame controls and native event log (compile/runtime verification pending)

- [x] Add minimal Android Gradle Kotlin DSL files and theme resources (compatibility/build verification pending)
- [x] Add Windows-first build and troubleshooting guide


## M2: E2EE prototype (2026-10-09)
- [x] Add cryptography package dependencies
- [x] Add in-memory Ed25519/X25519 identity generation and fingerprint
- [x] Add signed, authenticated-encryption single-recipient envelope prototype
- [x] Add tests for round trip, pinned sender mismatch, wrong recipient, tampering, and empty input
- [ ] Run `flutter pub get`, `flutter analyze`, and `flutter test` locally
- [ ] Independent cryptographic review before real-world use
- [ ] Design key persistence, replay protection, contact verification/QR, and a reviewed ratchet protocol


## M2.2: Key persistence and contact verification
- [x] Add OS-backed secure storage wrapper for identity keys
- [x] Prevent automatic identity replacement when stored identity exists
- [x] Add public contact bundle parsing and fingerprint verification
- [x] Add verified-contact record serialization and tests
- [ ] Run dependency resolution, analyzer and tests on developer machine
- [ ] Add QR sharing/scanning and contact UI
- [ ] Review platform secure-storage configuration and backup behavior


## M2.3: Identity/contact UI
- [x] Display public identity bundle as a QR code
- [x] Import public contact bundle as JSON
- [x] Require fingerprint confirmation before saving trusted contact
- [x] Display and remove verified contacts
- [ ] Implement QR scanning on Android/iOS
- [ ] Run Flutter analysis/tests and validate on devices


## M2.4: QR contact import and key-change warnings (2026-10-09)
- [x] Add camera QR scanning page using `mobile_scanner`
- [x] Return scanned content as untrusted input; keep bundle parsing and fingerprint verification mandatory
- [x] Add Android camera permission and iOS camera usage description reference
- [x] Warn when a display name collides with a different verified fingerprint; never replace the old record silently
- [x] Add pure unit tests for same-name/different-key detection
- [ ] Run `flutter pub get`, `flutter analyze`, and `flutter test`
- [ ] Build and verify camera permission/scanning on physical Android and iOS devices
- [ ] Before production, extend fingerprints from 64 bits to at least 128 bits and review key-change UX


## M2.5: Verified contact and messaging integration (2026-10-09)
- [x] Increase identity fingerprints from 64 to 128 bits
- [x] Validate saved contact fingerprint shape and public-key lengths
- [x] Add service API for sealing to a verified contact
- [x] Add service API for sender-pinned decrypt and replay rejection
- [x] Add bounded persistent replay identifier store
- [x] Add replay identifier tests and integration documentation
- [ ] Run Flutter analyzer/tests and Android build
- [ ] Wire service into a durable conversation repository and UI
- [ ] Serialize inbound processing and decide retention/eviction policy
- [ ] Independent cryptographic review; production must use a reviewed protocol


## M2.6: First local conversation flow (2026-10-09)
- [x] Add conversation screen and verified-contact selector
- [x] Encrypt outgoing text through the verified-contact service
- [x] Persist local message records and encoded outgoing envelopes with bounded history
- [x] Add manual inbound-envelope import and plaintext persistence only after service validation
- [x] Keep outgoing delivery state QUEUED; do not claim network delivery
- [x] Add message record serialization tests and testing documentation
- [ ] Run Flutter analyzer/tests and Android build
- [ ] Validate two-device envelope exchange on physical devices
- [ ] Replace secure-storage message history with a proper encrypted database before scale
- [ ] Integrate actual BLE/relay transport and authenticated delivery receipts


## M3.0: BLE encrypted-envelope transport integration (2026-10-09)
- [x] Add bounded message fragmentation and out-of-order reassembly
- [x] Connect conversations screen to native BLE start/stop and frame events
- [x] Send encrypted envelope frames over the existing Android BLE transport
- [x] Reassemble inbound frames and require verified sender key + E2EE validation
- [x] Use IN_TRANSIT only after local Android accepts all frames; FAILED on transport exception
- [x] Add frame transfer tests and physical-device validation guide
- [ ] Run Flutter analyzer/tests and Android debug build
- [ ] Validate on two physical Android devices
- [ ] Add authenticated end-to-end receipts before sender-side DELIVERED state
- [ ] Add durable retry queue, exponential backoff, internet relay and routing


## M3.1: Durable reliable delivery (2026-10-09)
- [x] Version message records to v2 with expiry, retry count, next/last attempt timestamps; read legacy v1 records with defaults.
- [x] Add a bounded exponential retry policy with randomized jitter, eight-attempt limit, and seven-day expiry.
- [x] Recover due queued/in-transit messages while BLE is active and the matching contact conversation is selected.
- [x] Add stable application message IDs inside encrypted payloads and re-envelope retries to allow a new receipt after an earlier receipt is lost.
- [x] Add recipient-signed (E2EE envelope signature) and encrypted delivery receipts bound to message ID, exact envelope digest, recipient identity fingerprint, and timestamp. Sender marks DELIVERED only after receipt envelope verification and matching.
- [x] Serialize native inbound event processing to reduce replay-store races.
- [x] Add retry-policy, expiry, and v1-to-v2 metadata migration tests.
- [ ] Run `flutter pub get`, `flutter analyze`, and `flutter test` on a Flutter SDK host.
- [ ] Verify two-device receipt/duplicate/retry behavior on physical Android devices.
- [ ] Persist receipts independently for offline return paths; current receipts are sent immediately when BLE is active, while message retries can solicit a fresh receipt.
- [ ] Replace the bounded secure-storage message list with an encrypted database before scale.
- [ ] Independent cryptographic/protocol review; this remains a prototype and is not production-ready.


## M3.2: Receipt durability and delivery hardening (2026-10-09)
- [x] Add bounded OS-backed persistent queue for delivery receipts and receipt acknowledgements.
- [x] Persist receipt before BLE attempt; retry queued receipts with backoff when app is running and BLE is active.
- [x] Keep receipt queued until authenticated acknowledgement arrives.
- [x] Validate delayed receipts against persisted history of sent envelope digests.
- [x] Upgrade message record serialization to v3 while preserving v1/v2 migration behavior.
- [x] Add receipt/ack serialization and envelope digest history tests.
- [ ] Run `flutter pub get`, `flutter analyze`, and `flutter test` on a Flutter SDK host.
- [ ] Verify receipt loss, retry, app restart, and duplicate handling on two physical Android devices.
- [ ] Add OS-managed background execution only after platform-specific design and battery testing.
- [ ] Replace bounded secure-storage JSON queues with an encrypted database before scale.
- [ ] Independent security/protocol review before real-world sensitive use.


## M3.3: Android transport hardening (2026-10-09)
- [x] Serialize complete message/receipt frame batches in Flutter to prevent interleaving.
- [x] Invalidate queued batches and clear incomplete reassembly state when the BLE session stops or peer disconnects.
- [x] Add aggregate partial-transfer byte budget and observable reassembly cleanup.
- [x] Add bounded native Android FIFO frame queue.
- [x] Wait for client GATT write / server notification callbacks before resolving native frame-send calls.
- [x] Emit GATT readiness after client CCCD subscription succeeds or server peer enables notifications.
- [x] Add tests for sender serialization, failed-batch recovery, stale-session invalidation, reassembly memory budget, expiry, and clearing.
- [ ] Run Flutter analysis/tests and Android Gradle build on a configured toolchain.
- [ ] Validate disconnect/reconnect and mid-transfer loss on two physical Android devices.
- [ ] Implement iOS Core Bluetooth transport and define multi-peer topology before mesh routing.


## M3.4: Internet relay foundation (2026-10-09)
- [x] Define a versioned relay API for opaque envelope submission, recipient polling and queue acknowledgement.
- [x] Authenticate sender/recipient proof-of-possession with Ed25519 signatures and key-derived pseudonymous IDs.
- [x] Add SQLite-backed durable queues, TTL cleanup, mailbox quota, bounded envelope sizes and idempotent submission.
- [x] Reject conflicting message-ID reuse and bind recipient acknowledgements to sender, message ID and exact envelope digest.
- [x] Add relay tests for submit/poll, duplicates/conflicts, invalid signature, expiry, oversize payload, recipient-key mismatch and acknowledgement removal.
- [ ] Connect Flutter transport-neutral messaging to the relay API with TLS and bounded retries.
- [ ] Add nonce replay cache, edge/body limits, rate limiting, abuse controls, observability and deployment review before public exposure.
- [ ] Run mobile Flutter analysis/tests, Android build and two-device BLE/relay integration tests.
- [ ] Independent review of relay request signing and the existing E2EE protocol before production use.


## M3.5: Flutter internet relay client integration (2026-10-09)
- [x] Add a Dart relay client implementing the M3.4 Ed25519 canonical request signatures, identity IDs, submit, poll and acknowledgement endpoints.
- [x] Enforce HTTPS for non-loopback relay URLs; allow HTTP only for local development.
- [x] Verify received relay envelope size and SHA-256 digest before handing it to the app.
- [x] Add conversation UI controls to submit locally queued envelopes and poll the configured relay.
- [x] Route polled envelopes through verified-contact matching, signature/decryption, replay protection, local persistence and receipt generation before acknowledging the relay queue copy.
- [x] Keep relay acceptance separate from the end-to-end DELIVERED state.
- [x] Add tests for relay identity ID derivation and URL policy.
- [ ] Run `flutter pub get`, `flutter analyze` and `flutter test` on a Flutter SDK host.
- [ ] Test Flutter client against the relay API on two devices and verify retry/restart behavior.
- [ ] Add a durable automatic relay retry scheduler and connectivity-aware transport selection.
- [ ] Review nonce replay handling, server request limits, rate limiting, abuse controls, TLS deployment and protocol signatures before public exposure.


## M3.6: Automatic delivery orchestration
- [x] Add transport route planner preferring ready BLE and falling back to configured internet relay when BLE is unavailable.
- [x] Extend foreground retry-queue draining to choose BLE or relay automatically.
- [x] Persist relay attempt count, last-attempt time, next retry time and failure state.
- [x] Keep relay acceptance distinct from authenticated recipient delivery.
- [x] Add pure route-planner unit tests and a test guide.
- [ ] Run Flutter analyzer/tests and Android build on a configured Flutter toolchain.
- [ ] Test automatic fallback, duplicate submit/restart recovery and receipt arrival on two physical devices.
- [ ] Add relay routing for delivery receipts and acknowledgements.
- [ ] Add connectivity monitoring and platform-specific background scheduling after battery testing.


## M3.7: Unified receipts and recovery
- [x] Route queued delivery receipts and receipt acknowledgements over ready BLE or the configured internet relay.
- [x] Fall back to relay when a BLE receipt batch fails.
- [x] Keep delivery receipts queued until an authenticated receipt acknowledgement is received.
- [x] Use deterministic URL-safe relay IDs for exact envelope bytes to make uncertain HTTP retries idempotent.
- [x] Keep relay queue acknowledgement separate from the E2EE recipient receipt state.
- [x] Add a relay envelope-ID unit test and recovery documentation.
- [ ] Run Flutter analyzer/tests on a configured Flutter SDK host.
- [ ] Validate message + receipt + receiptAck over relay between two physical devices, including lost responses and app restart.
- [ ] Verify duplicate receipt delivery does not create duplicate visible messages and queue limits remain safe.
- [ ] Add platform-specific background scheduling only after lifecycle and battery testing.


## M3.8: Connectivity awareness and restart recovery
- [x] Observe app lifecycle and recover local queues when the app resumes.
- [x] Add foreground relay mailbox polling every 30 seconds when a valid relay URL is configured.
- [x] Resume retry/receipt queue draining using persisted next-attempt timestamps and expiry.
- [x] Document request-based internet availability detection and its limitations.
- [ ] Run Flutter analyzer/tests and Android/iOS builds on configured toolchains.
- [ ] Validate background/resume, force-stop/relaunch, network toggles, relay outage and delayed receipts on physical devices.
- [ ] Add native network-interface monitoring and OS-managed background scheduling only after platform/battery design.
- [ ] Verify no duplicate visible messages and authenticated-receipt-only delivery state.


## M3.9: Integration reliability and device validation gate
- [x] Add relay mailbox quota, strict-field validation, wrong-digest acknowledgement, and repeated-ack integration tests.
- [x] Document a two-device BLE/relay/restart/expiry release-gate matrix.
- [x] Document reproducible Flutter and relay validation commands.
- [ ] Run Flutter analyze/tests and Android/iOS builds on configured toolchains.
- [ ] Execute two-physical-device end-to-end test matrix and record results.
- [ ] Complete independent protocol/security review, TLS deployment, abuse controls, and privacy review before public beta.


## M4.0: Beta readiness and security hardening
- [x] **M4.8 — Android BLE setup recovery hardening (source change + validation plan).** Failed GATT service discovery and notification subscription now close the unusable client and resume scanning; scan starts are guarded against duplicates; partial startup failures clean up. Two-device tests remain pending. See `docs/android/m4-8-ble-recovery-validation.md`.
- [x] Serialize local message repository add/update mutations to reduce lost updates.
- [x] Scope message deduplication to peer fingerprint, direction, and application message ID.
- [x] Add a prototype threat model and explicit beta security checklist.
- [ ] Run Flutter analyzer, tests, and Android build on a configured toolchain.
- [ ] Test message-store concurrency and duplicate-delivery behavior on devices.
- [ ] Complete relay deployment hardening, replay review, transactional storage migration, and independent security review.


## M4.1: Storage and protocol hardening
- [x] Bind relay request nonces to canonical signed requests and reject reuse for a different request.
- [x] Preserve idempotent exact submit retries.
- [x] Serialize the mobile inbound replay-check/decrypt/record transaction.
- [x] Test submit nonce reuse, exact retry, and poll nonce reuse.
- [ ] Migrate mobile messages from secure-storage JSON to a transactional encrypted database.
- [ ] Run Flutter analyzer/tests and device concurrency tests.
- [ ] Review nonce retention and shared-store requirements for multi-instance relay deployment.


## M4.2: Encrypted transactional message persistence
- [x] Introduce SQLCipher-backed transactional SQLite message storage with key in platform secure storage.
- [x] Add legacy JSON migration that removes legacy data only after a committed import.
- [x] Add database-level peer-scoped unique message identity and bounded history.
- [ ] Resolve dependencies and run Flutter analyzer/tests on Android/iOS toolchains.
- [ ] Validate migration, crash recovery, key-loss behavior, and device concurrency.
- [ ] Define production key recovery and data-retention policies.


## M4.3: Storage migration validation and recovery
- [x] Fix Dart import placement for SQLCipher/path dependencies.
- [x] Reset cached database-open future and close database on migration failure.
- [x] Document fresh install, migration, duplicate, malformed-data, interruption, concurrency, restart, and key-loss cases.
- [ ] Add executable isolated database tests with test database factory and mock secure storage.
- [ ] Run Flutter pub get, analyze, test, Android build, and iOS build on configured hosts.
- [ ] Execute device migration/restart/concurrency matrix.


## M4.4: Storage lifecycle reliability
- [x] Serialize database close with queued add/update mutations.
- [x] Document database lifecycle, migration rollback, key-loss, deduplication, and retention tests.
- [ ] Add and run SQLCipher-backed Flutter integration tests.
- [ ] Run Flutter dependency resolution, analyzer, tests, and Android/iOS builds.
- [ ] Verify close/reopen and migration behavior on physical devices.


## M4.5: End-to-end delivery verification
- [x] Add relay mailbox lifecycle test: submit, repeated poll without ack, signed digest ack, and mailbox removal.
- [x] Document two-device BLE/relay acceptance matrix and test-record template.
- [ ] Run Flutter analyzer, unit/widget tests, and Android/iOS builds on configured hosts.
- [ ] Verify direct BLE delivery and receipt on two physical devices.
- [ ] Verify relay fallback, restart recovery, invalid receipt handling, and expiry on devices.


## M4.6: CI integration gates
- [x] Add Android debug APK build to Flutter CI after format/analyze/test gates.
- [x] Add a dedicated clean-environment relay pytest workflow.
- [x] Document what CI proves and what still requires physical devices.
- [ ] Run both GitHub Actions workflows on the repository and resolve any failures.
- [ ] Install APK on two Android devices and verify BLE, receipts, and relay fallback.
- [ ] Add iOS build/test job when macOS runner configuration is ready.


## M4.7: Android BLE permission lifecycle
- [x] Guard against overlapping runtime permission requests.
- [x] Recheck runtime permissions after callback and fail pending call on activity destruction.
- [x] Document Android 11/12+, BLE transfer, disconnect, and repeated-cycle acceptance tests.
- [ ] Run Flutter format/analyze/test and Android debug build in CI.
- [ ] Validate BLE transfer and reconnect on two physical devices.

## M4.13: Database key validation
- [x] Fail closed when a persisted SQLCipher key is malformed instead of silently replacing it.
- [x] Add unit tests for missing, valid, malformed, padded, and invalid-character keys.
- [x] Document safe recovery behavior and the verification limitation.
- [ ] Run Flutter analyzer/tests and Android debug build in CI.
- [ ] Verify encrypted database reopen and key-loss scenarios on Android devices.

## M4.12: Flutter verification pipeline
- [x] Make CI run formatting, static analysis, Flutter tests, and Android debug build.
- [x] Upload the successful CI debug APK as a short-lived artifact.
- [x] Add a repeatable local verification script and record exact verification limits.
- [ ] Observe a successful CI run; workflow has not been executed in this environment.
- [ ] Complete physical-device BLE and end-to-end delivery testing.

## M4.11: Delivery regression tests
- [x] Fix compatibility between receipt ID validation and padded base64url fallback IDs.
- [x] Add regression tests for padded IDs and malformed padding.
- [x] Add BLE reassembly tests for conflicting duplicate fragments and conflicting fragment counts.
- [x] Document regression findings and remaining validation work.
- [ ] Run Flutter tests/analyzer and two-device end-to-end scenarios.

## M4.10: End-to-end delivery audit
- [x] Scope authenticated receipt lookup to the outgoing message and verified sender.
- [x] Validate receipt message IDs and SHA-256 base64url envelope digests.
- [x] Add focused field-validation unit tests and document delivery invariants.
- [ ] Run Flutter formatter/analyzer/unit tests and SQLCipher-backed integration tests.
- [ ] Execute two-device delayed-receipt, wrong-sender, interrupted-transfer, and restart scenarios.

## M4.9: BLE recovery observability
- [x] Surface native BLE recovery, setup errors, and permission-denied events in the conversation UI.
- [x] Clear BLE-ready state and close the frame sender when native recovery tears down the client connection.
- [x] Document event semantics and device validation steps.
- [ ] Run Flutter format/analyze/test and Android build on a configured toolchain.
- [ ] Verify recovery UI and reassembly reset on two physical devices.

