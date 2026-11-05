import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:inlink/core/network/mesh/mesh_identity_handshake.dart';
import 'package:inlink/core/network/mesh/native_mesh_handshake_manager.dart';
import 'package:inlink/core/network/mesh/native_mesh_peer_transport.dart';
import 'package:inlink/core/network/native_network_transport.dart';
import 'package:inlink/core/security/contact_identity.dart';
import 'package:inlink/core/security/identity_vault.dart';
import 'package:inlink/core/security/secure_message.dart';

const addressA = 'AA:AA:AA:AA:AA:AA';
const addressB = 'BB:BB:BB:BB:BB:BB';

class MemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
    WebOptions? webOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
    WebOptions? webOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

class FakeNativeNetworkTransport extends NativeNetworkTransport {
  FakeNativeNetworkTransport({
    required this.localAddress,
    required this.remoteAddress,
  });

  final String localAddress;
  final String remoteAddress;
  final StreamController<Map<String, Object?>> _events =
      StreamController<Map<String, Object?>>.broadcast();
  FakeNativeNetworkTransport? remote;

  @override
  Stream<Map<String, Object?>> get events => _events.stream;

  @override
  Future<List<String>> getConnectedPeers() async => <String>[remoteAddress];

  void emitReady() => _events.add(<String, Object?>{
        'type': 'readyToSend',
        'peer': remoteAddress,
      });

  @override
  Future<Map<String, Object?>> sendBleFrameToPeer({
    required String peer,
    required Uint8List frame,
  }) async {
    if (peer.toUpperCase() != remoteAddress || remote == null) {
      throw StateError('Fake peer is not connected.');
    }
    remote!._events.add(<String, Object?>{
      'type': 'frameReceived',
      'peer': localAddress,
      'frame': frame.toList(),
    });
    return <String, Object?>{'accepted': true, 'path': 'fake', 'peer': peer};
  }

  Future<void> close() => _events.close();
}

Future<VerifiedInLinkContact> contactFor(
  IdentityKeyMaterial material,
  String name,
) async =>
    VerifiedInLinkContact(
      displayName: name,
      signingPublicKey: material.signingPublicKey,
      encryptionPublicKey: material.encryptionPublicKey,
      fingerprint: await fingerprintForPublicKeys(
        signingPublicKey: material.signingPublicKey,
        encryptionPublicKey: material.encryptionPublicKey,
      ),
      verifiedAtUtc: DateTime.utc(2026, 1, 1),
    );

Future<void> waitForBinding(
  VerifiedBlePeerDirectory directory,
  String address,
) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (directory.nodeForAddress(address) != null) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('mutual native handshake binds both addresses only to trusted identities',
      () async {
    final identityA = await IdentityKeyMaterial.generate();
    final identityB = await IdentityKeyMaterial.generate();
    final storageA = MemorySecureStorage()
      ..values['inlink.identity.v1'] = await identityA.toPrivateStorageJson();
    final storageB = MemorySecureStorage()
      ..values['inlink.identity.v1'] = await identityB.toPrivateStorageJson();
    final vaultA = IdentityVault(storage: storageA);
    final vaultB = IdentityVault(storage: storageB);
    final contactA = await contactFor(identityA, 'Device A');
    final contactB = await contactFor(identityB, 'Device B');

    final nativeA = FakeNativeNetworkTransport(
      localAddress: addressA,
      remoteAddress: addressB,
    );
    final nativeB = FakeNativeNetworkTransport(
      localAddress: addressB,
      remoteAddress: addressA,
    );
    nativeA.remote = nativeB;
    nativeB.remote = nativeA;

    final directoryA = VerifiedBlePeerDirectory();
    final directoryB = VerifiedBlePeerDirectory();
    final managerA = NativeMeshHandshakeManager(
      native: nativeA,
      handshake: MeshIdentityHandshake(vault: vaultA, directory: directoryA),
      directory: directoryA,
      trustedContacts: () async => <VerifiedInLinkContact>[contactB],
    );
    final managerB = NativeMeshHandshakeManager(
      native: nativeB,
      handshake: MeshIdentityHandshake(vault: vaultB, directory: directoryB),
      directory: directoryB,
      trustedContacts: () async => <VerifiedInLinkContact>[contactA],
    );

    await Future.wait(<Future<void>>[managerA.start(), managerB.start()]);
    nativeA.emitReady();
    nativeB.emitReady();

    try {
      await waitForBinding(directoryA, addressB);
      await waitForBinding(directoryB, addressA);
      final nodeA = await meshNodeIdForKeys(
        signingPublicKey: identityA.signingPublicKey,
        encryptionPublicKey: identityA.encryptionPublicKey,
      );
      final nodeB = await meshNodeIdForKeys(
        signingPublicKey: identityB.signingPublicKey,
        encryptionPublicKey: identityB.encryptionPublicKey,
      );
      expect(directoryA.nodeForAddress(addressB), nodeB);
      expect(directoryB.nodeForAddress(addressA), nodeA);
    } finally {
      await managerA.dispose();
      await managerB.dispose();
      await nativeA.close();
      await nativeB.close();
    }
  });
}
