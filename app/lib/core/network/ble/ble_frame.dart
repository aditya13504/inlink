import 'dart:typed_data';

/// Versioned transport frame used by the first BLE interoperability prototype.
///
/// This framing is NOT encryption, authentication, or a message protocol. The
/// payload must eventually be an authenticated-encryption ciphertext produced
/// by the secure messaging layer. Never put plaintext private messages here.
class BleFrame {
  BleFrame({
    required this.transferId,
    required this.fragmentIndex,
    required this.fragmentCount,
    required List<int> payload,
  }) : payload = Uint8List.fromList(payload) {
    if (transferId < 0 || transferId > 0xFFFFFFFF) {
      throw ArgumentError.value(transferId, 'transferId', 'Must fit uint32');
    }
    if (fragmentCount < 1 || fragmentCount > maxFragmentCount) {
      throw ArgumentError.value(
        fragmentCount,
        'fragmentCount',
        'Must be between 1 and $maxFragmentCount',
      );
    }
    if (fragmentIndex < 0 || fragmentIndex >= fragmentCount) {
      throw ArgumentError.value(
        fragmentIndex,
        'fragmentIndex',
        'Must be in [0, fragmentCount)',
      );
    }
    if (this.payload.isEmpty || this.payload.length > maxPayloadBytes) {
      throw ArgumentError.value(
        this.payload.length,
        'payload',
        'Payload must contain 1-$maxPayloadBytes bytes',
      );
    }
  }

  static const int protocolVersion = 1;
  static const int headerLength = 14;
  static const int maxPayloadBytes = 180;
  static const int maxMessageBytes = 16 * 1024;
  static const int maxFragmentCount = (maxMessageBytes + maxPayloadBytes - 1) ~/ maxPayloadBytes;
  static const int _magicI = 0x49; // ASCII I
  static const int _magicL = 0x4C; // ASCII L
  static const int _dataKind = 0x01;

  final int transferId;
  final int fragmentIndex;
  final int fragmentCount;
  final Uint8List payload;

  Uint8List encode() {
    final bytes = Uint8List(headerLength + payload.length);
    final data = ByteData.sublistView(bytes);
    bytes[0] = _magicI;
    bytes[1] = _magicL;
    bytes[2] = protocolVersion;
    bytes[3] = _dataKind;
    data.setUint32(4, transferId, Endian.big);
    data.setUint16(8, fragmentIndex, Endian.big);
    data.setUint16(10, fragmentCount, Endian.big);
    data.setUint16(12, payload.length, Endian.big);
    bytes.setRange(headerLength, bytes.length, payload);
    return bytes;
  }

  static BleFrame decode(List<int> input) {
    if (input.length < headerLength) {
      throw const FormatException('BLE frame is shorter than its header');
    }
    final bytes = Uint8List.fromList(input);
    final data = ByteData.sublistView(bytes);
    if (bytes[0] != _magicI || bytes[1] != _magicL) {
      throw const FormatException('Invalid InLink BLE frame magic');
    }
    if (bytes[2] != protocolVersion) {
      throw FormatException('Unsupported BLE frame version: ${bytes[2]}');
    }
    if (bytes[3] != _dataKind) {
      throw FormatException('Unsupported BLE frame kind: ${bytes[3]}');
    }
    final payloadLength = data.getUint16(12, Endian.big);
    if (payloadLength < 1 || payloadLength > maxPayloadBytes) {
      throw const FormatException('Invalid BLE frame payload length');
    }
    if (input.length != headerLength + payloadLength) {
      throw const FormatException('BLE frame length does not match header');
    }
    try {
      return BleFrame(
        transferId: data.getUint32(4, Endian.big),
        fragmentIndex: data.getUint16(8, Endian.big),
        fragmentCount: data.getUint16(10, Endian.big),
        payload: bytes.sublist(headerLength),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid BLE frame fields: $error');
    }
  }
}
