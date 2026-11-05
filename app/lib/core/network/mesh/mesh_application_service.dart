import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../../messaging/local_message_repository.dart';
import '../../security/contact_identity.dart';
import '../../security/identity_vault.dart';
import '../../security/secure_message.dart';
import '../../security/verified_message_service.dart';
import 'authenticated_mesh_ingress.dart';
import 'mesh_identity_handshake.dart';
import 'mesh_application_message_store.dart';
import 'mesh_routing_engine.dart';
import 'mesh_transport_adapter.dart';

const int meshApplicationPayloadVersion = 1;
const int _maxChatTextBytes = 8 * 1024;
const List<int> _receiptDomain = <int>[
  0x49, 0x6e, 0x4c, 0x69, 0x6e, 0x6b, 0x2d, 0x44,
  0x65, 0x6c, 0x69, 0x76, 0x65, 0x72, 0x79, 0x2d,
  0x52, 0x65, 0x63, 0x65, 0x69, 0x70, 0x74, 0x2d, 0x76, 0x31, 0x00,
];

enum InLinkDeliveryState {
  queued,
  inboundMessage,
  delivered,
  relaying,
  duplicate,
  rejected,
  recoveryComplete,
}

class InLinkApplicationEvent {
  const InLinkApplicationEvent({
    required this.state,
    this.messageId,
    this.peerNodeId,
    this.text,
    this.detail = '',
  });

  final InLinkDeliveryState state;
  final String? messageId;
  final String? peerNodeId;
  final String? text;
  final String detail;
}

/// Application orchestration layer for one-to-one text over the mesh.
///
/// It persists an opaque E2EE envelope before attempting transport, restores
/// pending routes at startup, handles authenticated inbound text, and sends a
/// signed+encrypted receipt only after the inbound E2EE envelope has passed
/// sender pinning, signature verification, decryption and replay checks.
class MeshApplicationService {
  MeshApplicationService({
    required this.localNodeId,
    required this.vault,
    required this.verifiedMessages,
    required this.adapter,
    required this.ingress,
    required this.messageStore,
    DateTime Function()? clock,
    Random? random,
  })  : _clock = clock ?? DateTime.now,
        _random = random ?? Random.secure();

  final String localNodeId;
  final IdentityVault vault;
  final VerifiedMessageService verifiedMessages;
  final MeshTransportAdapter adapter;
  final AuthenticatedMeshIngress ingress;
  final MeshApplicationMessageStore messageStore;
  final DateTime Function() _clock;
  final Random _random;

  final StreamController<InLinkApplicationEvent> _events =
      StreamController<InLinkApplicationEvent>.broadcast();
  StreamSubscription<MeshIngressEvent>? _ingressSubscription;
  bool _started = false;
  bool _disposed = false;

  Stream<InLinkApplicationEvent> get events => _events.stream;

  Future<int> start() async {
    if (_disposed) throw StateError('Mesh application service is disposed.');
    if (_started) return 0;
    final now = _clock().toUtc();
    final restored = await adapter.durableRouter?.restore(now: now) ?? 0;
    _ingressSubscription = ingress.events.listen(
      _handleIngress,
      onError: (Object _) => _emit(const InLinkApplicationEvent(
        state: InLinkDeliveryState.rejected,
        detail: 'Mesh ingress stream failed.',
      )),
    );
    try {
      await ingress.start();
      await _restoreApplicationOutbox(now);
    } catch (_) {
      // Leave startup retryable if native ingress or durable outbox recovery
      // fails. Do not strand the UI in a false-ready state after one attempt.
      await _ingressSubscription?.cancel();
      _ingressSubscription = null;
      rethrow;
    }
    _started = true;
    _emit(InLinkApplicationEvent(
      state: InLinkDeliveryState.recoveryComplete,
      detail: 'Restored $restored pending mesh routes.',
    ));
    try {
      await retryPending();
    } catch (_) {
      // Ingress and durable recovery are initialized; transport can be retried
      // independently without tearing down the authenticated receive stream.
      _emit(const InLinkApplicationEvent(
        state: InLinkDeliveryState.rejected,
        detail: 'Initial mesh transport retry failed; pending messages were retained.',
      ));
    }
    return restored;
  }

