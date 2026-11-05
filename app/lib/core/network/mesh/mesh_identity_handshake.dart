import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../../security/contact_identity.dart';
import '../../security/identity_vault.dart';
import 'native_mesh_peer_transport.dart';

const int meshHandshakeVersion = 1;
const int _meshNonceBytes = 32;
const int _maxOutstandingChallenges = 256;
const Duration _challengeLifetime = Duration(minutes: 2);
const List<int> _handshakeDomain = <int>[
  0x49, 0x6e, 0x4c, 0x69, 0x6e, 0x6b, 0x2d, 0x4d,
  0x65, 0x73, 0x68, 0x2d, 0x48, 0x53, 0x4b, 0x2d, 0x76, 0x31, 0x00,
];

/// Stable pseudonymous node identifier derived from the two public identity keys.
/// It is not a BLE address and contains no account or phone-number information.
Future<String> meshNodeIdForKeys({
  required List<int> signingPublicKey,
  required List<int> encryptionPublicKey,
}) async {
  if (signingPublicKey.length != 32 || encryptionPublicKey.length != 32) {
    throw const FormatException('Mesh identity keys must each be 32 bytes.');
  }
  final digest = await Sha256().hash(<int>[
    ..._handshakeDomain,
    ...signingPublicKey,
    ...encryptionPublicKey,
  ]);
  return base64UrlEncode(digest.bytes).replaceAll('=', '');
}

/// Signed challenge proof. The challenge is fresh, expires quickly, and is
/// consumed on verification attempt. This authenticates a previously trusted
/// contact; it does not establish trust in arbitrary QR or radio identities.
class MeshIdentityHandshake {
  MeshIdentityHandshake({
    required this.vault,
    required this.directory,
    Random? random,
    DateTime Function()? clock,
  })  : _random = random ?? Random.secure(),
        _clock = clock ?? DateTime.now;

  final IdentityVault vault;
  final VerifiedBlePeerDirectory directory;
  final Random _random;
  final DateTime Function() _clock;
  final Map<String, DateTime> _outstanding = <String, DateTime>{};

  String createChallenge() {
    _pruneChallenges();
    if (_outstanding.length >= _maxOutstandingChallenges) {
      throw StateError('Too many outstanding mesh identity challenges.');
    }
    final bytes = List<int>.generate(_meshNonceBytes, (_) => _random.nextInt(256));
    final challenge = base64UrlEncode(bytes).replaceAll('=', '');
    _outstanding[challenge] = _clock().toUtc().add(_challengeLifetime);
    return challenge;
  }

  /// Creates a signed proof for a challenge received over the active BLE link.
  Future<String> createProof(String challenge) async {
    _decodeNonce(challenge);
    final identity = await vault.loadOrCreateIdentity();
    final nodeId = await meshNodeIdForKeys(
      signingPublicKey: identity.signingPublicKey,
      encryptionPublicKey: identity.encryptionPublicKey,
    );
    final unsigned = <String, Object>{
      'version': meshHandshakeVersion,
      'challenge': challenge,
      'node_id': nodeId,
      'signing_key': base64UrlEncode(identity.signingPublicKey),
      'encryption_key': base64UrlEncode(identity.encryptionPublicKey),
    };
    final signature = await Ed25519().sign(
      _canonicalProof(unsigned),
      keyPair: identity.signingKeyPair,
    );
    return jsonEncode(<String, Object>{
      ...unsigned,
      'signature': base64UrlEncode(signature.bytes),
    });
  }

