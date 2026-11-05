# M7 Closure — Authenticated Mesh Identity and Ingress

## Delivered in this package

- Signed, challenge-based peer proof using existing Ed25519 identity material.
- Stable pseudonymous node ID derived from signing/encryption public keys.
- Strict size, key-length, version, field-set, challenge-expiry and replay checks.
- BLE address binding occurs only after proof verification against a previously
  user-verified contact.
- Ingress coordinator connecting frame reassembly, mesh routing, trusted-contact
  resolution and the existing E2EE open/replay-protection service.
- Protocol specification, test plan and handshake unit tests.

## Acceptance status

| Area | Status |
|---|---|
| Source/docs included in archive | Complete |
| Relay regression tests | Run when packaging; see delivery summary |
| Flutter unit tests/analyze | Not run if Flutter/Dart SDK unavailable |
| Android build and physical devices | Pending external validation |
| Mutual handshake in both directions | Supported by running the exchange both ways; device wiring still required |
| E2EE destination processing | Coordinator added; app lifecycle/chat UI wiring still requires integration |
| Cryptographic audit | Not performed |

## Security boundaries

- A successful handshake authenticates a known public identity for a BLE link;
  it does not itself encrypt the BLE link or establish forward secrecy.
- Unknown contacts remain untrusted. User fingerprint verification is still
  required before a key is admitted to the trusted contact list.
- Intermediate routers only see the opaque E2EE envelope and routing metadata.
- No production-readiness claim is made. CI, Android compilation, two-device
  validation and independent security review remain release gates.