  /// Sends one text message to a contact that was previously verified by the
  /// app's fingerprint flow. This method never falls back to plaintext.
  Future<String> sendText({
    required VerifiedInLinkContact contact,
    required String text,
    Duration ttl = const Duration(days: 2),
    int hopLimit = meshMaxHopLimit,
  }) async {
    _ensureStarted();
    final normalizedText = text.trim();
    final textBytes = utf8.encode(normalizedText);
    if (textBytes.isEmpty || textBytes.length > _maxChatTextBytes) {
      throw ArgumentError.value(
        textBytes.length,
        'text',
        'Message must contain 1-$_maxChatTextBytes UTF-8 bytes.',
      );
    }
    if (ttl <= Duration.zero || ttl > meshMaxMessageAge) {
      throw ArgumentError.value(ttl, 'ttl', 'TTL must be positive and at most 7 days.');
    }

    final destinationNodeId = await meshNodeIdForKeys(
      signingPublicKey: contact.signingPublicKey,
      encryptionPublicKey: contact.encryptionPublicKey,
    );
    if (destinationNodeId == localNodeId) {
      throw ArgumentError('Cannot send a mesh message to this device identity.');
    }

    final messageId = _newId();
    final now = _clock().toUtc();
    final payload = <String, Object>{
      'version': meshApplicationPayloadVersion,
      'kind': 'text',
      'message_id': messageId,
      'sender_node_id': localNodeId,
      'destination_node_id': destinationNodeId,
      'created_at': now.millisecondsSinceEpoch ~/ 1000,
      'text': normalizedText,
    };
    final encodedPayload = jsonEncode(payload);
    if (utf8.encode(encodedPayload).length > EncryptedMessageEnvelope.maxPlaintextBytes) {
      throw ArgumentError('Message envelope exceeds the E2EE plaintext limit.');
    }

    final envelope = await verifiedMessages.sealToVerifiedContact(
      contact: contact,
      plaintext: encodedPayload,
    );
    final expiresAt = now.add(ttl);
    final encodedEnvelope = envelope.encode();
    // Persist the local conversation record before the route queue or transport
    // is touched. If the process dies after this write, startup can reconstruct
    // the pending mesh route from this record.
    await messageStore.saveOutgoing(
      messageId: messageId,
      contactFingerprint: contact.fingerprint,
      text: normalizedText,
      encodedEnvelope: encodedEnvelope,
      createdAtUtc: now,
      expiresAtUtc: expiresAt,
    );
    try {
      await adapter.originate(
        messageId: messageId,
        destinationNodeId: destinationNodeId,
        opaqueEnvelope: encodedEnvelope,
        now: now,
        expiresAt: expiresAt,
        hopLimit: hopLimit,
      );
    } catch (_) {
      // Keep the encrypted outbox record. A later retry/startup can restore it;
      // never delete a user's message because a transport was temporarily down.
    }
    _emit(InLinkApplicationEvent(
      state: InLinkDeliveryState.queued,
      messageId: messageId,
      peerNodeId: destinationNodeId,
      detail: 'Encrypted message saved locally; awaiting authenticated recipient receipt.',
    ));
    return messageId;
  }

  /// Call after a native peer connects or internet relay connectivity changes.
  /// A successful local send only means transport accepted the packet; it does
  /// not mark the message delivered.
  Future<MeshFlushResult> retryPending() async {
    _ensureStarted();
    return adapter.flush(now: _clock().toUtc());
  }


