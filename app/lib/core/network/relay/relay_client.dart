import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../../security/contact_identity.dart';
import '../../security/secure_message.dart';

const int relayProtocolVersion = 2;
const int relayMaxEnvelopeBytes = 16 * 1024;

/// An envelope fetched from the relay. It remains untrusted until the existing
/// E2EE verification/decryption path accepts it.
class RelayedEnvelope {
  const RelayedEnvelope({
    required this.senderId,
    required this.messageId,
    required this.encodedEnvelope,
    required this.envelopeDigest,
    required this.createdAt,
    required this.expiresAt,
  });

  final String senderId;
  final String messageId;
  final String encodedEnvelope;
  final String envelopeDigest;
  final int createdAt;
  final int expiresAt;
}

class RelayApiException implements Exception {
  const RelayApiException(this.statusCode, this.code);
  final int statusCode;
  final String code;
  @override
  String toString() => 'Relay request failed ($statusCode): $code';
}

/// HTTP client for the experimental M3.4 relay protocol.
/// Only HTTPS is accepted except for loopback development URLs. Relay
/// acceptance never means the recipient has received or decrypted a message.
class RelayClient {
  RelayClient(String baseUrl, {HttpClient? httpClient})
      : baseUri = _validateBaseUri(baseUrl),
        _http = httpClient ?? HttpClient() {
    _http.connectionTimeout = const Duration(seconds: 10);
    _http.idleTimeout = const Duration(seconds: 15);
  }

  final Uri baseUri;
  final HttpClient _http;
  final Ed25519 _ed25519 = Ed25519();
  final Sha256 _sha256 = Sha256();

