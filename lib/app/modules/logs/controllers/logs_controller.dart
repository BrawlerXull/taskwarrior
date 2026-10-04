import 'package:get/get.dart';
import 'package:taskwarrior/app/utils/debug_logger/app_logger.dart';
import 'package:taskwarrior/app/utils/debug_logger/log_database_helper.dart';

class LogsController extends GetxController {
  LogsController({LogDatabaseHelper? store})
      : _store = store ?? LogDatabaseHelper.instance;

  final LogDatabaseHelper _store;

  final logs = <LogRecord>[].obs;
  final isLoading = true.obs;

  /// Levels currently shown; debug records are never persisted.
  final levels = <LogLevel>{LogLevel.info, LogLevel.warning, LogLevel.error}.obs;

  /// Tag to show, or null for all tags.
  final tag = RxnString();

  List<String> get tags => (logs.map((r) => r.tag).toSet().toList()..sort());

  List<LogRecord> get visibleLogs => logs
      .where((r) => levels.contains(r.level))
      .where((r) => tag.value == null || r.tag == tag.value)
      .toList();

  @override
  void onInit() {
    super.onInit();
    loadLogs();
  }

  Future<void> loadLogs() async {
    isLoading.value = true;
    logs.assignAll(await _store.getLogs());
    if (tag.value != null && !tags.contains(tag.value)) tag.value = null;
    isLoading.value = false;
  }

  Future<void> clearLogs() async {
    await _store.clearLogs();
    await loadLogs();
  }

  void toggleLevel(LogLevel level) {
    if (!levels.remove(level)) levels.add(level);
  }

  /// Visible records, oldest first, as plain text for bug reports.
  String exportVisible() => visibleLogs.reversed.map((r) {
        final line = r.format(withTime: true);
        return r.stackTrace == null ? line : '$line\n${r.stackTrace}';
      }).join('\n');
}
