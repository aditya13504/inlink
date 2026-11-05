import 'dart:collection';
import 'dart:convert';

/// Bounds for the experimental store-and-forward mesh routing layer.
///
/// This layer only forwards opaque end-to-end encrypted envelopes. It does not
/// authenticate peers or decrypt payloads; the existing E2EE verifier must do
/// that at the destination.
const int meshProtocolVersion = 1;
const int meshMaxHopLimit = 8;
const int meshMaxPayloadBytes = 15 * 1024;
const int meshMaxPacketBytes = 16 * 1024;
const int meshMaxQueuedPackets = 256;
const int meshMaxSeenEntries = 4096;
const Duration meshMaxMessageAge = Duration(days: 7);
const Duration meshAllowedClockSkew = Duration(minutes: 5);

final RegExp _meshIdPattern = RegExp(r'^[A-Za-z0-9_-]{16,64}$');

class MeshPacket {
  const MeshPacket({
    required this.messageId,
    required this.originNodeId,
    required this.destinationNodeId,
    required this.createdAtEpochSeconds,
    required this.expiresAtEpochSeconds,
    required this.hopLimit,
    required this.hopCount,
    required this.opaqueEnvelope,
    this.protocolVersion = meshProtocolVersion,
  });

  final int protocolVersion;
  final String messageId;
  final String originNodeId;
  final String destinationNodeId;
  final int createdAtEpochSeconds;
  final int expiresAtEpochSeconds;
  final int hopLimit;
  final int hopCount;

  /// Encoded E2EE envelope. Routers must never inspect or modify its contents.
  final String opaqueEnvelope;

  String get routeKey => '$originNodeId:$messageId';

  MeshPacket forwarded() => MeshPacket(
        protocolVersion: protocolVersion,
        messageId: messageId,
        originNodeId: originNodeId,
        destinationNodeId: destinationNodeId,
        createdAtEpochSeconds: createdAtEpochSeconds,
        expiresAtEpochSeconds: expiresAtEpochSeconds,
        hopLimit: hopLimit,
        hopCount: hopCount + 1,
        opaqueEnvelope: opaqueEnvelope,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'protocol_version': protocolVersion,
        'message_id': messageId,
        'origin_node_id': originNodeId,
        'destination_node_id': destinationNodeId,
        'created_at': createdAtEpochSeconds,
        'expires_at': expiresAtEpochSeconds,
        'hop_limit': hopLimit,
        'hop_count': hopCount,
        'opaque_envelope': opaqueEnvelope,
      };

  String encode() => jsonEncode(toJson());

  /// Validates a wire packet strictly before it enters routing state.
  ///
  /// Unknown fields are rejected to keep the v1 wire contract unambiguous.
  static MeshPacket decode(
    String encoded, {
    required DateTime now,
    int maxPacketBytes = meshMaxPacketBytes,
  }) {
    if (utf8.encode(encoded).length > maxPacketBytes) {
      throw const FormatException(
        'Mesh packet exceeds the encoded-size limit.',
      );
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Mesh packet is not valid JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Mesh packet must be a JSON object.');
    }
    const fields = <String>{
      'protocol_version',
      'message_id',
      'origin_node_id',
      'destination_node_id',
      'created_at',
      'expires_at',
      'hop_limit',
      'hop_count',
      'opaque_envelope',
    };
    if (decoded.keys.toSet().difference(fields).isNotEmpty ||
        fields.difference(decoded.keys.toSet()).isNotEmpty) {
      throw const FormatException('Mesh packet has missing or unknown fields.');
    }

    final version = decoded['protocol_version'];
    final messageId = decoded['message_id'];
    final origin = decoded['origin_node_id'];
    final destination = decoded['destination_node_id'];
    final created = decoded['created_at'];
    final expires = decoded['expires_at'];
    final hopLimit = decoded['hop_limit'];
    final hopCount = decoded['hop_count'];
    final envelope = decoded['opaque_envelope'];

    if (version is! int ||
        messageId is! String ||
        origin is! String ||
        destination is! String ||
        created is! int ||
        expires is! int ||
        hopLimit is! int ||
        hopCount is! int ||
        envelope is! String) {
      throw const FormatException('Mesh packet contains invalid field types.');
    }
    final packet = MeshPacket(
      protocolVersion: version,
      messageId: messageId,
      originNodeId: origin,
      destinationNodeId: destination,
      createdAtEpochSeconds: created,
      expiresAtEpochSeconds: expires,
      hopLimit: hopLimit,
      hopCount: hopCount,
      opaqueEnvelope: envelope,
    );
    packet.validate(now: now, maxPacketBytes: maxPacketBytes);
    return packet;
  }

