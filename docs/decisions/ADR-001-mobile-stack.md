# ADR-001: Mobile Stack

Status: Accepted for prototype; revisit after M1 feasibility tests.

## Decision
Use Flutter/Dart for shared UI and application orchestration, with native Kotlin and Swift adapters for radio/network APIs.

## Context
A shared UI reduces solo-development cost. Native networking is needed because mobile operating systems expose platform-specific radio APIs and background constraints.

## Consequences
- Maintain native code on both platforms.
- Define stable platform-channel contracts.
- Test actual Android and iOS devices early.
- Do not assume simulator behaviour proves BLE correctness.
