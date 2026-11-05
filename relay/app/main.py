"""Experimental InLink opaque-envelope relay.

This service authenticates pseudonymous Ed25519 identities, stores opaque
end-to-end encrypted envelopes in SQLite, and never decrypts message content.
It is a protocol foundation, not a production-hardened public service.
"""
from __future__ import annotations

import base64
import hashlib
import os
import re
import secrets
import sqlite3
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, ConfigDict, Field

PROTOCOL_VERSION = 2
MAX_ENVELOPE_BYTES = 16 * 1024
MAX_MAILBOX_ITEMS = 1000
MAX_TTL_SECONDS = 7 * 24 * 60 * 60
CLOCK_SKEW_SECONDS = 300
IDENTITY_RE = re.compile(r"^[A-Za-z0-9_-]{43}$")
ID_RE = re.compile(r"^[A-Za-z0-9_-]{16,64}$")
DB_PATH = os.environ.get("INLINK_RELAY_DB", str(Path(__file__).resolve().parent.parent / "relay.sqlite3"))

app = FastAPI(title="InLink Relay API", version="1.0.0", description="Experimental opaque E2EE envelope forwarding")


def b64u_decode(value: str, *, expected_length: int | None = None) -> bytes:
    if not value or not re.fullmatch(r"[A-Za-z0-9_-]+", value):
        raise HTTPException(status_code=400, detail="invalid_base64url")
    try:
        raw = base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))
    except Exception as exc:
        raise HTTPException(status_code=400, detail="invalid_base64url") from exc
    if expected_length is not None and len(raw) != expected_length:
        raise HTTPException(status_code=400, detail="invalid_key_length")
    return raw


def b64u_encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


def identity_id(public_key_raw: bytes) -> str:
    return b64u_encode(hashlib.sha256(public_key_raw).digest())


def verify_request(public_key: str, signature: str, canonical: bytes, timestamp: int) -> str:
    now = int(time.time())
    if abs(now - timestamp) > CLOCK_SKEW_SECONDS:
        raise HTTPException(status_code=401, detail="request_timestamp_out_of_range")
    raw_key = b64u_decode(public_key, expected_length=32)
    try:
        Ed25519PublicKey.from_public_bytes(raw_key).verify(b64u_decode(signature, expected_length=64), canonical)
    except (InvalidSignature, ValueError) as exc:
        raise HTTPException(status_code=401, detail="invalid_request_signature") from exc
    return identity_id(raw_key)


def canonical_submit(*, sender_id: str, recipient_id: str, message_id: str, expires_at: int, digest: str, timestamp: int, nonce: str) -> bytes:
    return f"INLINK-RELAY-SUBMIT-V2\n{sender_id}\n{recipient_id}\n{message_id}\n{expires_at}\n{digest}\n{timestamp}\n{nonce}".encode()


def canonical_poll(*, recipient_id: str, timestamp: int, nonce: str, limit: int) -> bytes:
    # Include every caller-controlled poll option in the signature. Poll auth
    # data is carried in a POST body, not a URL that routine access logs retain.
    return f"INLINK-RELAY-POLL-V2\n{recipient_id}\n{timestamp}\n{nonce}\n{limit}".encode()



def canonical_ack(*, recipient_id: str, sender_id: str, message_id: str, digest: str, timestamp: int, nonce: str) -> bytes:
    return f"INLINK-RELAY-ACK-V2\n{recipient_id}\n{sender_id}\n{message_id}\n{digest}\n{timestamp}\n{nonce}".encode()


