import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inlink/core/security/secure_message.dart';

void main() {
  group('InLink v1 secure message prototype', () {
    late IdentityKeyMaterial alice;
    late IdentityKeyMaterial bob;

    setUp(() async {
      alice = await IdentityKeyMaterial.generate();
      bob = await IdentityKeyMaterial.generate();
    });

    test('encrypts, signs, serializes and decrypts a message', () async {
      const message = 'hello over an untrusted transport';
      final envelope = await EncryptedMessageEnvelope.seal(
        sender: alice,
        recipientEncryptionPublicKey: bob.encryptionPublicKey,
        plaintext: utf8.encode(message),
      );

      final wire = envelope.encode();
      expect(wire, isNot(contains(message)));
      final parsed = EncryptedMessageEnvelope.decode(wire);
      final plaintext = await parsed.open(
        recipient: bob,
        trustedSenderSigningPublicKey: alice.signingPublicKey,
      );

      expect(utf8.decode(plaintext), message);
    });

    test('rejects a sender key that is not the pinned contact key', () async {
      final envelope = await EncryptedMessageEnvelope.seal(
        sender: alice,
        recipientEncryptionPublicKey: bob.encryptionPublicKey,
        plaintext: utf8.encode('test'),
      );

      final mallory = await IdentityKeyMaterial.generate();
      await expectLater(
        envelope.open(
          recipient: bob,
          trustedSenderSigningPublicKey: mallory.signingPublicKey,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an envelope addressed to a different recipient', () async {
      final envelope = await EncryptedMessageEnvelope.seal(
        sender: alice,
        recipientEncryptionPublicKey: bob.encryptionPublicKey,
        plaintext: utf8.encode('test'),
      );
      final eve = await IdentityKeyMaterial.generate();

      expect(
        () => envelope.open(
          recipient: eve,
          trustedSenderSigningPublicKey: alice.signingPublicKey,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects tampered ciphertext after signing', () async {
      final envelope = await EncryptedMessageEnvelope.seal(
        sender: alice,
        recipientEncryptionPublicKey: bob.encryptionPublicKey,
        plaintext: utf8.encode('tamper test'),
      );
      final map = Map<String, dynamic>.from(envelope.toJson());
      final ciphertext = base64Url.decode(map['ciphertext'] as String);
      ciphertext[0] ^= 1;
      map['ciphertext'] = base64UrlEncode(ciphertext);
      final tampered = EncryptedMessageEnvelope.decode(jsonEncode(map));

      await expectLater(
        tampered.open(
          recipient: bob,
          trustedSenderSigningPublicKey: alice.signingPublicKey,
        ),
        throwsA(anything),
      );
    });

    test('rejects empty plaintext', () async {
      await expectLater(
        EncryptedMessageEnvelope.seal(
          sender: alice,
          recipientEncryptionPublicKey: bob.encryptionPublicKey,
          plaintext: const <int>[],
        ),
        throwsArgumentError,
      );
    });
  });
}
