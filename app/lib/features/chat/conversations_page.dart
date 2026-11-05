// ignore_for_file: curly_braces_in_flow_control_structures, prefer_initializing_formals, unawaited_futures

import 'dart:math';
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cryptography/cryptography.dart';

import '../../core/messaging/local_message_repository.dart';
import '../../core/messaging/delivery_policy.dart';
import '../../core/messaging/delivery_orchestrator.dart';
import '../../core/messaging/delivery_receipt_queue.dart';
import '../../core/messaging/delivery_receipt_validation.dart';
import '../../core/network/ble/message_frame_transfer.dart';
import '../../core/network/ble/serialized_frame_sender.dart';
import '../../core/network/native_network_transport.dart';
import '../../core/network/relay/relay_client.dart';
import '../../core/network/network_transport.dart';
import '../../core/security/secure_message.dart';
import '../../core/security/contact_identity.dart';
import '../../core/security/identity_vault.dart';
import '../../core/security/replay_protection_store.dart';
import '../../core/security/verified_message_service.dart';
import '../../core/network/mesh/mesh_application_service.dart';

class ConversationsPage extends StatefulWidget {
  const ConversationsPage({super.key, IdentityVault? vault,
    LocalMessageRepository? repository, VerifiedMessageService? messageService,
    NetworkTransport? transport, MeshApplicationService? meshService})
      : vault = vault,
        repository = repository,
        messageService = messageService,
        transport = transport,
        meshService = meshService;

  final IdentityVault? vault;
  final LocalMessageRepository? repository;
  final VerifiedMessageService? messageService;
  final NetworkTransport? transport;
  /// Optional, caller-configured mesh service. When supplied, this page owns its lifecycle.
  final MeshApplicationService? meshService;

