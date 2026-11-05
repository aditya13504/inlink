import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../ble/ble_frame.dart';
import '../ble/message_frame_transfer.dart';
import '../native_network_transport.dart';
import '../../security/contact_identity.dart';
import 'mesh_identity_handshake.dart';
import 'native_mesh_peer_transport.dart';

/// Performs a mutually initiated challenge/proof exchange over an already
/// connected native BLE link. A BLE address is only a temporary transport
/// handle; [MeshIdentityHandshake] binds it only after a pinned-contact proof.
class NativeMeshHandshakeManager {
  NativeMeshHandshakeManager({
    required this.native,
    required this.handshake,
    required this.directory,
    required this.trustedContacts,
    Random? random,
  }) : _random = random ?? Random.secure();

  static const int _version = 1;
  static const int _maxControlBytes = 2048;

  final NativeNetworkTransport native;
  final MeshIdentityHandshake handshake;
  final VerifiedBlePeerDirectory directory;
  final Future<List<VerifiedInLinkContact>> Function() trustedContacts;
  final Random _random;

  final Map<String, String> _pendingChallenges = <String, String>{};
  final Map<String, DateTime> _challengeCreatedAt = <String, DateTime>{};
  final Set<String> _challengeStarted = <String>{};
  final Map<String, MessageFrameReassembler> _reassemblers =
      <String, MessageFrameReassembler>{};
  StreamSubscription<Map<String, Object?>>? _subscription;
  Future<void> _eventTail = Future<void>.value();
  bool _disposed = false;
  Timer? _retryTimer;

