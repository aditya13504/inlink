# InLink BLE Frame v1 (prototype)

Status: proposed for the M1 physical-device experiment. Changes require updating
Dart tests and the Android/iOS interoperability implementation together.

## Purpose and security boundary

This format splits an opaque byte payload into BLE-friendly fragments. It is a
transport framing layer only: it provides **no encryption, authentication,
confidentiality, sender identity, or replay protection**. Until the secure
messaging milestone exists, exchange only synthetic test bytes—not real private
messages. In production, the payload must be authenticated-encryption output
from the message layer.

## Wire format

All integers are unsigned and big-endian. Header size is 14 bytes.

| Offset | Size | Field | v1 value / meaning |
|---:|---:|---|---|
| 0 | 1 | Magic 1 | `0x49` (`I`) |
| 1 | 1 | Magic 2 | `0x4C` (`L`) |
| 2 | 1 | Version | `0x01` |
| 3 | 1 | Kind | `0x01` = data fragment |
| 4 | 4 | Transfer ID | Random or collision-resistant per-transfer uint32; not an identity |
| 8 | 2 | Fragment index | Zero-based |
| 10 | 2 | Fragment count | Total fragments in transfer |
| 12 | 2 | Payload length | Number of bytes immediately following header |
| 14 | 1–180 | Payload | Opaque fragment bytes |

Constraints:

- Payload per frame: 1–180 bytes. This is a conservative application limit, not
a claim about every BLE MTU or platform.
- Maximum logical transfer: 16,384 bytes; at most 92 fragments.
- `fragmentCount` must be 1–92 and `fragmentIndex` must be less than it.
- Frame length must equal 14 + `payload length`; reject truncation, trailing
  bytes, unknown versions, unknown kinds, invalid lengths, and invalid indexes.
- The receiver must bound in-progress transfers and discard incomplete data
  after a timeout. Reassembly must verify consistent transfer ID/count and must
  not deliver duplicate completed transfers twice.
- Transfer IDs are not cryptographic nonces and must not be used as AEAD nonces.

## M1 scope and known omissions

The Dart codec is implemented with unit tests. Native BLE scanning, advertising,
GATT write/notify, reassembly, timeouts, permissions, and physical-device
interoperability remain incomplete. Do not mark M1 complete until Android and
iOS devices exchange these frames and logs show both directions working.