  Future<void> _restoreApplicationOutbox(DateTime now) async {
    final contacts = await vault.listVerifiedContacts();
    final pending = await messageStore.listPendingOutgoing(nowUtc: now);
    for (final message in pending) {
      VerifiedInLinkContact? recipient;
      for (final contact in contacts) {
        if (contact.fingerprint.toLowerCase() != message.contactFingerprint.toLowerCase()) {
          continue;
        }
        recipient = contact;
        break;
      }
      if (recipient == null || message.encodedEnvelope == null) continue;
      final destinationNodeId = await meshNodeIdForKeys(
        signingPublicKey: recipient.signingPublicKey,
        encryptionPublicKey: recipient.encryptionPublicKey,
      );
      try {
        await adapter.originate(
          messageId: message.id,
          destinationNodeId: destinationNodeId,
          opaqueEnvelope: message.encodedEnvelope!,
          now: now,
          expiresAt: message.expiresAtUtc,
        );
      } on StateError {
        // The durable mesh queue may already have restored this route. The
        // outbox row is still authoritative for receipt expectations.
      } catch (_) {
        // Leave the encrypted outbox record intact for a later reconnect/retry.
      }
    }
  }

  Future<void> _handleIngress(MeshIngressEvent event) async {
    if (_disposed) return;
    switch (event.status) {
      case MeshIngressStatus.forwarded:
        _emit(InLinkApplicationEvent(
          state: InLinkDeliveryState.relaying,
          messageId: event.messageId,
          peerNodeId: event.originNodeId,
          detail: 'Opaque encrypted packet accepted for forwarding.',
        ));
        return;
      case MeshIngressStatus.duplicate:
        _emit(InLinkApplicationEvent(
          state: InLinkDeliveryState.duplicate,
          messageId: event.messageId,
          peerNodeId: event.originNodeId,
        ));
        return;
      case MeshIngressStatus.rejected:
      case MeshIngressStatus.notForThisNode:
        _emit(InLinkApplicationEvent(
          state: InLinkDeliveryState.rejected,
          messageId: event.messageId,
          peerNodeId: event.originNodeId,
          detail: event.detail,
        ));
        return;
      case MeshIngressStatus.delivered:
        break;
    }

    final plaintext = event.plaintext;
    final originNodeId = event.originNodeId;
    final routeMessageId = event.messageId;
    if (plaintext == null || originNodeId == null || routeMessageId == null) {
      _emit(const InLinkApplicationEvent(
        state: InLinkDeliveryState.rejected,
        detail: 'Authenticated inbound event is missing required fields.',
      ));
      return;
    }

    final Map<String, dynamic> payload;
    try {
      if (utf8.encode(plaintext).length > EncryptedMessageEnvelope.maxPlaintextBytes) {
        throw const FormatException('Application payload too large.');
      }
      final decoded = jsonDecode(plaintext);
      if (decoded is! Map<String, dynamic> || decoded['version'] != meshApplicationPayloadVersion) {
        throw const FormatException('Unsupported application payload.');
      }
      payload = decoded;
    } on FormatException catch (error) {
      _emit(InLinkApplicationEvent(
        state: InLinkDeliveryState.rejected,
        messageId: routeMessageId,
        peerNodeId: originNodeId,
        detail: error.message,
      ));
      return;
    }

    final kind = payload['kind'];
    if (kind == 'text') {
      await _acceptText(
        payload: payload,
        routeMessageId: routeMessageId,
        originNodeId: originNodeId,
      );
    } else if (kind == 'delivery_receipt') {
      await _acceptReceipt(
        payload: payload,
        routeMessageId: routeMessageId,
        originNodeId: originNodeId,
      );
    } else {
      _emit(InLinkApplicationEvent(
        state: InLinkDeliveryState.rejected,
        messageId: routeMessageId,
        peerNodeId: originNodeId,
        detail: 'Unknown application payload kind.',
      ));
    }
  }

