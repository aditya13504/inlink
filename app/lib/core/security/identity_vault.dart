import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'contact_identity.dart';
import 'secure_message.dart';

/// Stores identity secrets using platform-provided secure storage.
///
/// Android uses encrypted preferences backed by Android Keystore through the
/// plugin; iOS uses Keychain. Device configuration, backups and OS security
/// still affect the real security properties. This class never logs secrets.
class IdentityVault {
  IdentityVault({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _identityKey = 'inlink.identity.v1';
  static const String _contactsKey = 'inlink.verified_contacts.v1';

  final FlutterSecureStorage _storage;

  Future<IdentityKeyMaterial?> loadIdentity() async {
    final encoded = await _storage.read(key: _identityKey);
    if (encoded == null) return null;
    return IdentityKeyMaterial.fromPrivateStorageJson(encoded);
  }

  /// Generates and saves an identity only when no identity is stored.
  /// Existing identity is preserved to avoid accidental identity rotation.
  Future<IdentityKeyMaterial> loadOrCreateIdentity() async {
    final existing = await loadIdentity();
    if (existing != null) return existing;
    final generated = await IdentityKeyMaterial.generate();
    await _storage.write(
      key: _identityKey,
      value: await generated.toPrivateStorageJson(),
    );
    return generated;
  }

  Future<void> saveVerifiedContact(VerifiedInLinkContact contact) async {
    final contacts = await listVerifiedContacts();
    final key = contact.fingerprint.toLowerCase();
    contacts.removeWhere((item) => item.fingerprint.toLowerCase() == key);
    contacts.add(contact);
    await _storage.write(
      key: _contactsKey,
      value: jsonEncode(contacts.map((item) => item.toJson()).toList()),
    );
  }

  Future<List<VerifiedInLinkContact>> listVerifiedContacts() async {
    final encoded = await _storage.read(key: _contactsKey);
    if (encoded == null) return <VerifiedInLinkContact>[];
    final decoded = jsonDecode(encoded);
    if (decoded is! List) throw const FormatException('Saved contacts store is invalid.');
    return decoded
        .map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('Saved contact record is invalid.');
          }
          return VerifiedInLinkContact.fromJson(item);
        })
        .toList(growable: true);
  }

  Future<void> deleteVerifiedContact(String fingerprint) async {
    final contacts = await listVerifiedContacts();
    contacts.removeWhere(
      (item) => item.fingerprint.toLowerCase() == fingerprint.toLowerCase(),
    );
    await _storage.write(
      key: _contactsKey,
      value: jsonEncode(contacts.map((item) => item.toJson()).toList()),
    );
  }

  /// Destructive. Use only from an explicit user-confirmed identity reset flow.
  Future<void> deleteIdentity() => _storage.delete(key: _identityKey);
}
