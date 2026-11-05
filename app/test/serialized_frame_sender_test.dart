import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inlink/core/network/ble/serialized_frame_sender.dart';

void main() {
  test('batches are serialized and their fragments do not interleave', () async {
    final sender = SerializedFrameSender();
    final events = <String>[];
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();

    Future<void> send(Uint8List frame) async {
      final label = String.fromCharCode(frame.single);
      events.add('start-$label');
      if (label == 'a') {
        if (!firstStarted.isCompleted) firstStarted.complete();
        await releaseFirst.future;
      }
      events.add('end-$label');
    }

    final batchA = sender.sendBatch(
      <Uint8List>[Uint8List.fromList(<int>[97]), Uint8List.fromList(<int>[98])],
      send,
    );
    await firstStarted.future;
    final batchB = sender.sendBatch(
      <Uint8List>[Uint8List.fromList(<int>[120]), Uint8List.fromList(<int>[121])],
      send,
    );
    expect(events, <String>['start-a']);
    releaseFirst.complete();
    await Future.wait<void>(<Future<void>>[batchA, batchB]);

    expect(events, <String>[
      'start-a', 'end-a', 'start-b', 'end-b', 'start-x', 'end-x', 'start-y', 'end-y',
    ]);
  });

  test('a failed batch does not permanently poison the sender queue', () async {
    final sender = SerializedFrameSender();
    await expectLater(
      sender.sendBatch(
        <Uint8List>[Uint8List.fromList(<int>[1])],
        (_) async => throw StateError('simulated disconnect'),
      ),
      throwsStateError,
    );
    await sender.sendBatch(
      <Uint8List>[Uint8List.fromList(<int>[2])],
      (_) async {},
    );
  });

  test('close invalidates queued work even if sender is reopened', () async {
    final sender = SerializedFrameSender();
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final sent = <int>[];

    final first = sender.sendBatch(
      <Uint8List>[Uint8List.fromList(<int>[1])],
      (frame) async {
        firstStarted.complete();
        await releaseFirst.future;
        sent.add(frame.single);
      },
    );
    await firstStarted.future;
    final stale = sender.sendBatch(
      <Uint8List>[Uint8List.fromList(<int>[2])],
      (frame) async { sent.add(frame.single); },
    );
    sender.close();
    sender.reopen();
    releaseFirst.complete();
    await first;
    await expectLater(stale, throwsStateError);
    expect(sent, <int>[1]);
  });
}
