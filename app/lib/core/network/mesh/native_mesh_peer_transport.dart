import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../ble/message_frame_transfer.dart';
import '../ble/ble_frame.dart';
import '../native_network_transport.dart';
import 'mesh_transport_adapter.dart';

/// Explicit mapping between authenticated InLink node IDs and ephemeral BLE
/// transport addresses. A caller may bind only after its identity handshake
/// has authenticated the remote node; this class does not perform that handshake.
class VerifiedBlePeerDirectory {
  final Map<String, String> _nodeToAddress = <String, String>{};

  Map<String, String> get snapshot => Map<String, String>.unmodifiable(_nodeToAddress);

  void bindAfterAuthentication({required String nodeId, required String bleAddress}) {
    if (!RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(nodeId)) {
      throw ArgumentError.value(nodeId, 'nodeId', 'Invalid InLink node ID.');
    }
    if (!RegExp(r'^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$').hasMatch(bleAddress)) {
      throw ArgumentError.value(bleAddress, 'bleAddress', 'Expected an Android BLE address.');
    }
    final conflict = _nodeToAddress.entries.any((entry) =>
        entry.key != nodeId && entry.value.toUpperCase() == bleAddress.toUpperCase());
    if (conflict) throw StateError('BLE address is already bound to a different authenticated node.');
    _nodeToAddress[nodeId] = bleAddress.toUpperCase();
  }

  void removeNode(String nodeId) => _nodeToAddress.remove(nodeId);
  String? addressFor(String nodeId) => _nodeToAddress[nodeId];
  String? nodeForAddress(String address) {
    final normalized = address.toUpperCase();
    for (final entry in _nodeToAddress.entries) {
      if (entry.value == normalized) return entry.key;
    }
    return null;
  }
}

/// Android multi-peer BLE transport for opaque mesh packets.
///
/// It fragments packets into the existing 180-byte BLE payload frames. Frame
/// reception/reassembly and authenticated identity binding remain explicit app
/// responsibilities; MAC addresses are never used as node IDs.
class NativeMeshPeerTransport implements MeshPeerTransport {
  NativeMeshPeerTransport({
    required this.native,
    required this.directory,
    Random? random,
  }) : _random = random ?? Random.secure();

  final NativeNetworkTransport native;
  final VerifiedBlePeerDirectory directory;
  final Random _random;

  @override
  Future<Set<String>> connectedPeerIds() async {
    final connected = (await native.getConnectedPeers()).map((value) => value.toUpperCase()).toSet();
    return directory.snapshot.entries
        .where((entry) => connected.contains(entry.value))
        .map((entry) => entry.key)
        .toSet();
  }

  @override
  Future<bool> sendPacket({required String peerId, required String encodedPacket}) async {
    final address = directory.addressFor(peerId);
    if (address == null) return false;
    final connected = (await native.getConnectedPeers()).map((value) => value.toUpperCase()).toSet();
    if (!connected.contains(address)) return false;
    final bytes = utf8.encode(encodedPacket);
    final transferId = _random.nextInt(0x100000000);
    final frames = MessageFrameTransfer.fragment(messageBytes: bytes, transferId: transferId);
    // Sequential sends preserve per-transfer fragment order on the single
    // native queue. Local acceptance is not end-to-end delivery.
    for (final frame in frames) {
      await native.sendBleFrameToPeer(peer: address, frame: Uint8List.fromList(frame));
    }
    return true;
  }
}


class NativeMeshPacketEvent {
  const NativeMeshPacketEvent({required this.fromPeerId, required this.encodedPacket});
  final String fromPeerId;
  final String encodedPacket;
}

/// Reassembles native frame events per BLE address and emits complete packet
/// strings only for peers already bound to authenticated InLink identities.
/// The caller must still validate the mesh packet and E2EE envelope.
class NativeMeshFrameReceiver {
  NativeMeshFrameReceiver({required this.native, required this.directory});
  final NativeNetworkTransport native;
  final VerifiedBlePeerDirectory directory;
  final Map<String, MessageFrameReassembler> _reassemblers = <String, MessageFrameReassembler>{};

  Stream<NativeMeshPacketEvent> receivePackets() async* {
    await for (final event in native.events) {
      final type = event['type'];
      final rawPeer = event['peer'];
      if (rawPeer is! String) continue;
      final address = rawPeer.toUpperCase();
      if (type == 'peerDisconnected') {
        _reassemblers.remove(address)?.clear();
        continue;
      }
      if (type != 'frameReceived') continue;
      final nodeId = directory.nodeForAddress(address);
      if (nodeId == null) continue;
      final rawFrame = event['frame'];
      if (rawFrame is! List || rawFrame.isEmpty || rawFrame.any((value) => value is! int || value < 0 || value > 255)) continue;
      try {
        final frameBytes = rawFrame.cast<int>();
        BleFrame.decode(frameBytes); // strict early validation before buffering
        final reassembler = _reassemblers.putIfAbsent(address, MessageFrameReassembler.new);
        final complete = reassembler.accept(frameBytes);
        if (complete == null) continue;
        final packet = utf8.decode(complete, allowMalformed: false);
        yield NativeMeshPacketEvent(fromPeerId: nodeId, encodedPacket: packet);
      } on FormatException {
        // Malformed or conflicting fragments are discarded without routing.
      } on ArgumentError {
        // Invalid frame fields are untrusted transport input.
      }
    }
  }

  void clear() {
    for (final reassembler in _reassemblers.values) {
      reassembler.clear();
    }
    _reassemblers.clear();
  }
}
