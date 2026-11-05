import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'database_key_validation.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as path_util;
import 'package:sqflite_sqlcipher/sqflite.dart';

enum LocalMessageDirection { outgoing, incoming }

enum LocalDeliveryStatus { queued, inTransit, delivered, failed, expired }

class LocalChatMessage {
  LocalChatMessage({
    required this.id,
    required this.contactFingerprint,
    required this.direction,
    required this.text,
    required this.createdAtUtc,
    required this.status,
    this.encodedEnvelope,
    this.error,
    this.transport = 'legacy',
    DateTime? expiresAtUtc,
    this.retryCount = 0,
    DateTime? nextAttemptAtUtc,
    this.lastAttemptAtUtc,
    this.sentEnvelopeDigests = const <String>[],
  })  : expiresAtUtc = (expiresAtUtc ?? createdAtUtc.add(const Duration(days: 7))).toUtc(),
        nextAttemptAtUtc = (nextAttemptAtUtc ?? createdAtUtc).toUtc();

  final String id;
  final String contactFingerprint;
  final LocalMessageDirection direction;
  final String text;
  final DateTime createdAtUtc;
  final LocalDeliveryStatus status;
  final String? encodedEnvelope;
  final String? error;
  /// Application transport namespace; avoids replaying legacy-relay messages into mesh.
  final String transport;
  final DateTime expiresAtUtc;
  final int retryCount;
  final DateTime nextAttemptAtUtc;
  final DateTime? lastAttemptAtUtc;
  /// Digests of every outbound envelope used for this application message.
  /// This lets a delayed receipt for an earlier retry remain verifiable.
  final List<String> sentEnvelopeDigests;

  Map<String, Object?> toJson() => <String, Object?>{
        'version': 4,
        'id': id,
        'contactFingerprint': contactFingerprint,
        'direction': direction.name,
        'text': text,
        'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
        'status': status.name,
        'encodedEnvelope': encodedEnvelope,
        'error': error,
        'transport': transport,
        'expiresAtUtc': expiresAtUtc.toUtc().toIso8601String(),
        'retryCount': retryCount,
        'nextAttemptAtUtc': nextAttemptAtUtc.toUtc().toIso8601String(),
        'lastAttemptAtUtc': lastAttemptAtUtc?.toUtc().toIso8601String(),
        'sentEnvelopeDigests': sentEnvelopeDigests,
      };

  static LocalChatMessage fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if ((version != 1 && version != 2 && version != 3 && version != 4) ||
        json['id'] is! String ||
        json['contactFingerprint'] is! String ||
        json['direction'] is! String ||
        json['text'] is! String ||
        json['createdAtUtc'] is! String ||
        json['status'] is! String) {
      throw const FormatException('Invalid saved message record.');
    }
    final transport = version >= 4 ? json['transport'] : 'legacy';
    if (transport is! String || (transport != 'legacy' && transport != 'mesh')) {
      throw const FormatException('Saved message transport is invalid.');
    }
    final direction = LocalMessageDirection.values
        .where((value) => value.name == json['direction'])
        .firstOrNull;
    final status = LocalDeliveryStatus.values
        .where((value) => value.name == json['status'])
        .firstOrNull;
    final createdAt = DateTime.tryParse(json['createdAtUtc'] as String);
    if (direction == null || status == null || createdAt == null) {
      throw const FormatException('Saved message metadata is invalid.');
    }
    DateTime? optionalDate(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! String) throw FormatException('Saved $key is invalid.');
      final parsed = DateTime.tryParse(value);
      if (parsed == null) throw FormatException('Saved $key is invalid.');
      return parsed.toUtc();
    }
    final expiresAt = optionalDate('expiresAtUtc');
    final nextAttempt = optionalDate('nextAttemptAtUtc');
    final lastAttempt = optionalDate('lastAttemptAtUtc');
    final retries = version == 1 ? 0 : json['retryCount'];
    if (version >= 2 && (retries is! int || retries < 0 || retries > 100000)) {
      throw const FormatException('Saved retry count is invalid.');
    }
    return LocalChatMessage(
      id: json['id'] as String,
      contactFingerprint: json['contactFingerprint'] as String,
      direction: direction,
      text: json['text'] as String,
      createdAtUtc: createdAt.toUtc(),
      status: status,
      encodedEnvelope: json['encodedEnvelope'] as String?,
      error: json['error'] as String?,
      transport: transport,
      expiresAtUtc: expiresAt ?? createdAt.toUtc().add(const Duration(days: 7)),
      retryCount: retries as int,
      nextAttemptAtUtc: nextAttempt ?? createdAt.toUtc(),
      lastAttemptAtUtc: lastAttempt,
      sentEnvelopeDigests: version >= 3 && json['sentEnvelopeDigests'] is List
          ? (json['sentEnvelopeDigests'] as List).whereType<String>().take(32).toList()
          : <String>[],
    );
  }

  LocalChatMessage copyWith({
    LocalDeliveryStatus? status,
    String? error,
    bool clearError = false,
    String? encodedEnvelope,
    String? transport,
    DateTime? expiresAtUtc,
    int? retryCount,
    DateTime? nextAttemptAtUtc,
    DateTime? lastAttemptAtUtc,
    List<String>? sentEnvelopeDigests,
  }) => LocalChatMessage(
        id: id,
        contactFingerprint: contactFingerprint,
        direction: direction,
        text: text,
        createdAtUtc: createdAtUtc,
        status: status ?? this.status,
        encodedEnvelope: encodedEnvelope ?? this.encodedEnvelope,
        error: clearError ? null : (error ?? this.error),
        transport: transport ?? this.transport,
        expiresAtUtc: expiresAtUtc ?? this.expiresAtUtc,
        retryCount: retryCount ?? this.retryCount,
        nextAttemptAtUtc: nextAttemptAtUtc ?? this.nextAttemptAtUtc,
        lastAttemptAtUtc: lastAttemptAtUtc ?? this.lastAttemptAtUtc,
        sentEnvelopeDigests: sentEnvelopeDigests ?? this.sentEnvelopeDigests,
      );
}


