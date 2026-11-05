/// Validation helpers for authenticated delivery receipt payload fields.
///
/// These checks validate structure only; callers must first authenticate and
/// decrypt the envelope, then bind the fields to the verified peer and message.
bool isValidReceiptMessageId(String value) =>
    value.isNotEmpty &&
    value.length <= 128 &&
    RegExp(r'^[A-Za-z0-9:_-]+=?$').hasMatch(value);

/// SHA-256 encoded with Dart's base64UrlEncode: 32 bytes, URL-safe alphabet,
/// with the single trailing padding character produced by Dart's encoder.
bool isValidEnvelopeDigest(String value) =>
    RegExp(r'^[A-Za-z0-9_-]{43}=$').hasMatch(value);
