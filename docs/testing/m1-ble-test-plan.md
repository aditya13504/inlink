# M1 BLE Physical-Device Test Plan

## Preconditions

- Use two physical devices; emulators are not sufficient for radio validation.
- Record OS version, phone model, app build/commit, BLE permission choices, and
  whether the app is foregrounded or backgrounded.
- Use only synthetic test payloads. No encryption is implemented yet.
- Bluetooth enabled on both devices; location/system settings as required by
  the Android version and device vendor.

## Test cases

| ID | Scenario | Expected evidence |
|---|---|---|
| BLE-01 | Device A advertises while B scans | B sees a peer with an ephemeral session identifier; no phone number/name required |
| BLE-02 | Both devices discover each other | Duplicate advertisements do not create unbounded duplicate peer entries |
| BLE-03 | A sends a short synthetic payload to B | B receives byte-for-byte identical payload |
| BLE-04 | B sends a short synthetic payload to A | A receives byte-for-byte identical payload |
| BLE-05 | Payload spans multiple fragments | Reassembled payload exactly matches original and is delivered once |
| BLE-06 | Disconnect during transfer | Transfer fails or remains incomplete; it is never reported delivered |
| BLE-07 | Peer disconnects and reconnects | Discovery and transfer recover without restarting the app |
| BLE-08 | Bluetooth permission denied | UI explains the permission is needed and does not crash or spin indefinitely |
| BLE-09 | App backgrounded / screen locked | Record observed behavior; do not assume continuous scanning or advertising |
| BLE-10 | Malformed frame injected in codec tests | Frame rejected without crash or unbounded allocation |

## Measurements

For each run record discovery time, connection time, payload size, send-to-receive
latency, RSSI if available, disconnect cause, reconnect time, battery/thermal
observations, and whether the app was foregrounded. Repeat at several distances
and with bodies/walls between devices. Treat results as device-specific, not a
universal range guarantee.

## Completion gate

M1 is complete only when Android↔Android and Android↔iOS are demonstrated where
devices are available, test cases BLE-01 through BLE-07 pass, permission failures
are handled, and platform background limitations are documented. iOS builds and
physical tests require macOS/Xcode and an iPhone.
