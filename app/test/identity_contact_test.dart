import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inlink/core/security/contact_identity.dart';
import 'package:inlink/core/security/secure_message.dart';

void main() {
  group('Identity storage serialization', () {
    test('restores the same public identity after serialization', () async {
      final identity = await IdentityKeyMaterial.generate();
      final beforeFingerprint = await identity.fingerprint();
      final restored = await IdentityKeyMaterial.fromPrivateStorageJson(
        await identity.toPrivateStorageJson(),
      );

      expect(restored.signingPublicKey, identity.signingPublicKey);
      expect(restored.encryptionPublicKey, identity.encryptionPublicKey);
      expect(await restored.fingerprint(), beforeFingerprint);
    });

    test('rejects an unsupported or malformed private identity record', () async {
      await expectLater(
        IdentityKeyMaterial.fromPrivateStorageJson(jsonEncode({'version': 99})),
        throwsFormatException,
      );
      await expectLater(
        IdentityKeyMaterial.fromPrivateStorageJson(
          jsonEncode({
            'version': 1,
            'signingPrivateKey': base64UrlEncode([1]),
            'signingPublicKey': base64UrlEncode(List<int>.filled(32, 1)),
            'encryptionPrivateKey': base64UrlEncode(List<int>.filled(32, 1)),
            'encryptionPublicKey': base64UrlEncode(List<int>.filled(32, 1)),
          }),
        ),
        throwsFormatException,
      );
    });
  });

  group('Contact verification', () {
    test('bundle round trip requires fingerprint confirmation', () async {
      final identity = await IdentityKeyMaterial.generate();
      final contact = InLinkPublicContact.parseBundle(
        jsonEncode(identity.publicBundleJson()),
      );
      expect(contact.signingPublicKey, identity.signingPublicKey);
      expect(contact.encryptionPublicKey, identity.encryptionPublicKey);

      final fingerprint = await contact.fingerprint();
      final verified = await contact.verifyFingerprint(
        displayName: 'Alice',
        fingerprintEnteredByUser: fingerprint.toUpperCase(),
      );
      expect(verified.displayName, 'Alice');
      expect(fingerprint.split(':').length, 16);
      expect(verified.fingerprint, fingerprint);

      final restored = VerifiedInLinkContact.fromJson(verified.toJson());
      expect(restored.fingerprint, verified.fingerprint);
      expect(restored.displayName, 'Alice');
    });

    test('wrong fingerprint is never accepted as a trusted contact', () async {
      final identity = await IdentityKeyMaterial.generate();
      final contact = InLinkPublicContact.parseBundle(
        jsonEncode(identity.publicBundleJson()),
      );
      await expectLater(
        contact.verifyFingerprint(
          displayName: 'Alice',
          fingerprintEnteredByUser: '00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00',
        ),
        throwsFormatException,
      );
    });

    test('rejects malformed public contact bundles', () {
      expect(
        () => InLinkPublicContact.parseBundle('{"version":1}'),
        throwsFormatException,
      );
      expect(
        () => InLinkPublicContact.parseBundle(List<String>.filled(2049, 'x').join()),
        throwsFormatException,
      );
      expect(
        () => InLinkPublicContact.parseBundle(
          '{"version":1,"signingKey":"AA==","encryptionKey":"AA==","extra":true}',
        ),
        throwsFormatException,
      );
    });
  });
}
