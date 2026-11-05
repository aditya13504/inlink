# M14 — Beta Deployment Plan

## Purpose

Prepare InLink for a controlled, opt-in beta after the required build, security, privacy, and
device-acceptance gates have evidence. This milestone supplies the process and release artifacts;
it does not claim that a beta has been published or that the app is production-ready.

## Beta principles

- Invite only testers who understand this is experimental software.
- Do not use InLink for emergency, safety-critical, or high-risk communication.
- Use test identities and non-sensitive test messages; never seed real private keys or user data.
- Explain that end-to-end encryption and local encrypted storage are not independently audited.
- Explain that relays can observe metadata and may delay, drop, or withhold messages.
- Do not promise delivery without a viable BLE or internet path and a verified recipient receipt.
- Collect the minimum diagnostics needed; redact message contents, keys, tokens, and identifying data.
- Provide an exit path: testers can stop testing, uninstall, and request deletion of any feedback data
  that the project team controls.

## Phase 0 — Evidence before inviting testers

The release owner must attach evidence for each applicable gate:

- [ ] A clean CI run of M11, M12, and M13 source checks.
- [ ] Relay tests pass and dependency/static-analysis findings are reviewed.
- [ ] Flutter format/analyzer/tests pass on the pinned toolchain.
- [ ] Android debug/release candidate builds successfully; signing configuration is external to source.
- [ ] A complete iOS Xcode project exists and builds on a supported macOS/Xcode runner.
- [ ] Physical Android BLE tests pass, including authentication, reconnect, duplicate frames, receipts,
      restart recovery, and malformed frames.
- [ ] Cross-platform Android/iOS tests pass where iOS support is claimed.
- [ ] Privacy notice, tester consent, retention policy, and feedback contact are approved.
- [ ] Known limitations and unresolved issues are published with the invitation.
- [ ] Independent security review status and unresolved findings are disclosed.

**Do not invite external testers while a critical/high security issue is unresolved or a claimed
platform has not passed its required build and acceptance tests.** A private developer-only
smoke test may be used to gather the missing evidence.

## Phase 1 — Internal smoke test

Use a small team and test identities. Validate install, first launch, identity creation/recovery
behavior, contact verification, one-to-one messaging, relay path where configured, BLE path,
authenticated delivery receipt, offline queue behavior, duplicate/replay handling, restart recovery,
permission denial, radio/network loss, and uninstall/data-removal behavior. Capture outcomes without
capturing message content or secrets.

## Phase 2 — Closed beta

1. Freeze a source commit and version/build number.
2. Produce signed artifacts using the team's protected signing process; do not commit keystores,
   provisioning profiles, certificates, passwords, or tokens.
3. Generate checksums and retain build provenance.
4. Publish release notes, privacy/consent copy, known issues, and rollback instructions.
5. Invite a limited cohort using an approved distribution channel.
6. Review crash reports and feedback on a defined cadence; triage security reports immediately.
7. Stop expansion if crash rates, message integrity, identity verification, privacy, or security issues
   cross the team's pre-agreed stop criteria.

## Phase 3 — Review and exit

At the end of the test window, summarize tester count, platform/version distribution, install success,
crash-free sessions (only if trustworthy telemetry exists), messaging/receipt results, issue severity,
and user feedback. Do not invent metrics if telemetry is absent. Decide to continue, fix and repeat,
or stop. Public release requires a separate decision and security review.

## Rollback / pause triggers

Immediately pause new invitations and distribution if there is suspected plaintext/key exposure,
identity spoofing, message integrity failure, delivery receipts accepted without recipient
authentication, a critical/high exploitable issue, unexpected collection of sensitive data, or
widespread launch/crash failure. Preserve only redacted diagnostic evidence needed for response.
