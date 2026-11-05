import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A receipt that has been durably recorded before attempting BLE transmission.
class PendingDeliveryReceipt {
  PendingDeliveryReceipt({
    required this.id,
    this.type = 'receipt',
    required this.contactFingerprint,
    required this.messageId,
    required this.envelopeDigest,
    required this.recipientFingerprint,
    required this.receivedAtUtc,
    this.retryCount = 0,
    DateTime? nextAttemptAtUtc,
    DateTime? createdAtUtc,
  })  : createdAtUtc = (createdAtUtc ?? receivedAtUtc).toUtc(),
        nextAttemptAtUtc = (nextAttemptAtUtc ?? receivedAtUtc).toUtc();

  final String id;
  final String type;
  final String contactFingerprint;
  final String messageId;
  final String envelopeDigest;
  final String recipientFingerprint;
  final DateTime receivedAtUtc;
  final DateTime createdAtUtc;
  final int retryCount;
  final DateTime nextAttemptAtUtc;

  Map<String, Object?> toJson() => <String, Object?>{
        'version': 1,
        'id': id,
        'type': type,
        'contactFingerprint': contactFingerprint,
        'messageId': messageId,
        'envelopeDigest': envelopeDigest,
        'recipientFingerprint': recipientFingerprint,
        'receivedAtUtc': receivedAtUtc.toUtc().toIso8601String(),
        'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
        'retryCount': retryCount,
        'nextAttemptAtUtc': nextAttemptAtUtc.toUtc().toIso8601String(),
      };

  static PendingDeliveryReceipt fromJson(Map<String, dynamic> json) {
    DateTime parseDate(String key) {
      final raw = json[key];
      if (raw is! String) throw FormatException('Invalid receipt $key.');
      final value = DateTime.tryParse(raw);
      if (value == null) throw FormatException('Invalid receipt $key.');
      return value.toUtc();
    }

    final retries = json['retryCount'];
    if (json['version'] != 1 ||
        json['id'] is! String ||
        (json['type'] != 'receipt' && json['type'] != 'receiptAck') ||
        json['contactFingerprint'] is! String ||
        json['messageId'] is! String ||
        json['envelopeDigest'] is! String ||
        json['recipientFingerprint'] is! String ||
        retries is! int || retries < 0 || retries > 100000) {
      throw const FormatException('Invalid saved delivery receipt.');
    }
    final received = parseDate('receivedAtUtc');
    return PendingDeliveryReceipt(
      id: json['id'] as String,
      type: json['type'] as String,
      contactFingerprint: json['contactFingerprint'] as String,
      messageId: json['messageId'] as String,
      envelopeDigest: json['envelopeDigest'] as String,
      recipientFingerprint: json['recipientFingerprint'] as String,
      receivedAtUtc: received,
      createdAtUtc: parseDate('createdAtUtc'),
      retryCount: retries,
      nextAttemptAtUtc: parseDate('nextAttemptAtUtc'),
    );
  }

  PendingDeliveryReceipt copyWith({
    int? retryCount,
    DateTime? nextAttemptAtUtc,
  }) => PendingDeliveryReceipt(
        id: id,
        type: type,
        contactFingerprint: contactFingerprint,
        messageId: messageId,
        envelopeDigest: envelopeDigest,
        recipientFingerprint: recipientFingerprint,
        receivedAtUtc: receivedAtUtc,
        createdAtUtc: createdAtUtc,
        retryCount: retryCount ?? this.retryCount,
        nextAttemptAtUtc: nextAttemptAtUtc ?? this.nextAttemptAtUtc,
      );
}

/// Bounded OS-backed storage for receipts awaiting a live return path.
class DeliveryReceiptQueue {
  DeliveryReceiptQueue({
    FlutterSecureStorage? storage,
    this.maxReceipts = 200,
    this.maxAge = const Duration(days: 7),
  }) : _storage = storage ?? const FlutterSecureStorage() {
    if (maxReceipts < 20) {
      throw ArgumentError.value(maxReceipts, 'maxReceipts', 'Must be at least 20.');
    }
  }

  static const String _storageKey = 'inlink.delivery_receipts.v1';
  final FlutterSecureStorage _storage;
  final int maxReceipts;
  final Duration maxAge;

  Future<List<PendingDeliveryReceipt>> listAll() async {
    final encoded = await _storage.read(key: _storageKey);
    if (encoded == null) return <PendingDeliveryReceipt>[];
    final decoded = jsonDecode(encoded);
    if (decoded is! List) throw const FormatException('Saved receipt queue is invalid.');
    return decoded.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Saved receipt entry is invalid.');
      }
      return PendingDeliveryReceipt.fromJson(item);
    }).toList(growable: true);
  }

  Future<void> enqueue(PendingDeliveryReceipt receipt) async {
    final all = await listAll();
    if (all.any((item) => item.id == receipt.id)) return;
    all.add(receipt);
    all.sort((a, b) => a.createdAtUtc.compareTo(b.createdAtUtc));
    if (all.length > maxReceipts) {
      all.removeRange(0, all.length - maxReceipts);
    }
    await _write(all);
  }

  Future<List<PendingDeliveryReceipt>> listDue(DateTime nowUtc) async {
    final now = nowUtc.toUtc();
    final all = await listAll();
    final fresh = all.where((item) => item.createdAtUtc.add(maxAge).isAfter(now)).toList();
    if (fresh.length != all.length) await _write(fresh);
    return fresh.where((item) => !item.nextAttemptAtUtc.isAfter(now)).toList()
      ..sort((a, b) => a.nextAttemptAtUtc.compareTo(b.nextAttemptAtUtc));
  }

  Future<void> update(PendingDeliveryReceipt receipt) async {
    final all = await listAll();
    final index = all.indexWhere((item) => item.id == receipt.id);
    if (index < 0) return;
    all[index] = receipt;
    await _write(all);
  }

  Future<void> remove(String id) async {
    final all = await listAll();
    all.removeWhere((item) => item.id == id);
    await _write(all);
  }

  Future<void> _write(List<PendingDeliveryReceipt> items) => _storage.write(
        key: _storageKey,
        value: jsonEncode(items.map((item) => item.toJson()).toList()),
      );
}
