# Relay API v2 — integrated hardening contract

Status: development-only FastAPI + SQLite prototype. The Flutter client and relay now use the same v2 contract. This is not a production deployment approval.

## Identity and envelope rules

- `protocol_version` is `2`.
- A pseudonymous identity ID is unpadded Base64URL of `SHA-256(raw 32-byte Ed25519 public key)`. It is a key identifier, not a verified civil identity.
- `envelope` is unpadded Base64URL of opaque E2EE envelope bytes. Maximum decoded envelope size is 16 KiB. The relay does not decrypt or inspect message plaintext.
- `message_id` is 16–64 URL-safe characters. Sender plus message ID is the idempotency key.
- Expiry must be in the future and no more than seven days ahead.
- Each recipient mailbox is capped at 1,000 unacknowledged live items; poll returns at most 100 items.
- Request JSON rejects unknown fields. Base64URL values use URL-safe characters without padding.
- Every signed operation uses a ±300-second timestamp window and a nonce of at least 16 URL-safe characters. The relay persists nonce-to-request bindings per identity for 24 hours. Exact retries of the same canonical request are allowed; reusing a nonce for a different canonical request is rejected.

## Canonical request signatures

Signatures are detached Ed25519 signatures over UTF-8 bytes of these exact canonical strings, with literal newline separators and no trailing newline:

- Submit: `INLINK-RELAY-SUBMIT-V2\n{sender_id}\n{recipient_id}\n{message_id}\n{expires_at}\n{envelope_digest}\n{timestamp}\n{nonce}`
- Poll: `INLINK-RELAY-POLL-V2\n{recipient_id}\n{timestamp}\n{nonce}\n{limit}`
- Ack: `INLINK-RELAY-ACK-V2\n{recipient_id}\n{sender_id}\n{message_id}\n{envelope_digest}\n{timestamp}\n{nonce}`

`envelope_digest` is unpadded Base64URL of SHA-256 over the decoded envelope bytes. The poll limit is signed so an intermediary cannot alter it without invalidating the signature. Public keys must hash to the claimed identity ID.

## Endpoints

### `POST /v2/relay/messages`

The sender submits an opaque envelope in a strict JSON body. Responses include `202 accepted`, `202 duplicate`, `409 message_id_conflict`, `401` for invalid signatures/identity, `413` for envelope size violations, `400` for invalid/expired TTL, and `429` for mailbox quota exhaustion.

### `POST /v2/relay/messages/poll`

The recipient sends `protocol_version`, `recipient_id`, `recipient_public_key`, `timestamp`, `nonce`, `signature`, and `limit` (1–100) in the JSON body. Signed authentication material is not put in URL query parameters, reducing accidental exposure in access logs. Polling does not remove messages.

### `POST /v2/relay/acks`

The recipient signs an acknowledgement for a specific sender, message ID, and exact envelope digest. A valid acknowledgement removes that queued copy. It is a relay-queue acknowledgement only, not the app's end-to-end receipt or proof that plaintext was displayed.

### `GET /health`

Returns process health and the supported protocol version.

## Security and deployment boundaries

- The relay still observes routing IDs, IP addresses, timing, sizes, frequency, and traffic patterns. E2EE does not hide metadata.
- HTTPS/TLS, edge request/body limits, per-IP and per-identity rate limits, abuse controls, monitoring, protected database backups, retention policy, patching, and operational ownership are required before public exposure.
- Nonce state is local SQLite state. A multi-instance deployment requires shared atomic replay protection or strict single-writer routing.
- The app's E2EE envelope remains a prototype without independent cryptographic review or a Double Ratchet. Do not use this for sensitive communications.