@contextmanager
def db() -> Iterator[sqlite3.Connection]:
    conn = sqlite3.connect(DB_PATH, timeout=10, isolation_level="IMMEDIATE")
    conn.row_factory = sqlite3.Row
    try:
        conn.execute("PRAGMA foreign_keys = ON")
        conn.execute("PRAGMA journal_mode = WAL")
        conn.execute("""CREATE TABLE IF NOT EXISTS relay_messages (
            sender_id TEXT NOT NULL,
            recipient_id TEXT NOT NULL,
            message_id TEXT NOT NULL,
            envelope_b64u TEXT NOT NULL,
            envelope_digest TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            expires_at INTEGER NOT NULL,
            acknowledged_at INTEGER,
            PRIMARY KEY(sender_id, message_id)
        )""")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_relay_mailbox ON relay_messages(recipient_id, acknowledged_at, expires_at, created_at)")
        conn.execute("""CREATE TABLE IF NOT EXISTS request_nonces (
            identity_id TEXT NOT NULL,
            nonce TEXT NOT NULL,
            request_digest TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            PRIMARY KEY(identity_id, nonce)
        )""")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_request_nonces_created ON request_nonces(created_at)")
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def reserve_request_nonce(
    conn: sqlite3.Connection,
    *,
    identity: str,
    nonce: str,
    canonical: bytes,
    now: int,
) -> None:
    """Prevent nonce reuse for a different signed request; permit exact retries."""
    digest = hashlib.sha256(canonical).hexdigest()
    existing = conn.execute(
        "SELECT request_digest FROM request_nonces WHERE identity_id=? AND nonce=?",
        (identity, nonce),
    ).fetchone()
    if existing is not None:
        if existing["request_digest"] != digest:
            raise HTTPException(status_code=409, detail="request_nonce_reused")
        return
    conn.execute(
        "INSERT INTO request_nonces(identity_id, nonce, request_digest, created_at) VALUES(?,?,?,?)",
        (identity, nonce, digest, now),
    )
    conn.execute("DELETE FROM request_nonces WHERE created_at < ?", (now - 24 * 60 * 60,))


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class SubmitRequest(StrictModel):
    protocol_version: int = Field(ge=1, le=PROTOCOL_VERSION)
    sender_id: str = Field(min_length=43, max_length=43)
    recipient_id: str = Field(min_length=43, max_length=43)
    message_id: str = Field(min_length=16, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")
    envelope: str = Field(min_length=1, max_length=22000)
    expires_at: int = Field(gt=0)
    timestamp: int = Field(gt=0)
    nonce: str = Field(min_length=16, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")
    sender_public_key: str = Field(min_length=43, max_length=43)
    signature: str = Field(min_length=86, max_length=86)


class AckRequest(StrictModel):
    protocol_version: int = Field(ge=1, le=PROTOCOL_VERSION)
    recipient_id: str = Field(min_length=43, max_length=43)
    sender_id: str = Field(min_length=43, max_length=43)
    message_id: str = Field(min_length=16, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")
    envelope_digest: str = Field(min_length=43, max_length=43)
    timestamp: int = Field(gt=0)
    nonce: str = Field(min_length=16, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")
    recipient_public_key: str = Field(min_length=43, max_length=43)
    signature: str = Field(min_length=86, max_length=86)


class PollRequest(StrictModel):
    protocol_version: int = Field(ge=1, le=PROTOCOL_VERSION)
    recipient_id: str = Field(min_length=43, max_length=43)
    recipient_public_key: str = Field(min_length=43, max_length=43)
    timestamp: int = Field(gt=0)
    nonce: str = Field(min_length=16, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")
    signature: str = Field(min_length=86, max_length=86)
    limit: int = Field(default=100, ge=1, le=100)


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "protocol_version": PROTOCOL_VERSION}


@app.post("/v2/relay/messages", status_code=202)
def submit_message(req: SubmitRequest) -> dict:
    if req.protocol_version != PROTOCOL_VERSION:
        raise HTTPException(status_code=426, detail="unsupported_protocol_version")
    if not IDENTITY_RE.fullmatch(req.sender_id) or not IDENTITY_RE.fullmatch(req.recipient_id):
        raise HTTPException(status_code=400, detail="invalid_identity_id")
    envelope_bytes = b64u_decode(req.envelope)
    if not envelope_bytes or len(envelope_bytes) > MAX_ENVELOPE_BYTES:
        raise HTTPException(status_code=413, detail="envelope_size_limit")
    digest = b64u_encode(hashlib.sha256(envelope_bytes).digest())
    expected_identity = identity_id(b64u_decode(req.sender_public_key, expected_length=32))
    if req.sender_id != expected_identity:
        raise HTTPException(status_code=401, detail="sender_identity_key_mismatch")
    canonical = canonical_submit(sender_id=req.sender_id, recipient_id=req.recipient_id, message_id=req.message_id, expires_at=req.expires_at, digest=digest, timestamp=req.timestamp, nonce=req.nonce)
    verified_id = verify_request(req.sender_public_key, req.signature, canonical, req.timestamp)
    if verified_id != req.sender_id:
        raise HTTPException(status_code=401, detail="sender_identity_key_mismatch")
    now = int(time.time())
    if req.expires_at <= now:
        raise HTTPException(status_code=400, detail="message_expired")
    if req.expires_at > now + MAX_TTL_SECONDS:
        raise HTTPException(status_code=400, detail="expiry_exceeds_max_ttl")

    with db() as conn:
        conn.execute("DELETE FROM relay_messages WHERE expires_at <= ? OR acknowledged_at IS NOT NULL", (now,))
        existing = conn.execute("SELECT envelope_digest, recipient_id FROM relay_messages WHERE sender_id=? AND message_id=?", (req.sender_id, req.message_id)).fetchone()
        if existing:
            if existing["envelope_digest"] != digest or existing["recipient_id"] != req.recipient_id:
                raise HTTPException(status_code=409, detail="message_id_conflict")
            return {"protocol_version": PROTOCOL_VERSION, "status": "duplicate", "message_id": req.message_id, "envelope_digest": digest}
        reserve_request_nonce(conn, identity=req.sender_id, nonce=req.nonce, canonical=canonical, now=now)
        count = conn.execute("SELECT COUNT(*) AS n FROM relay_messages WHERE recipient_id=? AND acknowledged_at IS NULL AND expires_at > ?", (req.recipient_id, now)).fetchone()["n"]
        if count >= MAX_MAILBOX_ITEMS:
            raise HTTPException(status_code=429, detail="recipient_mailbox_quota_exceeded")
        conn.execute("INSERT INTO relay_messages(sender_id, recipient_id, message_id, envelope_b64u, envelope_digest, created_at, expires_at) VALUES(?,?,?,?,?,?,?)", (req.sender_id, req.recipient_id, req.message_id, req.envelope, digest, now, req.expires_at))
    return {"protocol_version": PROTOCOL_VERSION, "status": "accepted", "message_id": req.message_id, "envelope_digest": digest, "expires_at": req.expires_at}


@app.post("/v2/relay/messages/poll")
def poll_messages(req: PollRequest) -> dict:
    if req.protocol_version != PROTOCOL_VERSION:
        raise HTTPException(status_code=426, detail="unsupported_protocol_version")
    if not IDENTITY_RE.fullmatch(req.recipient_id):
        raise HTTPException(status_code=400, detail="invalid_identity_id")
    canonical = canonical_poll(
        recipient_id=req.recipient_id,
        timestamp=req.timestamp,
        nonce=req.nonce,
        limit=req.limit,
    )
    verified_id = verify_request(
        req.recipient_public_key, req.signature, canonical, req.timestamp
    )
    if verified_id != req.recipient_id:
        raise HTTPException(status_code=401, detail="recipient_identity_key_mismatch")
    now = int(time.time())
    with db() as conn:
        reserve_request_nonce(
            conn, identity=req.recipient_id, nonce=req.nonce,
            canonical=canonical, now=now,
        )
        conn.execute(
            "DELETE FROM relay_messages WHERE expires_at <= ? OR acknowledged_at IS NOT NULL",
            (now,),
        )
        rows = conn.execute(
            """SELECT sender_id, message_id, envelope_b64u, envelope_digest, created_at, expires_at
               FROM relay_messages
               WHERE recipient_id=? AND acknowledged_at IS NULL AND expires_at>?
               ORDER BY created_at LIMIT ?""",
            (req.recipient_id, now, req.limit),
        ).fetchall()
    return {
        "protocol_version": PROTOCOL_VERSION,
        "messages": [
            dict(
                sender_id=r["sender_id"],
                message_id=r["message_id"],
                envelope=r["envelope_b64u"],
                envelope_digest=r["envelope_digest"],
                created_at=r["created_at"],
                expires_at=r["expires_at"],
            )
            for r in rows
        ],
    }


@app.post("/v2/relay/acks", status_code=200)
def acknowledge_message(req: AckRequest) -> dict:
    if req.protocol_version != PROTOCOL_VERSION:
        raise HTTPException(status_code=426, detail="unsupported_protocol_version")
    if not IDENTITY_RE.fullmatch(req.recipient_id):
        raise HTTPException(status_code=400, detail="invalid_identity_id")
    if not re.fullmatch(r"[A-Za-z0-9_-]{43}", req.envelope_digest):
        raise HTTPException(status_code=400, detail="invalid_envelope_digest")
    canonical = canonical_ack(
        recipient_id=req.recipient_id, sender_id=req.sender_id,
        message_id=req.message_id, digest=req.envelope_digest,
        timestamp=req.timestamp, nonce=req.nonce,
    )
    verified_id = verify_request(req.recipient_public_key, req.signature, canonical, req.timestamp)
    if verified_id != req.recipient_id:
        raise HTTPException(status_code=401, detail="recipient_identity_key_mismatch")
    now = int(time.time())
    with db() as conn:
        reserve_request_nonce(conn, identity=req.recipient_id, nonce=req.nonce, canonical=canonical, now=now)
        row = conn.execute("SELECT envelope_digest FROM relay_messages WHERE sender_id=? AND recipient_id=? AND message_id=? AND expires_at>? AND acknowledged_at IS NULL", (req.sender_id, req.recipient_id, req.message_id, now)).fetchone()
        if row is None:
            # Idempotent acknowledgement for a message already removed/expired.
            return {"protocol_version": PROTOCOL_VERSION, "status": "not_found"}
        if row["envelope_digest"] != req.envelope_digest:
            raise HTTPException(status_code=409, detail="envelope_digest_mismatch")
        conn.execute("UPDATE relay_messages SET acknowledged_at=? WHERE sender_id=? AND recipient_id=? AND message_id=?", (now, req.sender_id, req.recipient_id, req.message_id))
        conn.execute("DELETE FROM relay_messages WHERE sender_id=? AND recipient_id=? AND message_id=?", (req.sender_id, req.recipient_id, req.message_id))
    return {"protocol_version": PROTOCOL_VERSION, "status": "acknowledged", "message_id": req.message_id}
