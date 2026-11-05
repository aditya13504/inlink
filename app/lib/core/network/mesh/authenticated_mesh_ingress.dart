import 'dart:async';

import '../../security/contact_identity.dart';
import '../../security/verified_message_service.dart';
import 'mesh_routing_engine.dart';
import 'mesh_identity_handshake.dart';
import 'mesh_transport_adapter.dart';
import 'native_mesh_peer_transport.dart';

enum MeshIngressStatus {
  delivered,
  forwarded,
  duplicate,
  rejected,
  notForThisNode,
}

class MeshIngressEvent {
  const MeshIngressEvent({
    required this.status,
    this.originNodeId,
    this.messageId,
    this.plaintext,
    this.detail = '',
  });

  final MeshIngressStatus status;
  final String? originNodeId;
  final String? messageId;

  /// Populated only after E2EE signature verification, authenticated decryption,
  /// sender pinning and replay checks all succeed.
  final String? plaintext;
  final String detail;
}

/// Joins native frame reassembly, mesh routing, contact pinning and E2EE opening.
/// Intermediate nodes see only opaque envelopes; only the destination decrypts.
class AuthenticatedMeshIngress {
  AuthenticatedMeshIngress({
    required this.receiver,
    required this.router,
    required this.verifiedMessages,
    required this.trustedContacts,
    required this.localNodeId,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final NativeMeshFrameReceiver receiver;
  final MeshTransportAdapter router;
  final VerifiedMessageService verifiedMessages;
  final Future<List<VerifiedInLinkContact>> Function() trustedContacts;
  final String localNodeId;
  final DateTime Function() _clock;
  StreamSubscription<NativeMeshPacketEvent>? _subscription;
  final StreamController<MeshIngressEvent> _events =
      StreamController<MeshIngressEvent>.broadcast();

  Stream<MeshIngressEvent> get events => _events.stream;

  Future<void> start() async {
    if (_subscription != null) return;
    _subscription = receiver.receivePackets().listen(
      (event) async {
        try {
          final result = await router.receive(
            encodedPacket: event.encodedPacket,
            fromPeerId: event.fromPeerId,
            now: _clock().toUtc(),
          );
          if (result.status == MeshReceiveStatus.deliver && result.packet != null) {
            final packet = result.packet!;
            final contacts = await trustedContacts();
            VerifiedInLinkContact? sender;
            for (final contact in contacts) {
              final nodeId = await _nodeIdForContact(contact);
              if (nodeId == packet.originNodeId) {
                sender = contact;
                break;
              }
            }
            if (sender == null) {
              _events.add(MeshIngressEvent(
                status: MeshIngressStatus.rejected,
                originNodeId: packet.originNodeId,
                messageId: packet.messageId,
                detail: 'Origin node is not a trusted contact.',
              ));
              return;
            }
            final plaintext = await verifiedMessages.openFromVerifiedContact(
              contact: sender,
              encodedEnvelope: packet.opaqueEnvelope,
            );
            _events.add(MeshIngressEvent(
              status: MeshIngressStatus.delivered,
              originNodeId: packet.originNodeId,
              messageId: packet.messageId,
              plaintext: plaintext,
            ));
          } else if (result.status == MeshReceiveStatus.queuedForForwarding) {
            _events.add(MeshIngressEvent(
              status: MeshIngressStatus.forwarded,
              detail: 'Accepted for store-and-forward routing.',
            ));
          } else if (result.status == MeshReceiveStatus.duplicate) {
            _events.add(const MeshIngressEvent(status: MeshIngressStatus.duplicate));
          } else {
            _events.add(MeshIngressEvent(
              status: MeshIngressStatus.rejected,
              detail: result.detail.isEmpty ? result.status.name : result.detail,
            ));
          }
        } catch (error) {
          // Never emit the envelope or plaintext in logs/events on failure.
          _events.add(MeshIngressEvent(
            status: MeshIngressStatus.rejected,
            detail: error is FormatException
                ? error.message
                : 'Inbound packet failed authentication or processing.',
          ));
        }
      },
      onError: (Object _) {
        _events.add(const MeshIngressEvent(
          status: MeshIngressStatus.rejected,
          detail: 'Native mesh receive stream failed.',
        ));
      },
    );
  }

  Future<String> _nodeIdForContact(VerifiedInLinkContact contact) async {
    // Imported locally to keep node-ID derivation identical to the handshake.
    return meshNodeIdForKeys(
      signingPublicKey: contact.signingPublicKey,
      encryptionPublicKey: contact.encryptionPublicKey,
    );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    receiver.clear();
    await _events.close();
  }
}
