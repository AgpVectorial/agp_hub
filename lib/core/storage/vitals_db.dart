import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tipuri de semnal vital stocate în DB
enum VitalType { hr, spo2, temp, steps, battery }

/// O înregistrare din istoric
class VitalRecord {
  final int? id;
  final String deviceId;
  final VitalType type;
  final double value;
  final DateTime ts;

  const VitalRecord({
    this.id,
    required this.deviceId,
    required this.type,
    required this.value,
    required this.ts,
  });

  Map<String, dynamic> toMap() => {
        'deviceId': deviceId,
        'type': type.name,
        'value': value,
        'ts': ts.millisecondsSinceEpoch,
      };

  factory VitalRecord.fromMap(Map<String, dynamic> m) => VitalRecord(
        id: m['id'] as int?,
        deviceId: m['deviceId'] as String,
        type: VitalType.values.firstWhere((e) => e.name == m['type']),
        value: (m['value'] as num).toDouble(),
        ts: DateTime.fromMillisecondsSinceEpoch(m['ts'] as int),
      );
}

/// Baza de date SQLite pentru istoricul semnalelor vitale.
class VitalsDatabase {
  static const _dbName = 'vitals_history.db';
  static const _table = 'vital_samples';
  static const _version = 1;

  Database? _db;
  static VitalsDatabase? _instance;

  VitalsDatabase._();
  factory VitalsDatabase() => _instance ??= VitalsDatabase._();

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _dbName);
    _db = await openDatabase(
      path,
      version: _version,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            deviceId TEXT NOT NULL,
            type TEXT NOT NULL,
            value REAL NOT NULL,
            ts INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_device_type_ts ON $_table (deviceId, type, ts)',
        );
      },
    );
    return _db!;
  }

  /// Inserează un sample.
  Future<void> insert(VitalRecord rec) async {
    final db = await database;
    await db.insert(_table, rec.toMap());
  }

  /// Inserează un batch de sample-uri (mai eficient).
  Future<void> insertBatch(List<VitalRecord> records) async {
    if (records.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final rec in records) {
      batch.insert(_table, rec.toMap());
    }
    await batch.commit(noResult: true);
  }

  /// Returnează sample-urile pentru un device + tip, în intervalul temporal.
  Future<List<VitalRecord>> query({
    required String deviceId,
    required VitalType type,
    DateTime? from,
    DateTime? to,
    int? limit,
  }) async {
    final db = await database;
    final where = StringBuffer('deviceId = ? AND type = ?');
    final args = <dynamic>[deviceId, type.name];

    if (from != null) {
      where.write(' AND ts >= ?');
      args.add(from.millisecondsSinceEpoch);
    }
    if (to != null) {
      where.write(' AND ts <= ?');
      args.add(to.millisecondsSinceEpoch);
    }

    final rows = await db.query(
      _table,
      where: where.toString(),
      whereArgs: args,
      orderBy: 'ts ASC',
      limit: limit,
    );
    return rows.map(VitalRecord.fromMap).toList();
  }

  /// Ultimele N sample-uri (cele mai recente).
  Future<List<VitalRecord>> latest({
    required String deviceId,
    required VitalType type,
    int count = 100,
  }) async {
    final db = await database;
    final rows = await db.query(
      _table,
      where: 'deviceId = ? AND type = ?',
      whereArgs: [deviceId, type.name],
      orderBy: 'ts DESC',
      limit: count,
    );
    return rows.map(VitalRecord.fromMap).toList().reversed.toList();
  }

  /// Șterge sample-uri mai vechi de [days] zile.
  Future<int> pruneOlderThan(int days) async {
    final db = await database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: days))
        .millisecondsSinceEpoch;
    return db.delete(_table, where: 'ts < ?', whereArgs: [cutoff]);
  }

  /// Numărul total de sample-uri pentru un device + tip.
  Future<int> count({
    required String deviceId,
    required VitalType type,
  }) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM $_table WHERE deviceId = ? AND type = ?',
      [deviceId, type.name],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }
}

/// Provider global pentru baza de date.
final vitalsDbProvider = Provider<VitalsDatabase>((_) => VitalsDatabase());
