# InLink

> **Current status — M13 security and release hardening source:** Android has an experimental multi-peer BLE transport, and an iOS CoreBluetooth central/peripheral implementation is now included with a shared method-channel contract. iOS project scaffolding, Flutter builds/tests, cross-platform physical-device validation, and independent security review remain pending. See [`docs/release/m13-security-release-hardening-closure.md`](docs/release/m13-security-release-hardening-closure.md).


**InLink** is a pseudonymous, privacy-first, hybrid messaging project for Android and iOS.

This repository is an evolving experimental prototype spanning the foundation, verified-contact encrypted messaging, Android BLE framing, retry metadata, and authenticated delivery-receipt flows.

> Status: early development only. Android BLE, the new iOS CoreBluetooth source, and the cryptographic envelope are not production-reviewed. The repository currently lacks a complete generated Xcode project; iOS source is not yet build-verified. The experimental relay API is connected to the Flutter client. Do not use this prototype for sensitive communication.

## Product principles

- Pseudonymous identity; no mandatory phone number.
- Offline-first local communication where the platform and radio topology permit it.
- Internet relays for global delivery when connectivity exists.
- Honest delivery states: queued is not delivered.
- Treat peers and relays as untrusted.
- Use reviewed cryptographic libraries; do not invent cryptography.

## Repository layout

- `app/`: Flutter mobile app and native platform integration.
  - `app/lib/core/network/mesh/`: experimental mesh routing core, SQLCipher durable queue, restart restoration coordinator, and native multi-peer BLE adapter.
- `docs/`: requirements, architecture, threat model, protocol draft and ADRs.
- `protocol/`: draft schema and test-vector notes.
- `relay/`: experimental Python/FastAPI + SQLite relay service and tests.
- `.github/workflows/`: starter CI workflow.

## Prerequisites

- Flutter stable SDK
- Android Studio / Android SDK
- Xcode and macOS for building/running iOS
- Git

Check the local toolchain:

```bash
flutter doctor
```

## Run the app

```bash
cd app
flutter pub get
flutter analyze
flutter test
flutter run
```

iOS builds and simulator/device runs require macOS with Xcode. BLE behaviour must be tested on physical devices; simulators are not sufficient to validate radio behaviour.

## Current implementation status

- [x] Product foundation docs
- [x] Flutter app scaffold
- [x] Transport-neutral network interface
- [x] Fake transport for UI/protocol development
- [x] Native method-channel placeholders for Android and iOS
- [x] Initial unit test
- [x] Experimental Android BLE/GATT frame transport (device validation pending)
- [x] Verified-contact E2EE message-envelope prototype
- [x] Bounded persistent message outbox with retry metadata and expiry
- [x] Persistent receipt/receipt-ack queue and authenticated delivery-state checks
- [x] iOS CoreBluetooth transport source and shared method-channel contract (build/device validation pending)
- [x] Experimental internet relay API and Flutter client integration (v2 development protocol)
- [x] Foreground Flutter relay adapter and BLE/relay route selection (background delivery not guaranteed)
- [x] Platform-neutral multi-hop routing core and transport adapter contract (native multi-peer transport and durable queue pending)
- [ ] Independent security review

## Security

See [`docs/threat-model.md`](docs/threat-model.md) and [`SECURITY.md`](SECURITY.md). This is an early development scaffold, not a production-ready secure messenger.


## Android BLE status
The Android GATT transport is experimental and source-level only in this environment. It has not been compiled or tested on physical devices. Review `docs/testing/android-ble-m1.md` and `docs/testing/android-transport-hardening-m3-3.md` before attempting the experiment.

The Android folder now also includes minimal Gradle build scripts and theme
resources. These have not been validated against a locally installed Flutter
SDK; follow `docs/testing/android-build-setup.md` and report the first build
error for a targeted fix.


## E2EE prototype status
The project contains an experimental signed/encrypted one-recipient envelope in `app/lib/core/security/secure_message.dart`, with identity material stored through the OS-backed vault. This is not a reviewed production messaging protocol and must not be used for sensitive communication. Run `flutter pub get`, `flutter analyze`, and `flutter test` before proceeding. See `docs/decisions/ADR-004-e2ee-prototype.md`.


## Identity persistence and contacts
The project now includes an experimental `IdentityVault` using OS-backed secure
storage and a public-contact fingerprint verification flow. Imported bundles
are not trusted until the user compares fingerprints through a separate trusted
channel. See `docs/testing/identity-and-contact-verification.md`.


## Identity/contact UI
A basic Identity & contacts page is now linked from the main toolbar. It displays
a QR code containing public keys only, supports JSON bundle import, requires
out-of-band fingerprint confirmation, and lists verified contacts. QR scanning
and local device verification remain future tasks. See `docs/testing/contact-ui.md`.

