import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warning, error }

/// One structured log entry.
class LogRecord {
  LogRecord({
    required this.level,
    required this.tag,
    required this.message,
    DateTime? time,
    this.error,
    this.stackTrace,
  }) : time = time ?? DateTime.now();

  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;
  final String? error;
  final String? stackTrace;

  /// Single-line form used for the console and for copied logs.
  String format({bool withTime = false}) {
    final line = StringBuffer();
    if (withTime) line.write('${time.toIso8601String()} ');
    line.write('[${level.name.toUpperCase()}] [$tag] $message');
    if (error != null) line.write(': $error');
    return line.toString();
  }
}

/// Destination for persisted log records (the debug-log database in the app).
abstract interface class LogSink {
  void write(LogRecord record);
}

/// Tagged, levelled logger.
///
/// Every record is printed to the console. Records at [LogLevel.info] and
/// above are also handed to the attached [LogSink], which backs the Logs
/// page. [LogLevel.debug] records are console-only and are dropped entirely
/// in release builds, so routine interaction noise never gets persisted.
///
/// Persisted logs leave the device when users copy them into bug reports:
/// never log credentials or task contents (descriptions, annotations, tags);
/// log counts and UUIDs instead.
class AppLogger {
  const AppLogger(this.tag);

  final String tag;

  static LogSink? _sink;

  /// Routes persisted records to [sink]; called once from `main()`.
  static void attachSink(LogSink sink) => _sink = sink;

  void debug(String message) {
    if (kDebugMode) _log(LogLevel.debug, message);
  }

  void info(String message) => _log(LogLevel.info, message);

  void warning(String message, [Object? error, StackTrace? stackTrace]) =>
      _log(LogLevel.warning, message, error, stackTrace);

  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      _log(LogLevel.error, message, error, stackTrace);

  void _log(
    LogLevel level,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    final record = LogRecord(
      level: level,
      tag: tag,
      message: message,
      error: error?.toString(),
      stackTrace: stackTrace?.toString(),
    );
    debugPrint(record.format());
    if (record.stackTrace != null) debugPrint(record.stackTrace);
    if (level != LogLevel.debug) _sink?.write(record);
  }
}
