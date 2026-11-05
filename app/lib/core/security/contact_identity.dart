import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Returns a 128-bit display fingerprint for the pair of public identity keys.
Future<String> fingerprintForPublicKeys({
  required List<int> signingPublicKey,
  required List<int> encryptionPublicKey,
}) async {
  if (signingPublicKey.length != 32 || encryptionPublicKey.length != 32) {
    throw const FormatException('Contact public keys must each be 32 bytes.');
  }
  final digest = await Sha256().hash(<int>[
    ...signingPublicKey,
    ...encryptionPublicKey,
  ]);
  return digest.bytes
      .take(16)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join(':');
}

/// Public, shareable identity information. Importing a bundle does not make it
/// trusted; the user must compare its fingerprint over a separate channel.
class InLinkPublicContact {
  InLinkPublicContact({
    required this.signingPublicKey,
    required this.encryptionPublicKey,
  }) {
    if (signingPublicKey.length != 32 || encryptionPublicKey.length != 32) {
      throw const FormatException('Contact public keys must each be 32 bytes.');
    }
  }

  final List<int> signingPublicKey;
  final List<int> encryptionPublicKey;

  static InLinkPublicContact parseBundle(String encoded) {
    // A public identity bundle is tiny. Bound input before JSON parsing so
    // arbitrary QR/paste content cannot create unbounded parser work.
    if (encoded.length > 2048) {
      throw const FormatException('Contact bundle is too large.');
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != 1 ||
        decoded.length != 3 ||
        !decoded.keys.toSet().containsAll(
          const <String>{'version', 'signingKey', 'encryptionKey'},
        )) {
      throw const FormatException('Unsupported InLink contact bundle.');
    }
    final signing = decoded['signingKey'];
    final encryption = decoded['encryptionKey'];
    if (signing is! String || encryption is! String) {
      throw const FormatException('Contact bundle is missing public keys.');
    }
    try {
      return InLinkPublicContact(
        signingPublicKey: base64Url.decode(signing),
        encryptionPublicKey: base64Url.decode(encryption),
      );
    } on FormatException {
      throw const FormatException('Contact bundle contains invalid base64url keys.');
    }
  }

  String toBundle() => jsonEncode(<String, Object>{
        'version': 1,
        'signingKey': base64UrlEncode(signingPublicKey),
        'encryptionKey': base64UrlEncode(encryptionPublicKey),
      });

  Future<String> fingerprint() => fingerprintForPublicKeys(
        signingPublicKey: signingPublicKey,
        encryptionPublicKey: encryptionPublicKey,
      );

  /// Creates a trusted contact only if the user-supplied fingerprint matches
  /// the bundle fingerprint. Compare this value out of band before accepting.
  Future<VerifiedInLinkContact> verifyFingerprint({
    required String displayName,
    required String fingerprintEnteredByUser,
  }) async {
    final expected = _normalizeFingerprint(await fingerprint());
    final entered = _normalizeFingerprint(fingerprintEnteredByUser);
    if (entered.isEmpty || entered != expected) {
      throw const FormatException('Fingerprint mismatch; contact was not trusted.');
    }
    final name = displayName.trim();
    if (name.isEmpty || name.length > 80) {
      throw ArgumentError.value(displayName, 'displayName', 'Name must contain 1-80 characters.');
    }
    return VerifiedInLinkContact(
      displayName: name,
      signingPublicKey: List<int>.unmodifiable(signingPublicKey),
      encryptionPublicKey: List<int>.unmodifiable(encryptionPublicKey),
      fingerprint: await fingerprint(),
      verifiedAtUtc: DateTime.now().toUtc(),
    );
  }

  static String _normalizeFingerprint(String input) =>
      input.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
}

class VerifiedInLinkContact {
  const VerifiedInLinkContact({
    required this.displayName,
    required this.signingPublicKey,
    required this.encryptionPublicKey,
    required this.fingerprint,
    required this.verifiedAtUtc,
  });

  final String displayName;
  final List<int> signingPublicKey;
  final List<int> encryptionPublicKey;
  final String fingerprint;
  final DateTime verifiedAtUtc;

  Map<String, Object> toJson() => <String, Object>{
        'version': 1,
        'displayName': displayName,
        'signingPublicKey': base64UrlEncode(signingPublicKey),
        'encryptionPublicKey': base64UrlEncode(encryptionPublicKey),
        'fingerprint': fingerprint,
        'verifiedAtUtc': verifiedAtUtc.toIso8601String(),
      };

  static VerifiedInLinkContact fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 ||
        json['displayName'] is! String ||
        json['signingPublicKey'] is! String ||
        json['encryptionPublicKey'] is! String ||
        json['fingerprint'] is! String ||
        json['verifiedAtUtc'] is! String) {
      throw const FormatException('Invalid saved contact record.');
    }
    final signing = base64Url.decode(json['signingPublicKey'] as String);
    final encryption = base64Url.decode(json['encryptionPublicKey'] as String);
    if (signing.length != 32 || encryption.length != 32) {
      throw const FormatException('Saved contact public key length is invalid.');
    }
    final verifiedAt = DateTime.tryParse(json['verifiedAtUtc'] as String);
    if (verifiedAt == null) throw const FormatException('Invalid contact verification timestamp.');
    final displayName = (json['displayName'] as String).trim();
    final fingerprint = json['fingerprint'] as String;
    if (displayName.isEmpty || displayName.length > 80) {
      throw const FormatException('Saved contact display name is invalid.');
    }
    final normalizedFingerprint =
        fingerprint.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
    if (normalizedFingerprint.length != 32) {
      throw const FormatException('Saved contact fingerprint must be 128 bits.');
    }
    return VerifiedInLinkContact(
      displayName: displayName,
      signingPublicKey: List<int>.unmodifiable(signing),
      encryptionPublicKey: List<int>.unmodifiable(encryption),
      fingerprint: fingerprint,
      verifiedAtUtc: verifiedAt,
    );
  }
}
