// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter_test/flutter_test.dart';
import 'package:inlink/core/messaging/delivery_receipt_validation.dart';

void main() {
  final digestBody = List<String>.filled(43, 'A').join();

  group('delivery receipt field validation', () {
    test('accepts generated application message IDs', () {
      expect(isValidReceiptMessageId('0123456789abcdef0123456789abcdef'), isTrue);
      expect(isValidReceiptMessageId('in-aBc_123:legacy'), isTrue);
      // Legacy envelope fallback IDs use `in-` + padded base64url SHA-256.
      expect(isValidReceiptMessageId('in-' + List<String>.filled(43, 'A').join() + '='), isTrue);
    });

    test('rejects empty, oversized, or delimiter-bearing message IDs', () {
      expect(isValidReceiptMessageId(''), isFalse);
      expect(isValidReceiptMessageId(List<String>.filled(129, 'a').join()), isFalse);
      expect(isValidReceiptMessageId('id with spaces'), isFalse);
      expect(isValidReceiptMessageId('id/other'), isFalse);
      expect(isValidReceiptMessageId('id=='), isFalse);
      expect(isValidReceiptMessageId('id=tail'), isFalse);
    });

    test('accepts a 32-byte SHA-256 base64url digest', () {
      expect(isValidEnvelopeDigest(digestBody + '='), isTrue);
    });

    test('rejects malformed envelope digests', () {
      expect(isValidEnvelopeDigest(''), isFalse);
      expect(isValidEnvelopeDigest(digestBody), isFalse);
      expect(isValidEnvelopeDigest(List<String>.filled(42, 'A').join() + '!='), isFalse);
      expect(isValidEnvelopeDigest(digestBody + '=='), isFalse);
    });
  });
}
