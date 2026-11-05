import 'package:flutter_test/flutter_test.dart';
import 'package:inlink/core/network/relay/relay_client.dart';
import 'package:inlink/core/security/secure_message.dart';

void main() {
  group('RelayClient protocol helpers', () {
    test('derives a 43-character URL-safe identity ID from a signing key', () async {
      final identity = await IdentityKeyMaterial.generate();
      final id = await RelayClient.identityId(identity.signingPublicKey);
      expect(id, hasLength(43));
      expect(id, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(await RelayClient.identityId(identity.signingPublicKey), id);
    });


    test('derives stable URL-safe relay IDs from exact envelope bytes', () async {
      final first = await RelayClient.messageIdForEnvelope('opaque-envelope');
      final same = await RelayClient.messageIdForEnvelope('opaque-envelope');
      final changed = await RelayClient.messageIdForEnvelope('different-envelope');
      expect(first, hasLength(43));
      expect(first, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(same, first);
      expect(changed, isNot(first));
    });

    test('requires HTTPS except for loopback development URLs', () {
      expect(() => RelayClient('http://relay.example.com'), throwsFormatException);
      expect(() => RelayClient('https://relay.example.com/path?token=x'), throwsFormatException);
      final local = RelayClient('http://127.0.0.1:8000');
      local.close();
      final secure = RelayClient('https://relay.example.com');
      secure.close();
    });

    test('rejects URLs containing credentials or fragments', () {
      expect(() => RelayClient('https://user:pass@relay.example.com'), throwsFormatException);
      expect(() => RelayClient('https://relay.example.com/#frag'), throwsFormatException);
    });
  });
}
