# InLink Relay — v2 development prototype

A Python/FastAPI service that stores and forwards opaque end-to-end encrypted envelopes. The relay does not possess message-decryption keys, but it can observe routing IDs, IP addresses, timing, envelope sizes, and traffic patterns.

## Run locally

Python 3.11+ is recommended.

```bash
cd relay
python -m venv .venv
# Windows PowerShell: .venv\\Scripts\\Activate.ps1
# macOS/Linux: source .venv/bin/activate
python -m pip install -r requirements.txt
uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Health check: `GET http://127.0.0.1:8000/health`

Run the tests:

```bash
python -m pytest -q tests
```

Set `INLINK_RELAY_DB` to choose the SQLite database path. The default is `relay/relay.sqlite3`; do not commit runtime databases.

## API summary

- `POST /v2/relay/messages` — sender submits an opaque envelope.
- `POST /v2/relay/messages/poll` — recipient polls with signed authentication in the JSON body. The requested limit is signed; authentication data is not placed in the URL.
- `POST /v2/relay/acks` — recipient acknowledges a specific sender/message/digest. This removes a relay queue copy; it does not set the app's E2EE `DELIVERED` state.
- `GET /health` — process health and protocol version.

See [`../docs/protocol/relay-api.md`](../docs/protocol/relay-api.md) for canonical signatures and limits.

## Security boundary

This is a development foundation, not a public production service. Before internet exposure, deploy behind HTTPS/TLS and add edge request/body limits, authentication-aware rate limits, abuse controls, monitoring, protected backups, and an operator retention policy. Protect the SQLite file and host. Do not log request bodies or envelopes. Public keys are self-authenticating identifiers, not proof of real-world identity. This relay does not provide a global directory, key revocation, anonymous routing, or multi-relay routing.

The v2 request protocol binds each operation to an Ed25519 signature, timestamp, and nonce. Nonce bindings are persisted in local SQLite for 24 hours; exact retries are permitted while a nonce reused for a different request is rejected. A multi-instance deployment needs shared atomic nonce state.
