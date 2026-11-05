/// Validates a persisted SQLCipher key without silently replacing it.
///
/// A missing key means this is a first launch and a new key may be generated.
/// A present but malformed key is an error: overwriting it would make an
/// existing encrypted database unrecoverable and hide possible storage damage.
String? validateExistingDatabaseKey(String? value) {
  if (value == null) return null;
  if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value)) {
    throw const FormatException(
      'Stored InLink database key is malformed; refusing to replace it.',
    );
  }
  return value;
}
