import 'package:flutter_test/flutter_test.dart';
import 'package:inlink/core/network/ble/ble_frame.dart';

void main() {
  group('BleFrame', () {
    test('round-trips header fields and payload', () {
      final original = BleFrame(
        transferId: 0x1234ABCD,
        fragmentIndex: 1,
        fragmentCount: 3,
        payload: [0, 1, 2, 127, 255],
      );

      final decoded = BleFrame.decode(original.encode());
      expect(decoded.transferId, original.transferId);
      expect(decoded.fragmentIndex, original.fragmentIndex);
      expect(decoded.fragmentCount, original.fragmentCount);
      expect(decoded.payload, original.payload);
    });

    test('rejects a truncated frame', () {
      expect(() => BleFrame.decode([0x49, 0x4C]), throwsFormatException);
    });

    test('rejects an unknown protocol version', () {
      final bytes = BleFrame(
        transferId: 1,
        fragmentIndex: 0,
        fragmentCount: 1,
        payload: [42],
      ).encode();
      bytes[2] = 99;
      expect(() => BleFrame.decode(bytes), throwsFormatException);
    });

    test('rejects a payload length mismatch', () {
      final bytes = BleFrame(
        transferId: 1,
        fragmentIndex: 0,
        fragmentCount: 1,
        payload: [42],
      ).encode();
      bytes[13] = 2;
      expect(() => BleFrame.decode(bytes), throwsFormatException);
    });

    test('rejects invalid fragment indexes and oversized payloads', () {
      expect(
        () => BleFrame(
          transferId: 1,
          fragmentIndex: 2,
          fragmentCount: 2,
          payload: [1],
        ),
        throwsArgumentError,
      );
      expect(
        () => BleFrame(
          transferId: 1,
          fragmentIndex: 0,
          fragmentCount: 1,
          payload: List.filled(BleFrame.maxPayloadBytes + 1, 1),
        ),
        throwsArgumentError,
      );
    });
  });
}
