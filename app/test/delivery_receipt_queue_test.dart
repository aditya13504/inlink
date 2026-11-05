import 'package:flutter_test/flutter_test.dart';
import 'package:inlink/core/messaging/delivery_receipt_queue.dart';
import 'package:inlink/core/messaging/local_message_repository.dart';

void main() {
  test('receipt serialization retains type, stable ID and retry schedule', () {
    final receipt = PendingDeliveryReceipt(
      id: 'message-a:digest-a',
      contactFingerprint: 'aa:bb',
      messageId: 'message-a',
      envelopeDigest: 'digest-a',
      recipientFingerprint: 'cc:dd',
      receivedAtUtc: DateTime.utc(2026, 10, 9, 10),
      createdAtUtc: DateTime.utc(2026, 10, 9, 10),
      retryCount: 2,
      nextAttemptAtUtc: DateTime.utc(2026, 10, 9, 10, 5),
    );
    final restored = PendingDeliveryReceipt.fromJson(receipt.toJson());
    expect(restored.id, receipt.id);
    expect(restored.type, 'receipt');
    expect(restored.retryCount, 2);
    expect(restored.nextAttemptAtUtc, receipt.nextAttemptAtUtc);
  });

  test('receipt acknowledgement is represented distinctly', () {
    final ack = PendingDeliveryReceipt(
      id: 'ack:message-a:digest-a',
      type: 'receiptAck',
      contactFingerprint: 'aa:bb',
      messageId: 'message-a',
      envelopeDigest: 'digest-a',
      recipientFingerprint: 'aa:bb',
      receivedAtUtc: DateTime.utc(2026, 10, 9),
    );
    expect(PendingDeliveryReceipt.fromJson(ack.toJson()).type, 'receiptAck');
  });

  test('message version 3 persists all envelope digests across retries', () {
    final message = LocalChatMessage(
      id: 'message-a',
      contactFingerprint: 'aa:bb',
      direction: LocalMessageDirection.outgoing,
      text: 'hello',
      createdAtUtc: DateTime.utc(2026, 10, 9),
      status: LocalDeliveryStatus.inTransit,
      encodedEnvelope: 'new-envelope',
      sentEnvelopeDigests: const <String>['old-digest', 'new-digest'],
    );
    final restored = LocalChatMessage.fromJson(message.toJson());
    expect(restored.sentEnvelopeDigests, <String>['old-digest', 'new-digest']);
  });

  test('legacy message versions still migrate without digest history', () {
    final restored = LocalChatMessage.fromJson(<String, dynamic>{
      'version': 2,
      'id': 'legacy',
      'contactFingerprint': 'aa:bb',
      'direction': 'outgoing',
      'text': 'hello',
      'createdAtUtc': '2026-10-09T00:00:00.000Z',
      'status': 'queued',
      'encodedEnvelope': null,
      'error': null,
      'expiresAtUtc': '2026-10-16T00:00:00.000Z',
      'retryCount': 0,
      'nextAttemptAtUtc': '2026-10-09T00:00:00.000Z',
      'lastAttemptAtUtc': null,
    });
    expect(restored.sentEnvelopeDigests, isEmpty);
  });
}
