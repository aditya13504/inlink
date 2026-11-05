import 'package:flutter_test/flutter_test.dart';
import 'package:inlink/core/security/contact_identity.dart';
import 'package:inlink/core/security/contact_key_change.dart';

VerifiedInLinkContact contact({
  required String name,
  required String fingerprint,
  int keyByte = 1,
}) {
  return VerifiedInLinkContact(
    displayName: name,
    signingPublicKey: List<int>.filled(32, keyByte),
    encryptionPublicKey: List<int>.filled(32, keyByte),
    fingerprint: fingerprint,
    verifiedAtUtc: DateTime.utc(2026),
  );
}

void main() {
  test('detects same name with a different fingerprint', () {
    expect(
      hasDifferentKeyForSameName(
        existingContacts: [contact(name: 'Alice', fingerprint: 'aa:bb')],
        candidate: contact(name: ' alice ', fingerprint: 'cc:dd', keyByte: 2),
      ),
      isTrue,
    );
  });

  test('allows same contact fingerprint and different names', () {
    expect(
      hasDifferentKeyForSameName(
        existingContacts: [contact(name: 'Alice', fingerprint: 'aa:bb')],
        candidate: contact(name: 'Bob', fingerprint: 'cc:dd', keyByte: 2),
      ),
      isFalse,
    );
    expect(
      hasDifferentKeyForSameName(
        existingContacts: [contact(name: 'Alice', fingerprint: 'aa:bb')],
        candidate: contact(name: 'Alice', fingerprint: 'aa:bb'),
      ),
      isFalse,
    );
  });
}
