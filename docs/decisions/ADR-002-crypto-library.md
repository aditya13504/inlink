# ADR-002: Cryptographic Library

Status: Open — must be resolved before implementing private messaging.

## Decision
Do not write custom cryptographic primitives. Evaluate maintained libraries for asynchronous end-to-end messaging, cross-platform support, key lifecycle, licensing and security review history.

## Acceptance criteria
- Document protocol and threat model.
- Verify supported Dart/Android/iOS integration paths.
- Verify key storage and backup assumptions.
- Verify interoperability and test vectors.
- Record maintenance and licensing risks.
- Obtain security review before production.
