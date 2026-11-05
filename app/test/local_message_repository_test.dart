import 'package:flutter_test/flutter_test.dart';
import 'package:inlink/core/messaging/local_message_repository.dart';

void main() {
  test('message record round-trips its core fields', () {
    final original = LocalChatMessage(
      id: 'msg-1',
      contactFingerprint: 'aa:bb',
      direction: LocalMessageDirection.outgoing,
      text: 'hello',
      createdAtUtc: DateTime.utc(2026, 10, 9),
      status: LocalDeliveryStatus.queued,
      encodedEnvelope: '{"version":1}',
    );
    final restored = LocalChatMessage.fromJson(original.toJson());
    expect(restored.id, original.id);
    expect(restored.contactFingerprint, original.contactFingerprint);
    expect(restored.direction, LocalMessageDirection.outgoing);
    expect(restored.text, 'hello');
    expect(restored.status, LocalDeliveryStatus.queued);
    expect(restored.encodedEnvelope, '{"version":1}');
    expect(restored.transport, 'legacy');
  });

  test('rejects unknown direction/status and invalid timestamps', () {
    final invalid = <String, Object?>{
      'version': 1,
      'id': 'x',
      'contactFingerprint': 'aa',
      'direction': 'unknown',
      'text': 'hello',
      'createdAtUtc': 'not-a-date',
      'status': 'unknown',
    };
    expect(() => LocalChatMessage.fromJson(invalid), throwsFormatException);
  });
}
