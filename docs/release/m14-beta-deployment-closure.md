# M14 Closure — Beta Deployment Preparation

## Delivered

- Android restricted-beta distribution runbook.
- iOS/TestFlight runbook that explicitly records the incomplete Xcode project scaffold blocker.
- Beta phase plan with release gates, internal smoke-test scenarios, rollback triggers, and exit review.
- Tester consent/privacy notice template.
- Redacted bug-report and messaging-delivery templates.
- Relay/app operations and monitoring guidance.
- Per-build release evidence record template.
- `scripts/validate_m14_beta.py` source-level readiness guardrail.
- Security workflow integration for the M14 validator.

## Actual status

**NOT APPROVED for external beta deployment.** This milestone prepares the beta process and evidence
templates; it does not publish a build to Google Play, App Store Connect, or TestFlight.

No Android/iOS builds, store uploads, tester invitations, production relay deployment, or physical
cross-platform acceptance runs are asserted by this archive. The iOS Xcode project scaffold is still
incomplete as recorded by the preceding milestone. Flutter/Dart toolchain availability, signing,
store configuration, and independent security review remain external gates.

## Required next actions before an external beta

1. Run the full source and relay CI on the hosted CI service and resolve findings.
2. Run Flutter formatting, analysis, tests, and Android build with pinned SDKs.
3. Create and review the complete iOS project; build and test on a supported macOS/Xcode runner.
4. Complete physical-device BLE and relay acceptance, including authenticated delivery receipts,
   restart recovery, duplicate/replay behavior, permissions, and background limitations.
5. Review the tester notice, privacy disclosures, data retention, and support/security contacts.
6. Complete required security review and resolve critical/high findings.
7. Record build checksums and provenance, then obtain explicit release-owner approval.

A successful M14 source validator means only that the expected beta preparation artifacts and wording
are present.
