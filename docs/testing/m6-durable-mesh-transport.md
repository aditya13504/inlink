# M6 validation checklist

## Automated checks to run on a Flutter host

```sh
cd app
flutter pub get
dart format lib test
flutter analyze
flutter test
cd ..
python -m pytest relay/tests -q
```

The current authoring environment does not include Flutter/Dart or Android SDK, so the Flutter suite and Android compilation cannot be reported as passed from this package build.

## Device matrix

- Two Android phones: connect, send one frame, disconnect, reconnect.
- Four Android phones: one central phone with multiple outbound connections and multiple inbound GATT peers; verify each targeted send reaches only the selected peer.
- At capacity: verify scanning pauses; after a disconnect, verify scanning resumes.
- Fragmented packet: send a packet near the 16 KiB limit and confirm reassembly, expiry of incomplete transfers, and rejection of conflicting duplicate fragments.
- Interrupted transfer: disconnect between fragments; confirm no partial packet reaches routing/decryption and the durable queue remains eligible for retry.
- Restart recovery: enqueue packet, force-stop app, relaunch, restore queue, and verify immutable fingerprint, expiry, ingress peer, and attempted-peer list.
- Queue pressure: fill 256 entries; verify next distinct entry is rejected without deleting unexpired records.
- Replay/conflict: duplicate route key with same immutable content is idempotent; same route key with different immutable content is rejected.
- Identity binding: ensure a BLE address is bound only after a successful authenticated handshake and never use MAC address as a cryptographic node ID.
- Receipt gate: local BLE acceptance must not remove the route; only authenticated end-to-end receipt removes it.

Record Android model, OS version, Bluetooth chipset, observed peer cap, packet size, transfer duration, disconnect count, and battery impact.
