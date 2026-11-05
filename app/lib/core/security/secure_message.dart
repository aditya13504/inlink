import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

Future<Uint8List> _extractPrivateKeyBytes(KeyPair keyPair) async {
  final extracted = await keyPair.extract();
  if (extracted is! SimpleKeyPairData) {
    throw StateError(
      'Cryptography provider returned an unsupported key pair.',
    );
  }
  return Uint8List.fromList(await extracted.extractPrivateKeyBytes());
}

/// Experimental InLink v1 identity key material.
///
/// This object keeps private keys in memory only. Persistent storage, platform
/// secure storage, key rotation, and account recovery are not implemented.
class IdentityKeyMaterial {
  IdentityKeyMaterial._({
    required this.signingKeyPair,
    required this.encryptionKeyPair,
    required this.signingPublicKey,
    required this.encryptionPublicKey,
  });

  final KeyPair signingKeyPair;
  final KeyPair encryptionKeyPair;
  final Uint8List signingPublicKey;
  final Uint8List encryptionPublicKey;

  static Future<IdentityKeyMaterial> generate() async {
    final signingPair = await Ed25519().newKeyPair();
    final encryptionPair = await X25519().newKeyPair();
    final signingPublic = await signingPair.extractPublicKey();
    final encryptionPublic = await encryptionPair.extractPublicKey();

    if (signingPublic.bytes.length != 32 || encryptionPublic.bytes.length != 32) {
      throw StateError('Unexpected public-key length from cryptography provider.');
    }

    return IdentityKeyMaterial._(
      signingKeyPair: signingPair,
      encryptionKeyPair: encryptionPair,
      signingPublicKey: Uint8List.fromList(signingPublic.bytes),
      encryptionPublicKey: Uint8List.fromList(encryptionPublic.bytes),
    );
  }

  Map<String, Object> publicBundleJson() => <String, Object>{
        'version': 1,
        'signingKey': base64UrlEncode(signingPublicKey),
        'encryptionKey': base64UrlEncode(encryptionPublicKey),
      };

  Future<String> fingerprint() async {
    final hash = await Sha256().hash(<int>[
      ...signingPublicKey,
      ...encryptionPublicKey,
    ]);
    return hash.bytes
        .take(16)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(':');
  }

  /// Exports key material for storage in an OS-backed secure storage service.
  /// Never write this JSON to ordinary files, logs, analytics, or backups.
  Future<String> toPrivateStorageJson() async {
    final signingPrivate = await _extractPrivateKeyBytes(signingKeyPair);
    final encryptionPrivate = await _extractPrivateKeyBytes(encryptionKeyPair);
    return jsonEncode(<String, Object>{
      'version': 1,
      'signingPrivateKey': base64UrlEncode(signingPrivate),
      'signingPublicKey': base64UrlEncode(signingPublicKey),
      'encryptionPrivateKey': base64UrlEncode(encryptionPrivate),
      'encryptionPublicKey': base64UrlEncode(encryptionPublicKey),
    });
  }

  /// Reconstructs key objects from a value obtained from secure storage.
  /// Callers must not use this method with arbitrary untrusted JSON.
  static Future<IdentityKeyMaterial> fromPrivateStorageJson(String encoded) async {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
      throw const FormatException('Unsupported identity storage format.');
    }

    Uint8List readKey(String name) {
      final value = decoded[name];
      if (value is! String) throw FormatException('Missing identity key: $name');
      final bytes = Uint8List.fromList(base64Url.decode(value));
      if (bytes.length != 32) throw FormatException('Invalid identity key length: $name');
      return bytes;
    }

    final signingPrivate = readKey('signingPrivateKey');
    final signingPublic = readKey('signingPublicKey');
    final encryptionPrivate = readKey('encryptionPrivateKey');
    final encryptionPublic = readKey('encryptionPublicKey');

    final signingPair = SimpleKeyPairData(
      signingPrivate,
      publicKey: SimplePublicKey(signingPublic, type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );
    final encryptionPair = SimpleKeyPairData(
      encryptionPrivate,
      publicKey: SimplePublicKey(encryptionPublic, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );

    return IdentityKeyMaterial._(
      signingKeyPair: signingPair,
      encryptionKeyPair: encryptionPair,
      signingPublicKey: signingPublic,
      encryptionPublicKey: encryptionPublic,
    );
  }
}

/// Signed, authenticated-encryption envelope for a single recipient.
///
/// Wire encoding is JSON/base64url for inspectability in this prototype.
/// The canonical bytes used for AAD/signatures are built explicitly and do not
/// depend on JSON map ordering.
class EncryptedMessageEnvelope {
  EncryptedMessageEnvelope._({
    required this.senderSigningPublicKey,
    required this.recipientEncryptionPublicKey,
    required this.ephemeralPublicKey,
    required this.salt,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
    required this.signature,
  });

