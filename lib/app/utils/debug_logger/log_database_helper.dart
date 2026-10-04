import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:taskwarrior/app/utils/debug_logger/app_logger.dart';

/// SQLite store behind the Logs page.
///
/// Records are buffered and written in batches; errors are flushed right
/// away so they survive a crash. On open, records older than [maxAge] or
/// beyond the newest [maxEntries] are pruned so the database stays small.
class LogDatabaseHelper implements LogSink {
  LogDatabaseHelper._();

  static final LogDatabaseHelper instance = LogDatabaseHelper._();

  static const int maxEntries = 5000;
  static const Duration maxAge = Duration(days: 7);
  static const Duration _flushDelay = Duration(milliseconds: 500);
  static const int _maxBuffered = 50;

  static const String tableName = 'logs';
  static const String columnId = 'id';
  static const String columnTimestamp = 'timestamp';
  static const String columnLevel = 'level';
  static const String columnTag = 'tag';
  static const String columnMessage = 'message';
  static const String columnError = 'error';
  static const String columnStackTrace = 'stack_trace';

  Future<Database>? _database;
  final List<LogRecord> _pending = [];
  Timer? _flushTimer;
  Future<void> _lastWrite = Future.value();

  Future<Database> get database => _database ??= _open();

  Future<Database> _open() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final db = await openDatabase(
      join(documentsDirectory.path, 'debug_logs.db'),
      version: 2,
      onCreate: (db, version) => _createTable(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 stored raw debugPrint lines, which could include task contents.
        // They have no level or tag to migrate, so start fresh.
        await db.execute('DROP TABLE IF EXISTS $tableName');
        await _createTable(db);
      },
    );
    await _prune(db);
    return db;
  }

  Future<void> _createTable(Database db) => db.execute('''
        CREATE TABLE $tableName (
          $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
          $columnTimestamp INTEGER NOT NULL,
          $columnLevel TEXT NOT NULL,
          $columnTag TEXT NOT NULL,
          $columnMessage TEXT NOT NULL,
          $columnError TEXT,
          $columnStackTrace TEXT
        )
        ''');

  Future<void> _prune(Database db) async {
    final cutoff = DateTime.now().subtract(maxAge).millisecondsSinceEpoch;
    await db.delete(tableName,
        where: '$columnTimestamp < ?', whereArgs: [cutoff]);
    await db.execute('''
        DELETE FROM $tableName WHERE $columnId NOT IN (
          SELECT $columnId FROM $tableName
          ORDER BY $columnId DESC LIMIT $maxEntries
        )
        ''');
  }

  @override
  void write(LogRecord record) {
    _pending.add(record);
    if (record.level == LogLevel.error || _pending.length >= _maxBuffered) {
      unawaited(flush());
    } else {
      _flushTimer ??= Timer(_flushDelay, () => unawaited(flush()));
    }
  }

  /// Writes all buffered records; resolves once they are in the database.
  Future<void> flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_pending.isEmpty) return _lastWrite;
    final records = List.of(_pending);
    _pending.clear();
    return _lastWrite = _lastWrite.then((_) => _insert(records));
  }

  Future<void> _insert(List<LogRecord> records) async {
    try {
      final batch = (await database).batch();
      for (final record in records) {
        batch.insert(tableName, _toRow(record));
      }
      await batch.commit(noResult: true);
    } catch (e) {
      // Not AppLogger: a failing store must not log back into itself.
      debugPrint('Dropped ${records.length} log records: $e');
    }
  }

  /// Newest first.
  Future<List<LogRecord>> getLogs() async {
    await flush();
    final rows = await (await database)
        .query(tableName, orderBy: '$columnId DESC');
    return rows.map(_fromRow).toList();
  }

  Future<void> clearLogs() async {
    await flush();
    await (await database).delete(tableName);
  }

  static Map<String, Object?> _toRow(LogRecord record) => {
        columnTimestamp: record.time.millisecondsSinceEpoch,
        columnLevel: record.level.name,
        columnTag: record.tag,
        columnMessage: record.message,
        columnError: record.error,
        columnStackTrace: record.stackTrace,
      };

  static LogRecord _fromRow(Map<String, Object?> row) => LogRecord(
        time: DateTime.fromMillisecondsSinceEpoch(row[columnTimestamp] as int),
        level: LogLevel.values.asNameMap()[row[columnLevel]] ?? LogLevel.info,
        tag: row[columnTag] as String,
        message: row[columnMessage] as String,
        error: row[columnError] as String?,
        stackTrace: row[columnStackTrace] as String?,
      );
}
