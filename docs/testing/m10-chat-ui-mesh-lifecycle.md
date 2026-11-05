# M10 Chat UI / Mesh Lifecycle Acceptance Matrix

| Scenario | Expected result |
|---|---|
| No mesh service injected | Mesh status says it is not configured; mesh send action is disabled; existing BLE/relay flow remains available |
| Configured service injected | UI subscribes to mesh events and starts service on page initialization |
| Service startup restores routes | Status displays recovery count and conversation history refreshes |
| User taps mesh send | Uses selected verified contact; service persists encrypted envelope before routing; no legacy/plaintext fallback |
| Outgoing route queued | Durable conversation appears after refresh with queued state |
| Recipient receipt verified | Service emits delivered event and local history reflects delivered |
| Inbound authenticated message | Service persists inbound record before receipt; UI refreshes conversation |
| Forwarding/duplicate/rejection event | Status updates without exposing plaintext/envelope contents |
| Retry pressed | Calls service retry, displays accepted/failed counts, refreshes local history |
| Service startup/send fails | UI shows safe generic status; persisted outbox record is retained if already written |
| Widget disposed | Mesh event subscription is cancelled and injected service is disposed |
| Default app composition | Mesh action remains disabled until stable multi-peer transport and authenticated identity binding are wired |

## Composition invariant

The injected `MeshApplicationService` must use `SqlCipherMeshApplicationMessageStore` backed by the same `LocalMessageRepository` instance passed into `ConversationsPage`. Do not construct two repositories and assume they share the same SQLCipher database lifecycle/key setup.
