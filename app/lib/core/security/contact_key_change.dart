import 'contact_identity.dart';

/// Detects a display-name collision where the public identity differs.
/// This is a warning signal, not proof of impersonation.
bool hasDifferentKeyForSameName({
  required Iterable<VerifiedInLinkContact> existingContacts,
  required VerifiedInLinkContact candidate,
}) {
  final normalizedName = candidate.displayName.trim().toLowerCase();
  final normalizedFingerprint = candidate.fingerprint.toLowerCase();
  return existingContacts.any((contact) =>
      contact.displayName.trim().toLowerCase() == normalizedName &&
      contact.fingerprint.toLowerCase() != normalizedFingerprint);
}
