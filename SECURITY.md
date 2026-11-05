# Security Policy

InLink is an early-stage, experimental messaging project. **Do not use it for emergency,
safety-critical, or high-risk communication.** The presence of cryptographic code, signed
relay requests, local encrypted-storage code, or BLE peer authentication does not mean the
whole system has been independently audited or is production-secure.

## Reporting a vulnerability

Until a private security reporting channel is formally published, do not post exploit details,
private keys, message contents, or sensitive logs in public issues. Contact the project
maintainer through a private channel agreed by the project owner. Include the affected commit,
platform, impact, reproduction steps, and a redacted proof of concept. Do not include real user
data or secrets.

## Current security posture

- The relay prototype verifies signed requests and stores opaque envelopes; it can still observe
  routing metadata and can delay, drop, replay-attempt, or selectively withhold traffic.
- Mobile identity, envelope, storage, replay-protection, delivery-receipt, and native transport
  components are evolving prototypes. They have not received an independent end-to-end audit.
- BLE discovery and a transport handle are not proof of identity. Only the app's authenticated
  identity flow should establish trust.
- A relay's HTTP acceptance is not proof of recipient delivery. Delivery requires a verified
  authenticated recipient receipt.
- Radio/network gaps, OS background limits, powered-off devices, and malicious intermediaries can
  prevent delivery. No global delivery guarantee is made.
- Experimental crypto formats and protocol versions may change before a stable release.

## Vulnerability handling

1. Acknowledge receipt privately and assign an owner.
2. Reproduce in a non-production test environment; preserve logs with secrets and message content
   removed.
3. Assess severity, affected versions, exploitability, and user impact.
4. Prepare a fix and regression test; do not silently weaken protocol checks to restore availability.
5. Coordinate a release/advisory and user action where needed.
6. Record the incident, root cause, and follow-up controls.

## Production release blockers

A public production release is blocked until all applicable items are complete:

- A documented, reviewed protocol and cryptographic design, including key generation, storage,
  rotation, recovery, deletion, and identity-change handling.
- Independent security review of mobile clients, relay, native BLE boundary, storage, and update
  pipeline; no unresolved critical/high findings in security-critical paths.
- Supported Flutter/Dart/Android/iOS toolchains; reproducible CI builds and platform-specific
  signing/release procedures.
- Authenticated multi-device interoperability tests for BLE, relay, receipts, restart recovery,
  and duplicate/replay behavior.
- Production relay TLS termination, abuse/rate controls, operational monitoring, backup/retention
  policy, and privacy review.
- A private vulnerability intake path, incident-response owner, and release rollback procedure.
- A reviewed dependency inventory and resolved critical/high dependency advisories.

Passing source checks or unit tests alone does not satisfy these gates.