  Future<void> _acceptText({
    required Map<String, dynamic> payload,
    required String routeMessageId,
    required String originNodeId,
  }) async {
    if (payload.length != 7 ||
        payload['message_id'] != routeMessageId ||
        payload['sender_node_id'] != originNodeId ||
        payload['destination_node_id'] != localNodeId ||
        payload['created_at'] is! int ||
        payload['text'] is! String) {
      _emit(InLinkApplicationEvent(
        state: InLinkDeliveryState.rejected,
        messageId: routeMessageId,
        peerNodeId: originNodeId,
        detail: 'Text payload metadata does not match authenticated route.',
      ));
      return;
    }
    final text = payload['text'] as String;
    if (text.isEmpty || utf8.encode(text).length > _maxChatTextBytes) {
      _emit(InLinkApplicationEvent(
        state: InLinkDeliveryState.rejected,
        messageId: routeMessageId,
        peerNodeId: originNodeId,
        detail: 'Text payload violates message size limits.',
      ));
      return;
    }

    // Find the pinned sender and persist the message before acknowledging it.
    // A receipt must never claim durable delivery when local storage failed.
    final contacts = await vault.listVerifiedContacts();
    VerifiedInLinkContact? sender;
    for (final contact in contacts) {
      final nodeId = await meshNodeIdForKeys(
        signingPublicKey: contact.signingPublicKey,
        encryptionPublicKey: contact.encryptionPublicKey,
      );
      if (nodeId == originNodeId) {
        sender = contact;
        break;
      }
    }
    if (sender == null) {
      _emit(InLinkApplicationEvent(
        state: InLinkDeliveryState.rejected,
        messageId: routeMessageId,
        peerNodeId: originNodeId,
        detail: 'No trusted contact available for receipt.',
      ));
      return;
    }

    try {
      await messageStore.saveIncomingIfAbsent(
        messageId: routeMessageId,
        contactFingerprint: sender.fingerprint,
        text: text,
        receivedAtUtc: _clock().toUtc(),
      );
    } catch (_) {
      _emit(InLinkApplicationEvent(
        state: InLinkDeliveryState.rejected,
        messageId: routeMessageId,
        peerNodeId: originNodeId,
        detail: 'Could not persist inbound message; no delivery receipt was sent.',
      ));
      return;
    }
    _emit(InLinkApplicationEvent(
      state: InLinkDeliveryState.inboundMessage,
      messageId: routeMessageId,
      peerNodeId: originNodeId,
      text: text,
    ));

    final now = _clock().toUtc();
    final localIdentity = await vault.loadOrCreateIdentity();
    final receiptFields = <String, Object>{
      'version': meshApplicationPayloadVersion,
      'kind': 'delivery_receipt',
      'message_id': routeMessageId,
      'sender_node_id': localNodeId,
      'destination_node_id': originNodeId,
      'delivered_at': now.millisecondsSinceEpoch ~/ 1000,
    };
    final signature = await Ed25519().sign(
      _receiptSignedBytes(receiptFields),
      keyPair: localIdentity.signingKeyPair,
    );
    final receiptPayload = jsonEncode(<String, Object>{
      ...receiptFields,
      'signature': base64UrlEncode(signature.bytes),
    });
    final receiptEnvelope = await verifiedMessages.sealToVerifiedContact(
      contact: sender,
      plaintext: receiptPayload,
    );
    await adapter.originate(
      messageId: _newId(),
      destinationNodeId: originNodeId,
      opaqueEnvelope: receiptEnvelope.encode(),
      now: now,
      expiresAt: now.add(const Duration(days: 2)),
    );
  }

