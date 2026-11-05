import '../../messaging/local_message_repository.dart';

/// Durable application-level message operations needed by mesh orchestration.
/// Implementations must persist before returning successfully.
abstract interface class MeshApplicationMessageStore {
  Future<void> saveOutgoing({
    required String messageId,
    required String contactFingerprint,
    required String text,
    required String encodedEnvelope,
    required DateTime createdAtUtc,
    required DateTime expiresAtUtc,
  });

  Future<bool> saveIncomingIfAbsent({
    required String messageId,
    required String contactFingerprint,
    required String text,
    required DateTime receivedAtUtc,
  });

  Future<List<LocalChatMessage>> listPendingOutgoing({required DateTime nowUtc});

  Future<LocalChatMessage?> findOutgoing(String messageId);

  Future<void> markDelivered({
    required String messageId,
    required String contactFingerprint,
  });
}

/// Bridges mesh messaging to the existing SQLCipher-backed conversation store.
/// The conversation repository is the durable source of truth for local text,
/// status and encrypted envelope; the mesh queue remains the source of truth
/// for route metadata and transport retry.
class SqlCipherMeshApplicationMessageStore implements MeshApplicationMessageStore {
  SqlCipherMeshApplicationMessageStore(this.repository);

  final LocalMessageRepository repository;

  @override
  Future<void> saveOutgoing({
    required String messageId,
    required String contactFingerprint,
    required String text,
    required String encodedEnvelope,
    required DateTime createdAtUtc,
    required DateTime expiresAtUtc,
  }) async {
    await repository.add(LocalChatMessage(
      id: messageId,
      contactFingerprint: contactFingerprint,
      direction: LocalMessageDirection.outgoing,
      text: text,
      createdAtUtc: createdAtUtc.toUtc(),
      expiresAtUtc: expiresAtUtc.toUtc(),
      status: LocalDeliveryStatus.queued,
      transport: 'mesh',
      encodedEnvelope: encodedEnvelope,
    ));
  }

  @override
  Future<bool> saveIncomingIfAbsent({
    required String messageId,
    required String contactFingerprint,
    required String text,
    required DateTime receivedAtUtc,
  }) async {
    final existing = await repository.listForContact(contactFingerprint);
    if (existing.any((message) =>
        message.id == messageId &&
        message.direction == LocalMessageDirection.incoming)) {
      return false;
    }
    await repository.add(LocalChatMessage(
      id: messageId,
      contactFingerprint: contactFingerprint,
      direction: LocalMessageDirection.incoming,
      text: text,
      createdAtUtc: receivedAtUtc.toUtc(),
      expiresAtUtc: receivedAtUtc.toUtc().add(const Duration(days: 7)),
      status: LocalDeliveryStatus.delivered,
      transport: 'mesh',
    ));
    return true;
  }

  @override
  Future<List<LocalChatMessage>> listPendingOutgoing({required DateTime nowUtc}) async {
    final now = nowUtc.toUtc();
    final messages = await repository.listAll();
    return messages.where((message) =>
      message.direction == LocalMessageDirection.outgoing &&
      message.transport == 'mesh' &&
      message.encodedEnvelope != null &&
      message.status != LocalDeliveryStatus.delivered &&
      message.status != LocalDeliveryStatus.expired &&
      message.expiresAtUtc.isAfter(now)
    ).toList()
      ..sort((a, b) => a.createdAtUtc.compareTo(b.createdAtUtc));
  }

  @override
  Future<LocalChatMessage?> findOutgoing(String messageId) async {
    final messages = await repository.listAll();
    for (final message in messages) {
      if (message.id == messageId &&
          message.direction == LocalMessageDirection.outgoing) {
        return message;
      }
    }
    return null;
  }

  @override
  Future<void> markDelivered({
    required String messageId,
    required String contactFingerprint,
  }) async {
    final messages = await repository.listForContact(contactFingerprint);
    for (final message in messages) {
      if (message.id == messageId &&
          message.direction == LocalMessageDirection.outgoing) {
        await repository.update(message.copyWith(
          status: LocalDeliveryStatus.delivered,
          clearError: true,
        ));
        return;
      }
    }
  }
}
