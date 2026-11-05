# InLink Milestone 4 — Integrated Hardening Closure

**Scope:** durable encrypted local storage, delivery integrity, replay resistance,
relay reliability, Android BLE recovery, observability, and automated verification.

**Disposition:** the integrated implementation package is assembled. The code and
relay behavior checks that can run in this environment pass. The overall milestone
is **not release-verified** until Flutter CI and physical-device gates below pass.

## Included in this integrated package

- SQLCipher-backed transactional message storage, schema migration, serialized
  mutations, bounded retention, and fail-closed validation of a malformed stored
  database key.
- Persistent message/receipt retry metadata, peer-scoped deduplication, replay
  protection, strict receipt checks, and delivery-state audit rules.
- Relay-side strict request schemas, Ed25519 authentication, timestamps, nonce
  reuse detection, idempotent submissions, expiry/quota enforcement, and digest-
  matched acknowledgements.
- Relay API v2: poll authentication is in a POST body instead of query parameters,
  and the poll limit is covered by the signature. The Flutter client and relay
  server have been updated together; the old v1 routes are intentionally not kept
  as compatibility aliases because this prototype has no production clients.
- Android BLE permission/reconnect hardening and observable transport recovery.
- Flutter CI for formatting, analysis, unit/widget tests, debug APK build, and APK
  artifact upload; relay CI; a local Flutter verification script.
- Security, recovery, integration, and acceptance documentation.

## Validation actually performed for this package

- Relay pytest suite: **17 tests passed**.
- Python source compilation: checked during packaging.
- Relay v2 contract checks: route/version behavior, POST-only polling, nonce replay,
  altered signed limit, strict request fields, idempotent delivery, digest checks,
  and mailbox quota.
- Workflow YAML parsed successfully in the earlier pipeline check.
- ZIP archive integrity checked after packaging.

## External gates still required

These are deliberately not marked passed because the required toolchain/devices are
not available in this build environment. No `app/pubspec.lock` could be generated here:

1. Run `flutter pub get` on a machine with Flutter stable and Android SDK, review
   and commit the generated `app/pubspec.lock` for reproducible dependency resolution,
   then run `./scripts/verify_flutter.sh`. Formatting, `flutter analyze`, all Flutter
   tests, and `flutter build apk --debug` must pass.
2. Confirm the CI workflow succeeds on the exact packaged commit and retrieve the
   generated `inlink-android-debug` artifact.
3. Test on at least two physical Android phones: BLE discovery, connect, notification
   subscription, full fragmented transfer, duplicate/conflicting fragments,
   disconnect mid-transfer, reconnect, app pause/resume, permission denial/regrant,
   and receipt after delayed/retried delivery.
4. Test database reopen/migration and key-loss/corruption cases on a device. Never
   silently delete an encrypted database or overwrite a malformed stored key.
5. Conduct an independent cryptographic and application security review before
   any sensitive or public-beta use.

## Explicit non-goals / known limits

- The current E2EE envelope is a prototype and does not provide a reviewed Double
  Ratchet / post-compromise security guarantee.
- iOS transport and cross-platform physical-device validation are not complete.
- BLE background delivery is not guaranteed; delivery requires a viable route.
- Relay operators still observe metadata. Public relay deployment needs TLS, edge
  rate/body limits, abuse controls, monitoring, backups, retention policy, and
  operational ownership.
- A relay queue acknowledgement is not the app's authenticated end-to-end
  `DELIVERED` receipt.
- This package is not production-approved.

## Single acceptance decision

Milestone 4 may be called **release-verified** only when the Flutter CI/build and
physical-device/security gates above have recorded passing evidence. Until then,
call it **implementation-complete, verification-pending**.
