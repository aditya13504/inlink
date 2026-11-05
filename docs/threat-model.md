# Threat Model — Initial

## Assets
- Private identity keys and session keys.
- Plaintext messages and local conversation history.
- Contact identity bindings.
- Delivery metadata and relay queues.
- App signing/build integrity.

## Adversaries
- Passive radio or network observer.
- Malicious or compromised peer.
- Malicious relay operator.
- Packet replay/flooding attacker.
- Person with temporary access to an unlocked or stolen device.
- Attacker distributing a modified application.

## Trust boundaries
- Flutter/Dart app to native platform code.
- Device to nearby peer.
- Device to internet relay.
- Community relay to another relay/bridge.
- App build pipeline to installed application.

## Required controls
- Use established, reviewed cryptographic libraries.
- Verify peer identity for private conversations.
- Authenticate acknowledgements.
- Use message IDs and replay protection.
- Bound packet size, queue size, retry rate and storage retention.
- Avoid logging plaintext or private keys.
- Store sensitive key material with platform-protected facilities.
- Make relay metadata retention explicit and minimal.
- Pin dependencies and protect release signing.
- Independently review security-critical paths before production.

## Known limitations
Encryption does not hide all metadata. A compromised endpoint can expose plaintext. A relay can delay/drop traffic. Offline communication cannot bridge a physical/network gap without a relay path. OS background restrictions can interrupt availability.

## Release gate
No public production release before a documented cryptographic design, external security review, recovery/key-rotation plan and incident-response process.