  static const int protocolVersion = 1;
  static const int maxPlaintextBytes = 16 * 1024;
  static const int _publicKeyBytes = 32;
  static const int _saltBytes = 32;
  static const int _nonceBytes = 12;
  static const int _macBytes = 16;
  static const int _signatureBytes = 64;
  static const List<int> _domain = <int>[
    0x49, 0x6E, 0x4C, 0x69, 0x6E, 0x6B, 0x2D, 0x45,
    0x32, 0x45, 0x45, 0x2D, 0x76, 0x31, 0x00,
  ]; // "InLink-E2EE-v1\0"

  final Uint8List senderSigningPublicKey;
  final Uint8List recipientEncryptionPublicKey;
  final Uint8List ephemeralPublicKey;
  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List mac;
  final Uint8List signature;

  static final X25519 _x25519 = X25519();
  static final Ed25519 _ed25519 = Ed25519();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final Chacha20 _chacha = Chacha20.poly1305Aead();

  static Uint8List _secureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256), growable: false),
    );
  }

  static Uint8List _header({
    required List<int> senderSigningPublicKey,
    required List<int> recipientEncryptionPublicKey,
    required List<int> ephemeralPublicKey,
    required List<int> salt,
    required List<int> nonce,
  }) {
    return Uint8List.fromList(<int>[
      ..._domain,
      protocolVersion,
      ...senderSigningPublicKey,
      ...recipientEncryptionPublicKey,
      ...ephemeralPublicKey,
      ...salt,
      ...nonce,
    ]);
  }

  static Uint8List _signedBytes({
    required List<int> header,
    required List<int> ciphertext,
    required List<int> mac,
  }) {
    final length = ByteData(4)..setUint32(0, ciphertext.length, Endian.big);
    return Uint8List.fromList(<int>[
      ...header,
      ...length.buffer.asUint8List(),
      ...ciphertext,
      ...mac,
    ]);
  }

  static Future<EncryptedMessageEnvelope> seal({
    required IdentityKeyMaterial sender,
    required List<int> recipientEncryptionPublicKey,
    required List<int> plaintext,
  }) async {
    if (recipientEncryptionPublicKey.length != _publicKeyBytes) {
      throw ArgumentError.value(
        recipientEncryptionPublicKey.length,
        'recipientEncryptionPublicKey',
        'Expected $_publicKeyBytes bytes',
      );
    }
    if (plaintext.isEmpty || plaintext.length > maxPlaintextBytes) {
      throw ArgumentError.value(
        plaintext.length,
        'plaintext',
        'Message must contain 1-$maxPlaintextBytes bytes',
      );
    }

    final ephemeralPair = await _x25519.newKeyPair();
    final ephemeralPublic = await ephemeralPair.extractPublicKey();
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: ephemeralPair,
      remotePublicKey: SimplePublicKey(
        recipientEncryptionPublicKey,
        type: KeyPairType.x25519,
      ),
    );

    final salt = _secureRandomBytes(_saltBytes);
    final nonce = _secureRandomBytes(_nonceBytes);
    final header = _header(
      senderSigningPublicKey: sender.signingPublicKey,
      recipientEncryptionPublicKey: recipientEncryptionPublicKey,
      ephemeralPublicKey: ephemeralPublic.bytes,
      salt: salt,
      nonce: nonce,
    );
    final messageKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: salt,
      info: _domain,
    );
    final box = await _chacha.encrypt(
      plaintext,
      secretKey: messageKey,
      nonce: nonce,
      aad: header,
    );
    final toSign = _signedBytes(
      header: header,
      ciphertext: box.cipherText,
      mac: box.mac.bytes,
    );
    final signature = await _ed25519.sign(toSign, keyPair: sender.signingKeyPair);

    return EncryptedMessageEnvelope._(
      senderSigningPublicKey: Uint8List.fromList(sender.signingPublicKey),
      recipientEncryptionPublicKey: Uint8List.fromList(recipientEncryptionPublicKey),
      ephemeralPublicKey: Uint8List.fromList(ephemeralPublic.bytes),
      salt: salt,
      nonce: nonce,
      ciphertext: Uint8List.fromList(box.cipherText),
      mac: Uint8List.fromList(box.mac.bytes),
      signature: Uint8List.fromList(signature.bytes),
    );
  }

  /// Verifies the sender against a previously trusted/pinned signing key,
  /// verifies the envelope signature, then decrypts and authenticates payload.
  Future<Uint8List> open({
    required IdentityKeyMaterial recipient,
    required List<int> trustedSenderSigningPublicKey,
  }) async {
    if (trustedSenderSigningPublicKey.length != _publicKeyBytes ||
        senderSigningPublicKey.length != _publicKeyBytes ||
        recipientEncryptionPublicKey.length != _publicKeyBytes ||
        ephemeralPublicKey.length != _publicKeyBytes ||
        salt.length != _saltBytes ||
        nonce.length != _nonceBytes ||
        mac.length != _macBytes ||
        signature.length != _signatureBytes ||
        ciphertext.isEmpty ||
        ciphertext.length > maxPlaintextBytes) {
      throw const FormatException('Invalid InLink encrypted envelope lengths.');
    }
    if (!_constantTimeEquals(senderSigningPublicKey, trustedSenderSigningPublicKey)) {
      throw const FormatException('Sender key does not match the trusted contact key.');
    }
    if (!_constantTimeEquals(recipientEncryptionPublicKey, recipient.encryptionPublicKey)) {
      throw const FormatException('Envelope is addressed to a different recipient key.');
    }

    final header = _header(
      senderSigningPublicKey: senderSigningPublicKey,
      recipientEncryptionPublicKey: recipientEncryptionPublicKey,
      ephemeralPublicKey: ephemeralPublicKey,
      salt: salt,
      nonce: nonce,
    );
    final toSign = _signedBytes(
      header: header,
      ciphertext: ciphertext,
      mac: mac,
    );
    final validSignature = await _ed25519.verify(
      toSign,
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(
          senderSigningPublicKey,
          type: KeyPairType.ed25519,
        ),
      ),
    );
    if (!validSignature) {
      throw const FormatException('Envelope signature verification failed.');
    }

    final recipientPrivateKey =
        await _extractPrivateKeyBytes(recipient.encryptionKeyPair);
    final recipientPair = SimpleKeyPairData(
      recipientPrivateKey,
      publicKey: SimplePublicKey(
        recipient.encryptionPublicKey,
        type: KeyPairType.x25519,
      ),
      type: KeyPairType.x25519,
    );
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: recipientPair,
      remotePublicKey: SimplePublicKey(
        ephemeralPublicKey,
        type: KeyPairType.x25519,
      ),
    );
    final messageKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: salt,
      info: _domain,
    );

    final box = SecretBox(
      ciphertext,
      nonce: nonce,
      mac: Mac(mac),
    );
    final plaintext = await _chacha.decrypt(
      box,
      secretKey: messageKey,
      aad: header,
    );
    if (plaintext.isEmpty || plaintext.length > maxPlaintextBytes) {
      throw const FormatException('Decrypted message size is invalid.');
    }
    return Uint8List.fromList(plaintext);
  }

  Map<String, Object> toJson() => <String, Object>{
        'version': protocolVersion,
        'senderSigningPublicKey': base64UrlEncode(senderSigningPublicKey),
        'recipientEncryptionPublicKey': base64UrlEncode(recipientEncryptionPublicKey),
        'ephemeralPublicKey': base64UrlEncode(ephemeralPublicKey),
        'salt': base64UrlEncode(salt),
        'nonce': base64UrlEncode(nonce),
        'ciphertext': base64UrlEncode(ciphertext),
        'mac': base64UrlEncode(mac),
        'signature': base64UrlEncode(signature),
      };

  String encode() => jsonEncode(toJson());

  static EncryptedMessageEnvelope decode(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic> || decoded['version'] != protocolVersion) {
      throw const FormatException('Unsupported or invalid envelope version.');
    }

    Uint8List bytes(String field, {required int exactLength, int? maxLength}) {
      final value = decoded[field];
      if (value is! String) throw FormatException('Missing envelope field: $field');
      final parsed = Uint8List.fromList(base64Url.decode(value));
      if (parsed.length < (exactLength == -1 ? 1 : exactLength) ||
          (exactLength != -1 && parsed.length != exactLength) ||
          (maxLength != null && parsed.length > maxLength)) {
        throw FormatException('Invalid envelope field length: $field');
      }
      return parsed;
    }

    return EncryptedMessageEnvelope._(
      senderSigningPublicKey: bytes('senderSigningPublicKey', exactLength: 32),
      recipientEncryptionPublicKey: bytes('recipientEncryptionPublicKey', exactLength: 32),
      ephemeralPublicKey: bytes('ephemeralPublicKey', exactLength: 32),
      salt: bytes('salt', exactLength: 32),
      nonce: bytes('nonce', exactLength: 12),
      ciphertext: bytes('ciphertext', exactLength: -1, maxLength: maxPlaintextBytes),
      mac: bytes('mac', exactLength: 16),
      signature: bytes('signature', exactLength: 64),
    );
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}