  void validate({
    required DateTime now,
    int maxPacketBytes = meshMaxPacketBytes,
  }) {
    if (protocolVersion != meshProtocolVersion) {
      throw const FormatException('Unsupported mesh protocol version.');
    }
    if (!_meshIdPattern.hasMatch(messageId) ||
        !_meshIdPattern.hasMatch(originNodeId) ||
        !_meshIdPattern.hasMatch(destinationNodeId)) {
      throw const FormatException(
        'Mesh IDs must be 16–64 URL-safe characters.',
      );
    }
    if (originNodeId == destinationNodeId) {
      throw const FormatException('Mesh origin and destination must differ.');
    }
    if (hopLimit < 1 ||
        hopLimit > meshMaxHopLimit ||
        hopCount < 0 ||
        hopCount > hopLimit) {
      throw const FormatException(
        'Mesh hop counters are outside protocol bounds.',
      );
    }
    if (opaqueEnvelope.isEmpty ||
        utf8.encode(opaqueEnvelope).length > meshMaxPayloadBytes) {
      throw const FormatException(
        'Opaque envelope is empty or exceeds 15 KiB.',
      );
    }
    final nowSeconds = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    if (createdAtEpochSeconds > nowSeconds + meshAllowedClockSkew.inSeconds) {
      throw const FormatException(
        'Mesh packet creation time is in the future.',
      );
    }
    if (expiresAtEpochSeconds <= nowSeconds) {
      throw const FormatException('Mesh packet has expired.');
    }
    if (expiresAtEpochSeconds <= createdAtEpochSeconds ||
        expiresAtEpochSeconds - createdAtEpochSeconds >
            meshMaxMessageAge.inSeconds) {
      throw const FormatException('Mesh packet expiry window is invalid.');
    }
    if (utf8.encode(encode()).length > maxPacketBytes) {
      throw const FormatException(
        'Mesh packet exceeds the encoded-size limit.',
      );
    }
  }

  /// Stable immutable fields detect route-key reuse with changed content.
  /// Hop count is excluded because forwarding legitimately changes it.
  String get immutableFingerprint => jsonEncode(<Object?>[
        protocolVersion,
        messageId,
        originNodeId,
        destinationNodeId,
        createdAtEpochSeconds,
        expiresAtEpochSeconds,
        hopLimit,
        opaqueEnvelope,
      ]);
}

enum MeshReceiveStatus {
  deliver,
  queuedForForwarding,
  duplicate,
  hopLimitReached,
  queueFull,
  conflictingDuplicate,
  rejected,
}

class MeshReceiveResult {
  const MeshReceiveResult({
    required this.status,
    this.packet,
    this.forwardedPacket,
    this.forwardTo = const <String>[],
    this.detail = '',
  });

  final MeshReceiveStatus status;

  /// Present only for a packet addressed to this node.
  final MeshPacket? packet;

  /// Present when the packet is accepted for onward forwarding.
  final MeshPacket? forwardedPacket;

  /// Connected peers eligible to receive the forwarded packet now.
  final List<String> forwardTo;
  final String detail;
}

class _SeenRecord {
  const _SeenRecord(this.immutableFingerprint, this.expiresAtEpochSeconds);

  final String immutableFingerprint;
  final int expiresAtEpochSeconds;
}

class _PendingPacket {
  _PendingPacket(this.packet, this.ingressPeerId);

  final MeshPacket packet;
  final String? ingressPeerId;
  final Set<String> attemptedPeers = <String>{};
}

/// Bounded flooding-based mesh routing engine.
///
/// This is a platform-neutral routing core. A transport adapter supplies peer
/// IDs and sends `pendingForPeer()` packets. Call `markForwarded()` only after
/// the transport accepts the complete packet; call `markForwardFailed()` if
/// the send fails. A receiver still has to validate/decrypt the inner E2EE
/// envelope before displaying a message.
class MeshRoutingEngine {
  MeshRoutingEngine({
    required this.localNodeId,
    this.maxQueuedPackets = meshMaxQueuedPackets,
    this.maxSeenEntries = meshMaxSeenEntries,
    this.maxPacketBytes = meshMaxPacketBytes,
  }) {
    if (!_meshIdPattern.hasMatch(localNodeId)) {
      throw ArgumentError.value(localNodeId, 'localNodeId', 'Invalid node ID.');
    }
    if (maxQueuedPackets < 1 ||
        maxSeenEntries < 1 ||
        maxPacketBytes < 512 ||
        maxPacketBytes > meshMaxPacketBytes) {
      throw ArgumentError('Mesh queue and size limits are invalid.');
    }
  }

  final String localNodeId;
  final int maxQueuedPackets;
  final int maxSeenEntries;
  final int maxPacketBytes;

