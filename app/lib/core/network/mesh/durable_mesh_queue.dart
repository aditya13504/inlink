import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as path_util;
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'mesh_routing_engine.dart';

const int durableMeshQueueSchemaVersion = 1;
const String _meshDbKey = 'inlink.mesh.db_key.v1';

/// Persisted opaque packet plus routing metadata. It never contains plaintext.
class DurableMeshQueueEntry {
  const DurableMeshQueueEntry({
    required this.packet,
    required this.ingressPeerId,
    required this.attemptedPeerIds,
    required this.enqueuedAtUtc,
  });

  final MeshPacket packet;
  final String? ingressPeerId;
  final Set<String> attemptedPeerIds;
  final DateTime enqueuedAtUtc;

  String get routeKey => packet.routeKey;
}

/// Independent SQLCipher database for store-and-forward mesh packets.
///
/// The database key lives in platform secure storage. Writes are transactional,
/// queue size is bounded, and expired rows are pruned before capacity checks.
class DurableMeshQueue {
  DurableMeshQueue({
    FlutterSecureStorage? secureStorage,
    String? databasePath,
    this.maxEntries = meshMaxQueuedPackets,
  })  : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _databasePathOverride = databasePath {
    if (maxEntries < 1 || maxEntries > meshMaxQueuedPackets) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'Must be 1..$meshMaxQueuedPackets.');
    }
  }

  final FlutterSecureStorage _secureStorage;
  final String? _databasePathOverride;
  final int maxEntries;
  Future<Database>? _databaseFuture;
  Future<void> _mutationTail = Future<void>.value();

  Future<T> _serialize<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _mutationTail = _mutationTail.then((_) async {
      try { completer.complete(await action()); }
      catch (error, stack) { completer.completeError(error, stack); }
    });
    return completer.future;
  }

  Future<Database> _database() {
    final existing = _databaseFuture;
    if (existing != null) return existing;
    final opening = _openDatabase();
    _databaseFuture = opening;
    return opening.catchError((Object error, StackTrace stack) {
      _databaseFuture = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<Database> _openDatabase() async {
    final key = await _loadKey();
    final dbPath = _databasePathOverride ?? path_util.join(await getDatabasesPath(), 'inlink_mesh_queue_v1.db');
    return openDatabase(
      dbPath,
      password: key,
      version: durableMeshQueueSchemaVersion,
      onCreate: (db, version) async {
        await db.execute('''CREATE TABLE mesh_queue (
          route_key TEXT PRIMARY KEY NOT NULL,
          immutable_fingerprint TEXT NOT NULL,
          encoded_packet TEXT NOT NULL,
          ingress_peer_id TEXT,
          attempted_peer_ids_json TEXT NOT NULL,
          enqueued_at_utc TEXT NOT NULL,
          expires_at_epoch_seconds INTEGER NOT NULL
        )''');
        await db.execute('CREATE INDEX idx_mesh_queue_expiry ON mesh_queue(expires_at_epoch_seconds)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Future migrations must be additive and transactional; unknown schema
        // versions are not silently rewritten by this queue.
      },
    );
  }

  Future<String> _loadKey() async {
    final existing = await _secureStorage.read(key: _meshDbKey);
    if (existing != null) {
      if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(existing)) {
        throw const FormatException('Stored mesh database key is malformed; refusing to replace it.');
      }
      return existing;
    }
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final generated = base64UrlEncode(bytes).replaceAll('=', '');
    await _secureStorage.write(key: _meshDbKey, value: generated);
    return generated;
  }

  Future<void> enqueue({required MeshPacket packet, String? ingressPeerId, required DateTime now}) => _serialize(() async {
    packet.validate(now: now);
    if (ingressPeerId != null && !RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(ingressPeerId)) {
      throw ArgumentError.value(ingressPeerId, 'ingressPeerId', 'Invalid peer identifier.');
    }
    final db = await _database();
    await db.transaction((txn) async {
      await txn.delete('mesh_queue', where: 'expires_at_epoch_seconds <= ?', whereArgs: <Object?>[now.toUtc().millisecondsSinceEpoch ~/ 1000]);
      final prior = await txn.query('mesh_queue', where: 'route_key = ?', whereArgs: <Object?>[packet.routeKey], limit: 1);
      if (prior.isNotEmpty) {
        if (prior.first['immutable_fingerprint'] != packet.immutableFingerprint) {
          throw StateError('Conflicting immutable content for an existing mesh route key.');
        }
        return;
      }
      final count = Sqflite.firstIntValue(await txn.rawQuery('SELECT COUNT(*) FROM mesh_queue')) ?? 0;
      if (count >= maxEntries) throw StateError('Durable mesh queue is full.');
      await txn.insert('mesh_queue', <String, Object?>{
        'route_key': packet.routeKey,
        'immutable_fingerprint': packet.immutableFingerprint,
        'encoded_packet': packet.encode(),
        'ingress_peer_id': ingressPeerId,
        'attempted_peer_ids_json': jsonEncode(<String>[]),
        'enqueued_at_utc': now.toUtc().toIso8601String(),
        'expires_at_epoch_seconds': packet.expiresAtEpochSeconds,
      });
    });
  });

  Future<List<DurableMeshQueueEntry>> listPending({required DateTime now}) => _serialize(() async {
    final db = await _database();
    final seconds = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    await db.delete('mesh_queue', where: 'expires_at_epoch_seconds <= ?', whereArgs: <Object?>[seconds]);
    final rows = await db.query('mesh_queue', orderBy: 'enqueued_at_utc ASC', limit: maxEntries);
    final entries = <DurableMeshQueueEntry>[];
    for (final row in rows) {
      try {
        final packet = MeshPacket.decode(row['encoded_packet']! as String, now: now);
        final rawAttempts = jsonDecode(row['attempted_peer_ids_json']! as String);
        if (rawAttempts is! List || rawAttempts.any((item) => item is! String)) continue;
        final enqueued = DateTime.tryParse(row['enqueued_at_utc']! as String);
        if (enqueued == null || row['immutable_fingerprint'] != packet.immutableFingerprint || row['route_key'] != packet.routeKey) continue;
        entries.add(DurableMeshQueueEntry(
          packet: packet,
          ingressPeerId: row['ingress_peer_id'] as String?,
          attemptedPeerIds: Set<String>.unmodifiable(rawAttempts.cast<String>()),
          enqueuedAtUtc: enqueued.toUtc(),
        ));
      } on FormatException {
        // Fail closed for malformed/corrupted records; do not forward them.
        await db.delete('mesh_queue', where: 'route_key = ?', whereArgs: <Object?>[row['route_key']]);
      }
    }
    return entries;
  });

  Future<void> markAttempted({required String routeKey, required String peerId}) => _serialize(() async {
    if (!RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(peerId)) throw ArgumentError.value(peerId, 'peerId');
    final db = await _database();
    await db.transaction((txn) async {
      final rows = await txn.query('mesh_queue', columns: <String>['attempted_peer_ids_json'], where: 'route_key = ?', whereArgs: <Object?>[routeKey], limit: 1);
      if (rows.isEmpty) return;
      final decoded = jsonDecode(rows.first['attempted_peer_ids_json']! as String);
      if (decoded is! List || decoded.any((item) => item is! String)) throw const FormatException('Persisted mesh attempts are invalid.');
      final peers = decoded.cast<String>().toSet()..add(peerId);
      await txn.update('mesh_queue', <String, Object?>{'attempted_peer_ids_json': jsonEncode(peers.toList()..sort())}, where: 'route_key = ?', whereArgs: <Object?>[routeKey]);
    });
  });

  Future<void> markAttemptFailed({required String routeKey, required String peerId}) => _serialize(() async {
    final db = await _database();
    await db.transaction((txn) async {
      final rows = await txn.query('mesh_queue', columns: <String>['attempted_peer_ids_json'], where: 'route_key = ?', whereArgs: <Object?>[routeKey], limit: 1);
      if (rows.isEmpty) return;
      final decoded = jsonDecode(rows.first['attempted_peer_ids_json']! as String);
      if (decoded is! List || decoded.any((item) => item is! String)) throw const FormatException('Persisted mesh attempts are invalid.');
      final peers = decoded.cast<String>().toSet()..remove(peerId);
      await txn.update('mesh_queue', <String, Object?>{'attempted_peer_ids_json': jsonEncode(peers.toList()..sort())}, where: 'route_key = ?', whereArgs: <Object?>[routeKey]);
    });
  });

  /// Remove only after authenticated application-level completion or expiry.
  /// Clears prior local-send attempts at process recovery. A native BLE write
  /// acceptance is not an authenticated receipt, so it is safe to retry after
  /// restart; receiver-side route-key deduplication suppresses duplicates.
  Future<void> resetAttemptsForRecovery() => _serialize(() async {
    final db = await _database();
    await db.update('mesh_queue', <String, Object?>{
      'attempted_peer_ids_json': jsonEncode(<String>[]),
    });
  });

  Future<void> remove(String routeKey) => _serialize(() async {
    final db = await _database();
    await db.delete('mesh_queue', where: 'route_key = ?', whereArgs: <Object?>[routeKey]);
  });

  Future<int> pruneExpired(DateTime now) => _serialize(() async {
    final db = await _database();
    return db.delete('mesh_queue', where: 'expires_at_epoch_seconds <= ?', whereArgs: <Object?>[now.toUtc().millisecondsSinceEpoch ~/ 1000]);
  });

  Future<void> close() async {
    await _mutationTail;
    final pending = _databaseFuture;
    _databaseFuture = null;
    if (pending != null) await (await pending).close();
  }
}
