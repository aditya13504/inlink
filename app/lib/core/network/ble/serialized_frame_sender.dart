import 'dart:async';
import 'dart:typed_data';

/// Serializes complete frame batches so fragments from separate envelopes never
/// interleave on a single BLE characteristic.
class SerializedFrameSender {
  Future<void> _tail = Future<void>.value();
  bool _closed = false;
  int _session = 0;

  bool get isClosed => _closed;

  Future<void> sendBatch(
    List<Uint8List> frames,
    Future<void> Function(Uint8List frame) sendFrame,
  ) {
    if (_closed) {
      return Future<void>.error(StateError('BLE frame sender is closed.'));
    }
    if (frames.isEmpty) {
      return Future<void>.error(ArgumentError('A frame batch cannot be empty.'));
    }
    final submittedSession = _session;
    final immutableBatch = frames
        .map((frame) => Uint8List.fromList(frame))
        .toList(growable: false);
    final operation = _tail.then((_) async {
      if (_closed || submittedSession != _session) {
        throw StateError('BLE frame batch belongs to a stale session.');
      }
      for (final frame in immutableBatch) {
        if (_closed || submittedSession != _session) {
          throw StateError('BLE frame sender was closed mid-batch.');
        }
        await sendFrame(frame);
      }
    });
    // Keep the queue usable after a failed batch, while propagating that
    // failure to the caller that submitted the batch.
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }

  /// Prevent queued-but-not-started batches from starting after transport stop.
  /// An in-flight native write cannot be cancelled through the current channel.
  void close() {
    _closed = true;
    _session++;
  }

  /// Start a fresh logical session after BLE has been restarted.
  void reopen() {
    _session++;
    _closed = false;
  }

  Future<void> idle() => _tail;
}
