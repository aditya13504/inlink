import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inlink/core/network/mesh/mesh_routing_engine.dart';

const nodeA = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const nodeB = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
const nodeC = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';
const nodeD = 'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD';
const messageId = 'message_mesh_0001';

void main() {
  final now = DateTime.utc(2026, 10, 9, 12);

  MeshPacket packet({
    String origin = nodeA,
    String destination = nodeC,
    String id = messageId,
    String envelope = 'opaque-encrypted-envelope',
    int hopLimit = 8,
    int hopCount = 0,
    DateTime? createdAt,
    DateTime? expiresAt,
  }) {
    final created = createdAt ?? now;
    final expiry = expiresAt ?? now.add(const Duration(days: 2));
    return MeshPacket(
      messageId: id,
      originNodeId: origin,
      destinationNodeId: destination,
      createdAtEpochSeconds: created.millisecondsSinceEpoch ~/ 1000,
      expiresAtEpochSeconds: expiry.millisecondsSinceEpoch ~/ 1000,
      hopLimit: hopLimit,
      hopCount: hopCount,
      opaqueEnvelope: envelope,
    );
  }

  test('packet wire encoding round-trips without changing opaque envelope', () {
    final original = packet();
    final decoded = MeshPacket.decode(original.encode(), now: now);
    expect(decoded.toJson(), original.toJson());
    expect(decoded.opaqueEnvelope, 'opaque-encrypted-envelope');
  });

  test('strict decoder rejects unknown and missing fields', () {
    final withUnknown = packet().toJson()..['debug'] = true;
    expect(
      () => MeshPacket.decode(jsonEncode(withUnknown), now: now),
      throwsFormatException,
    );
    final missing = packet().toJson()..remove('destination_node_id');
    expect(
      () => MeshPacket.decode(jsonEncode(missing), now: now),
      throwsFormatException,
    );
  });

  test(
    'decoder rejects unsupported version, invalid IDs, and bad hop bounds',
    () {
      final wrongVersion = packet().toJson()..['protocol_version'] = 99;
      expect(
        () => MeshPacket.decode(jsonEncode(wrongVersion), now: now),
        throwsFormatException,
      );
      final badId = packet().toJson()..['origin_node_id'] = 'not-valid';
      expect(
        () => MeshPacket.decode(jsonEncode(badId), now: now),
        throwsFormatException,
      );
      final badHops = packet().toJson()..['hop_count'] = 9;
      expect(
        () => MeshPacket.decode(jsonEncode(badHops), now: now),
        throwsFormatException,
      );
    },
  );

  test(
    'decoder rejects expired, too-far-future, and overlong-lived packets',
    () {
      final expired =
          packet(expiresAt: now.subtract(const Duration(seconds: 1)));
      expect(() => expired.validate(now: now), throwsFormatException);
      final future = packet(createdAt: now.add(const Duration(minutes: 6)));
      expect(() => future.validate(now: now), throwsFormatException);
      final tooLong = packet(expiresAt: now.add(const Duration(days: 8)));
      expect(() => tooLong.validate(now: now), throwsFormatException);
    },
  );

  test('decoder enforces payload and total packet size limits', () {
    final tooLargePayload = packet(envelope: 'x' * (meshMaxPayloadBytes + 1));
    expect(() => tooLargePayload.validate(now: now), throwsFormatException);
    expect(
      () => MeshPacket.decode('x' * (meshMaxPacketBytes + 1), now: now),
      throwsFormatException,
    );
  });

  test('origin and destination cannot be the same node', () {
    final invalid = packet(origin: nodeA, destination: nodeA);
    expect(() => invalid.validate(now: now), throwsFormatException);
  });

  test('intermediate node increments hop count and excludes ingress peer', () {
    final router = MeshRoutingEngine(localNodeId: nodeB);
    final incoming = packet().encode();
    final result = router.receive(
      encodedPacket: incoming,
      fromPeerId: nodeA,
      connectedPeerIds: <String>[nodeA, nodeC, nodeD],
      now: now,
    );

    expect(result.status, MeshReceiveStatus.queuedForForwarding);
    expect(result.forwardedPacket!.hopCount, 1);
    expect(result.forwardedPacket!.opaqueEnvelope, 'opaque-encrypted-envelope');
    expect(result.forwardTo, <String>[nodeC, nodeD]);
    expect(router.pendingCount, 1);
  });

  test(
    'three-node route delivers at destination and does not decrypt at relay',
    () {
      final relay = MeshRoutingEngine(localNodeId: nodeB);
      final destination = MeshRoutingEngine(localNodeId: nodeC);
      final incoming = packet().encode();

      final atRelay = relay.receive(
        encodedPacket: incoming,
        fromPeerId: nodeA,
        connectedPeerIds: <String>[nodeA, nodeC],
        now: now,
      );
      expect(atRelay.status, MeshReceiveStatus.queuedForForwarding);
      final forwarded = atRelay.forwardedPacket!;
      final atDestination = destination.receive(
        encodedPacket: forwarded.encode(),
        fromPeerId: nodeB,
        connectedPeerIds: const <String>[],
        now: now,
      );

      expect(atDestination.status, MeshReceiveStatus.deliver);
      expect(
        atDestination.packet!.opaqueEnvelope,
        'opaque-encrypted-envelope',
      );
      expect(atDestination.packet!.hopCount, 1);
    },
  );

  test('forward target list ignores malformed neighbor IDs', () {
    final router = MeshRoutingEngine(localNodeId: nodeB);
    final result = router.receive(
      encodedPacket: packet().encode(),
      fromPeerId: nodeA,
      connectedPeerIds: <String>['bad-peer', nodeC, nodeB],
      now: now,
    );
    expect(result.forwardTo, <String>[nodeC]);
  });

  test('duplicate packet and looped packet are suppressed', () {
    final router = MeshRoutingEngine(localNodeId: nodeB);
    final original = packet().encode();
    final first = router.receive(
      encodedPacket: original,
      fromPeerId: nodeA,
      connectedPeerIds: <String>[nodeC],
      now: now,
    );
    final duplicate = router.receive(
      encodedPacket: original,
      fromPeerId: nodeC,
      connectedPeerIds: <String>[nodeA],
      now: now,
    );
    final looped = packet(hopCount: 2).encode();
    final loop = router.receive(
      encodedPacket: looped,
      fromPeerId: nodeC,
      connectedPeerIds: <String>[nodeA],
      now: now,
    );

    expect(first.status, MeshReceiveStatus.queuedForForwarding);
    expect(duplicate.status, MeshReceiveStatus.duplicate);
    expect(loop.status, MeshReceiveStatus.duplicate);
    expect(router.pendingCount, 1);
  });

  test('pending deduplication survives seen-cache eviction', () {
    final router = MeshRoutingEngine(localNodeId: nodeB, maxSeenEntries: 1);
    final first = packet(id: 'message_mesh_0001');
    final second = packet(id: 'message_mesh_0002');
    router.receive(
      encodedPacket: first.encode(),
      fromPeerId: nodeA,
      connectedPeerIds: <String>[nodeC],
      now: now,
    );
    router.receive(
      encodedPacket: second.encode(),
      fromPeerId: nodeA,
      connectedPeerIds: <String>[nodeC],
      now: now,
    );
    final duplicate = router.receive(
      encodedPacket: first.encode(),
      fromPeerId: nodeA,
      connectedPeerIds: <String>[nodeC],
      now: now,
    );
    expect(duplicate.status, MeshReceiveStatus.duplicate);
    expect(router.pendingCount, 2);
  });

  test('same route key with different immutable payload is rejected', () {
    final router = MeshRoutingEngine(localNodeId: nodeB);
    router.receive(
      encodedPacket: packet().encode(),
      fromPeerId: nodeA,
      connectedPeerIds: <String>[nodeC],
      now: now,
    );
    final conflict = router.receive(
      encodedPacket: packet(envelope: 'different-envelope').encode(),
      fromPeerId: nodeA,
      connectedPeerIds: <String>[nodeC],
      now: now,
    );
    expect(conflict.status, MeshReceiveStatus.conflictingDuplicate);
  });

  test('hop limit prevents onward forwarding', () {
    final router = MeshRoutingEngine(localNodeId: nodeB);
    final result = router.receive(
      encodedPacket: packet(hopLimit: 2, hopCount: 2).encode(),
      fromPeerId: nodeA,
      connectedPeerIds: <String>[nodeC],
      now: now,
    );
    expect(result.status, MeshReceiveStatus.hopLimitReached);
    expect(router.pendingCount, 0);
  });

  test(
    'bounded queue refuses new packets without evicting accepted packet',
    () {
      final router = MeshRoutingEngine(
        localNodeId: nodeB,
        maxQueuedPackets: 1,
      );
      final first = router.receive(
        encodedPacket: packet(id: 'message_mesh_0001').encode(),
        fromPeerId: nodeA,
        connectedPeerIds: <String>[nodeC],
        now: now,
      );
      final second = router.receive(
        encodedPacket: packet(id: 'message_mesh_0002').encode(),
        fromPeerId: nodeA,
        connectedPeerIds: <String>[nodeC],
        now: now,
      );
      expect(first.status, MeshReceiveStatus.queuedForForwarding);
      expect(second.status, MeshReceiveStatus.queueFull);
      expect(router.pendingCount, 1);
    },
  );

  test('offline queue can be retried when a neighbor appears', () {
    final router = MeshRoutingEngine(localNodeId: nodeB);
    final result = router.receive(
      encodedPacket: packet().encode(),
      fromPeerId: nodeA,
      connectedPeerIds: const <String>[],
      now: now,
    );
    expect(result.status, MeshReceiveStatus.queuedForForwarding);
    expect(result.forwardTo, isEmpty);
    expect(router.pendingForPeer(nodeA, now: now), isEmpty);
    expect(router.pendingForPeer(nodeC, now: now), hasLength(1));

    router.markForwarded(routeKey: packet().routeKey, peerId: nodeC);
    expect(router.pendingForPeer(nodeC, now: now), isEmpty);
    expect(router.pendingForPeer(nodeD, now: now), hasLength(1));
    router.markForwardFailed(routeKey: packet().routeKey, peerId: nodeC);
    expect(router.pendingForPeer(nodeC, now: now), hasLength(1));
  });

  test('locally originated packet is queued until a route is available', () {
    final router = MeshRoutingEngine(localNodeId: nodeA);
    final created = router.originate(
      messageId: messageId,
      destinationNodeId: nodeC,
      opaqueEnvelope: 'already-encrypted-envelope',
      now: now,
    );
    expect(created.originNodeId, nodeA);
    expect(created.hopCount, 0);
    expect(router.pendingForPeer(nodeB, now: now), hasLength(1));
    expect(router.pendingCount, 1);
  });

  test('expiry purges pending and seen cache entries', () {
    final router = MeshRoutingEngine(localNodeId: nodeB);
    final shortLived = packet(expiresAt: now.add(const Duration(minutes: 1)));
    router.receive(
      encodedPacket: shortLived.encode(),
      fromPeerId: nodeA,
      connectedPeerIds: <String>[nodeC],
      now: now,
    );
    expect(router.pendingCount, 1);
    router.purge(now.add(const Duration(minutes: 2)));
    expect(router.pendingCount, 0);
    expect(router.seenCount, 0);
  });

  test('seen cache remains bounded by its configured capacity', () {
    final router = MeshRoutingEngine(localNodeId: nodeB, maxSeenEntries: 1);
    router.receive(
      encodedPacket: packet(destination: nodeB).encode(),
      fromPeerId: nodeA,
      connectedPeerIds: const <String>[],
      now: now,
    );
    router.receive(
      encodedPacket: packet(
        origin: nodeC,
        destination: nodeB,
        id: 'message_mesh_0002',
      ).encode(),
      fromPeerId: nodeD,
      connectedPeerIds: const <String>[],
      now: now,
    );
    expect(router.seenCount, 1);
  });

  test('invalid ingress peer is rejected', () {
    final router = MeshRoutingEngine(localNodeId: nodeB);
    final result = router.receive(
      encodedPacket: packet().encode(),
      fromPeerId: 'bad-peer',
      connectedPeerIds: <String>[nodeC],
      now: now,
    );
    expect(result.status, MeshReceiveStatus.rejected);
    expect(router.pendingCount, 0);
  });

  test('origin refuses duplicate route IDs and enforces queue bound', () {
    final router = MeshRoutingEngine(localNodeId: nodeA, maxQueuedPackets: 1);
    router.originate(
      messageId: 'message_mesh_0001',
      destinationNodeId: nodeC,
      opaqueEnvelope: 'encrypted-1',
      now: now,
    );
    expect(
      () => router.originate(
        messageId: 'message_mesh_0001',
        destinationNodeId: nodeC,
        opaqueEnvelope: 'encrypted-2',
        now: now,
      ),
      throwsStateError,
    );
    expect(
      () => router.originate(
        messageId: 'message_mesh_0002',
        destinationNodeId: nodeD,
        opaqueEnvelope: 'encrypted-3',
        now: now,
      ),
      throwsStateError,
    );
  });

  test('only the exact route key is removed on completion', () {
    final router = MeshRoutingEngine(localNodeId: nodeA);
    final created = router.originate(
      messageId: messageId,
      destinationNodeId: nodeC,
      opaqueEnvelope: 'encrypted',
      now: now,
    );
    router.removePending(created.routeKey);
    expect(router.pendingCount, 0);
  });
  test('restores durable pending packet and peer attempts after restart', () {
    final packetToRestore = packet(hopCount: 1);
    final restored = MeshRoutingEngine(localNodeId: nodeB);
    restored.restorePending(
      packet: packetToRestore,
      ingressPeerId: nodeA,
      attemptedPeerIds: <String>[nodeD],
      now: now,
    );
    expect(restored.pendingCount, 1);
    expect(restored.pendingForPeer(nodeA, now: now), isEmpty);
    expect(restored.pendingForPeer(nodeD, now: now), isEmpty);
    expect(restored.pendingForPeer(nodeC, now: now), hasLength(1));
  });

  test('restored route key cannot replace different immutable packet content', () {
    final restored = MeshRoutingEngine(localNodeId: nodeB);
    restored.restorePending(
      packet: packet(),
      ingressPeerId: nodeA,
      attemptedPeerIds: const <String>[],
      now: now,
    );
    expect(
      () => restored.restorePending(
        packet: packet(envelope: 'different-envelope'),
        ingressPeerId: nodeA,
        attemptedPeerIds: const <String>[],
        now: now,
      ),
      throwsStateError,
    );
  });

}
