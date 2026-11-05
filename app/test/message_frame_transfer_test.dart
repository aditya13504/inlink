import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inlink/core/network/ble/message_frame_transfer.dart';
import 'package:inlink/core/network/ble/ble_frame.dart';

void main() {
  test('fragments and reassembles a message in reverse order', () {
    final bytes = utf8.encode('message-' * 100);
    final frames = MessageFrameTransfer.fragment(messageBytes: bytes, transferId: 42);
    final reassembler = MessageFrameReassembler();
    List<int>? completed;
    for (final frame in frames.reversed) {
      completed = reassembler.accept(frame) ?? completed;
    }
    expect(completed, bytes);
  });

  test('duplicate identical fragments are harmless', () {
    final bytes = utf8.encode('x' * 300);
    final frames = MessageFrameTransfer.fragment(messageBytes: bytes, transferId: 7);
    final reassembler = MessageFrameReassembler();
    expect(reassembler.accept(frames.first), isNull);
    expect(reassembler.accept(frames.first), isNull);
    List<int>? complete;
    for (final frame in frames.skip(1)) {
      complete = reassembler.accept(frame) ?? complete;
    }
    expect(complete, bytes);
  });

  test('enforces total buffered-byte budget across partial transfers', () {
    final reassembler = MessageFrameReassembler(
      maxConcurrentTransfers: 4,
      maxBufferedBytes: 200,
    );
    final first = BleFrame(
      transferId: 1,
      fragmentIndex: 0,
      fragmentCount: 2,
      payload: List<int>.filled(180, 1),
    ).encode();
    final second = BleFrame(
      transferId: 2,
      fragmentIndex: 0,
      fragmentCount: 2,
      payload: List<int>.filled(30, 2),
    ).encode();
    expect(reassembler.accept(first), isNull);
    expect(reassembler.bufferedBytes, 180);
    expect(() => reassembler.accept(second), throwsFormatException);
    expect(reassembler.bufferedBytes, 180);
  });

  test('clear discards partial transfers after disconnect', () {
    final reassembler = MessageFrameReassembler();
    final frame = MessageFrameTransfer.fragment(
      messageBytes: utf8.encode('partial-' * 50),
      transferId: 123,
    ).first;
    reassembler.accept(frame);
    expect(reassembler.activeTransfers, 1);
    reassembler.clear();
    expect(reassembler.activeTransfers, 0);
    expect(reassembler.bufferedBytes, 0);
  });

  test('expires transfers and rejects timestamps moving backwards', () {
    final reassembler = MessageFrameReassembler(maxTransferAge: const Duration(seconds: 5));
    final frame = MessageFrameTransfer.fragment(
      messageBytes: utf8.encode('partial-' * 50),
      transferId: 9,
    ).first;
    reassembler.accept(frame, now: DateTime.utc(2026, 10, 9, 12));
    expect(reassembler.activeTransfers, 1);
    final singleFrame = BleFrame(
      transferId: 10,
      fragmentIndex: 0,
      fragmentCount: 1,
      payload: <int>[7],
    ).encode();
    expect(
      reassembler.accept(singleFrame, now: DateTime.utc(2026, 10, 9, 12, 0, 6)),
      <int>[7],
    );
    expect(reassembler.activeTransfers, 0);
    expect(reassembler.bufferedBytes, 0);

    reassembler.accept(frame, now: DateTime.utc(2026, 10, 9, 12));
    final otherPartial = BleFrame(
      transferId: 11,
      fragmentIndex: 0,
      fragmentCount: 2,
      payload: List<int>.filled(50, 9),
    ).encode();
    reassembler.accept(otherPartial, now: DateTime.utc(2026, 10, 9, 11));
    expect(reassembler.activeTransfers, 1);
    expect(reassembler.bufferedBytes, 50);
  });


  test('conflicting duplicate fragment discards the partial transfer', () {
    final reassembler = MessageFrameReassembler();
    final first = BleFrame(
      transferId: 77,
      fragmentIndex: 0,
      fragmentCount: 2,
      payload: <int>[1, 2, 3],
    ).encode();
    final conflict = BleFrame(
      transferId: 77,
      fragmentIndex: 0,
      fragmentCount: 2,
      payload: <int>[1, 2, 4],
    ).encode();

    expect(reassembler.accept(first), isNull);
    expect(reassembler.activeTransfers, 1);
    expect(() => reassembler.accept(conflict), throwsFormatException);
    expect(reassembler.activeTransfers, 0);
    expect(reassembler.bufferedBytes, 0);
  });

  test('conflicting fragment count discards the partial transfer', () {
    final reassembler = MessageFrameReassembler();
    final first = BleFrame(
      transferId: 78,
      fragmentIndex: 0,
      fragmentCount: 2,
      payload: <int>[1, 2, 3],
    ).encode();
    final conflict = BleFrame(
      transferId: 78,
      fragmentIndex: 1,
      fragmentCount: 3,
      payload: <int>[4, 5],
    ).encode();

    expect(reassembler.accept(first), isNull);
    expect(() => reassembler.accept(conflict), throwsFormatException);
    expect(reassembler.activeTransfers, 0);
    expect(reassembler.bufferedBytes, 0);
  });

  test('rejects messages larger than frame protocol maximum', () {
    expect(
      () => MessageFrameTransfer.fragment(
        messageBytes: List<int>.filled(16385, 1),
        transferId: 1,
      ),
      throwsArgumentError,
    );
  });
}