### Current milestone: M2.4 QR contact import
Camera-based QR import and same-name/different-key warnings are now scaffolded. Scanning does not establish trust; users must still compare the fingerprint through an independent trusted channel. See `docs/testing/contact-qr-scanning.md` for validation steps and known limitations.


### M2.5 verified messaging integration
The project includes verified-contact messaging APIs, 128-bit fingerprints, bounded persistent replay protection, and a conversation UI. See `docs/testing/verified-messaging-m2.5.md`.


### M2.6 first local conversation flow
The conversation UI encrypts outgoing messages for verified contacts and stores them locally. Manual envelope import remains available for controlled testing. Later M3 milestones connect this flow to experimental Android BLE. See `docs/testing/chat-flow-m2.6.md`.


### M3 BLE encrypted-envelope transport
The chat flow frames encrypted envelopes over the experimental Android BLE transport and reassembles incoming frames. `IN_TRANSIT` means local Android frame acceptance only; it is not proof of remote delivery. See `docs/testing/ble-message-transport-m3.md` and the M3.2 notes below.


### M3.1 delivery lifecycle (prototype)

- Outgoing records persist retry metadata and a seven-day expiry; old v1 records are read with safe defaults.
- Retries use bounded exponential backoff with jitter and a maximum of eight attempts. The queue runs while the app is open, BLE is active, and the selected conversation matches the queued recipient; mobile OS background execution is not guaranteed.
- `IN_TRANSIT` means local Android frame acceptance only. `DELIVERED` requires a receipt encrypted to the sender by the verified contact, with the envelope signature verified, the message ID and exact envelope digest matched, and the receipt addressed to the sender identity.
- M3.1 originally sent receipts immediately. M3.2 supersedes that behavior with a persistent receipt/receipt-ack queue and delayed-receipt digest history.
- Expiry and retry metadata are durable, but the current secure-storage JSON repository is bounded to 200 messages and is not a production database.
- **Not verified here:** Flutter dependency resolution, static analysis, unit tests, Android build, and two-device tests require a configured Flutter SDK and physical devices.


### M3.2 receipt durability and delivery hardening
Delivery receipts and receipt acknowledgements now have a separate bounded secure-storage queue. Receipts are saved before BLE transmission, retried while the app is running and BLE is active, and retained until an authenticated acknowledgement arrives. Outgoing messages retain sent-envelope digest history so delayed receipts for earlier retries can still be validated. This remains an experimental at-least-once delivery prototype; no Flutter analysis/tests, Android build, or physical-device validation has been run in this environment. See `docs/testing/reliable-delivery-m3-2.md`.


### M3.3 Android transport hardening
The experimental Android GATT transport now serializes native frame operations through a bounded FIFO queue and waits for GATT write/notification callbacks before reporting local frame-operation success. Flutter serializes complete frame batches, invalidates old-session queued work on disconnect, and only drains delivery/receipt queues after GATT readiness. Fragment reassembly has an aggregate memory budget and explicit lifecycle cleanup. These changes are source-only and remain unverified by Flutter tests, Gradle compilation, or physical-device runs. See `docs/testing/android-transport-hardening-m3-3.md`.


### M3.4 Internet relay foundation
A separate `relay/` service now provides an experimental FastAPI + SQLite API for opaque E2EE-envelope submission, signed recipient polling, bounded durable mailboxes, expiry, idempotent submission, and recipient-signed queue acknowledgements. The relay API is not yet connected to the Flutter app. Relay acceptance/queue acknowledgement is not end-to-end delivery; only the app's authenticated recipient receipt may eventually set `DELIVERED`. See `docs/protocol/relay-api.md` and `relay/README.md`. The relay prototype's Python tests passed in the available environment; Flutter analysis, Android builds, mobile integration, deployment hardening, and independent security review remain outstanding.


## Internet relay prototype (M3.5)

The conversation screen now includes a relay URL field with **Send queued** and **Poll relay** actions. The Flutter client signs relay requests with the local Ed25519 identity, verifies downloaded envelope digests, and routes incoming envelopes through the same verified-contact/E2EE/replay-protection path used by BLE. Configure a relay service using [`relay/README.md`](relay/README.md). Non-loopback endpoints must use HTTPS.

This is a manually triggered development integration, not a background messaging service. Relay queue acknowledgement is distinct from end-to-end `DELIVERED`. Flutter analysis, device builds and two-device integration tests still need to be run on a configured Flutter toolchain.


M3.6 adds foreground automatic delivery route selection: ready BLE is preferred, with configured internet relay fallback when BLE is unavailable. See `docs/testing/delivery-orchestration-m3-6.md`.


M3.7 routes persistent delivery receipts and acknowledgements over BLE or the internet relay, with deterministic relay IDs for exact encrypted envelopes. See `docs/testing/receipts-recovery-m3-7.md`.


