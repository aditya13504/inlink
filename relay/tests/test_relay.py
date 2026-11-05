import base64
import hashlib
import os
import time

import pytest
from fastapi.testclient import TestClient
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from app import main


def b64u(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode().rstrip("=")


def make_identity():
    private = Ed25519PrivateKey.generate()
    public_raw = private.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    return private, b64u(public_raw), main.identity_id(public_raw)


def sign(private, canonical: bytes) -> str:
    return b64u(private.sign(canonical))


@pytest.fixture

def client(tmp_path, monkeypatch):
    monkeypatch.setattr(main, "DB_PATH", str(tmp_path / "test.sqlite3"))
    with TestClient(main.app) as test_client:
        yield test_client


def make_submit(sender_private, sender_public, sender_id, recipient_id, envelope=b"opaque-ciphertext", message_id="message_id_000001", expires_at=None, timestamp=None, nonce="nonce_for_submit_001"):
    timestamp = int(time.time()) if timestamp is None else timestamp
    expires_at = int(time.time()) + 3600 if expires_at is None else expires_at
    digest = b64u(hashlib.sha256(envelope).digest())
    canonical = main.canonical_submit(sender_id=sender_id, recipient_id=recipient_id, message_id=message_id, expires_at=expires_at, digest=digest, timestamp=timestamp, nonce=nonce)
    return {"protocol_version": main.PROTOCOL_VERSION, "sender_id": sender_id, "recipient_id": recipient_id, "message_id": message_id,
            "envelope": b64u(envelope), "expires_at": expires_at, "timestamp": timestamp, "nonce": nonce,
            "sender_public_key": sender_public, "signature": sign(sender_private, canonical)}


def make_poll(recipient_private, recipient_public, recipient_id, nonce="nonce_for_poll_0001", limit=100):
    timestamp = int(time.time())
    canonical = main.canonical_poll(
        recipient_id=recipient_id, timestamp=timestamp, nonce=nonce, limit=limit
    )
    return {"protocol_version": main.PROTOCOL_VERSION, "recipient_id": recipient_id,
            "recipient_public_key": recipient_public, "timestamp": timestamp,
            "nonce": nonce, "signature": sign(recipient_private, canonical), "limit": limit}



def test_health_reports_protocol_v2_and_legacy_routes_are_not_registered(client):
    health = client.get("/health")
    assert health.status_code == 200
    assert health.json()["protocol_version"] == 2
    assert client.post("/v1/relay/messages", json={}).status_code == 404
    assert client.post("/v2/relay/messages/poll", json={
        "protocol_version": 2,
        "recipient_id": "A" * 43,
        "recipient_public_key": "A" * 43,
        "timestamp": int(time.time()),
        "nonce": "nonce_missing_signature_001",
        "signature": "A" * 86,
        "limit": 1,
        "unexpected": "field",
    }).status_code == 422


def test_accepts_opaque_envelope_and_recipient_can_poll(client):
    sender_priv, sender_pub, sender_id = make_identity()
    recipient_priv, recipient_pub, recipient_id = make_identity()
    envelope = b"this-is-opaque-e2ee-envelope"
    response = client.post("/v2/relay/messages", json=make_submit(sender_priv, sender_pub, sender_id, recipient_id, envelope=envelope))
    assert response.status_code == 202
    assert response.json()["status"] == "accepted"

    poll = client.post("/v2/relay/messages/poll", json=make_poll(recipient_priv, recipient_pub, recipient_id))
    assert poll.status_code == 200
    message = poll.json()["messages"][0]
    assert message["sender_id"] == sender_id
    assert base64.urlsafe_b64decode(message["envelope"] + "=" * (-len(message["envelope"]) % 4)) == envelope
    assert message["envelope_digest"] == b64u(hashlib.sha256(envelope).digest())


def test_duplicate_submission_is_idempotent_but_conflicting_id_rejected(client):
    sender_priv, sender_pub, sender_id = make_identity()
    _, _, recipient_id = make_identity()
    request = make_submit(sender_priv, sender_pub, sender_id, recipient_id)
    assert client.post("/v2/relay/messages", json=request).json()["status"] == "accepted"
    assert client.post("/v2/relay/messages", json=request).json()["status"] == "duplicate"
    conflict = make_submit(sender_priv, sender_pub, sender_id, recipient_id, envelope=b"different", message_id=request["message_id"])
    response = client.post("/v2/relay/messages", json=conflict)
    assert response.status_code == 409
    assert response.json()["detail"] == "message_id_conflict"


def test_rejects_invalid_sender_signature(client):
    sender_priv, sender_pub, sender_id = make_identity()
    _, _, recipient_id = make_identity()
    request = make_submit(sender_priv, sender_pub, sender_id, recipient_id)
    request["signature"] = b64u(os.urandom(64))
    response = client.post("/v2/relay/messages", json=request)
    assert response.status_code == 401


def test_rejects_expired_and_oversized_envelopes(client):
    sender_priv, sender_pub, sender_id = make_identity()
    _, _, recipient_id = make_identity()
    expired = make_submit(sender_priv, sender_pub, sender_id, recipient_id, expires_at=int(time.time()) - 1)
    response = client.post("/v2/relay/messages", json=expired)
    assert response.status_code == 400
    assert response.json()["detail"] == "message_expired"
    oversized = make_submit(sender_priv, sender_pub, sender_id, recipient_id, envelope=b"x" * (main.MAX_ENVELOPE_BYTES + 1), message_id="message_id_000002")
    response = client.post("/v2/relay/messages", json=oversized)
    assert response.status_code == 413


def test_poll_requires_recipient_proof_of_possession(client):
    _, _, recipient_id = make_identity()
    other_priv, other_pub, _ = make_identity()
    params = make_poll(other_priv, other_pub, recipient_id)
    response = client.post("/v2/relay/messages/poll", json=params)
    assert response.status_code == 401
    assert response.json()["detail"] == "recipient_identity_key_mismatch"


def test_ack_removes_message_from_mailbox(client):
    sender_priv, sender_pub, sender_id = make_identity()
    recipient_priv, recipient_pub, recipient_id = make_identity()
    envelope = b"ciphertext-for-ack"
    submitted = make_submit(sender_priv, sender_pub, sender_id, recipient_id, envelope=envelope)
    assert client.post("/v2/relay/messages", json=submitted).status_code == 202
    digest = b64u(hashlib.sha256(envelope).digest())
    timestamp = int(time.time())
    nonce = "nonce_for_ack_000001"
    canonical = main.canonical_ack(recipient_id=recipient_id, sender_id=sender_id, message_id=submitted["message_id"], digest=digest, timestamp=timestamp, nonce=nonce)
    ack = {"protocol_version": main.PROTOCOL_VERSION, "recipient_id": recipient_id, "sender_id": sender_id, "message_id": submitted["message_id"],
           "envelope_digest": digest, "timestamp": timestamp, "nonce": nonce, "recipient_public_key": recipient_pub,
           "signature": sign(recipient_priv, canonical)}
    response = client.post("/v2/relay/acks", json=ack)
    assert response.status_code == 200
    assert response.json()["status"] == "acknowledged"
    # A retried acknowledgement after a lost HTTP response is safe.
    repeated = client.post("/v2/relay/acks", json=ack)
    assert repeated.status_code == 200
    assert repeated.json()["status"] == "not_found"
    poll = client.post("/v2/relay/messages/poll", json=make_poll(recipient_priv, recipient_pub, recipient_id))
    assert poll.json()["messages"] == []


def test_rejects_stale_request_timestamp(client):
    sender_priv, sender_pub, sender_id = make_identity()
    _, _, recipient_id = make_identity()
    stale = int(time.time()) - main.CLOCK_SKEW_SECONDS - 10
    request = make_submit(sender_priv, sender_pub, sender_id, recipient_id, timestamp=stale)
    response = client.post("/v2/relay/messages", json=request)
    assert response.status_code == 401
    assert response.json()["detail"] == "request_timestamp_out_of_range"



def test_mailbox_quota_is_enforced(client, monkeypatch):
    monkeypatch.setattr(main, "MAX_MAILBOX_ITEMS", 1)
    sender_priv, sender_pub, sender_id = make_identity()
    _, _, recipient_id = make_identity()
    first = make_submit(
        sender_priv, sender_pub, sender_id, recipient_id,
        envelope=b"first", message_id="message_id_quota_001",
    )
    second = make_submit(
        sender_priv, sender_pub, sender_id, recipient_id,
        envelope=b"second", message_id="message_id_quota_002",
        nonce="nonce_for_submit_002",
    )
    assert client.post("/v2/relay/messages", json=first).status_code == 202
    response = client.post("/v2/relay/messages", json=second)
    assert response.status_code == 429
    assert response.json()["detail"] == "recipient_mailbox_quota_exceeded"


def test_relay_rejects_unknown_fields(client):
    sender_priv, sender_pub, sender_id = make_identity()
    _, _, recipient_id = make_identity()
    request = make_submit(sender_priv, sender_pub, sender_id, recipient_id)
    request["unexpected_plaintext"] = "should never be accepted"
    response = client.post("/v2/relay/messages", json=request)
    assert response.status_code == 422


def test_ack_with_wrong_digest_does_not_remove_queued_message(client):
    sender_priv, sender_pub, sender_id = make_identity()
    recipient_priv, recipient_pub, recipient_id = make_identity()
    envelope = b"opaque-message-for-wrong-digest"
    submitted = make_submit(
        sender_priv, sender_pub, sender_id, recipient_id,
        envelope=envelope, message_id="message_id_wrong_digest",
    )
    assert client.post("/v2/relay/messages", json=submitted).status_code == 202
    wrong_digest = b64u(hashlib.sha256(b"not-the-envelope").digest())
    timestamp = int(time.time())
    nonce = "nonce_for_ack_wrong_digest"
    canonical = main.canonical_ack(
        recipient_id=recipient_id, sender_id=sender_id,
        message_id=submitted["message_id"], digest=wrong_digest,
        timestamp=timestamp, nonce=nonce,
    )
    ack = {
        "protocol_version": main.PROTOCOL_VERSION,
        "recipient_id": recipient_id,
        "sender_id": sender_id,
        "message_id": submitted["message_id"],
        "envelope_digest": wrong_digest,
        "timestamp": timestamp,
        "nonce": nonce,
        "recipient_public_key": recipient_pub,
        "signature": sign(recipient_priv, canonical),
    }
    response = client.post("/v2/relay/acks", json=ack)
    assert response.status_code == 409
    poll = client.post(
        "/v2/relay/messages/poll",
        json=make_poll(recipient_priv, recipient_pub, recipient_id),
    )
    assert len(poll.json()["messages"]) == 1



def test_request_nonce_cannot_be_reused_for_different_submit(client):
    sender_priv, sender_pub, sender_id = make_identity()
    _, _, recipient_id = make_identity()
    first = make_submit(sender_priv, sender_pub, sender_id, recipient_id,
        envelope=b"nonce-first", message_id="message_nonce_first_001",
        nonce="same_nonce_for_submit_01")
    second = make_submit(sender_priv, sender_pub, sender_id, recipient_id,
        envelope=b"nonce-second", message_id="message_nonce_second_01",
        nonce="same_nonce_for_submit_01")
    assert client.post("/v2/relay/messages", json=first).status_code == 202
    response = client.post("/v2/relay/messages", json=second)
    assert response.status_code == 409
    assert response.json()["detail"] == "request_nonce_reused"


def test_exact_submit_retry_remains_idempotent(client):
    sender_priv, sender_pub, sender_id = make_identity()
    _, _, recipient_id = make_identity()
    request = make_submit(sender_priv, sender_pub, sender_id, recipient_id,
        envelope=b"same-exact-request", message_id="message_nonce_exact_001",
        nonce="nonce_exact_retry_0001")
    assert client.post("/v2/relay/messages", json=request).json()["status"] == "accepted"
    retry = client.post("/v2/relay/messages", json=request)
    assert retry.status_code == 202
    assert retry.json()["status"] == "duplicate"


def test_poll_nonce_cannot_be_reused_for_different_request(client):
    recipient_priv, recipient_pub, recipient_id = make_identity()
    first = make_poll(recipient_priv, recipient_pub, recipient_id, nonce="same_nonce_poll_001")
    second = make_poll(recipient_priv, recipient_pub, recipient_id, nonce="same_nonce_poll_001")
    second["timestamp"] += 1
    canonical = main.canonical_poll(recipient_id=recipient_id,
        timestamp=second["timestamp"], nonce=second["nonce"], limit=second["limit"])
    second["signature"] = sign(recipient_priv, canonical)
    assert client.post("/v2/relay/messages/poll", json=first).status_code == 200
    response = client.post("/v2/relay/messages/poll", json=second)
    assert response.status_code == 409
    assert response.json()["detail"] == "request_nonce_reused"

def test_poll_authentication_is_not_accepted_in_query_parameters(client):
    recipient_priv, recipient_pub, recipient_id = make_identity()
    query = make_poll(recipient_priv, recipient_pub, recipient_id)
    response = client.get("/v2/relay/messages/poll", params=query)
    assert response.status_code == 405


def test_poll_limit_is_covered_by_signature(client):
    recipient_priv, recipient_pub, recipient_id = make_identity()
    request = make_poll(
        recipient_priv, recipient_pub, recipient_id,
        nonce="nonce_poll_limit_signed", limit=2,
    )
    request["limit"] = 1  # Alter an unsigned-in-the-old-protocol option.
    response = client.post("/v2/relay/messages/poll", json=request)
    assert response.status_code == 401
    assert response.json()["detail"] == "invalid_request_signature"


def test_end_to_end_delivery_retries_until_recipient_acknowledges(client):
    """Simulate a lost recipient processing window, then authenticated receipt."""
    sender_priv, sender_pub, sender_id = make_identity()
    recipient_priv, recipient_pub, recipient_id = make_identity()
    envelope = b"end-to-end-opaque-encrypted-envelope"
    request = make_submit(
        sender_priv, sender_pub, sender_id, recipient_id,
        envelope=envelope, message_id="message_e2e_retry_001",
        nonce="nonce_e2e_submit_001",
    )

    submitted = client.post("/v2/relay/messages", json=request)
    assert submitted.status_code == 202
    assert submitted.json()["status"] == "accepted"

    # Recipient is temporarily unable to process the message. Polling alone
    # must not delete it; only a signed acknowledgement may remove it.
    first_poll = make_poll(
        recipient_priv, recipient_pub, recipient_id,
        nonce="nonce_e2e_poll_001",
    )
    first = client.post("/v2/relay/messages/poll", json=first_poll)
    assert first.status_code == 200
    assert len(first.json()["messages"]) == 1
    assert first.json()["messages"][0]["message_id"] == request["message_id"]

    second = client.post(
        "/v2/relay/messages/poll",
        json=make_poll(
            recipient_priv, recipient_pub, recipient_id,
            nonce="nonce_e2e_poll_002",
        ),
    )
    assert second.status_code == 200
    received = second.json()["messages"]
    assert len(received) == 1
    assert received[0]["envelope"] == request["envelope"]

    digest = b64u(hashlib.sha256(envelope).digest())
    timestamp = int(time.time())
    ack_nonce = "nonce_e2e_ack_001"
    ack_canonical = main.canonical_ack(
        recipient_id=recipient_id,
        sender_id=sender_id,
        message_id=request["message_id"],
        digest=digest,
        timestamp=timestamp,
        nonce=ack_nonce,
    )
    ack = {
        "protocol_version": main.PROTOCOL_VERSION,
        "recipient_id": recipient_id,
        "sender_id": sender_id,
        "message_id": request["message_id"],
        "envelope_digest": digest,
        "timestamp": timestamp,
        "nonce": ack_nonce,
        "recipient_public_key": recipient_pub,
        "signature": sign(recipient_priv, ack_canonical),
    }
    acknowledged = client.post("/v2/relay/acks", json=ack)
    assert acknowledged.status_code == 200
    assert acknowledged.json()["status"] == "acknowledged"

    final_poll = client.post(
        "/v2/relay/messages/poll",
        json=make_poll(
            recipient_priv, recipient_pub, recipient_id,
            nonce="nonce_e2e_poll_003",
        ),
    )
    assert final_poll.status_code == 200
    assert final_poll.json()["messages"] == []

