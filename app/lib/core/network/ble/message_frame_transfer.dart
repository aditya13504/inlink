import 'dart:typed_data';

import 'ble_frame.dart';

/// Fragments an already-encrypted envelope into transport frames.
class MessageFrameTransfer {
  static List<Uint8List> fragment({
    required List<int> messageBytes,
    required int transferId,
  }) {
    if (messageBytes.isEmpty || messageBytes.length > BleFrame.maxMessageBytes) {
      throw ArgumentError.value(
        messageBytes.length,
        'messageBytes.length',
        'Message must contain 1-${BleFrame.maxMessageBytes} bytes.',
      );
    }
    final count =
        (messageBytes.length + BleFrame.maxPayloadBytes - 1) ~/ BleFrame.maxPayloadBytes;
    final frames = <Uint8List>[];
    for (var index = 0; index < count; index++) {
      final start = index * BleFrame.maxPayloadBytes;
      final end = (start + BleFrame.maxPayloadBytes < messageBytes.length)
          ? start + BleFrame.maxPayloadBytes
          : messageBytes.length;
      frames.add(BleFrame(
        transferId: transferId,
        fragmentIndex: index,
        fragmentCount: count,
        payload: messageBytes.sublist(start, end),
      ).encode());
    }
    return frames;
  }
}

/// Bounded in-memory reassembly. The app must still validate/decrypt the
/// completed envelope; transport frames are untrusted and unauthenticated.
class MessageFrameReassembler {
  MessageFrameReassembler({
    this.maxConcurrentTransfers = 16,
    this.maxTransferAge = const Duration(minutes: 2),
    this.maxBufferedBytes = 256 * 1024,
  }) {
    if (maxConcurrentTransfers < 1) {
      throw ArgumentError.value(maxConcurrentTransfers, 'maxConcurrentTransfers');
    }
    if (maxTransferAge <= Duration.zero) {
      throw ArgumentError.value(maxTransferAge, 'maxTransferAge');
    }
    if (maxBufferedBytes < BleFrame.maxPayloadBytes) {
      throw ArgumentError.value(maxBufferedBytes, 'maxBufferedBytes');
    }
  }

  final int maxConcurrentTransfers;
  final Duration maxTransferAge;
  final int maxBufferedBytes;
  final Map<int, _PartialTransfer> _partials = <int, _PartialTransfer>{};

  /// Number of partial transfers currently retained in memory.
  int get activeTransfers => _partials.length;

  /// Total payload bytes retained across partial transfers.
  int get bufferedBytes => _partials.values.fold<int>(
    0,
    (sum, partial) => sum + partial.bufferedBytes,
  );

  /// Drop incomplete work on disconnect or explicit session reset.
  void clear() => _partials.clear();

  Uint8List? accept(List<int> encodedFrame, {DateTime? now}) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    _expire(timestamp);
    final frame = BleFrame.decode(encodedFrame);
    var partial = _partials[frame.transferId];
    if (partial == null) {
      if (_partials.length >= maxConcurrentTransfers) {
        final oldest = _partials.entries.reduce((a, b) =>
            a.value.createdAt.isBefore(b.value.createdAt) ? a : b);
        _partials.remove(oldest.key);
      }
      if (frame.payload.length > maxBufferedBytes) {
        throw const FormatException('Fragment exceeds reassembly memory budget.');
      }
      partial = _PartialTransfer(
        count: frame.fragmentCount,
        createdAt: timestamp,
      );
      _partials[frame.transferId] = partial;
    }
    if (partial.count != frame.fragmentCount) {
      _partials.remove(frame.transferId);
      throw const FormatException('Conflicting fragment count for transfer.');
    }
    final existing = partial.fragments[frame.fragmentIndex];
    if (existing != null) {
      if (!_sameBytes(existing, frame.payload)) {
        _partials.remove(frame.transferId);
        throw const FormatException('Conflicting duplicate fragment.');
      }
      return null;
    }
    if (bufferedBytes + frame.payload.length > maxBufferedBytes) {
      _partials.remove(frame.transferId);
      throw const FormatException('Reassembly memory budget exceeded.');
    }
    partial.fragments[frame.fragmentIndex] = frame.payload;
    partial.bufferedBytes += frame.payload.length;
    if (partial.fragments.length != partial.count) return null;

    final total = partial.bufferedBytes;
    if (total > BleFrame.maxMessageBytes) {
      _partials.remove(frame.transferId);
      throw const FormatException('Reassembled message exceeds size limit.');
    }
    final output = Uint8List(total);
    var offset = 0;
    for (var index = 0; index < partial.count; index++) {
      final chunk = partial.fragments[index];
      if (chunk == null) return null;
      output.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    _partials.remove(frame.transferId);
    return output;
  }

  void _expire(DateTime now) {
    _partials.removeWhere((_, value) =>
      now.difference(value.createdAt) > maxTransferAge ||
      now.isBefore(value.createdAt));
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}

class _PartialTransfer {
  _PartialTransfer({required this.count, required this.createdAt});
  final int count;
  final DateTime createdAt;
  final Map<int, Uint8List> fragments = <int, Uint8List>{};
  int bufferedBytes = 0;
}
