# M4.8 — BLE connection recovery validation

## Scope

This milestone hardens the experimental Android GATT client lifecycle when a peer
is discovered but cannot be used. It prevents the scanner from remaining stopped
after service discovery or notification subscription fails, avoids duplicate scan
starts, and cleans up partially initialized BLE sessions when `startBle` throws.

This is not proof of reliable background mesh. Validate on two physical Android
devices, with the app foregrounded, before treating the transport as usable.

## Setup

1. Install the same debug build on two Android devices with BLE support.
2. Grant the requested Bluetooth permissions on both devices and enable Bluetooth.
3. Open InLink on both devices, subscribe to the `inlink/network-events` stream,
   and start BLE.
4. Capture event timestamps and Android logs for each run.

## Acceptance cases

| ID | Scenario | Expected result |
|---|---|---|
| REC-01 | Both devices start BLE | Each reports start plus advertising/scanning state; peer discovery eventually occurs |
| REC-02 | Peer disappears during connection setup | `peerDisconnected`/`error` is emitted; scanning resumes if permissions remain |
| REC-03 | GATT service is missing or service discovery fails | `error` and `recovery` events; unusable client is closed and scan resumes |
| REC-04 | CCCD is missing or local notification setup fails | `error` and `recovery` events; no permanently stuck client connection |
| REC-05 | Remote rejects CCCD subscription | Subscription failure is reported and discovery resumes |
| REC-06 | Client disconnects after a successful session | Queue fails explicitly; GATT closes; scanning resumes once |
| REC-07 | `startBle` fails after partial initialization | Method call returns an error and partial scanner/advertiser/GATT resources are cleaned up |
| REC-08 | Repeat connect/disconnect 20 times | No permanently stopped scanner, duplicate scan start, or unresolved send future |
| REC-09 | Stop BLE while frames are queued | Active and queued sends fail with `ble_stopped`; stopped event is emitted |
| REC-10 | Revoke Bluetooth permission in Android settings, return to app | Operations fail safely; no crash; permission can be requested again |
| REC-11 | One device lacks advertising support | `startBle` returns `ble_role_unavailable`; no partial session remains |
| REC-12 | Disconnect during a frame send | Pending send fails; application retry policy decides whether to retry |

## Evidence to record

For each case record device model, Android version, app build hash, test time,
event sequence, logcat errors, and whether the acceptance condition passed.
Do not log plaintext message bodies, private keys, or full contact identity data.

## Known limitations

- The native transport remains a single-peer experimental BLE implementation.
- Android BLE callback ordering and behavior vary by vendor and OS version.
- Successful GATT write/notification means the transport operation was accepted,
  not that the recipient authenticated or persisted the message.
- Flutter/Dart and Android SDK builds must be run in a configured development
  environment; this archive's source checks do not substitute for compilation or
  physical-device testing.
