# M4.0 — Beta readiness and security hardening

## Status

This milestone adds a serialized local message-store mutation queue, scopes
message deduplication to `(contact fingerprint, direction, application message
ID)`, and documents the security gates required before a public beta.

The code change reduces the chance that overlapping local read-modify-write
operations overwrite each other, and prevents an ID chosen by one peer from
colliding with a different peer's message. It does **not** make the current
secure-storage JSON blob a production database or provide cross-process locking.

## Threat model (current prototype)

### Assets
- Local identity private keys and verified-contact keys.
- Plaintext message bodies and delivery metadata.
- Queued ciphertext and message IDs.
- Sender/recipient relationships, timing, IP addresses, and relay mailbox activity.

### Trust boundaries
- BLE peer discovery and transport are untrusted until envelope signature,
  pinned-contact identity, and authenticated decryption all succeed.
- Relay operators are not trusted with plaintext, but can observe IP addresses,
  timing, ciphertext sizes, mailbox identifiers, and traffic patterns.
- Local app storage is protected by platform secure storage where available,
  but the current one-blob repository has bounded capacity and no transactional
  database semantics.
- QR/fingerprint exchange depends on users comparing fingerprints over a trusted
  channel. QR transfer alone does not establish out-of-band identity assurance.

### Explicitly out of scope for beta approval
- Forward secrecy / post-compromise security from a Double Ratchet.
- Multi-device identity and key recovery.
- Group chats, anonymous network routing, traffic-analysis resistance.
- Guaranteed BLE background delivery, global reach without a path, or protection
  against a compromised operating system.
- A claim that the current prototype has received independent cryptographic review.

## Required security work before public beta

- [ ] Replace prototype key exchange/session protocol with a reviewed,
      well-specified protocol providing forward secrecy and key rotation, or
      document a restricted private-alpha threat model and obtain expert review.
- [ ] Review nonce/replay semantics across BLE, relay submission, polling,
      and acknowledgements; add request replay tests without breaking safe retries.
- [ ] Test corrupted, oversized, truncated, malformed, stale, and duplicate frames.
- [ ] Review identity import/export, fingerprint normalization, QR parsing, and
      contact replacement flows.
- [ ] Move message persistence to a transactional encrypted database with schema
      migrations and atomic writes; define retention and secure deletion behavior.
- [ ] Verify no logs, crash reports, analytics, or notifications leak plaintext,
      private keys, or sensitive contact data.
- [ ] Deploy relays only behind HTTPS/TLS termination; configure request/body
      limits, rate limits, abuse reporting, mailbox quotas, retention, backups,
      patching, and monitoring without logging message bodies.
- [ ] Complete dependency/license review, threat modeling, and independent
      security assessment.

## Local validation

Relay tests:

```bash
cd relay
python -m pip install -r requirements.txt
python -m pytest -q tests
```

Flutter validation from `app/`:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

No Flutter/Dart toolchain or physical devices are available in this build
environment. Therefore mobile tests/builds and real-device security checks remain
**not run**, not passed. The relay test suite is the only executable test suite
run as part of this milestone.


## M4.1 protocol hardening update

The relay persists a nonce per signing identity and binds it to the SHA-256
digest of the canonical signed request. Reusing the same nonce for a different
request returns `409 request_nonce_reused`; exact retries with the same nonce
and canonical request remain safe. Nonce records older than 24 hours are purged.

The mobile verified-message service serializes fingerprint checking, replay
lookup, authenticated decryption, and replay recording as one inbound queue,
closing a concurrent same-instance replay-check race.

Remaining limitations: multi-instance relay deployments need a shared atomic
nonce store. The Flutter message store remains a bounded secure-storage JSON
blob, not a transactional database. Independent security review is still needed.