  @override
  State<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends State<ConversationsPage> with WidgetsBindingObserver {
  late final IdentityVault _vault = widget.vault ?? IdentityVault();
  late final LocalMessageRepository _repository =
      widget.repository ?? LocalMessageRepository();
  late final DeliveryReceiptQueue _receiptQueue = DeliveryReceiptQueue();
  late final VerifiedMessageService _service = widget.messageService ??
      VerifiedMessageService(
        vault: _vault,
        replayStore: ReplayProtectionStore(),
      );

  List<VerifiedInLinkContact> _contacts = <VerifiedInLinkContact>[];
  List<LocalChatMessage> _messages = <LocalChatMessage>[];
  VerifiedInLinkContact? _selected;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final NetworkTransport _transport = widget.transport ?? NativeNetworkTransport();
  final TextEditingController _relayUrlController = TextEditingController(text: 'https://relay.example.invalid');
  NativeNetworkTransport? get _nativeTransport =>
      _transport is NativeNetworkTransport ? _transport : null;
  StreamSubscription<Map<String, Object?>>? _eventSubscription;
  final MessageFrameReassembler _reassembler = MessageFrameReassembler();
  final SerializedFrameSender _frameSender = SerializedFrameSender();
  final DeliveryPolicy _deliveryPolicy = const DeliveryPolicy();
  final DeliveryRoutePlanner _routePlanner = const DeliveryRoutePlanner();
  Future<void> _inboundTail = Future<void>.value();
  Timer? _retryTimer;
  Timer? _relayPollTimer;
  bool _drainingQueue = false;
  bool _drainingReceipts = false;
  bool _bleActive = false;
  bool _bleReady = false;
  bool _meshStarting = false;
  bool _meshReady = false;
  String _meshStatus = 'Mesh transport is not configured';
  StreamSubscription<InLinkApplicationEvent>? _meshEventSubscription;
  String? _transportNote;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _frameSender.close();
    _refresh();
    _retryTimer = Timer.periodic(const Duration(seconds: 5), (_) => _drainRetryQueue());
    _relayPollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _pollRelayIfConfigured(),
    );
    final native = _nativeTransport;
    if (native != null) {
      _eventSubscription = native.events.listen(
        _onTransportEvent,
        onError: (Object error) {
          if (mounted) setState(() => _transportNote = 'BLE event stream error: $error');
        },
      );
    }
    if (widget.meshService != null) unawaited(_startMeshService());
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _recoverOnResume();
    }
  }

  Future<void> _recoverOnResume() async {
    if (!mounted) return;
    await _refresh();
    if (_relayConfigured) {
      await _pollRelayIfConfigured();
    }
    if (mounted) {
      await _drainRetryQueue();
    }
  }

  Future<void> _pollRelayIfConfigured() async {
    if (!mounted || !_relayConfigured || _busy) return;
    await _pollRelay();
  }


  Future<void> _startMeshService() async {
    final mesh = widget.meshService;
    if (mesh == null || _meshStarting || _meshReady) return;
    if (mounted) {
      setState(() {
        _meshStarting = true;
        _meshStatus = 'Restoring encrypted mesh outbox…';
      });
    }
    _meshEventSubscription ??= mesh.events.listen(
      _onMeshEvent,
      onError: (Object _) {
        if (!mounted) return;
        setState(() => _meshStatus = 'Mesh event stream error');
      },
    );
    try {
      final restored = await mesh.start();
      if (!mounted) return;
      setState(() {
        _meshReady = true;
        _meshStatus = 'Mesh ready · restored $restored pending routes';
      });
      await _refresh();
    } catch (_) {
      if (mounted) setState(() => _meshStatus = 'Mesh startup failed · tap Retry');
    } finally {
      if (mounted) setState(() => _meshStarting = false);
    }
  }

  void _onMeshEvent(InLinkApplicationEvent event) {
    if (!mounted) return;
    final label = switch (event.state) {
      InLinkDeliveryState.queued => 'Mesh message queued',
      InLinkDeliveryState.inboundMessage => 'Authenticated mesh message received',
      InLinkDeliveryState.delivered => 'Recipient receipt verified · delivered',
      InLinkDeliveryState.relaying => 'Encrypted packet forwarding',
      InLinkDeliveryState.duplicate => 'Duplicate packet ignored',
      InLinkDeliveryState.rejected => 'Mesh packet rejected',
      InLinkDeliveryState.recoveryComplete =>
        event.detail.isEmpty ? 'Mesh recovery complete' : event.detail,
    };
    setState(() => _meshStatus = label);
    if (event.state == InLinkDeliveryState.inboundMessage ||
        event.state == InLinkDeliveryState.delivered ||
        event.state == InLinkDeliveryState.queued ||
        event.state == InLinkDeliveryState.recoveryComplete) {
      unawaited(_refresh());
    }
  }

  Future<void> _retryMesh() async {
    final mesh = widget.meshService;
    if (mesh == null || _meshStarting) return;
    if (!_meshReady) {
      await _startMeshService();
      return;
    }
    setState(() {
      _meshStarting = true;
      _meshStatus = 'Retrying pending mesh messages…';
    });
    try {
      final result = await mesh.retryPending();
      if (mounted) {
        setState(() => _meshStatus =
            'Mesh retry · ${result.accepted} accepted, ${result.failed} failed');
      }
      await _refresh();
    } catch (_) {
      if (mounted) setState(() => _meshStatus = 'Mesh retry failed');
    } finally {
      if (mounted) setState(() => _meshStarting = false);
    }
  }

  Future<void> _sendOverMesh() async {
    final contact = _selected;
    final mesh = widget.meshService;
    final text = _composer.text.trim();
    if (contact == null || mesh == null || text.isEmpty || _busy) return;
    if (!_meshReady) {
      setState(() => _error = 'Mesh is not ready. Retry mesh startup before sending.');
      return;
    }
    if (text.length > 4000) {
      setState(() => _error = 'Messages are limited to 4,000 characters in this prototype.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await mesh.sendText(contact: contact, text: text);
      _composer.clear();
      await _refresh();
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Mesh send could not start. If the message was already saved, it remains in the durable outbox.');
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onTransportEvent(Map<String, Object?> event) async {
    // Serialize all inbound work so replay-check + accept + repository writes
    // cannot overlap when native events arrive in a burst.
    _inboundTail = _inboundTail.then((_) => _processTransportEvent(event));
    await _inboundTail;
  }

  Future<void> _processTransportEvent(Map<String, Object?> event) async {
    final type = event['type']?.toString();
    if (type == 'started') {
      _reassembler.clear();
      if (mounted) setState(() { _bleActive = true; _transportNote = 'BLE active; waiting for a peer.'; });
    } else if (type == 'stopped') {
      _frameSender.close();
      _reassembler.clear();
      if (mounted) setState(() { _bleActive = false; _transportNote = 'BLE stopped; partial transfers discarded.'; });
    } else if (type == 'peerConnected') {
      if (mounted) setState(() => _transportNote = 'BLE peer connected; waiting for GATT readiness.');
    } else if (type == 'readyToSend') {
      _bleReady = true;
      _frameSender.reopen();
      if (mounted) setState(() => _transportNote = 'BLE GATT ready. Frame batches will be serialized.');
      _drainRetryQueue();
    } else if (type == 'peerDisconnected') {
      _bleReady = false;
      _frameSender.close();
      _reassembler.clear();
      if (mounted) setState(() => _transportNote = 'BLE peer disconnected; queued frame batches paused and partial transfers discarded.');
    } else if (type == 'recovery') {
      // Native Android has torn down an unusable GATT session. Never leave
      // the route planner believing BLE is ready while the native layer scans.
      _bleReady = false;
      _frameSender.close();
      _reassembler.clear();
      final reason = event['reason']?.toString() ?? 'connection setup failed';
      if (mounted) {
        setState(() => _transportNote =
            'BLE recovering ($reason); queued messages remain eligible for retry.');
      }
    } else if (type == 'error') {
      final operation = event['operation']?.toString() ?? 'BLE';
      final message = event['message']?.toString();
      final code = event['code']?.toString();
      final isConnectionSetupFailure = <String>{
        'connect',
        'discoverServices',
        'subscribeNotifications',
        'recoveryScan',
      }.contains(operation);
      if (isConnectionSetupFailure) {
        _bleReady = false;
        _frameSender.close();
        _reassembler.clear();
      }
      if (mounted) {
        setState(() => _transportNote =
            'BLE $operation error: ${message ?? code ?? event['status'] ?? 'unknown error'}');
      }
    } else if (type == 'permissionDenied') {
      _bleReady = false;
      _bleActive = false;
      _frameSender.close();
      _reassembler.clear();
      if (mounted) {
        setState(() => _transportNote =
            'Bluetooth permission denied; grant permission and start BLE again.');
      }
    } else if (type == 'frameReceived') {
      final raw = event['frame'];
      if (raw is! List) return;
      try {
        final complete = _reassembler.accept(raw.cast<int>());
        if (complete == null) return;
        final encoded = utf8.decode(complete, allowMalformed: false);
        await _acceptEncodedEnvelope(encoded, source: 'BLE');
      } catch (error) {
        if (mounted) setState(() => _transportNote = 'Rejected BLE message: $error');
      }
    }
  }

  Future<bool> _acceptEncodedEnvelope(String encoded, {required String source}) async {
    try {
      final envelope = EncryptedMessageEnvelope.decode(encoded);
      final contacts = await _vault.listVerifiedContacts();
      VerifiedInLinkContact? sender;
      for (final candidate in contacts) {
        if (_sameBytes(candidate.signingPublicKey, envelope.senderSigningPublicKey)) {
          sender = candidate;
          break;
        }
      }
      if (sender == null) {
        if (mounted) setState(() => _transportNote = 'Received envelope from an unverified sender; rejected.');
        return false;
      }
      final plaintext = await _service.openFromVerifiedContact(
        contact: sender,
        encodedEnvelope: encoded,
      );
      final decoded = _decodeApplicationPayload(plaintext);
      if (decoded['type'] == 'receipt') {
        await _acceptDeliveryReceipt(sender, decoded);
        if (mounted) setState(() => _transportNote = 'Authenticated delivery receipt processed.');
        return true;
      }
      if (decoded['type'] == 'receiptAck') {
        await _acceptReceiptAcknowledgement(sender, decoded);
        if (mounted) setState(() => _transportNote = 'Receipt acknowledgement processed.');
        return true;
      }
      final messageId = decoded['type'] == 'message' && decoded['messageId'] is String
          ? decoded['messageId'] as String
          : await _serviceReplayId(encoded);
      final visibleText = decoded['type'] == 'message' && decoded['text'] is String
          ? decoded['text'] as String
          : plaintext;
      await _repository.add(LocalChatMessage(
        id: messageId,
        contactFingerprint: sender.fingerprint,
        direction: LocalMessageDirection.incoming,
        text: visibleText,
        createdAtUtc: DateTime.now().toUtc(),
        status: LocalDeliveryStatus.delivered,
        encodedEnvelope: encoded,
      ));
      if (decoded['type'] == 'message' && decoded['messageId'] is String) {
        await _sendDeliveryReceipt(
          contact: sender,
          messageId: messageId,
          envelopeDigest: await _digest(encoded),
        );
      }
      await _refresh();
      if (mounted) setState(() => _transportNote = 'Authenticated encrypted message received via $source.');
      return true;
    } catch (error) {
      if (mounted) setState(() => _transportNote = 'Rejected $source message: $error');
      return false;
    }
  }

  bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) { diff |= a[i] ^ b[i]; }
    return diff == 0;
  }

  RelayClient _newRelayClient() {
    final client = RelayClient(_relayUrlController.text);
    return client;
  }

  Future<void> _sendQueuedViaRelay() async {
    final contact = _selected;
    if (contact == null || _busy) return;
    RelayClient? client;
    setState(() { _busy = true; _error = null; });
    try {
      client = _newRelayClient();
      final identity = await _vault.loadOrCreateIdentity();
      final messages = await _repository.listForContact(contact.fingerprint);
      var submitted = 0;
      var duplicates = 0;
      for (final message in messages) {
        if (message.direction != LocalMessageDirection.outgoing ||
            message.encodedEnvelope == null ||
            message.status == LocalDeliveryStatus.delivered ||
            message.status == LocalDeliveryStatus.expired ||
            !message.expiresAtUtc.isAfter(DateTime.now().toUtc())) continue;
        final result = await client.submitMessage(
          identity: identity,
          recipient: contact,
          messageId: message.id,
          encodedEnvelope: message.encodedEnvelope!,
          expiresAtUtc: message.expiresAtUtc,
        );
        if (result['status'] == 'accepted') submitted++;
        if (result['status'] == 'duplicate') duplicates++;
      }
      if (mounted) setState(() => _transportNote =
          'Relay accepted $submitted message(s); $duplicates were already queued. This is not recipient delivery.');
    } catch (error) {
      if (mounted) setState(() => _transportNote = 'Relay submission failed; messages remain locally queued: $error');
    } finally {
      client?.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pollRelay() async {
    if (_busy) return;
    RelayClient? client;
    setState(() { _busy = true; _error = null; });
    try {
      client = _newRelayClient();
      final identity = await _vault.loadOrCreateIdentity();
      final messages = await client.pollMessages(identity: identity);
      var accepted = 0;
      var rejected = 0;
      for (final message in messages) {
        try {
          final envelope = EncryptedMessageEnvelope.decode(message.encodedEnvelope);
          if (await RelayClient.identityId(envelope.senderSigningPublicKey) != message.senderId) {
            rejected++;
            continue;
          }
          // Serialize with BLE inbound events to prevent replay-store races.
          var didAccept = false;
          _inboundTail = _inboundTail.then((_) async {
            didAccept = await _acceptEncodedEnvelope(message.encodedEnvelope, source: 'internet relay');
          });
          await _inboundTail;
          if (didAccept) {
            await client.acknowledgeMessage(identity: identity, message: message);
            accepted++;
          } else {
            rejected++;
          }
        } catch (_) {
          rejected++;
        }
      }
      if (mounted) setState(() => _transportNote =
          'Relay poll: $accepted envelope(s) authenticated and acknowledged; $rejected left queued or rejected.');
    } catch (error) {
      if (mounted) setState(() => _transportNote = 'Relay polling failed: $error');
    } finally {
      client?.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startBle() async {
    final native = _nativeTransport;
    if (native == null) {
      setState(() => _transportNote = 'Configured transport does not expose native BLE.');
      return;
    }
    try {
      _bleReady = false;
      _frameSender.close();
      _reassembler.clear();
      await native.startBle();
      if (mounted) setState(() { _bleActive = true; _transportNote = 'BLE start requested; waiting for GATT readiness.'; });
    } catch (error) {
      if (mounted) setState(() => _transportNote = 'Could not start BLE: $error');
    }
  }

  Future<void> _stopBle() async {
    final native = _nativeTransport;
    if (native == null) return;
    try {
      _bleReady = false;
      _frameSender.close();
      _reassembler.clear();
      await native.stopBle();
      if (mounted) setState(() { _bleActive = false; _transportNote = 'BLE stopped; partial transfers discarded.'; });
    } catch (error) {
      if (mounted) setState(() => _transportNote = 'Could not stop BLE: $error');
    }
  }

  Future<void> _sendOverBle(LocalChatMessage message) async {
    final native = _nativeTransport;
    if (native == null) {
      if (mounted) setState(() => _error = 'Native BLE transport is not configured.');
      return;
    }
    if (message.direction != LocalMessageDirection.outgoing ||
        message.status == LocalDeliveryStatus.delivered ||
        message.status == LocalDeliveryStatus.expired) return;
    final now = DateTime.now().toUtc();
    if (_deliveryPolicy.isExpired(message.expiresAtUtc, now)) {
      await _repository.update(message.copyWith(status: LocalDeliveryStatus.expired, error: 'Message expired before delivery.'));
      await _refresh();
      return;
    }
    if (message.retryCount >= _deliveryPolicy.maxAttempts) {
      await _repository.update(message.copyWith(status: LocalDeliveryStatus.failed, error: 'Retry limit reached.'));
      await _refresh();
      return;
    }
    setState(() { _busy = true; _error = null; });
    final attempt = message.retryCount + 1;
    try {
      // Re-enveloping preserves the stable application message ID while giving
      // a retransmission a fresh envelope ID, allowing a recipient to re-issue
      // a receipt if an earlier receipt was lost.
      final wrapped = jsonEncode(<String, Object>{
        'version': 1,
        'type': 'message',
        'messageId': message.id,
        'text': message.text,
      });
      final contact = _contacts.where((c) => c.fingerprint == message.contactFingerprint).firstOrNull;
      if (contact == null) throw StateError('The verified contact for this queued message is unavailable.');
      final envelope = await _service.sealToVerifiedContact(contact: contact, plaintext: wrapped);
      final encodedEnvelope = envelope.encode();
      final envelopeDigest = await _digest(encodedEnvelope);
      final sentDigests = <String>{
        ...message.sentEnvelopeDigests,
        if (message.encodedEnvelope != null) await _digest(message.encodedEnvelope!),
        envelopeDigest,
      }.toList();
      await _repository.update(message.copyWith(
        encodedEnvelope: encodedEnvelope,
        sentEnvelopeDigests: sentDigests,
        retryCount: attempt,
        lastAttemptAtUtc: now,
        nextAttemptAtUtc: now.add(jitteredBackoff(policy: _deliveryPolicy, attempt: attempt)),
        clearError: true,
      ));
      final bytes = utf8.encode(encodedEnvelope);
      final random = Random.secure();
      final transferId = random.nextInt(0x100000000);
      final frames = MessageFrameTransfer.fragment(messageBytes: bytes, transferId: transferId);
      await _frameSender.sendBatch(
        frames,
        (frame) async { await native.sendBleFrame(frame); },
      );
      final latest = (await _repository.listAll()).where((item) => item.id == message.id).firstOrNull;
      if (latest != null) {
        await _repository.update(latest.copyWith(
          status: attempt >= _deliveryPolicy.maxAttempts
              ? LocalDeliveryStatus.failed
              : LocalDeliveryStatus.inTransit,
          error: attempt >= _deliveryPolicy.maxAttempts
              ? 'Retry limit reached; a late authenticated receipt can still confirm delivery.'
              : null,
        ));
      }
      await _refresh();
      if (mounted) setState(() => _transportNote =
        'Attempt $attempt: Android accepted ${frames.length} BLE frame(s). Waiting for a verified recipient receipt.');
    } catch (error) {
      final latest = (await _repository.listAll()).where((item) => item.id == message.id).firstOrNull;
      if (latest != null) {
        final exhausted = attempt >= _deliveryPolicy.maxAttempts;
        await _repository.update(latest.copyWith(
          status: exhausted ? LocalDeliveryStatus.failed : LocalDeliveryStatus.queued,
          error: error.toString(),
          retryCount: attempt,
          lastAttemptAtUtc: now,
          nextAttemptAtUtc: now.add(jitteredBackoff(policy: _deliveryPolicy, attempt: attempt)),
        ));
      }
      await _refresh();
      if (mounted) setState(() => _error = 'BLE attempt failed; retry is scheduled if the message has not expired: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> _decodeApplicationPayload(String plaintext) {
    try {
      final value = jsonDecode(plaintext);
      if (value is Map<String, dynamic> && value['version'] == 1 &&
          (value['type'] == 'message' || value['type'] == 'receipt' || value['type'] == 'receiptAck')) return value;
    } catch (_) {
      // Legacy prototype messages were encrypted as raw UTF-8 text.
    }
    return <String, dynamic>{'type': 'legacy', 'text': plaintext};
  }

  Future<String> _digest(String encodedEnvelope) async {
    final hash = await Sha256().hash(utf8.encode(encodedEnvelope));
    return base64UrlEncode(hash.bytes);
  }

  Future<void> _sendDeliveryReceipt({
    required VerifiedInLinkContact contact,
    required String messageId,
    required String envelopeDigest,
  }) async {
    final identity = await _vault.loadOrCreateIdentity();
    final receivedAt = DateTime.now().toUtc();
    final receiptId = '$messageId:$envelopeDigest';
    await _receiptQueue.enqueue(PendingDeliveryReceipt(
      id: receiptId,
      contactFingerprint: contact.fingerprint,
      messageId: messageId,
      envelopeDigest: envelopeDigest,
      recipientFingerprint: await identity.fingerprint(),
      receivedAtUtc: receivedAt,
      createdAtUtc: receivedAt,
      nextAttemptAtUtc: receivedAt,
    ));
    if (mounted) {
      setState(() => _transportNote =
          'Delivery receipt saved locally; it will be sent when BLE is available.');
    }
  }


  Future<void> _drainReceiptQueue() async {
    if (!mounted || _drainingReceipts ||
        (!_bleReady && !_relayConfigured)) return;
    _drainingReceipts = true;
    try {
      final now = DateTime.now().toUtc();
      final due = await _receiptQueue.listDue(now);
      for (final receipt in due) {
        if (!mounted || (!_bleReady && !_relayConfigured)) break;
        final contact = _contacts.where(
          (item) => item.fingerprint == receipt.contactFingerprint,
        ).firstOrNull;
        if (contact == null) continue;
        final attempt = receipt.retryCount + 1;
        try {
          final payload = jsonEncode(<String, Object>{
            'version': 1,
            'type': receipt.type,
            'messageId': receipt.messageId,
            'envelopeDigest': receipt.envelopeDigest,
            'recipientFingerprint': receipt.recipientFingerprint,
            'receivedAtUtc': receipt.receivedAtUtc.toUtc().toIso8601String(),
            'acknowledgedAtUtc': receipt.receivedAtUtc.toUtc().toIso8601String(),
          });
          // Each retry gets a fresh encrypted envelope. Its digest becomes the
          // relay queue ID, so a retry after an uncertain HTTP response is
          // idempotent for that exact envelope.
          final envelope = await _service.sealToVerifiedContact(
            contact: contact,
            plaintext: payload,
          );
          final encodedEnvelope = envelope.encode();
          var sent = false;
          String? routeUsed;

          if (_bleReady && _nativeTransport != null) {
            try {
              final frames = MessageFrameTransfer.fragment(
                messageBytes: utf8.encode(encodedEnvelope),
                transferId: Random.secure().nextInt(0x100000000),
              );
              await _frameSender.sendBatch(
                frames,
                (frame) async { await _nativeTransport!.sendBleFrame(frame); },
              );
              sent = true;
              routeUsed = 'BLE';
            } catch (_) {
              // If the direct link fails during this batch, attempt the relay
              // with the same envelope instead of losing the queued receipt.
            }
          }

          if (!sent && _relayConfigured) {
            RelayClient? client;
            try {
              client = _newRelayClient();
              final identity = await _vault.loadOrCreateIdentity();
              final relayMessageId =
                  await RelayClient.messageIdForEnvelope(encodedEnvelope);
              final result = await client.submitMessage(
                identity: identity,
                recipient: contact,
                messageId: relayMessageId,
                encodedEnvelope: encodedEnvelope,
                expiresAtUtc: receipt.createdAtUtc.add(_receiptQueue.maxAge),
              );
              if (result['status'] != 'accepted' &&
                  result['status'] != 'duplicate') {
                throw StateError('Relay returned an unexpected receipt status.');
              }
              sent = true;
              routeUsed = 'internet relay';
            } finally {
              client?.close();
            }
          }

          if (!sent) {
            throw StateError('No viable route for receipt delivery.');
          }

          // Receipt records remain until the other endpoint's authenticated
          // receiptAck arrives. A receiptAck is removed after transport
          // acceptance; if it is lost, a repeated receipt causes it to be
          // recreated.
          if (receipt.type == 'receiptAck') {
            await _receiptQueue.remove(receipt.id);
          } else {
            await _receiptQueue.update(receipt.copyWith(
              retryCount: attempt,
              nextAttemptAtUtc: now.add(jitteredBackoff(
                policy: _deliveryPolicy,
                attempt: attempt,
              )),
            ));
          }
          if (mounted) setState(() => _transportNote =
              'Receipt accepted by $routeUsed; awaiting authenticated acknowledgement.');
        } catch (error) {
          await _receiptQueue.update(receipt.copyWith(
            retryCount: attempt,
            nextAttemptAtUtc: now.add(jitteredBackoff(
              policy: _deliveryPolicy,
              attempt: attempt,
            )),
          ));
          if (mounted) setState(() =>
              _transportNote = 'Receipt remains queued for retry: $error');
        }
      }
    } catch (error) {
      if (mounted) setState(() => _transportNote = 'Receipt queue recovery issue: $error');
    } finally {
      _drainingReceipts = false;
    }
  }

  Future<void> _acceptDeliveryReceipt(
    VerifiedInLinkContact sender,
    Map<String, dynamic> receipt,
  ) async {
    final id = receipt['messageId'];
    final digest = receipt['envelopeDigest'];
    final targetFingerprint = receipt['recipientFingerprint'];
    final receivedAt = receipt['receivedAtUtc'];
    if (id is! String || !isValidReceiptMessageId(id) ||
        digest is! String || !isValidEnvelopeDigest(digest) ||
        targetFingerprint is! String || targetFingerprint.isEmpty ||
        receivedAt is! String || DateTime.tryParse(receivedAt) == null) {
      throw const FormatException('Malformed delivery receipt.');
    }
    final own = await _vault.loadOrCreateIdentity();
    if (targetFingerprint != await own.fingerprint()) {
      throw const FormatException('Delivery receipt targets a different identity.');
    }
    final all = await _repository.listAll();
    // Message IDs are scoped to a conversation in storage. Bind lookup to the
    // authenticated sender before checking envelope digest or changing status.
    final message = all.where((item) =>
      item.id == id &&
      item.direction == LocalMessageDirection.outgoing &&
      item.contactFingerprint == sender.fingerprint
    ).firstOrNull;
    final digestMatches = message != null && (
      message.sentEnvelopeDigests.contains(digest) ||
      (message.encodedEnvelope != null && await _digest(message.encodedEnvelope!) == digest)
    );
    if (message == null || message.direction != LocalMessageDirection.outgoing ||
        message.contactFingerprint != sender.fingerprint || !digestMatches) {
      throw const FormatException('Receipt does not match a sent envelope for this message.');
    }
    await _repository.update(message.copyWith(status: LocalDeliveryStatus.delivered, clearError: true));
    await _enqueueReceiptAcknowledgement(
      contact: sender,
      messageId: id,
      envelopeDigest: digest,
    );
    await _refresh();
  }

  Future<void> _enqueueReceiptAcknowledgement({
    required VerifiedInLinkContact contact,
    required String messageId,
    required String envelopeDigest,
  }) async {
    final now = DateTime.now().toUtc();
    await _receiptQueue.enqueue(PendingDeliveryReceipt(
      id: 'ack:$messageId:$envelopeDigest',
      type: 'receiptAck',
      contactFingerprint: contact.fingerprint,
      messageId: messageId,
      envelopeDigest: envelopeDigest,
      recipientFingerprint: contact.fingerprint,
      receivedAtUtc: now,
      createdAtUtc: now,
      nextAttemptAtUtc: now,
    ));
  }

  Future<void> _acceptReceiptAcknowledgement(
    VerifiedInLinkContact sender,
    Map<String, dynamic> acknowledgement,
  ) async {
    final id = acknowledgement['messageId'];
    final digest = acknowledgement['envelopeDigest'];
    final targetFingerprint = acknowledgement['recipientFingerprint'];
    final acknowledgedAt = acknowledgement['acknowledgedAtUtc'];
    if (id is! String || !isValidReceiptMessageId(id) ||
        digest is! String || !isValidEnvelopeDigest(digest) ||
        targetFingerprint is! String || targetFingerprint.isEmpty ||
        acknowledgedAt is! String || DateTime.tryParse(acknowledgedAt) == null) {
      throw const FormatException('Malformed receipt acknowledgement.');
    }
    final own = await _vault.loadOrCreateIdentity();
    if (targetFingerprint != await own.fingerprint()) {
      throw const FormatException('Receipt acknowledgement targets a different identity.');
    }
    final queued = await _receiptQueue.listAll();
    final match = queued.where((item) =>
      item.type == 'receipt' &&
      item.messageId == id &&
      item.envelopeDigest == digest &&
      item.contactFingerprint == sender.fingerprint
    ).firstOrNull;
    if (match == null) {
      // A duplicate acknowledgement is harmless; it may arrive after cleanup.
      return;
    }
    await _receiptQueue.remove(match.id);
  }


  bool get _relayConfigured {
    final value = _relayUrlController.text.trim();
    if (value.isEmpty) return false;
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty || uri.host.toLowerCase().endsWith('.invalid')) {
      return false;
    }
    final host = uri.host.toLowerCase();
    final loopback = host == 'localhost' || host == '127.0.0.1' ||
        host == '::1' || host == '[::1]';
    return uri.scheme == 'https' || (uri.scheme == 'http' && loopback);
  }

  Future<void> _sendOverRelay(
    LocalChatMessage message,
    VerifiedInLinkContact contact,
  ) async {
    if (_busy || message.direction != LocalMessageDirection.outgoing ||
        message.encodedEnvelope == null ||
        message.status == LocalDeliveryStatus.delivered ||
        message.status == LocalDeliveryStatus.expired) return;

    final now = DateTime.now().toUtc();
    if (_deliveryPolicy.isExpired(message.expiresAtUtc, now)) {
      await _repository.update(message.copyWith(
        status: LocalDeliveryStatus.expired,
        error: 'Message expired before relay submission.',
      ));
      await _refresh();
      return;
    }
    if (message.retryCount >= _deliveryPolicy.maxAttempts) {
      await _repository.update(message.copyWith(
        status: LocalDeliveryStatus.failed,
        error: 'Retry limit reached; a late authenticated receipt can still confirm delivery.',
      ));
      return;
    }

    final attempt = message.retryCount + 1;
    final nextAttempt = now.add(jitteredBackoff(
      policy: _deliveryPolicy,
      attempt: attempt,
    ));
    setState(() { _busy = true; _error = null; });
    RelayClient? client;
    try {
      // Persist attempt metadata before I/O. If the process exits after server
      // acceptance but before the response, the same stable ID can be retried.
      await _repository.update(message.copyWith(
        retryCount: attempt,
        lastAttemptAtUtc: now,
        nextAttemptAtUtc: nextAttempt,
        clearError: true,
      ));
      final identity = await _vault.loadOrCreateIdentity();
      client = _newRelayClient();
      final result = await client.submitMessage(
        identity: identity,
        recipient: contact,
        messageId: message.id,
        encodedEnvelope: message.encodedEnvelope!,
        expiresAtUtc: message.expiresAtUtc,
      );
      final status = result['status'];
      if (status != 'accepted' && status != 'duplicate') {
        throw StateError('Relay returned an unexpected submission status.');
      }
      final latest = (await _repository.listAll())
          .where((item) => item.id == message.id).firstOrNull;
      if (latest != null) {
        await _repository.update(latest.copyWith(
          status: attempt >= _deliveryPolicy.maxAttempts
              ? LocalDeliveryStatus.failed
              : LocalDeliveryStatus.inTransit,
          error: attempt >= _deliveryPolicy.maxAttempts
              ? 'Retry limit reached; awaiting a possible authenticated recipient receipt.'
              : null,
          clearError: attempt < _deliveryPolicy.maxAttempts,
        ));
      }
      if (mounted) setState(() => _transportNote =
          'Internet relay ${status == 'duplicate' ? 'already has' : 'accepted'} this envelope. Awaiting an authenticated recipient receipt.');
    } catch (error) {
      final latest = (await _repository.listAll())
          .where((item) => item.id == message.id).firstOrNull;
      if (latest != null) {
        await _repository.update(latest.copyWith(
          status: attempt >= _deliveryPolicy.maxAttempts
              ? LocalDeliveryStatus.failed
              : LocalDeliveryStatus.queued,
          error: 'Relay attempt failed: $error',
          retryCount: attempt,
          lastAttemptAtUtc: now,
          nextAttemptAtUtc: nextAttempt,
        ));
      }
      if (mounted) setState(() => _transportNote =
          'Internet relay unavailable; message remains queued for a bounded retry.');
    } finally {
      client?.close();
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }


  Future<void> _drainRetryQueue() async {
    if (!mounted || _drainingQueue || _busy) return;
    _drainingQueue = true;
    try {
      if (_bleReady || _relayConfigured) await _drainReceiptQueue();
      final selected = _selected;
      if (selected == null) return;

      final now = DateTime.now().toUtc();
      final all = await _repository.listAll();
      for (final message in all) {
        if (message.direction == LocalMessageDirection.outgoing &&
            message.status != LocalDeliveryStatus.delivered &&
            message.status != LocalDeliveryStatus.expired &&
            _deliveryPolicy.isExpired(message.expiresAtUtc, now)) {
          await _repository.update(message.copyWith(
            status: LocalDeliveryStatus.expired,
            error: 'Message expired before delivery.',
          ));
        }
      }

      final route = _routePlanner.choose(
        bleReady: _bleReady,
        relayConfigured: _relayConfigured,
      );
      if (route == null) return;
      final due = await _repository.listDueForRetry(now);
      for (final message in due) {
        if (!mounted || _busy) break;
        if (message.contactFingerprint != selected.fingerprint) continue;
        if (route == DeliveryRoute.ble) {
          await _sendOverBle(message);
          // A ready BLE session can still fail mid-send. If the attempt left
          // the message queued, immediately try the relay as a fallback.
          if (_relayConfigured && mounted && !_busy) {
            final latest = (await _repository.listAll())
                .where((item) => item.id == message.id).firstOrNull;
            if (latest != null &&
                latest.status == LocalDeliveryStatus.queued &&
                latest.expiresAtUtc.isAfter(DateTime.now().toUtc())) {
              await _sendOverRelay(latest, selected);
            }
          }
        } else {
          await _sendOverRelay(message, selected);
        }
      }
    } catch (error) {
      if (mounted) setState(() => _transportNote = 'Delivery queue recovery issue: $error');
    } finally {
      _drainingQueue = false;
    }
  }

  Future<void> _refresh() async {
    try {
      final contacts = await _vault.listVerifiedContacts();
      final selected = _selected;
      final messages = selected == null
          ? await _repository.listAll()
          : await _repository.listForContact(selected.fingerprint);
      if (!mounted) return;
      setState(() {
        _contacts = contacts;
        _messages = messages;
        if (selected != null &&
            contacts.any((contact) => contact.fingerprint == selected.fingerprint)) {
          _selected = contacts.firstWhere(
              (contact) => contact.fingerprint == selected.fingerprint);
        } else if (contacts.isNotEmpty) {
          _selected = contacts.first;
        } else {
          _selected = null;
        }
        _loading = false;
        _error = null;
      });
      if (_selected != null) {
        final selectedMessages =
            await _repository.listForContact(_selected!.fingerprint);
        if (mounted) setState(() => _messages = selectedMessages);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load local conversations: $error';
      });
    }
  }

  String _newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _send() async {
    final contact = _selected;
    final text = _composer.text.trim();
    if (contact == null || text.isEmpty || _busy) return;
    if (text.length > 4000) {
      setState(() => _error = 'Messages are limited to 4,000 characters in this prototype.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final messageId = _newId();
      final wrapped = jsonEncode(<String, Object>{
        'version': 1,
        'type': 'message',
        'messageId': messageId,
        'text': text,
      });
      final envelope = await _service.sealToVerifiedContact(
        contact: contact,
        plaintext: wrapped,
      );
      final now = DateTime.now().toUtc();
      final encodedEnvelope = envelope.encode();
      final message = LocalChatMessage(
        id: messageId,
        contactFingerprint: contact.fingerprint,
        direction: LocalMessageDirection.outgoing,
        text: text,
        createdAtUtc: now,
        status: LocalDeliveryStatus.queued,
        encodedEnvelope: encodedEnvelope,
        sentEnvelopeDigests: <String>[await _digest(encodedEnvelope)],
      );
      await _repository.add(message);
      _composer.clear();
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = 'Message was not queued: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importEnvelope() async {
    final contact = _selected;
    if (contact == null) return;
    final controller = TextEditingController();
    final encoded = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Receive encrypted envelope'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Envelope JSON',
              hintText: 'Paste the complete encrypted envelope',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Process envelope'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (encoded == null || encoded.isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final plaintext = await _service.openFromVerifiedContact(contact: contact, encodedEnvelope: encoded);
      final decoded = _decodeApplicationPayload(plaintext);
      if (decoded['type'] == 'receipt') {
        await _acceptDeliveryReceipt(contact, decoded);
      } else if (decoded['type'] == 'receiptAck') {
        await _acceptReceiptAcknowledgement(contact, decoded);
      } else {
        final id = decoded['type'] == 'message' && decoded['messageId'] is String
            ? decoded['messageId'] as String : await _serviceReplayId(encoded);
        final visibleText = decoded['type'] == 'message' && decoded['text'] is String
            ? decoded['text'] as String : plaintext;
        await _repository.add(LocalChatMessage(
          id: id,
          contactFingerprint: contact.fingerprint,
          direction: LocalMessageDirection.incoming,
          text: visibleText,
          createdAtUtc: DateTime.now().toUtc(),
          status: LocalDeliveryStatus.delivered,
          encodedEnvelope: encoded,
        ));
      }
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = 'Envelope rejected: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _serviceReplayId(String encoded) async {
    // Use a collision-resistant digest for the local record key. The service's
    // persistent replay store independently enforces inbound replay rejection.
    final digest = await Sha256().hash(utf8.encode(encoded));
    return 'in-${base64UrlEncode(digest.bytes)}';
  }

  Future<void> _showEnvelope(LocalChatMessage message) async {
    final envelope = message.encodedEnvelope;
    if (envelope == null) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Encrypted envelope'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText(envelope),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copy the envelope text from the dialog to transfer it manually.')),
              );
            },
            icon: const Icon(Icons.check),
            label: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _eventSubscription?.cancel();
    _meshEventSubscription?.cancel();
    if (widget.meshService != null) unawaited(widget.meshService!.dispose());
    _retryTimer?.cancel();
    _relayPollTimer?.cancel();
    _frameSender.close();
    _reassembler.clear();
    _composer.dispose();
    _relayUrlController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contact = _selected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conversations'),
        actions: [
          IconButton(
            tooltip: 'Import received envelope',
            onPressed: _busy || contact == null ? null : _importEnvelope,
            icon: const Icon(Icons.move_to_inbox_outlined),
          ),
          IconButton(
            tooltip: 'Refresh conversations',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _contacts.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No verified contacts yet. Add a contact from the identity screen before starting a conversation.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.verified_user_outlined),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButton<VerifiedInLinkContact>(
                              isExpanded: true,
                              value: contact,
                              hint: const Text('Choose verified contact'),
                              items: _contacts.map((item) =>
                                DropdownMenuItem(
                                  value: item,
                                  child: Text(item.displayName, overflow: TextOverflow.ellipsis),
                                )).toList(),
                              onChanged: _busy ? null : (value) async {
                                if (value == null) return;
                                setState(() {
                                  _selected = value;
                                  _messages = <LocalChatMessage>[];
                                });
                                final messages = await _repository.listForContact(value.fingerprint);
                                if (mounted) setState(() => _messages = messages);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    if (_nativeTransport != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        child: Row(
                          children: [
                            Icon(_bleActive ? Icons.bluetooth_connected : Icons.bluetooth_disabled),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_transportNote ?? 'BLE is not active.')),
                            TextButton(
                              onPressed: _busy ? null : (_bleActive ? _stopBle : _startBle),
                              child: Text(_bleActive ? 'Stop BLE' : 'Start BLE'),
                            ),
                          ],
                        ),
                      ),
                    Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                        child: Row(
                          children: [
                            Icon(
                              _meshReady ? Icons.hub_outlined : Icons.hub,
                              color: _meshReady ? Theme.of(context).colorScheme.primary : null,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _meshStatus,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            if (widget.meshService != null)
                              TextButton(
                                onPressed: _meshStarting ? null : _retryMesh,
                                child: Text(_meshReady ? 'Retry' : 'Start mesh'),
                              ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _relayUrlController,
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Internet relay URL (HTTPS; loopback HTTP for development)',
                              isDense: true,
                              prefixIcon: Icon(Icons.cloud_outlined),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(child: OutlinedButton.icon(
                                onPressed: _busy ? null : _sendQueuedViaRelay,
                                icon: const Icon(Icons.cloud_upload_outlined),
                                label: const Text('Send queued'),
                              )),
                              const SizedBox(width: 8),
                              Expanded(child: OutlinedButton.icon(
                                onPressed: _busy ? null : _pollRelay,
                                icon: const Icon(Icons.cloud_download_outlined),
                                label: const Text('Poll relay'),
                              )),
                            ],
                          ),
                          Text(
                            _transportNote ?? 'Relay is optional. Relay acceptance is not end-to-end delivery.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (_error != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Text(
                          _error!,
                          style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                        ),
                      ),
                    Expanded(
                      child: _messages.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'No messages yet.\nCompose a message to create an encrypted, locally queued envelope.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(12),
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final message = _messages[index];
                                final outgoing = message.direction == LocalMessageDirection.outgoing;
                                return Align(
                                  alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 340),
                                    child: Card(
                                      color: outgoing
                                          ? Theme.of(context).colorScheme.primaryContainer
                                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            SelectableText(message.text),
                                            const SizedBox(height: 8),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  '${message.createdAtUtc.toLocal().hour.toString().padLeft(2, '0')}:${message.createdAtUtc.toLocal().minute.toString().padLeft(2, '0')} · ${message.status.name}',
                                                  style: Theme.of(context).textTheme.labelSmall,
                                                ),
                                                if (outgoing && message.status != LocalDeliveryStatus.delivered && message.status != LocalDeliveryStatus.expired) ...[
                                                  IconButton(
                                                    visualDensity: VisualDensity.compact,
                                                    tooltip: 'Send or retry over BLE',
                                                    onPressed: _busy ? null : () => _sendOverBle(message),
                                                    icon: const Icon(Icons.send, size: 18),
                                                  ),
                                                ],
                                                if (outgoing && message.encodedEnvelope != null) ...[
                                                  IconButton(
                                                    visualDensity: VisualDensity.compact,
                                                    tooltip: 'View encrypted envelope',
                                                    onPressed: () => _showEnvelope(message),
                                                    icon: const Icon(Icons.data_object, size: 18),
                                                  ),
                                                  if (_nativeTransport != null &&
                                                      (message.status == LocalDeliveryStatus.queued ||
                                                       message.status == LocalDeliveryStatus.failed))
                                                    IconButton(
                                                      visualDensity: VisualDensity.compact,
                                                      tooltip: 'Send encrypted message over BLE',
                                                      onPressed: _busy ? null : () => _sendOverBle(message),
                                                      icon: const Icon(Icons.bluetooth, size: 18),
                                                    ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _composer,
                                minLines: 1,
                                maxLines: 5,
                                maxLength: 4000,
                                enabled: !_busy && contact != null,
                                decoration: const InputDecoration(
                                  hintText: 'Write a message…',
                                  border: OutlineInputBorder(),
                                  counterText: '',
                                ),
                                onSubmitted: (_) => _send(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: widget.meshService == null
                                  ? 'Mesh application service is not wired in this app build'
                                  : 'Encrypt, persist, and send via mesh',
                              onPressed: _busy || contact == null ||
                                      !_meshReady || widget.meshService == null
                                  ? null
                                  : _sendOverMesh,
                              icon: const Icon(Icons.hub_outlined),
                            ),
                            const SizedBox(width: 2),
                            IconButton.filled(
                              tooltip: 'Encrypt and queue locally (legacy BLE/relay flow)',
                              onPressed: _busy || contact == null ? null : _send,
                              icon: _busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.send),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Text(
                        'IN_TRANSIT means Android accepted the frames. DELIVERED requires a matching receipt encrypted to you by the verified contact. Messages expire after 7 days; retry is bounded. BLE and internet relay are experimental; relay acceptance is not recipient delivery.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
    );
  }
}