  Future<void> _acceptReceipt({
    required Map<String, dynamic> payload,
    required String routeMessageId,
    required String originNodeId,
  }) async {
    const fields = <String>{
      'version', 'kind', 'message_id', 'sender_node_id',
      'destination_node_id', 'delivered_at', 'signature',
    };
    if (payload.length != fields.length ||
        !payload.keys.toSet().containsAll(fields) ||
        payload['message_id'] is! String ||
        payload['sender_node_id'] != originNodeId ||
        payload['destination_node_id'] != localNodeId ||
        payload['delivered_at'] is! int ||
        payload['signature'] is! String) {
      _emit(InLinkApplicationEvent(
        state: InLinkDeliveryState.rejected,
        messageId: routeMessageId,
        peerNodeId: originNodeId,
        detail: 'Delivery receipt metadata is invalid.',
      ));
      return;
    }

    final originalMessageId = payload['message_id'] as String;
    final original = await messageStore.findOutgoing(originalMessageId);
    if (original == null ||
        original.status == LocalDeliveryStatus.delivered ||
        original.status == LocalDeliveryStatus.expired ||
        !original.expiresAtUtc.isAfter(_clock().toUtc())) {
      _emit(InLinkApplicationEvent(
        state: InLinkDeliveryState.rejected,
        messageId: originalMessageId,
        peerNodeId: originNodeId,
        detail: 'Receipt does not match an unexpired pending outgoing message.',
      ));
      return;
    }

    final contacts = await vault.listVerifiedContacts();
    VerifiedInLinkContact? recipient;
    for (final contact in contacts) {
      final nodeId = await meshNodeIdForKeys(
        signingPublicKey: contact.signingPublicKey,
        encryptionPublicKey: contact.encryptionPublicKey,
      );
      if (nodeId == originNodeId) {
        recipient = contact;
        break;
      }
    }
    if (recipient == null ||
        recipient.fingerprint.toLowerCase() != original.contactFingerprint.toLowerCase()) {
      _emit(InLinkApplicationEvent(
        state: InLinkDeliveryState.rejected,
        messageId: originalMessageId,
        peerNodeId: originNodeId,
        detail: 'Receipt signer does not match the original message recipient.',
      ));
      return;
    }

    final List<int> signatureBytes;
    try {
      signatureBytes = _decodeSignature(payload['signature'] as String);
    } on FormatException {
      _emit(InLinkApplicationEvent(
        state: InLinkDeliveryState.rejected,
        messageId: originalMessageId,
        peerNodeId: originNodeId,
        detail: 'Delivery receipt signature encoding is invalid.',
      ));
      return;
    }
    final signedFields = <String, Object>{
      'version': meshApplicationPayloadVersion,
      'kind': 'delivery_receipt',
      'message_id': originalMessageId,
      'sender_node_id': originNodeId,
      'destination_node_id': localNodeId,
      'delivered_at': payload['delivered_at'] as int,
    };
    final valid = await Ed25519().verify(
      _receiptSignedBytes(signedFields),
      signature: Signature(
        signatureBytes,
        publicKey: SimplePublicKey(
          recipient.signingPublicKey,
          type: KeyPairType.ed25519,
        ),
      ),
    );
    if (!valid) {
      _emit(InLinkApplicationEvent(
        state: InLinkDeliveryState.rejected,
        messageId: originalMessageId,
        peerNodeId: originNodeId,
        detail: 'Delivery receipt signature is invalid.',
      ));
      return;
    }

    await messageStore.markDelivered(
      messageId: originalMessageId,
      contactFingerprint: original.contactFingerprint,
    );
    await adapter.durableRouter?.completeAfterAuthenticatedReceipt(
      '$localNodeId:$originalMessageId',
    );
    _emit(InLinkApplicationEvent(
      state: InLinkDeliveryState.delivered,
      messageId: originalMessageId,
      peerNodeId: originNodeId,
      detail: 'Authenticated recipient receipt verified.',
    ));
  }

  String _newId() {
    final bytes = List<int>.generate(18, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static List<int> _receiptSignedBytes(Map<String, Object> fields) =>
      <int>[..._receiptDomain, ...utf8.encode(jsonEncode(fields))];

  static List<int> _decodeSignature(String value) {
    try {
      final bytes = base64Url.decode(base64Url.normalize(value));
      if (bytes.length != 64) throw const FormatException();
      return bytes;
    } on FormatException {
      throw const FormatException('Delivery receipt signature encoding is invalid.');
    }
  }

  void _emit(InLinkApplicationEvent event) {
    if (!_disposed && !_events.isClosed) _events.add(event);
  }

  void _ensureStarted() {
    if (_disposed) throw StateError('Mesh application service is disposed.');
    if (!_started) throw StateError('Call start() before using mesh messaging.');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _ingressSubscription?.cancel();
    await ingress.dispose();
    await _events.close();
  }
}
