import 'package:flutter_test/flutter_test.dart';
import 'package:inlink/core/security/contact_identity.dart';

void main() {
  group('Public contact bundle', () {
    test('rejects a malformed bundle without keys', () {
      expect(
        () => InLinkPublicContact.parseBundle('{"version":1}'),
        throwsFormatException,
      );
    });

    test('rejects wrong key sizes', () {
      expect(
        () => InLinkPublicContact(
          signingPublicKey: [1, 2],
          encryptionPublicKey: List<int>.filled(32, 1),
        ),
        throwsFormatException,
      );
    });
  });
}
