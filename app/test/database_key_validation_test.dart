import 'package:flutter_test/flutter_test.dart';
import 'package:inlink/core/messaging/database_key_validation.dart';

void main() {
  group('validateExistingDatabaseKey', () {
    test('returns null when no key exists so first launch can create one', () {
      expect(validateExistingDatabaseKey(null), isNull);
    });

    test('accepts a 32-byte base64url key without padding', () {
      const key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      expect(key, hasLength(43));
      expect(validateExistingDatabaseKey(key), key);
    });

    test('rejects a short persisted key instead of silently replacing it', () {
      expect(
        () => validateExistingDatabaseKey('short'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects padded or non-base64url characters', () {
      expect(
        () => validateExistingDatabaseKey('${List<String>.filled(42, 'A').join()}='),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => validateExistingDatabaseKey('${List<String>.filled(42, 'A').join()}+'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
