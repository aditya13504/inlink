# InLink Milestone Tracker

## Completed in repository (implementation status; external gates may remain)
- M0–M8: see individual milestone closure documents.
- M9: durable mesh outbox and conversation state.
- M10: chat UI and mesh application lifecycle seam.
- M11: native Android mesh runtime composition and challenge/proof identity control channel; device validation remains pending.
- M12: iOS CoreBluetooth transport source and cross-platform reliability contract; iOS project scaffold, build, and physical interoperability validation remain pending.

## M9 remaining gates
- Chat UI wiring and transport selection.
- Flutter/Dart tests, analysis and Android build.
- Two-device and multi-hop physical testing.
- Independent cryptographic review.

## M10 remaining gates
- Wire a real multi-peer `MeshPeerTransport` and authenticated node-ID directory into the default app composition root.
- Run Flutter tests/analyzer and Android build.
- Verify two-device and three-node mesh behavior on physical hardware.
- Implement iOS Core Bluetooth and complete independent cryptographic review.

## M11 remaining gates
- Run `dart format lib test`, `flutter pub get`, `flutter analyze`, `flutter test`, and Android debug build on a Flutter-enabled host.
- Validate bilateral identity authentication and message receipts on two physical Android devices.
- Validate three-node store-and-forward, process recovery, and reconnect behavior.
- Implement and test iOS Core Bluetooth mesh integration.
- Complete independent cryptographic and privacy review before any beta approval.

## M12 remaining gates
- Generate/restore a complete Flutter iOS Runner project and integrate the new AppDelegate/Info.plist changes.
- Run Dart formatting, Flutter analysis/tests, Android debug build, and iOS no-code-sign build.
- Validate Android↔iOS and iOS↔iOS transport on physical devices, including negotiated MTU and frame queue behavior.
- Validate authenticated contact binding and receipt-only delivery status across platforms.
- Measure background restrictions and battery use before enabling iOS background modes.


## M13 — Security & Release Hardening
- [x] Update the security policy to match the current experimental architecture.
- [x] Add a focused repository security-baseline validator.
- [x] Add a least-privilege CI security workflow with relay tests, Bandit, and dependency audit.
- [x] Document security controls, manual acceptance gates, and explicit release blockers.
- [ ] Run the new workflow on the hosted CI service and resolve any findings.
- [ ] Complete Flutter/Android/iOS builds and physical cross-platform acceptance.
- [ ] Complete independent security and cryptographic review.

## M13 release decision
Source hardening is delivered, but production/public-beta security approval is **not granted**.


## M14 — Beta Deployment Preparation
- [x] Add Android restricted-beta distribution runbook.
- [x] Add iOS/TestFlight runbook with explicit Xcode scaffold blocker.
- [x] Add staged beta plan, tester consent/privacy template, and feedback/bug report template.
- [x] Add operational monitoring, incident severity, and rollback guidance.
- [x] Add per-build release evidence record and M14 source validator.
- [ ] Execute configured Flutter/Android/iOS builds and hosted CI.
- [ ] Complete physical-device BLE/relay/receipt acceptance.
- [ ] Complete independent security review and approve tester privacy materials.
- [ ] Obtain release-owner approval and publish a real beta candidate.

## M14 release decision
Beta preparation artifacts are delivered, but external beta deployment is **NOT APPROVED** until the
documented build, security, privacy, and device acceptance gates have evidence.