  final LinkedHashMap<String, _SeenRecord> _seen =
      LinkedHashMap<String, _SeenRecord>();
  final LinkedHashMap<String, _PendingPacket> _pending =
      LinkedHashMap<String, _PendingPacket>();

  int get pendingCount => _pending.length;
  int get seenCount => _seen.length;

  /// Receives an untrusted encoded packet from a directly connected peer.
  ///
  /// `connectedPeerIds` should contain currently usable neighbor IDs. A packet
  /// is queued even without eligible peers, enabling later store-forward
  /// attempts while the application process remains alive.
  MeshReceiveResult receive({
    required String encodedPacket,
    required String fromPeerId,
    required Iterable<String> connectedPeerIds,
    required DateTime now,
  }) {
    if (!_meshIdPattern.hasMatch(fromPeerId) || fromPeerId == localNodeId) {
      return const MeshReceiveResult(
        status: MeshReceiveStatus.rejected,
        detail: 'Invalid ingress peer identifier.',
      );
    }
    final MeshPacket packet;
    try {
      packet = MeshPacket.decode(
        encodedPacket,
        now: now,
        maxPacketBytes: maxPacketBytes,
      );
    } on FormatException catch (error) {
      return MeshReceiveResult(
        status: MeshReceiveStatus.rejected,
        detail: 'invalid:${error.message}',
      );
    }

    _purgeExpired(now);
    final pendingRecord = _pending[packet.routeKey];
    if (pendingRecord != null) {
      if (pendingRecord.packet.immutableFingerprint !=
          packet.immutableFingerprint) {
        return const MeshReceiveResult(
          status: MeshReceiveStatus.conflictingDuplicate,
          detail:
              'Pending route key arrived with different immutable content.',
        );
      }
      return const MeshReceiveResult(
        status: MeshReceiveStatus.duplicate,
        detail: 'Packet is already pending at this node.',
      );
    }
    final priorRecord = _seen[packet.routeKey];
    if (priorRecord != null) {
      if (priorRecord.immutableFingerprint != packet.immutableFingerprint) {
        return const MeshReceiveResult(
          status: MeshReceiveStatus.conflictingDuplicate,
          detail:
              'Same origin/message ID arrived with different '
              'immutable content.',
        );
      }
      return const MeshReceiveResult(
        status: MeshReceiveStatus.duplicate,
        detail: 'Packet was already processed by this node.',
      );
    }

    if (packet.destinationNodeId == localNodeId) {
      _remember(packet);
      return MeshReceiveResult(
        status: MeshReceiveStatus.deliver,
        packet: packet,
      );
    }

    if (packet.hopCount >= packet.hopLimit) {
      _remember(packet);
      return const MeshReceiveResult(
        status: MeshReceiveStatus.hopLimitReached,
        detail: 'Packet reached its hop limit before the destination.',
      );
    }

    if (_pending.length >= maxQueuedPackets) {
      return const MeshReceiveResult(
        status: MeshReceiveStatus.queueFull,
        detail: 'Mesh forwarding queue is full; packet was not accepted.',
      );
    }

    final forwarded = packet.forwarded();
    _remember(packet);
    _pending[packet.routeKey] = _PendingPacket(forwarded, fromPeerId);
    final peers = connectedPeerIds
        .where((peer) =>
            _meshIdPattern.hasMatch(peer) &&
            peer != fromPeerId &&
            peer != localNodeId)
        .toSet()
        .toList()
      ..sort();
    return MeshReceiveResult(
      status: MeshReceiveStatus.queuedForForwarding,
      forwardedPacket: forwarded,
      forwardTo: List<String>.unmodifiable(peers),
    );
  }

  /// Creates a locally originated packet. The caller supplies an already
  /// encrypted/signed E2EE envelope; this layer never creates plaintext.
  MeshPacket originate({
    required String messageId,
    required String destinationNodeId,
    required String opaqueEnvelope,
    required DateTime now,
    DateTime? expiresAt,
    int hopLimit = meshMaxHopLimit,
  }) {
    final created = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    final expiry = (expiresAt ?? now.toUtc().add(meshMaxMessageAge))
        .toUtc()
        .millisecondsSinceEpoch ~/
        1000;
    final packet = MeshPacket(
      messageId: messageId,
      originNodeId: localNodeId,
      destinationNodeId: destinationNodeId,
      createdAtEpochSeconds: created,
      expiresAtEpochSeconds: expiry,
      hopLimit: hopLimit,
      hopCount: 0,
      opaqueEnvelope: opaqueEnvelope,
    );
    packet.validate(now: now, maxPacketBytes: maxPacketBytes);
    if (_pending.containsKey(packet.routeKey) ||
        _seen.containsKey(packet.routeKey)) {
      throw StateError(
        'A mesh message with this origin and ID already exists.',
      );
    }
    if (_pending.length >= maxQueuedPackets) {
      throw StateError('Mesh forwarding queue is full.');
    }
    _remember(packet);
    _pending[packet.routeKey] = _PendingPacket(packet, null);
    return packet;
  }

