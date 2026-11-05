import 'package:flutter_test/flutter_test.dart';
import 'package:inlink/core/network/mesh/mesh_routing_engine.dart';
import 'package:inlink/core/network/mesh/mesh_transport_adapter.dart';

const nodeA = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const nodeB = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
const nodeC = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';
const nodeD = 'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD';

class FakeMeshTransport implements MeshPeerTransport {
  FakeMeshTransport({
    this.peers = const <String>{},
    this.failPeers = const <String>{},
  });

  Set<String> peers;
  Set<String> failPeers;
  final List<(String, String)> sent = <(String, String)>[];

  @override
  Future<Set<String>> connectedPeerIds() async => peers;

  @override
  Future<bool> sendPacket({
    required String peerId,
    required String encodedPacket,
  }) async {
    sent.add((peerId, encodedPacket));
    if (failPeers.contains(peerId)) {
      throw StateError('simulated transport failure');
    }
    return true;
  }
}

void main() {
  final now = DateTime.utc(2026, 10, 9, 12);

  test(
    'flush sends a locally originated packet to connected peers once',
    () async {
      final engine = MeshRoutingEngine(localNodeId: nodeA);
      final transport = FakeMeshTransport(peers: <String>{nodeB, nodeC});
      final adapter = MeshTransportAdapter(
        engine: engine,
        transport: transport,
      );

      await adapter.originate(
        messageId: 'message_mesh_0001',
        destinationNodeId: nodeD,
        opaqueEnvelope: 'opaque-e2ee-envelope',
        now: now,
      );

      expect(transport.sent, hasLength(2));
      final secondFlush = await adapter.flush(now: now);
      expect(secondFlush.attempted, 0);
    },
  );

  test('failed peer attempt is released while successful peer stays attempted',
      () async {
    final engine = MeshRoutingEngine(localNodeId: nodeA);
    final transport = FakeMeshTransport(
      peers: <String>{nodeB, nodeC},
      failPeers: <String>{nodeB},
    );
    final adapter = MeshTransportAdapter(engine: engine, transport: transport);
    engine.originate(
      messageId: 'message_mesh_0002',
      destinationNodeId: nodeD,
      opaqueEnvelope: 'opaque-e2ee-envelope',
      now: now,
    );

    final first = await adapter.flush(now: now);
    expect(first.attempted, 2);
    expect(first.accepted, 1);
    expect(first.failed, 1);
    expect(engine.pendingForPeer(nodeB, now: now), hasLength(1));
    expect(engine.pendingForPeer(nodeC, now: now), isEmpty);

    transport.failPeers = const <String>{};
    final second = await adapter.flush(now: now);
    expect(second.attempted, 1);
    expect(second.accepted, 1);
    expect(second.failed, 0);
  });

  test('received packet is forwarded to neighbors but not back to ingress',
      () async {
    final engine = MeshRoutingEngine(localNodeId: nodeB);
    final transport = FakeMeshTransport(peers: <String>{nodeA, nodeC});
    final adapter = MeshTransportAdapter(engine: engine, transport: transport);
    final packet = MeshPacket(
      messageId: 'message_mesh_0003',
      originNodeId: nodeA,
      destinationNodeId: nodeD,
      createdAtEpochSeconds: now.millisecondsSinceEpoch ~/ 1000,
      expiresAtEpochSeconds:
          now.add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000,
      hopLimit: 8,
      hopCount: 0,
      opaqueEnvelope: 'opaque-e2ee-envelope',
    );

    final result = await adapter.receive(
      encodedPacket: packet.encode(),
      fromPeerId: nodeA,
      now: now,
    );

    expect(result.status, MeshReceiveStatus.queuedForForwarding);
    expect(transport.sent, hasLength(1));
    expect(transport.sent.single.$1, nodeC);
  });

  test('destination packet is returned to the caller and not forwarded',
      () async {
    final engine = MeshRoutingEngine(localNodeId: nodeC);
    final transport = FakeMeshTransport(peers: <String>{nodeB, nodeD});
    final adapter = MeshTransportAdapter(engine: engine, transport: transport);
    final packet = MeshPacket(
      messageId: 'message_mesh_0004',
      originNodeId: nodeA,
      destinationNodeId: nodeC,
      createdAtEpochSeconds: now.millisecondsSinceEpoch ~/ 1000,
      expiresAtEpochSeconds:
          now.add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000,
      hopLimit: 8,
      hopCount: 1,
      opaqueEnvelope: 'opaque-e2ee-envelope',
    );

    final result = await adapter.receive(
      encodedPacket: packet.encode(),
      fromPeerId: nodeB,
      now: now,
    );

    expect(result.status, MeshReceiveStatus.deliver);
    expect(result.packet!.opaqueEnvelope, 'opaque-e2ee-envelope');
    expect(transport.sent, isEmpty);
  });
}
