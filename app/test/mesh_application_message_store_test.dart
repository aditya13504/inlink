import 'package:flutter_test/flutter_test.dart';
import 'package:inlink/core/messaging/local_message_repository.dart';
import 'package:inlink/core/network/mesh/mesh_application_message_store.dart';

class _FakeRepository extends LocalMessageRepository {
  _FakeRepository() : super(maxMessages: 20);

  final List<LocalChatMessage> rows = <LocalChatMessage>[];

  @override
  Future<List<LocalChatMessage>> listAll() async =>
      List<LocalChatMessage>.of(rows);

  @override
  Future<List<LocalChatMessage>> listForContact(String fingerprint) async =>
      rows.where((row) =>
        row.contactFingerprint.toLowerCase() == fingerprint.toLowerCase()
      ).toList();

  @override
  Future<void> add(LocalChatMessage message) async {
    final exists = rows.any((row) =>
      row.id == message.id &&
      row.direction == message.direction &&
      row.contactFingerprint.toLowerCase() == message.contactFingerprint.toLowerCase()
    );
    if (!exists) rows.add(message);
  }

  @override
  Future<void> update(LocalChatMessage message) async {
    final index = rows.indexWhere((row) =>
      row.id == message.id &&
      row.direction == message.direction &&
      row.contactFingerprint.toLowerCase() == message.contactFingerprint.toLowerCase()
    );
    if (index >= 0) rows[index] = message;
  }
}

void main() {
  late _FakeRepository repository;
  late SqlCipherMeshApplicationMessageStore store;

  setUp(() {
    repository = _FakeRepository();
    store = SqlCipherMeshApplicationMessageStore(repository);
  });

  test('outgoing envelope is persisted and restored as pending', () async {
    final now = DateTime.utc(2026, 10, 9, 12);
    repository.rows.add(LocalChatMessage(
      id: 'legacy-message-00000001',
      contactFingerprint: 'ABCD',
      direction: LocalMessageDirection.outgoing,
      text: 'legacy',
      createdAtUtc: now,
      expiresAtUtc: now.add(const Duration(days: 1)),
      status: LocalDeliveryStatus.queued,
      encodedEnvelope: '{"legacy":true}',
      transport: 'legacy',
    ));
    await store.saveOutgoing(
      messageId: 'message-0000000000000001',
      contactFingerprint: 'ABCD',
      text: 'hello',
      encodedEnvelope: '{"ciphertext":"opaque"}',
      createdAtUtc: now,
      expiresAtUtc: now.add(const Duration(days: 1)),
    );

    final pending = await store.listPendingOutgoing(nowUtc: now);
    expect(pending, hasLength(1));
    expect(pending.single.text, 'hello');
    expect(pending.single.encodedEnvelope, '{"ciphertext":"opaque"}');
    expect(pending.single.status, LocalDeliveryStatus.queued);
    expect(pending.single.transport, 'mesh');
  });

  test('incoming message is idempotent by contact and message ID', () async {
    final now = DateTime.utc(2026, 10, 9, 12);
    final first = await store.saveIncomingIfAbsent(
      messageId: 'message-0000000000000002',
      contactFingerprint: 'ABCD',
      text: 'hello',
      receivedAtUtc: now,
    );
    final second = await store.saveIncomingIfAbsent(
      messageId: 'message-0000000000000002',
      contactFingerprint: 'ABCD',
      text: 'hello',
      receivedAtUtc: now,
    );

    expect(first, isTrue);
    expect(second, isFalse);
    expect(repository.rows, hasLength(1));
    expect(repository.rows.single.transport, 'mesh');
  });

  test('authenticated delivery updates durable outgoing state', () async {
    final now = DateTime.utc(2026, 10, 9, 12);
    await store.saveOutgoing(
      messageId: 'message-0000000000000003',
      contactFingerprint: 'ABCD',
      text: 'hello',
      encodedEnvelope: '{"ciphertext":"opaque"}',
      createdAtUtc: now,
      expiresAtUtc: now.add(const Duration(days: 1)),
    );

    await store.markDelivered(
      messageId: 'message-0000000000000003',
      contactFingerprint: 'ABCD',
    );

    expect(
      (await store.findOutgoing('message-0000000000000003'))!.status,
      LocalDeliveryStatus.delivered,
    );
    expect(await store.listPendingOutgoing(nowUtc: now), isEmpty);
  });
}