  /// Returns pending packets that have not been accepted by this peer.
  /// The ingress peer is excluded to avoid immediately bouncing packets back.
  List<MeshPacket> pendingForPeer(String peerId, {required DateTime now}) {
    if (!_meshIdPattern.hasMatch(peerId)) return const <MeshPacket>[];
    _purgeExpired(now);
    return List<MeshPacket>.unmodifiable(
      _pending.values
          .where((entry) =>
              entry.ingressPeerId != peerId &&
              !entry.attemptedPeers.contains(peerId))
          .map((entry) => entry.packet),
    );
  }

  /// Restores one validated persisted queue entry after process restart.
  /// Existing route keys are accepted only when immutable content matches.
  void restorePending({
    required MeshPacket packet,
    required String? ingressPeerId,
    required Iterable<String> attemptedPeerIds,
    required DateTime now,
  }) {
    packet.validate(now: now, maxPacketBytes: maxPacketBytes);
    if (packet.destinationNodeId == localNodeId) {
      throw ArgumentError('A packet addressed to this node must be delivered, not restored for forwarding.');
    }
    if (ingressPeerId != null &&
        (!_meshIdPattern.hasMatch(ingressPeerId) || ingressPeerId == localNodeId)) {
      throw ArgumentError.value(ingressPeerId, 'ingressPeerId', 'Invalid ingress peer.');
    }
    final prior = _pending[packet.routeKey];
    if (prior != null) {
      if (prior.packet.immutableFingerprint != packet.immutableFingerprint) {
        throw StateError('Persisted route key conflicts with current pending content.');
      }
      prior.attemptedPeers.addAll(attemptedPeerIds.where(_meshIdPattern.hasMatch));
      return;
    }
    final seen = _seen[packet.routeKey];
    if (seen != null) {
      if (seen.immutableFingerprint != packet.immutableFingerprint) {
        throw StateError('Persisted route key conflicts with a previously seen packet.');
      }
      return;
    }
    if (_pending.length >= maxQueuedPackets) {
      throw StateError('Mesh forwarding queue is full while restoring persisted state.');
    }
    _remember(packet);
    _pending[packet.routeKey] = _PendingPacket(packet, ingressPeerId)
      ..attemptedPeers.addAll(attemptedPeerIds.where(_meshIdPattern.hasMatch));
  }

  /// Mark a packet as accepted by the transport for a peer.
  ///
  /// This means only local transport acceptance, not remote delivery. The
  /// packet remains in memory for retry to other peers and is removed only
  /// after expiry or explicit application-level completion.
  void markForwarded({
    required String routeKey,
    required String peerId,
  }) {
    if (!_meshIdPattern.hasMatch(peerId)) {
      throw ArgumentError.value(peerId, 'peerId', 'Invalid peer ID.');
    }
    final entry = _pending[routeKey];
    if (entry == null) return;
    entry.attemptedPeers.add(peerId);
  }

  void markForwardFailed({
    required String routeKey,
    required String peerId,
  }) {
    if (!_meshIdPattern.hasMatch(peerId)) {
      throw ArgumentError.value(peerId, 'peerId', 'Invalid peer ID.');
    }
    _pending[routeKey]?.attemptedPeers.remove(peerId);
  }

  /// Removes a pending packet once the app has authoritative completion
  /// evidence, or to explicitly cancel it. Queue removal is not automatic on
  /// local send acceptance.
  void removePending(String routeKey) => _pending.remove(routeKey);

  /// Drops expired pending packets and expired replay/deduplication entries.
  void purge(DateTime now) => _purgeExpired(now);

  void _remember(MeshPacket packet) {
    _seen.remove(packet.routeKey);
    _seen[packet.routeKey] = _SeenRecord(
      packet.immutableFingerprint,
      packet.expiresAtEpochSeconds,
    );
    while (_seen.length > maxSeenEntries) {
      _seen.remove(_seen.keys.first);
    }
  }

  void _purgeExpired(DateTime now) {
    final nowSeconds = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    _pending.removeWhere(
      (_, entry) => entry.packet.expiresAtEpochSeconds <= nowSeconds,
    );
    _seen.removeWhere(
      (_, record) => record.expiresAtEpochSeconds <= nowSeconds,
    );
  }
}
