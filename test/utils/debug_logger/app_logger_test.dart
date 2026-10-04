import 'package:flutter_test/flutter_test.dart';
import 'package:taskwarrior/app/utils/debug_logger/app_logger.dart';

class _RecordingSink implements LogSink {
  final records = <LogRecord>[];

  @override
  void write(LogRecord record) => records.add(record);
}

void main() {
  const log = AppLogger('Test');
  late _RecordingSink sink;

  setUp(() {
    sink = _RecordingSink();
    AppLogger.attachSink(sink);
  });

  test('persists info and above with level and tag', () {
    log.info('started');
    log.warning('slow', 'timeout');
    log.error('failed', StateError('boom'), StackTrace.current);

    expect(sink.records.map((r) => r.level),
        [LogLevel.info, LogLevel.warning, LogLevel.error]);
    expect(sink.records.every((r) => r.tag == 'Test'), isTrue);
    expect(sink.records[1].error, 'timeout');
    expect(sink.records[2].error, contains('boom'));
    expect(sink.records[2].stackTrace, isNotNull);
  });

  test('never persists debug records', () {
    log.debug('noise');
    expect(sink.records, isEmpty);
  });

  test('format puts level, tag, message and error on one line', () {
    final record = LogRecord(
      level: LogLevel.warning,
      tag: 'Sync',
      message: 'Sync failed',
      error: 'offline',
      time: DateTime.utc(2026, 10, 4, 12),
    );
    expect(record.format(), '[WARNING] [Sync] Sync failed: offline');
    expect(record.format(withTime: true),
        '2026-10-04T12:00:00.000Z [WARNING] [Sync] Sync failed: offline');
  });
}