  Future<void> start() async {
    if (_disposed) throw StateError('Mesh handshake manager is disposed.');
    if (_subscription != null) return;
    _subscription = native.events.listen(
      (event) {
        _eventTail = _eventTail.then((_) => _handleEvent(event)).catchError(
          (Object _) {
            // Control-channel failures are intentionally not logged with
            // untrusted payloads, keys, challenges, or proof contents.
          },
        );
      },
      onError: (Object _) {},
    );

    _retryTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_retryExpiredChallenges()),
    );

    // BLE may have been started before the conversations route was opened.
    // Attempt currently connected peers; not-ready links will be retried on
    // their later readyToSend event.
    try {
      for (final address in await native.getConnectedPeers()) {
        await _sendChallenge(address);
      }
    } catch (_) {
      // Native BLE may not be started or permissions may have changed.
    }
  }

  Future<void> _handleEvent(Map<String, Object?> event) async {
    if (_disposed) return;
    final type = event['type'];
    final rawPeer = event['peer'];
    if (rawPeer is! String || rawPeer.isEmpty) return;
    final address = rawPeer.toUpperCase();

    if (type == 'readyToSend') {
      await _sendChallenge(address);
      return;
    }
    if (type == 'peerDisconnected') {
      final nodeId = directory.nodeForAddress(address);
      if (nodeId != null) directory.removeNode(nodeId);
      final pendingChallenge = _pendingChallenges.remove(address);
      if (pendingChallenge != null) handshake.cancelChallenge(pendingChallenge);
      _challengeCreatedAt.remove(address);
      _challengeStarted.remove(address);
      _reassemblers.remove(address)?.clear();
      return;
    }
    if (type != 'frameReceived') return;

    final rawFrame = event['frame'];
    if (rawFrame is! List ||
        rawFrame.isEmpty ||
        rawFrame.length > 194 ||
        rawFrame.any((value) => value is! int || value < 0 || value > 255)) {
      return;
    }

    try {
      final encodedFrame = rawFrame.cast<int>();
      BleFrame.decode(encodedFrame);
      final reassembler = _reassemblers.putIfAbsent(
        address,
        MessageFrameReassembler.new,
      );
      final complete = reassembler.accept(encodedFrame);
      if (complete == null || complete.length > _maxControlBytes) return;
      final decoded = jsonDecode(utf8.decode(complete, allowMalformed: false));
      if (decoded is! Map<String, dynamic>) return;

      if (_isChallenge(decoded)) {
        final challenge = decoded['challenge'] as String;
        if (!_challengeStarted.contains(address) ||
            !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(challenge)) {
          return;
        }
        // The local side must have initiated a challenge first. A peer's
        // challenge is then answered so both sides can independently verify
        // each other; public identity keys in this proof are not secret.
        final proof = await handshake.createProof(challenge);
        await _sendControl(address, <String, Object>{
          'version': _version,
          'kind': 'proof',
          'proof': proof,
        });
      } else if (_isProof(decoded)) {
        final challenge = _pendingChallenges.remove(address);
        _challengeCreatedAt.remove(address);
        if (challenge == null) return;
        await handshake.verifyAndBind(
          bleAddress: address,
          expectedChallenge: challenge,
          encodedProof: decoded['proof'] as String,
          trustedContacts: await trustedContacts(),
        );
      }
    } on FormatException {
      // Ignore malformed control frames and invalid/untrusted proofs.
    } on ArgumentError {
      // Ignore malformed frame fields.
    } on StateError {
      // Challenge capacity, conflicting identity binding, or native state.
    } catch (_) {
      // Authentication and platform errors fail closed without payload logs.
    }
  }

  bool _isChallenge(Map<String, dynamic> value) =>
      value.length == 3 &&
      value.keys.toSet().containsAll(<String>{'version', 'kind', 'challenge'}) &&
      value['version'] == _version &&
      value['kind'] == 'challenge' &&
      value['challenge'] is String;

  bool _isProof(Map<String, dynamic> value) =>
      value.length == 3 &&
      value.keys.toSet().containsAll(<String>{'version', 'kind', 'proof'}) &&
      value['version'] == _version &&
      value['kind'] == 'proof' &&
      value['proof'] is String &&
      (value['proof'] as String).length <= _maxControlBytes;

  Future<void> _sendChallenge(String address) async {
    final normalizedAddress = address.toUpperCase();
    if (_disposed || _challengeStarted.contains(normalizedAddress)) return;
    _challengeStarted.add(normalizedAddress);
    String? challenge;
    try {
      final createdChallenge = handshake.createChallenge();
      challenge = createdChallenge;
      _pendingChallenges[normalizedAddress] = createdChallenge;
      _challengeCreatedAt[normalizedAddress] = DateTime.now().toUtc();
      await _sendControl(normalizedAddress, <String, Object>{
        'version': _version,
        'kind': 'challenge',
        'challenge': createdChallenge,
      });
    } catch (_) {
      _challengeStarted.remove(normalizedAddress);
      _pendingChallenges.remove(normalizedAddress);
      _challengeCreatedAt.remove(normalizedAddress);
      if (challenge != null) handshake.cancelChallenge(challenge);
      // The peer may not yet be GATT-ready; a later readiness event retries.
    }
  }

  Future<void> _retryExpiredChallenges() async {
    if (_disposed) return;
    final now = DateTime.now().toUtc();
    final expired = _challengeCreatedAt.entries
        .where((entry) => now.difference(entry.value) >= const Duration(seconds: 90))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final address in expired) {
      if (directory.nodeForAddress(address) != null) continue;
      final challenge = _pendingChallenges.remove(address);
      _challengeCreatedAt.remove(address);
      if (challenge != null) handshake.cancelChallenge(challenge);
      _challengeStarted.remove(address);
      await _sendChallenge(address);
    }
  }

  Future<void> _sendControl(String address, Map<String, Object> control) async {
    final encoded = jsonEncode(control);
    final bytes = utf8.encode(encoded);
    if (bytes.isEmpty || bytes.length > _maxControlBytes) {
      throw const FormatException('Mesh handshake control exceeds size limit.');
    }
    final frames = MessageFrameTransfer.fragment(
      messageBytes: bytes,
      transferId: _random.nextInt(0x100000000),
    );
    for (final frame in frames) {
      await native.sendBleFrameToPeer(
        peer: address,
        frame: Uint8List.fromList(frame),
      );
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _eventTail;
    for (final reassembler in _reassemblers.values) {
      reassembler.clear();
    }
    _reassemblers.clear();
    for (final challenge in _pendingChallenges.values) {
      handshake.cancelChallenge(challenge);
    }
    _pendingChallenges.clear();
    _challengeCreatedAt.clear();
    _challengeStarted.clear();
  }
}
