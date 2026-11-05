import 'mesh_routing_engine.dart';
import 'durable_mesh_router.dart';

/// Transport boundary expected by the mesh routing layer.
///
/// Peer IDs must be stable, verified node identifiers for the lifetime of a
/// connection. A BLE MAC address is not an identity and must not be treated as
/// one. Android exposes targeted multi-peer GATT sends; the Dart identity
/// handshake must bind each transport address to a previously verified contact.
abstract interface class MeshPeerTransport {
  Future<Set<String>> connectedPeerIds();

  /// Returns true only when the transport accepted the complete encoded packet
  /// for local transmission. It must not report end-to-end delivery.
  Future<bool> sendPacket({
    required String peerId,
    required String encodedPacket,
  });
}

class MeshFlushResult {
  const MeshFlushResult({
    required this.attempted,
    required this.accepted,
    required this.failed,
  });

  final int attempted;
  final int accepted;
  final int failed;
}

/// Connects the pure routing engine to a multi-peer transport implementation.
///
/// The native adapter supports targeted multi-peer sends through a verified
/// node-ID directory. NativeMeshRuntime composes identity binding, inbound
/// fragment reassembly, durable routing, and authenticated receipts.
class MeshTransportAdapter {
  const MeshTransportAdapter({
    required this.engine,
    required this.transport,
    this.durableRouter,
  });

  final MeshRoutingEngine engine;
  final MeshPeerTransport transport;
  final DurableMeshRouter? durableRouter;

  Future<MeshFlushResult> flush({required DateTime now}) async {
    final peers = (await transport.connectedPeerIds()).toList()..sort();
    var attempted = 0;
    var accepted = 0;
    var failed = 0;

    for (final peerId in peers) {
      final pending = engine.pendingForPeer(peerId, now: now);
      for (final packet in pending) {
        attempted++;
        try {
          final sent = await transport.sendPacket(
            peerId: peerId,
            encodedPacket: packet.encode(),
          );
          if (sent) {
            engine.markForwarded(
              routeKey: packet.routeKey,
              peerId: peerId,
            );
            await durableRouter?.markTransportAccepted(
              routeKey: packet.routeKey,
              peerId: peerId,
            );
            accepted++;
          } else {
            engine.markForwardFailed(
              routeKey: packet.routeKey,
              peerId: peerId,
            );
            await durableRouter?.markTransportFailed(
              routeKey: packet.routeKey,
              peerId: peerId,
            );
            failed++;
          }
        } catch (_) {
          engine.markForwardFailed(
            routeKey: packet.routeKey,
            peerId: peerId,
          );
          await durableRouter?.markTransportFailed(
            routeKey: packet.routeKey,
            peerId: peerId,
          );
          failed++;
        }
      }
    }

    return MeshFlushResult(
      attempted: attempted,
      accepted: accepted,
      failed: failed,
    );
  }

  Future<MeshPacket> originate({
    required String messageId,
    required String destinationNodeId,
    required String opaqueEnvelope,
    required DateTime now,
    DateTime? expiresAt,
    int hopLimit = meshMaxHopLimit,
  }) async {
    final packet = engine.originate(
      messageId: messageId,
      destinationNodeId: destinationNodeId,
      opaqueEnvelope: opaqueEnvelope,
      now: now,
      expiresAt: expiresAt,
      hopLimit: hopLimit,
    );
    try {
      await durableRouter?.persistAccepted(
        packet: packet,
        ingressPeerId: null,
        now: now,
      );
    } catch (_) {
      engine.removePending(packet.routeKey);
      rethrow;
    }
    await flush(now: now);
    return packet;
  }

  /// Processes a packet received from a directly connected neighbor. If it is
  /// for another node, eligible forwarding attempts begin immediately.
  Future<MeshReceiveResult> receive({
    required String encodedPacket,
    required String fromPeerId,
    required DateTime now,
  }) async {
    final peers = await transport.connectedPeerIds();
    final result = engine.receive(
      encodedPacket: encodedPacket,
      fromPeerId: fromPeerId,
      connectedPeerIds: peers,
      now: now,
    );
    if (result.status == MeshReceiveStatus.queuedForForwarding &&
        result.forwardedPacket != null) {
      await durableRouter?.persistAccepted(
        packet: result.forwardedPacket!,
        ingressPeerId: fromPeerId,
        now: now,
      );
      await flush(now: now);
    }
    return result;
  }
}
