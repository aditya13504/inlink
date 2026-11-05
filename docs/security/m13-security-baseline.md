# M13 — Security Baseline and Release Hardening

## Scope

M13 adds a repeatable source-level security gate and makes the release blockers explicit. It does
not certify the app as secure, replace a cryptographic audit, or claim that platform builds have
passed.

## Assets and security boundaries

- Identity and session private keys; SQLCipher database key.
- Plaintext before encryption and after authenticated decryption; local conversation history.
- Contact fingerprints, key-change decisions, replay state, and delivery receipts.
- Opaque relay envelopes, recipient identifiers, timestamps, request nonces, and mailbox state.
- Native BLE handles, frame queues, application build artifacts, signing credentials, and CI tokens.

Trust boundaries include Dart/native method channels, peer discovery versus verified identity,
local storage versus secure key storage, app-to-relay HTTPS, relay persistence, CI dependencies,
and signed release artifacts.

## Minimum controls

1. Keep discovery and BLE addresses/UUIDs separate from identity trust.
2. Verify signatures and bind signatures to canonical request fields; reject malformed lengths,
   unsupported protocol versions, expired timestamps, invalid digests, and nonce reuse for a
   different request.
3. Treat exact idempotent retries differently from a nonce reused for different request content.
4. Bound envelope/frame size, mailbox size, TTL, retries, and queue retention.
5. Do not log plaintext, private keys, authentication headers, or full signed request bodies.
6. Keep relay acceptance distinct from authenticated recipient delivery.
7. Ignore build outputs, local databases, environment files, and signing artifacts in source control.
8. Use least-privilege workflow permissions and automated dependency/source scans.
9. Do not embed production secrets in source, app assets, CI logs, or example configs.
10. Make security-sensitive failures explicit; do not silently generate replacement database keys
    after detecting a malformed persisted key.

## Automated checks added in M13

- `python scripts/validate_m13_security.py`: repository security-baseline assertions.
- Relay workflow: unit tests, source baseline checks, Bandit static analysis, and `pip-audit`.
- Flutter workflow: existing format, analyzer, tests, and Android debug build; these still require
  a working Flutter toolchain and successful CI execution.

The repository validator is intentionally a focused guardrail, not a general secret scanner or
proof of security. Use dedicated secret scanning and code review before accepting contributions.

## Release decision

The current status is **NOT APPROVED for production**. The iOS Xcode project scaffold is
incomplete, Flutter/Android/iOS builds have not been confirmed in this environment, no physical
cross-platform mesh acceptance run has been recorded, and independent security review remains
outstanding.

Do not remove or downgrade these blockers merely to obtain a green CI run.
