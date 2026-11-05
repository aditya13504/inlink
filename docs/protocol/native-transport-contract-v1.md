# InLink Native Transport Contract v1

## GATT service and characteristic

| Field | Value |
|---|---|
| Service UUID | `9F3A1000-7B4D-4F3C-9A12-2F6E1A000001` |
| Frame characteristic UUID | `9F3A1001-7B4D-4F3C-9A12-2F6E1A000001` |
| Characteristic properties | Write, Write Without Response, Notify, Read |
| Maximum encoded frame | 194 bytes (14-byte frame header + up to 180-byte payload) |
| Outbound native queue | Bounded; current Android and iOS implementations limit queued frames |
| Peer count | Platform-specific and bounded; current native source targets at most three outbound/connected peers |

## Platform handles

- Android reports BLE device addresses.
- iOS reports CoreBluetooth peripheral/central UUID strings.
- Handles are local to a device and can change after platform reset/re-pairing or OS lifecycle events. They are not identity keys.
- The mesh directory binds a handle to a stable pseudonymous node ID only after verifying a signed challenge against an already trusted contact.

## Send semantics

- `sendBleFrame` is an untargeted compatibility method; `sendBleFrameToPeer` requires a specific connected transport handle.
- A method result means the local GATT write/notification was accepted by the platform, not that the other application received or decrypted it.
- GATT MTU and notification backpressure can reject a send. Rejected frames must remain retryable at the application/outbox layer.
- The native transport never receives plaintext message text by design; it moves encoded protocol frames.

## Lifecycle semantics

- `startBle` starts scanning and advertising only after the platform reports Bluetooth ready and permissions allow it.
- `stopBle`, disconnect, radio power-off, and failed GATT operations fail active/pending native sends and clear connection state.
- Event consumers share one Dart broadcast stream; multiple consumers must not recreate independent native EventChannel listeners.
- Neither iOS nor Android guarantees continuous background scanning, advertising, or delivery. The app must not promise availability without a working radio/relay path.
