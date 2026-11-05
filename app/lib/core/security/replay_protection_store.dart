import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persistent bounded replay cache for already-accepted encrypted envelopes.
///
/// Callers should check before decrypting and record only after authentication
/// and decryption succeed. This storage API is not transactional across
/// concurrent calls; serialize inbound processing in the message repository.
class ReplayProtectionStore {
  ReplayProtectionStore({
    FlutterSecureStorage? storage,
    this.maxEntries = 4096,
  }) : _storage = storage ?? const FlutterSecureStorage() {
    if (maxEntries < 64) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'Must be at least 64.');
    }
  }

  static const String _storageKey = 'inlink.replay_ids.v1';
  final FlutterSecureStorage _storage;
  final int maxEntries;

  Future<String> identifierForEnvelope(String encodedEnvelope) async {
    final digest = await Sha256().hash(utf8.encode(encodedEnvelope));
    return base64UrlEncode(digest.bytes);
  }

  Future<bool> hasSeen(String envelopeId) async {
    final entries = await _readEntries();
    return entries.contains(envelopeId);
  }

  Future<void> recordAccepted(String envelopeId) async {
    if (envelopeId.isEmpty || envelopeId.length > 128) {
      throw ArgumentError.value(envelopeId, 'envelopeId', 'Invalid replay identifier.');
    }
    final entries = await _readEntries();
    if (entries.contains(envelopeId)) return;
    entries.add(envelopeId);
    if (entries.length > maxEntries) {
      entries.removeRange(0, entries.length - maxEntries);
    }
    await _storage.write(key: _storageKey, value: jsonEncode(entries));
  }

  Future<List<String>> _readEntries() async {
    final encoded = await _storage.read(key: _storageKey);
    if (encoded == null) return <String>[];
    final decoded = jsonDecode(encoded);
    if (decoded is! List || decoded.any((item) => item is! String)) {
      throw const FormatException('Replay-protection storage is invalid.');
    }
    return decoded.cast<String>().toList(growable: true);
  }
}
