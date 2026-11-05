import 'durable_mesh_queue.dart';
import 'mesh_routing_engine.dart';

/// Coordinates SQLCipher queue persistence with the in-memory route engine.
/// Call [restore] once at startup before accepting new mesh traffic.
class DurableMeshRouter {
  const DurableMeshRouter({required this.engine, required this.queue});
  final MeshRoutingEngine engine;
  final DurableMeshQueue queue;

  Future<int> restore({required DateTime now}) async {
    // A local transport write is not proof of remote delivery. Permit retry
    // after process death; packet deduplication at neighbors handles repeats.
    await queue.resetAttemptsForRecovery();
    final entries = await queue.listPending(now: now);
    var restored = 0;
    for (final entry in entries) {
      try {
        engine.restorePending(
          packet: entry.packet,
          ingressPeerId: entry.ingressPeerId,
          attemptedPeerIds: entry.attemptedPeerIds,
          now: now,
        );
        restored++;
      } on StateError {
        // Capacity or conflicting in-memory state is surfaced through count;
        // the encrypted durable row is retained for the next launch/retry.
      } on ArgumentError {
        // Invalid persisted route metadata is not injected into the engine.
      }
    }
    return restored;
  }

  Future<void> persistAccepted({
    required MeshPacket packet,
    required String? ingressPeerId,
    required DateTime now,
  }) => queue.enqueue(packet: packet, ingressPeerId: ingressPeerId, now: now);

  Future<void> markTransportAccepted({required String routeKey, required String peerId}) =>
      queue.markAttempted(routeKey: routeKey, peerId: peerId);

  Future<void> markTransportFailed({required String routeKey, required String peerId}) =>
      queue.markAttemptFailed(routeKey: routeKey, peerId: peerId);

  Future<void> completeAfterAuthenticatedReceipt(String routeKey) async {
    engine.removePending(routeKey);
    await queue.remove(routeKey);
  }
}