  /// Verifies the challenge, proof signature, deterministic node ID and pinned
  /// contact keys before binding a BLE address to a node ID.
  Future<VerifiedInLinkContact> verifyAndBind({
    required String bleAddress,
    required String expectedChallenge,
    required String encodedProof,
    required List<VerifiedInLinkContact> trustedContacts,
  }) async {
    final expires = _outstanding.remove(expectedChallenge);
    if (expires == null || !_validChallenge(expectedChallenge)) {
      throw const FormatException('Unknown or already-used mesh challenge.');
    }
    if (!_clock().toUtc().isBefore(expires)) {
      throw const FormatException('Mesh identity challenge expired.');
    }
    if (encodedProof.length > 2048) {
      throw const FormatException('Mesh identity proof exceeds size limit.');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(encodedProof);
    } on FormatException {
      throw const FormatException('Malformed mesh identity proof.');
    }
    const expectedKeys = <String>{
      'version', 'challenge', 'node_id', 'signing_key',
      'encryption_key', 'signature',
    };
    if (decoded is! Map<String, dynamic> ||
        decoded.length != expectedKeys.length ||
        !decoded.keys.toSet().containsAll(expectedKeys) ||
        decoded['version'] != meshHandshakeVersion ||
        decoded['challenge'] != expectedChallenge ||
        decoded.values.any((value) => value is! String && value is! int)) {
      throw const FormatException('Unsupported mesh identity proof.');
    }
    final signingEncoded = decoded['signing_key'] as String;
    final encryptionEncoded = decoded['encryption_key'] as String;
    final signatureEncoded = decoded['signature'] as String;
    final nodeId = decoded['node_id'] as String;
    final signingKey = _decodeKey(signingEncoded, 32, 'signing key');
    final encryptionKey = _decodeKey(encryptionEncoded, 32, 'encryption key');
    final signatureBytes = _decodeKey(signatureEncoded, 64, 'signature');

    final computedNodeId = await meshNodeIdForKeys(
      signingPublicKey: signingKey,
      encryptionPublicKey: encryptionKey,
    );
    if (nodeId != computedNodeId) {
      throw const FormatException('Mesh node ID does not match public identity keys.');
    }

    VerifiedInLinkContact? matched;
    for (final contact in trustedContacts) {
      if (_constantTimeEquals(contact.signingPublicKey, signingKey) &&
          _constantTimeEquals(contact.encryptionPublicKey, encryptionKey)) {
        matched = contact;
        break;
      }
    }
    if (matched == null) {
      throw const FormatException('Mesh peer is not a previously verified contact.');
    }
    final fingerprint = await fingerprintForPublicKeys(
      signingPublicKey: signingKey,
      encryptionPublicKey: encryptionKey,
    );
    if (!_normalize(matched.fingerprint).contains(_normalize(fingerprint)) ||
        _normalize(matched.fingerprint) != _normalize(fingerprint)) {
      throw const FormatException('Trusted contact fingerprint mismatch.');
    }

    final validSignature = await Ed25519().verify(
      _canonicalProof(<String, Object>{
        'version': meshHandshakeVersion,
        'challenge': expectedChallenge,
        'node_id': nodeId,
        'signing_key': signingEncoded,
        'encryption_key': encryptionEncoded,
      }),
      signature: Signature(
        signatureBytes,
        publicKey: SimplePublicKey(signingKey, type: KeyPairType.ed25519),
      ),
    );
    if (!validSignature) {
      throw const FormatException('Mesh identity proof signature is invalid.');
    }

    directory.bindAfterAuthentication(nodeId: nodeId, bleAddress: bleAddress);
    return matched;
  }

  /// Cancels a locally issued challenge when its transport send fails or the
  /// associated BLE link disconnects before a proof can arrive.
  void cancelChallenge(String challenge) => _outstanding.remove(challenge);

  void forgetPeer(String nodeId) => directory.removeNode(nodeId);

  void _pruneChallenges() {
    final now = _clock().toUtc();
    _outstanding.removeWhere((_, expiry) => !now.isBefore(expiry));
  }

  static List<int> _canonicalProof(Map<String, Object> fields) =>
      <int>[..._handshakeDomain, ...utf8.encode(jsonEncode(fields))];

  static List<int> _decodeKey(String encoded, int length, String label) {
    try {
      final decoded = base64Url.decode(base64Url.normalize(encoded));
      if (decoded.length != length) throw const FormatException();
      return decoded;
    } on FormatException {
      throw FormatException('Invalid mesh $label encoding.');
    }
  }

  static List<int> _decodeNonce(String challenge) {
    final nonce = _decodeKey(challenge, _meshNonceBytes, 'challenge');
    if (base64UrlEncode(nonce).replaceAll('=', '') != challenge) {
      throw const FormatException('Non-canonical mesh challenge.');
    }
    return nonce;
  }

  static bool _validChallenge(String challenge) {
    try {
      _decodeNonce(challenge);
      return true;
    } on FormatException {
      return false;
    }
  }

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}