M3.8 adds foreground lifecycle recovery and periodic relay polling when configured. This is not a guarantee of OS background delivery. See `docs/testing/connectivity-recovery-m3-8.md`.


M3.9 adds relay integration reliability tests and the two-device release-gate matrix. Physical-device and Flutter validation remain pending. See `docs/testing/integration-reliability-m3-9.md`.


M4.0 adds local repository mutation serialization, peer-scoped deduplication, and a beta threat model. Mobile builds/device tests and independent security review remain pending. See `docs/security/m4-beta-threat-model.md`.


M4.1 hardens signed relay request nonce handling and serializes inbound replay checks. Mobile transactional database migration and Flutter/device validation remain pending. See `docs/security/m4-beta-threat-model.md`.


M4.2 introduces SQLCipher-backed transactional message storage with legacy JSON migration. Flutter dependency resolution, analyzer/tests, mobile builds, and migration fault-injection remain pending. See `docs/storage/m4-2-encrypted-transactional-storage.md`.


M4.3 fixes SQLCipher import placement and failed-open/migration recovery handling, and adds a detailed storage validation matrix. Flutter tests/builds and device migration tests remain pending. See `docs/storage/m4-3-migration-validation.md`.


M4.4 serializes database close with queued repository mutations and documents storage lifecycle regression tests. SQLCipher-backed Flutter tests/builds and device validation remain pending; see `docs/storage/m4-4-storage-lifecycle-tests.md`.


M4.5 adds an end-to-end relay mailbox lifecycle regression test and a two-device delivery acceptance matrix. Mobile end-to-end tests remain pending; see `docs/messaging/m4-5-delivery-verification.md`.


M4.6 adds CI gates for Flutter formatting, analysis, tests, Android debug APK assembly, and relay server tests. The workflows need to run in the Git repository; physical-device delivery and iOS validation remain pending. See `docs/release/m4-6-ci-integration-gates.md`.


M4.7 hardens Android BLE permission request lifecycle handling and adds a two-device validation matrix. Physical-device tests and Android build verification remain pending; see `docs/android/m4-7-device-validation.md`.

M4.8 Android BLE setup recovery validation: `docs/android/m4-8-ble-recovery-validation.md`.

M4.9 BLE recovery observability: `docs/android/m4-9-transport-observability.md`.

M4.10 delivery audit: `docs/security/m4-10-delivery-audit.md`.

M4.11 delivery regression tests: `docs/security/m4-11-delivery-regression-tests.md`.

M4.12 Flutter verification: run `./scripts/verify_flutter.sh` with Flutter and Android SDK installed. See `docs/release/m4-12-flutter-verification.md`.

M4.13 database key validation: malformed persisted database keys now fail closed instead of being silently overwritten. See `docs/storage/m4-13-database-key-validation.md`.


## Milestone 7 — Authenticated Mesh Identity and Ingress

This package adds a signed, short-lived challenge/proof handshake that binds a
BLE transport address to a deterministic pseudonymous node ID only after
verification against a previously trusted contact. It also adds an ingress
coordinator that joins reassembled native packets, routing, contact lookup and
the existing E2EE verification/decryption/replay checks. See
`docs/protocol/mesh-identity-handshake-v1.md`,
`docs/testing/m7-authenticated-mesh-ingress.md`, and
`docs/release/m7-authenticated-mesh-ingress-closure.md`.

The new coordinator is an integration surface, not a claim that every UI
lifecycle path is already wired. Run Flutter analysis/tests, build Android,
and validate the handshake and delivery flow on physical devices before use.


## Milestone 8 — Application Messaging Orchestration

`app/lib/core/network/mesh/mesh_application_service.dart` composes verified
contact encryption, durable mesh queueing, startup recovery, inbound event
handling, retry triggers, and signed+encrypted recipient receipts. It deliberately
does not equate local transport acceptance with delivery. Read
`docs/release/m8-application-integration-closure.md` for remaining integration
gaps and `docs/testing/m8-application-integration.md` for required validation.


## Milestone 9 — Durable Mesh Outbox

M9 bridges the mesh application service to the SQLCipher conversation repository.
Outgoing encrypted envelopes and pending receipt expectations can be rebuilt
after process restart; inbound text is persisted before acknowledgement. The
history policy protects pending outgoing records from routine eviction. See
`docs/release/m9-durable-mesh-outbox-closure.md` and
`docs/testing/m9-durable-mesh-outbox.md`. UI wiring and device validation remain
explicitly outstanding.


## M14 — Beta Deployment Preparation

See [`docs/release/m14-beta-deployment-closure.md`](docs/release/m14-beta-deployment-closure.md) and the runbooks in `docs/beta/`. This package prepares a controlled beta process; it does not claim store publication or production readiness.
