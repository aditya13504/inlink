import 'dart:async';
import 'dart:convert';
import 'contact_identity.dart';
import 'identity_vault.dart';
import 'replay_protection_store.dart';
import 'secure_message.dart';

/// Narrow integration layer for one-to-one prototype messaging.
///
/// This is not a production messaging protocol: there is no ratchet, key
/// transparency, group messaging, or transactional inbound queue yet.
class VerifiedMessageService {
  VerifiedMessageService({
    required IdentityVault vault,
    required ReplayProtectionStore replayStore,
  })  : _vault = vault,
        _replayStore = replayStore;

  final IdentityVault _vault;
  final ReplayProtectionStore _replayStore;

  // Serialize the whole check -> decrypt -> record transaction to prevent
  // concurrent calls both passing hasSeen before either records acceptance.
  Future<void> _inboundTail = Future<void>.value();

  Future<T> _serializeInbound<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _inboundTail = _inboundTail.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<EncryptedMessageEnvelope> sealToVerifiedContact({
    required VerifiedInLinkContact contact,
    required String plaintext,
  }) async {
    await _assertContactFingerprint(contact);
    final sender = await _vault.loadOrCreateIdentity();
    final bytes = utf8.encode(plaintext);
    return EncryptedMessageEnvelope.seal(
      sender: sender,
      recipientEncryptionPublicKey: contact.encryptionPublicKey,
      plaintext: bytes,
    );
  }

  /// Returns null-free plaintext only after sender pinning, signature
  /// verification, authenticated decryption, and replay checks succeed.
  Future<String> openFromVerifiedContact({
    required VerifiedInLinkContact contact,
    required String encodedEnvelope,
  }) => _serializeInbound(() => _openFromVerifiedContact(
        contact: contact,
        encodedEnvelope: encodedEnvelope,
      ));

  Future<String> _openFromVerifiedContact({
    required VerifiedInLinkContact contact,
    required String encodedEnvelope,
  }) async {
    await _assertContactFingerprint(contact);
    final envelope = EncryptedMessageEnvelope.decode(encodedEnvelope);
    final replayId = await _replayStore.identifierForEnvelope(encodedEnvelope);
    if (await _replayStore.hasSeen(replayId)) {
      throw const FormatException('Duplicate encrypted message rejected.');
    }
    final recipient = await _vault.loadIdentity();
    if (recipient == null) {
      throw StateError('No local InLink identity exists.');
    }
    final plaintext = await envelope.open(
      recipient: recipient,
      trustedSenderSigningPublicKey: contact.signingPublicKey,
    );
    // Record only after successful signature verification and decryption.
    await _replayStore.recordAccepted(replayId);
    return utf8.decode(plaintext, allowMalformed: false);
  }

  Future<void> _assertContactFingerprint(VerifiedInLinkContact contact) async {
    final computed = await fingerprintForPublicKeys(
      signingPublicKey: contact.signingPublicKey,
      encryptionPublicKey: contact.encryptionPublicKey,
    );
    String normalize(String value) =>
        value.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
    if (normalize(computed) != normalize(contact.fingerprint)) {
      throw const FormatException('Contact fingerprint does not match its public keys.');
    }
  }
}