/// Encrypted, transactional SQLite-backed local message repository.
///
/// SQLCipher encrypts the database at rest. Its random key is stored in
/// platform secure storage. The old JSON blob is retained until migration commits.
class LocalMessageRepository {
  LocalMessageRepository({
    FlutterSecureStorage? storage,
    this.maxMessages = 200,
    String? databasePath,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _databasePathOverride = databasePath {
    if (maxMessages < 20) {
      throw ArgumentError.value(maxMessages, 'maxMessages', 'Must be at least 20.');
    }
  }

  static const String _legacyStorageKey = 'inlink.messages.v1';
  static const String _databaseKeyStorageKey = 'inlink.messages.db_key.v1';
  final FlutterSecureStorage _storage;
  final int maxMessages;
  final String? _databasePathOverride;

  Future<Database>? _databaseFuture;
  Future<void> _mutationTail = Future<void>.value();

  Future<T> _serializeMutation<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _mutationTail = _mutationTail.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<Database> _database() {
    final existing = _databaseFuture;
    if (existing != null) return existing;
    final opening = _openDatabase();
    _databaseFuture = opening;
    return opening.catchError((Object error, StackTrace stackTrace) {
      _databaseFuture = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  Future<Database> _openDatabase() async {
    final password = await _loadOrCreateDatabaseKey();
    final dbPath = _databasePathOverride ??
        path_util.join(await getDatabasesPath(), 'inlink_messages_v1.db');
    final database = await openDatabase(
      dbPath,
      password: password,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            row_id INTEGER PRIMARY KEY AUTOINCREMENT,
            id TEXT NOT NULL,
            contact_fingerprint TEXT NOT NULL,
            direction TEXT NOT NULL,
            created_at_utc TEXT NOT NULL,
            expires_at_utc TEXT NOT NULL,
            status TEXT NOT NULL,
            next_attempt_at_utc TEXT NOT NULL,
            record_json TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE UNIQUE INDEX idx_messages_peer_direction_id
          ON messages(contact_fingerprint, direction, id)
        ''');
        await db.execute(
          'CREATE INDEX idx_messages_retry ON messages(direction, status, next_attempt_at_utc)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE messages ADD COLUMN next_attempt_at_utc TEXT NOT NULL DEFAULT ""',
          );
          await db.execute(
            'CREATE INDEX idx_messages_retry ON messages(direction, status, next_attempt_at_utc)',
          );
        }
      },
    );

    try {
      final legacy = await _storage.read(key: _legacyStorageKey);
      if (legacy != null) {
        final decoded = jsonDecode(legacy);
        if (decoded is! List) {
          throw const FormatException(
            'Legacy saved messages store is invalid; migration stopped safely.',
          );
        }
        await database.transaction((txn) async {
          for (final item in decoded) {
            if (item is! Map<String, dynamic>) {
              throw const FormatException(
                'Legacy saved message record is invalid; migration stopped safely.',
              );
            }
            final message = LocalChatMessage.fromJson(item);
            await txn.insert(
              'messages',
              _toRow(message),
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
          await txn.rawDelete('''
            DELETE FROM messages WHERE row_id NOT IN
            (SELECT row_id FROM messages ORDER BY created_at_utc DESC, row_id DESC LIMIT ?)
          ''', <Object?>[maxMessages]);
        });
        // Remove legacy plaintext only after the DB transaction commits.
        await _storage.delete(key: _legacyStorageKey);
      }
      return database;
    } catch (_) {
      await database.close();
      rethrow;
    }
  }

  Future<String> _loadOrCreateDatabaseKey() async {
    final existing = validateExistingDatabaseKey(
      await _storage.read(key: _databaseKeyStorageKey),
    );
    if (existing != null) return existing;
    final random = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final key = base64UrlEncode(random).replaceAll('=', '');
    await _storage.write(key: _databaseKeyStorageKey, value: key);
    return key;
  }

  Map<String, Object?> _toRow(LocalChatMessage message) => <String, Object?>{
        'id': message.id,
        'contact_fingerprint': _normalize(message.contactFingerprint),
        'direction': message.direction.name,
        'created_at_utc': message.createdAtUtc.toUtc().toIso8601String(),
        'expires_at_utc': message.expiresAtUtc.toUtc().toIso8601String(),
        'status': message.status.name,
        'next_attempt_at_utc': message.nextAttemptAtUtc.toUtc().toIso8601String(),
        'record_json': jsonEncode(message.toJson()),
      };

  LocalChatMessage _fromRow(Map<String, Object?> row) {
    final raw = row['record_json'];
    if (raw is! String) throw const FormatException('Saved message row is invalid.');
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Saved message record is invalid.');
    }
    return LocalChatMessage.fromJson(decoded);
  }

  Future<List<LocalChatMessage>> listAll() async {
    final db = await _database();
    final rows = await db.query(
      'messages',
      orderBy: 'created_at_utc ASC, row_id ASC',
    );
    return rows.map(_fromRow).toList(growable: true);
  }

  Future<List<LocalChatMessage>> listDueForRetry(DateTime nowUtc) async {
    final now = nowUtc.toUtc();
    final all = await listAll();
    return all.where((message) =>
      message.direction == LocalMessageDirection.outgoing &&
      (message.status == LocalDeliveryStatus.queued ||
       message.status == LocalDeliveryStatus.inTransit ||
       message.status == LocalDeliveryStatus.failed) &&
      message.expiresAtUtc.isAfter(now) &&
      !message.nextAttemptAtUtc.isAfter(now) &&
      message.retryCount < 8
    ).toList()..sort((a, b) => a.nextAttemptAtUtc.compareTo(b.nextAttemptAtUtc));
  }

  Future<List<LocalChatMessage>> listForContact(String fingerprint) async {
    final all = await listAll();
    final key = _normalize(fingerprint);
    final messages = all.where((message) =>
        _normalize(message.contactFingerprint) == key).toList();
    messages.sort((a, b) => a.createdAtUtc.compareTo(b.createdAtUtc));
    return messages;
  }

  Future<void> add(LocalChatMessage message) => _serializeMutation(() async {
        final db = await _database();
        await db.transaction((txn) async {
          await txn.insert(
            'messages',
            _toRow(message),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          final count = Sqflite.firstIntValue(
            await txn.rawQuery('SELECT COUNT(*) FROM messages'),
          ) ?? 0;
          final excess = count - maxMessages;
          if (excess > 0) {
            // Preserve queued/in-transit/failed outgoing messages even when
            // history is full. Evict only terminal records; if every retained
            // row is still pending, reject the new write instead of silently
            // deleting a user's undelivered message.
            await txn.rawDelete('''
              DELETE FROM messages WHERE row_id IN (
                SELECT row_id FROM messages
                WHERE status IN ('delivered', 'expired')
                ORDER BY created_at_utc ASC, row_id ASC
                LIMIT ?
              )
            ''', <Object?>[excess]);
          }
          final remaining = Sqflite.firstIntValue(
            await txn.rawQuery('SELECT COUNT(*) FROM messages'),
          ) ?? 0;
          if (remaining > maxMessages) {
            throw StateError(
              'Message history is full of pending messages; retry after delivery or expiry.',
            );
          }
        });
      });

  Future<void> update(LocalChatMessage message) => _serializeMutation(() async {
        final db = await _database();
        await db.update(
          'messages',
          _toRow(message),
          where: 'id = ? AND direction = ? AND contact_fingerprint = ?',
          whereArgs: <Object?>[
            message.id,
            message.direction.name,
            _normalize(message.contactFingerprint),
          ],
        );
      });

  /// Waits for queued mutations before closing the connection.
  ///
  /// Keeping close on the same serialized queue prevents an add/update that
  /// was already accepted by this repository from racing a database close.
  /// Later operations may reopen the database, which is useful for lifecycle
  /// transitions and tests.
  Future<void> close() => _serializeMutation(() async {
        final future = _databaseFuture;
        _databaseFuture = null;
        if (future != null) {
          final db = await future;
          await db.close();
        }
      });

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
}
