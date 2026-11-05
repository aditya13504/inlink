import '../../messaging/local_message_repository.dart';
import '../../security/identity_vault.dart';
import '../../security/replay_protection_store.dart';
import '../../security/verified_message_service.dart';
import '../native_network_transport.dart';
import 'authenticated_mesh_ingress.dart';
import 'durable_mesh_queue.dart';
import 'durable_mesh_router.dart';
import 'mesh_application_message_store.dart';
import 'mesh_application_service.dart';
import 'mesh_identity_handshake.dart';
import 'mesh_routing_engine.dart';
import 'mesh_transport_adapter.dart';
import 'native_mesh_handshake_manager.dart';
import 'native_mesh_peer_transport.dart';

/// Owns one shared set of dependencies for the experimental native mesh chat
/// route. The same SQLCipher conversation repository is passed to both the UI
/// and mesh message store to prevent split-brain local message state.
class NativeMeshRuntime {
  NativeMeshRuntime._({
    required this.native,
    required this.vault,
    required this.repository,
    required this.verifiedMessages,
    required this.directory,
    required this.handshakeManager,
    required this.queue,
    required this.service,
    required this.localNodeId,
  });

  final NativeNetworkTransport native;
  final IdentityVault vault;
  final LocalMessageRepository repository;
  final VerifiedMessageService verifiedMessages;
  final VerifiedBlePeerDirectory directory;
  final NativeMeshHandshakeManager handshakeManager;
  final DurableMeshQueue queue;
  final MeshApplicationService service;
  final String localNodeId;

  bool _started = false;
  bool _disposed = false;

  static Future<NativeMeshRuntime> create({
    required NativeNetworkTransport native,
  }) async {
    final vault = IdentityVault();
    final repository = LocalMessageRepository();
    final identity = await vault.loadOrCreateIdentity();
    final localNodeId = await meshNodeIdForKeys(
      signingPublicKey: identity.signingPublicKey,
      encryptionPublicKey: identity.encryptionPublicKey,
    );
    final verifiedMessages = VerifiedMessageService(
      vault: vault,
      replayStore: ReplayProtectionStore(),
    );
    final directory = VerifiedBlePeerDirectory();
    final handshake = MeshIdentityHandshake(vault: vault, directory: directory);
    final handshakeManager = NativeMeshHandshakeManager(
      native: native,
      handshake: handshake,
      directory: directory,
      trustedContacts: vault.listVerifiedContacts,
    );
    final nativePeerTransport = NativeMeshPeerTransport(
      native: native,
      directory: directory,
    );
    final engine = MeshRoutingEngine(localNodeId: localNodeId);
    final queue = DurableMeshQueue();
    final durableRouter = DurableMeshRouter(engine: engine, queue: queue);
    final adapter = MeshTransportAdapter(
      engine: engine,
      transport: nativePeerTransport,
      durableRouter: durableRouter,
    );
    final receiver = NativeMeshFrameReceiver(
      native: native,
      directory: directory,
    );
    final ingress = AuthenticatedMeshIngress(
      receiver: receiver,
      router: adapter,
      verifiedMessages: verifiedMessages,
      trustedContacts: vault.listVerifiedContacts,
      localNodeId: localNodeId,
    );
    final service = MeshApplicationService(
      localNodeId: localNodeId,
      vault: vault,
      verifiedMessages: verifiedMessages,
      adapter: adapter,
      ingress: ingress,
      messageStore: SqlCipherMeshApplicationMessageStore(repository),
    );

    return NativeMeshRuntime._(
      native: native,
      vault: vault,
      repository: repository,
      verifiedMessages: verifiedMessages,
      directory: directory,
      handshakeManager: handshakeManager,
      queue: queue,
      service: service,
      localNodeId: localNodeId,
    );
  }

  /// Start only the authenticated BLE identity control channel. The chat page
  /// owns [service.start] and its UI event subscription.
  Future<void> start() async {
    if (_disposed) throw StateError('Native mesh runtime is disposed.');
    if (_started) return;
    await handshakeManager.start();
    _started = true;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await handshakeManager.dispose();
    await service.dispose();
    await queue.close();
    await repository.close();
  }
}