  static Uri _validateBaseUri(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' && _isLoopback(uri.host))) ||
        uri.userInfo.isNotEmpty || uri.query.isNotEmpty || uri.fragment.isNotEmpty) {
      throw const FormatException(
        'Relay URL must use HTTPS. HTTP is permitted only for localhost/loopback testing.',
      );
    }
    return uri.replace(path: uri.path == '/' ? '' : uri.path);
  }

  static bool _isLoopback(String host) =>
      host.toLowerCase() == 'localhost' ||
      host == '127.0.0.1' || host == '::1' || host == '[::1]';

  static Future<String> identityId(List<int> signingPublicKey) async =>
      _b64u((await Sha256().hash(signingPublicKey)).bytes);

  /// Stable idempotency key for one exact encoded envelope. A retransmission
  /// of the same bytes maps to the same relay ID; a freshly sealed retry gets
  /// a new ID so a previously delivered receipt can be re-processed.
  static Future<String> messageIdForEnvelope(String encodedEnvelope) async =>
      _b64u((await Sha256().hash(utf8.encode(encodedEnvelope))).bytes);

  static String _b64u(List<int> bytes) => base64UrlEncode(bytes).replaceAll('=', '');

  static List<int> _decodeB64u(String value) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw const FormatException('Relay returned invalid base64url data.');
    }
    return base64Url.decode(base64Url.normalize(value));
  }

  String _nonce() {
    final random = Random.secure();
    return _b64u(List<int>.generate(18, (_) => random.nextInt(256)));
  }

  Future<String> _sign(IdentityKeyMaterial identity, String canonical) async {
    final signature = await _ed25519.sign(
      utf8.encode(canonical),
      keyPair: identity.signingKeyPair,
    );
    return _b64u(signature.bytes);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    final uri = baseUri.replace(
      path: '${baseUri.path}$path',
      queryParameters: query,
    );
    final request = await _http.openUrl(method, uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final responseText = await utf8.decoder.bind(response).join();
    Map<String, dynamic> decoded;
    try {
      final value = jsonDecode(responseText);
      if (value is! Map<String, dynamic>) throw const FormatException();
      decoded = value;
    } catch (_) {
      throw RelayApiException(response.statusCode, 'invalid_server_response');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded['detail'];
      throw RelayApiException(response.statusCode, detail is String ? detail : 'http_error');
    }
    if (decoded['protocol_version'] != relayProtocolVersion) {
      throw const RelayApiException(502, 'unsupported_server_protocol');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> submitMessage({
    required IdentityKeyMaterial identity,
    required VerifiedInLinkContact recipient,
    required String messageId,
    required String encodedEnvelope,
    required DateTime expiresAtUtc,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(messageId)) {
      throw const FormatException('Message ID must be 16-64 URL-safe characters.');
    }
    final envelopeBytes = utf8.encode(encodedEnvelope);
    if (envelopeBytes.isEmpty || envelopeBytes.length > relayMaxEnvelopeBytes) {
      throw const FormatException('Encoded envelope exceeds the relay 16 KiB limit.');
    }
    final senderId = await identityId(identity.signingPublicKey);
    final recipientId = await identityId(recipient.signingPublicKey);
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final expiresAt = expiresAtUtc.toUtc().millisecondsSinceEpoch ~/ 1000;
    final nonce = _nonce();
    final digest = _b64u((await _sha256.hash(envelopeBytes)).bytes);
    final canonical = 'INLINK-RELAY-SUBMIT-V2\n$senderId\n$recipientId\n$messageId\n$expiresAt\n$digest\n$timestamp\n$nonce';
    final signature = await _sign(identity, canonical);
    return _request('POST', '/v2/relay/messages', body: <String, Object?>{
      'protocol_version': relayProtocolVersion,
      'sender_id': senderId,
      'recipient_id': recipientId,
      'message_id': messageId,
      'envelope': _b64u(envelopeBytes),
      'expires_at': expiresAt,
      'timestamp': timestamp,
      'nonce': nonce,
      'sender_public_key': _b64u(identity.signingPublicKey),
      'signature': signature,
    });
  }

  Future<List<RelayedEnvelope>> pollMessages({
    required IdentityKeyMaterial identity,
    int limit = 50,
  }) async {
    if (limit < 1 || limit > 100) throw ArgumentError.value(limit, 'limit');
    final recipientId = await identityId(identity.signingPublicKey);
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final nonce = _nonce();
    final canonical = 'INLINK-RELAY-POLL-V2\n$recipientId\n$timestamp\n$nonce\n$limit';
    final signature = await _sign(identity, canonical);
    final response = await _request('POST', '/v2/relay/messages/poll', body: <String, Object?>{
      'protocol_version': relayProtocolVersion,
      'recipient_id': recipientId,
      'recipient_public_key': _b64u(identity.signingPublicKey),
      'timestamp': timestamp,
      'nonce': nonce,
      'signature': signature,
      'limit': limit,
    });
    final rawMessages = response['messages'];
    if (rawMessages is! List) throw const RelayApiException(502, 'invalid_message_list');
    final messages = <RelayedEnvelope>[];
    for (final raw in rawMessages) {
      if (raw is! Map<String, dynamic> ||
          raw['sender_id'] is! String || raw['message_id'] is! String ||
          raw['envelope'] is! String || raw['envelope_digest'] is! String ||
          raw['created_at'] is! int || raw['expires_at'] is! int) {
        throw const RelayApiException(502, 'invalid_relay_message');
      }
      final bytes = _decodeB64u(raw['envelope'] as String);
      if (bytes.isEmpty || bytes.length > relayMaxEnvelopeBytes) {
        throw const RelayApiException(502, 'relay_envelope_size_limit');
      }
      final expectedDigest = _b64u((await _sha256.hash(bytes)).bytes);
      if (expectedDigest != raw['envelope_digest']) {
        throw const RelayApiException(502, 'relay_envelope_digest_mismatch');
      }
      messages.add(RelayedEnvelope(
        senderId: raw['sender_id'] as String,
        messageId: raw['message_id'] as String,
        encodedEnvelope: utf8.decode(bytes, allowMalformed: false),
        envelopeDigest: expectedDigest,
        createdAt: raw['created_at'] as int,
        expiresAt: raw['expires_at'] as int,
      ));
    }
    return messages;
  }

  /// Removes the queued copy only after authenticated E2EE processing succeeds.
  Future<Map<String, dynamic>> acknowledgeMessage({
    required IdentityKeyMaterial identity,
    required RelayedEnvelope message,
  }) async {
    final recipientId = await identityId(identity.signingPublicKey);
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final nonce = _nonce();
    final canonical = 'INLINK-RELAY-ACK-V2\n$recipientId\n${message.senderId}\n${message.messageId}\n${message.envelopeDigest}\n$timestamp\n$nonce';
    final signature = await _sign(identity, canonical);
    return _request('POST', '/v2/relay/acks', body: <String, Object?>{
      'protocol_version': relayProtocolVersion,
      'recipient_id': recipientId,
      'sender_id': message.senderId,
      'message_id': message.messageId,
      'envelope_digest': message.envelopeDigest,
      'timestamp': timestamp,
      'nonce': nonce,
      'recipient_public_key': _b64u(identity.signingPublicKey),
      'signature': signature,
    });
  }

  void close() => _http.close(force: true);
}
