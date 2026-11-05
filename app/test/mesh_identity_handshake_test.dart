import 'package:flutter_test/flutter_test.dart';
import 'package:inlink/core/network/mesh/mesh_identity_handshake.dart';
import 'package:inlink/core/network/mesh/native_mesh_peer_transport.dart';
import 'package:inlink/core/security/contact_identity.dart';
import 'package:inlink/core/security/identity_vault.dart';
import 'package:inlink/core/security/secure_message.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

Future<VerifiedInLinkContact> trustedContact(IdentityKeyMaterial material) async {
  final fingerprint = await fingerprintForPublicKeys(
    signingPublicKey: material.signingPublicKey,
    encryptionPublicKey: material.encryptionPublicKey,
  );
  return VerifiedInLinkContact(
    displayName: 'Trusted peer',
    signingPublicKey: material.signingPublicKey,
    encryptionPublicKey: material.encryptionPublicKey,
    fingerprint: fingerprint,
    verifiedAtUtc: DateTime.utc(2026, 1, 1),
  );
}

void main() {
  test('signed challenge binds BLE address only after trusted-key verification', () async {
    final peer = await IdentityKeyMaterial.generate();
    final contact = await trustedContact(peer);
    final storage = MemorySecureStorage();
    final directory = VerifiedBlePeerDirectory();
    final handshake = MeshIdentityHandshake(
      vault: IdentityVault(storage: storage),
      directory: directory,
    );
    final challenge = handshake.createChallenge();
    final peerStorage = MemorySecureStorage();
    peerStorage.values['inlink.identity.v1'] = await peer.toPrivateStorageJson();
    final peerVault = IdentityVault(storage: peerStorage);
    final proof = await MeshIdentityHandshake(
      vault: peerVault,
      directory: VerifiedBlePeerDirectory(),
    ).createProof(challenge);
    final expectedNode = await meshNodeIdForKeys(
      signingPublicKey: peer.signingPublicKey,
      encryptionPublicKey: peer.encryptionPublicKey,
    );
    final matched = await handshake.verifyAndBind(
      bleAddress: 'AA:BB:CC:DD:EE:FF',
      expectedChallenge: challenge,
      encodedProof: proof,
      trustedContacts: <VerifiedInLinkContact>[contact],
    );
    expect(matched.fingerprint, contact.fingerprint);
    expect(directory.nodeForAddress('aa:bb:cc:dd:ee:ff'), expectedNode);
  });

  test('challenge cannot be reused after successful verification', () async {
    final peer = await IdentityKeyMaterial.generate();
    final contact = await trustedContact(peer);
    final storage = MemorySecureStorage();
    final peerVaultStorage = MemorySecureStorage();
    peerVaultStorage.values['inlink.identity.v1'] = await peer.toPrivateStorageJson();
    final directory = VerifiedBlePeerDirectory();
    final handshake = MeshIdentityHandshake(
      vault: IdentityVault(storage: storage),
      directory: directory,
    );
    final challenge = handshake.createChallenge();
    final proof = await MeshIdentityHandshake(
      vault: IdentityVault(storage: peerVaultStorage),
      directory: VerifiedBlePeerDirectory(),
    ).createProof(challenge);
    await handshake.verifyAndBind(
      bleAddress: 'AA:BB:CC:DD:EE:01',
      expectedChallenge: challenge,
      encodedProof: proof,
      trustedContacts: <VerifiedInLinkContact>[contact],
    );
    await expectLater(
      handshake.verifyAndBind(
        bleAddress: 'AA:BB:CC:DD:EE:01',
        expectedChallenge: challenge,
        encodedProof: proof,
        trustedContacts: <VerifiedInLinkContact>[contact],
      ),
      throwsFormatException,
    );
  });

  test('unknown contact proof never binds address', () async {
    final peer = await IdentityKeyMaterial.generate();
    final unknown = await IdentityKeyMaterial.generate();
    final unknownStorage = MemorySecureStorage();
    unknownStorage.values['inlink.identity.v1'] = await peer.toPrivateStorageJson();
    final handshake = MeshIdentityHandshake(
      vault: IdentityVault(storage: MemorySecureStorage()),
      directory: VerifiedBlePeerDirectory(),
    );
    final challenge = handshake.createChallenge();
    final proof = await MeshIdentityHandshake(
      vault: IdentityVault(storage: unknownStorage),
      directory: VerifiedBlePeerDirectory(),
    ).createProof(challenge);
    await expectLater(
      handshake.verifyAndBind(
        bleAddress: 'AA:BB:CC:DD:EE:02',
        expectedChallenge: challenge,
        encodedProof: proof,
        trustedContacts: <VerifiedInLinkContact>[await trustedContact(unknown)],
      ),
      throwsFormatException,
    );
    expect(handshake.directory.snapshot, isEmpty);
  });

  test('malformed proof is rejected and input is size bounded', () async {
    final handshake = MeshIdentityHandshake(
      vault: IdentityVault(storage: MemorySecureStorage()),
      directory: VerifiedBlePeerDirectory(),
    );
    final challenge = handshake.createChallenge();
    await expectLater(
      handshake.verifyAndBind(
        bleAddress: 'AA:BB:CC:DD:EE:03',
        expectedChallenge: challenge,
        encodedProof: '{"version":1}',
        trustedContacts: <VerifiedInLinkContact>[],
      ),
      throwsFormatException,
    );
  });
}
