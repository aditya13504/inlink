# Beta Operations and Monitoring

## Minimum operational readiness

Before operating a relay for testers, the operator must document the service owner, escalation path,
deployment region, TLS termination, ingress limits, rate controls, storage permissions, backup and
restore process, mailbox expiry/cleanup, abuse response, and planned maintenance window.

## What to monitor

Only instrument metrics that the implementation actually emits and the privacy review approves.
Potential operational indicators include:

- Relay process health, request error rate, latency, and resource pressure.
- Rate-limit events and malformed/oversized request counts.
- Mailbox depth, expiry cleanup, and storage health.
- App startup crashes and transport failures, if reliable and privacy-reviewed telemetry exists.
- Tester-reported delivery/receipt failures and platform-specific regressions.

Do not claim crash-free rates, delivery success rates, or active-user counts unless the telemetry
exists, has a documented definition, and is validated. Prefer aggregate counters. Never log
plaintext, private keys, authorization headers, full envelopes, or contact identifiers unnecessarily.

## Incident severity and response

- **Critical:** suspected key/plaintext exposure, identity compromise, message tampering, false
  authenticated receipt, or exploitable critical issue. Pause beta expansion immediately.
- **High:** severe privacy/security defect, broad crash/launch failure, or widespread inability to
  message. Pause affected distribution and investigate.
- **Medium/Low:** limited functional defect without security or data-integrity impact. Triage, assign
  owner, set target fix version, and add regression coverage.

Every incident record should include a redacted timeline, affected versions, impact, containment,
root cause, fix, regression test, user communication decision, and follow-up owner. Keep access
limited and follow the approved retention policy.

## Stop / rollback

Keep the prior approved artifact and release notes available. Revoke beta access or pause invitations
when a stop trigger is reached. If an app rollback is not technically possible, publish a clear
pause/disable/uninstall instruction and state what happens to locally stored test data. Never promise
remote deletion of data from devices or relays unless it is implemented and verified.
