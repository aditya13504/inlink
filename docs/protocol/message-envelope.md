# Message Envelope — Conceptual Sketch

This is not a finalized wire schema. Do not implement security decisions based on this sketch alone.

Conceptual fields:
- protocol_version
- message_id: cryptographically random unique identifier
- conversation_ref: opaque reference
- sender_key_ref
- recipient_key_ref or recipient routing token
- created_at
- expires_at
- message_type
- encrypted_payload
- optional bounded routing metadata

The final schema must specify canonical encoding, field sizes, authentication coverage, privacy exposure, unknown-field handling, and version negotiation.

Relays should forward opaque encrypted envelopes and should not require message plaintext.
