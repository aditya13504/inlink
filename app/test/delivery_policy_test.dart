import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:inlink/core/messaging/delivery_policy.dart';
import 'package:inlink/core/messaging/local_message_repository.dart';

void main() {
  test('retry delay grows exponentially and is capped', () {
    const policy = DeliveryPolicy(
      baseDelay: Duration(seconds: 5),
      maxDelay: Duration(seconds: 20),
    );
    expect(policy.delayAfterAttempt(1), const Duration(seconds: 5));
    expect(policy.delayAfterAttempt(2), const Duration(seconds: 10));
    expect(policy.delayAfterAttempt(3), const Duration(seconds: 20));
    expect(policy.delayAfterAttempt(8), const Duration(seconds: 20));
  });

  test('jitter remains bounded and reproducible with injected random', () {
    const policy = DeliveryPolicy(baseDelay: Duration(seconds: 10));
    final delay = jitteredBackoff(policy: policy, attempt: 1, random: Random(1));
    expect(delay.inMilliseconds, inInclusiveRange(8000, 12000));
  });

  test('expiry uses UTC and seven-day default metadata round trips', () {
    final created = DateTime.utc(2026, 10, 1);
    final message = LocalChatMessage(
      id: 'message-1',
      contactFingerprint: 'aa:bb',
      direction: LocalMessageDirection.outgoing,
      text: 'hello',
      createdAtUtc: created,
      status: LocalDeliveryStatus.queued,
    );
    expect(message.expiresAtUtc, DateTime.utc(2026, 10, 8));
    expect(LocalChatMessage.fromJson(message.toJson()).expiresAtUtc, message.expiresAtUtc);
  });

  test('version 1 records migrate with safe delivery defaults', () {
    final restored = LocalChatMessage.fromJson(<String, dynamic>{
      'version': 1,
      'id': 'old-message',
      'contactFingerprint': 'aa:bb',
      'direction': 'outgoing',
      'text': 'old',
      'createdAtUtc': '2026-10-01T00:00:00.000Z',
      'status': 'queued',
      'encodedEnvelope': null,
      'error': null,
    });
    expect(restored.retryCount, 0);
    expect(restored.expiresAtUtc, DateTime.utc(2026, 10, 8));
    expect(restored.nextAttemptAtUtc, DateTime.utc(2026, 10, 1));
  });
}
