# M4.9 — BLE recovery observability

## Changes

The conversation delivery layer now consumes the native `recovery`, `error`,
and `permissionDenied` events instead of silently ignoring them. Recovery and
connection-setup failures clear `_bleReady`, close the serialized frame sender,
and discard incomplete inbound frame assemblies. This prevents the route planner
from treating BLE as ready after the native GATT client has been torn down.

The standalone transport diagnostics screen labels recovery events explicitly.
Error messages are surfaced in the UI with the native operation and available
message/code/status fields.

## Event semantics

| Event | UI / delivery behavior |
|---|---|
| `readyToSend` | BLE is eligible for frame transfer |
| `peerDisconnected` | BLE becomes unavailable; close sender and discard partial frame assemblies |
| `recovery` | BLE becomes unavailable; native layer is recovering and scanning again |
| `error` for `connect`, `discoverServices`, `subscribeNotifications`, or `recoveryScan` | Clear BLE-ready state and report operation error |
| `error` for other operations | Report diagnostic; do not assume every error invalidates an established connection |
| `permissionDenied` | Mark BLE inactive and not ready; require permission grant and explicit restart |
| `frameReceived` | Reassemble frame; accept only after envelope authentication and replay checks |

## Validation

1. Start BLE on both devices and verify the conversation status reaches GATT ready.
2. Make a peer disappear during GATT setup; confirm the UI reports recovery and no longer routes new attempts over BLE.
3. Trigger service-discovery or CCCD setup failure; verify error details are visible and recovery is shown.
4. Revoke permissions and return to the app; verify BLE is shown inactive/not ready.
5. Reconnect successfully; verify a new `readyToSend` event reopens the sender.
6. Interrupt a multi-frame message; verify partial reassembly is discarded after disconnect/recovery.
7. Check logs for secrets: do not log plaintext messages, private keys, or complete contact records.

## Limits

This is source-level UI/event integration only. Flutter tests, Android compilation,
and physical-device behavior remain unverified in this environment. An event that
says GATT is ready is a transport readiness signal, not an authenticated message
delivery receipt.
