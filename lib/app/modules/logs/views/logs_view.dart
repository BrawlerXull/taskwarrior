import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:taskwarrior/app/utils/debug_logger/app_logger.dart';
import '../controllers/logs_controller.dart';

class LogsView extends GetView<LogsController> {
  const LogsView({super.key});

  static const _filterableLevels = [
    LogLevel.info,
    LogLevel.warning,
    LogLevel.error,
  ];

  Future<void> _copyLogs(BuildContext context) async {
    final text = controller.exportVisible();
    final messenger = ScaffoldMessenger.of(context);
    if (text.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('No logs match the current filters.')));
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(SnackBar(
        content:
            Text('Copied ${controller.visibleLogs.length} log entries.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Logs'),
        actions: [
          Obx(
            () => IconButton(
              icon: const Icon(Icons.copy),
              onPressed:
                  controller.isLoading.value ? null : () => _copyLogs(context),
              tooltip: 'Copy Logs',
            ),
          ),
          Obx(
            () => IconButton(
              icon: const Icon(Icons.refresh),
              onPressed:
                  controller.isLoading.value ? null : controller.loadLogs,
              tooltip: 'Refresh Logs',
            ),
          ),
          Obx(
            () => IconButton(
              icon: const Icon(Icons.delete_forever),
              onPressed:
                  controller.isLoading.value ? null : controller.clearLogs,
              tooltip: 'Clear All Logs',
            ),
          ),
        ],
      ),
      body: Obx(
        () {
          if (controller.isLoading.value) {
            return const Center(child: CircularProgressIndicator());
          }
          if (controller.logs.isEmpty) {
            return const Center(
              child: Text(
                'No debug logs found.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }
          final visible = controller.visibleLogs;
          return Column(
            children: [
              _buildFilters(),
              Expanded(
                child: visible.isEmpty
                    ? const Center(
                        child: Text(
                          'No logs match the current filters.',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8.0),
                        itemCount: visible.length,
                        itemBuilder: (context, index) =>
                            _LogCard(record: visible[index]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        children: [
          for (final level in _filterableLevels)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: FilterChip(
                label: Text(level.name),
                selected: controller.levels.contains(level),
                onSelected: (_) => controller.toggleLevel(level),
              ),
            ),
          DropdownButton<String?>(
            value: controller.tag.value,
            hint: const Text('All tags'),
            items: [
              const DropdownMenuItem<String?>(child: Text('All tags')),
              for (final tag in controller.tags)
                DropdownMenuItem<String?>(value: tag, child: Text(tag)),
            ],
            onChanged: (tag) => controller.tag.value = tag,
          ),
        ],
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({required this.record});

  final LogRecord record;

  Color _levelColor(ColorScheme colors) => switch (record.level) {
        LogLevel.error => colors.error,
        LogLevel.warning => Colors.orange,
        LogLevel.info => colors.primary,
        LogLevel.debug => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(Theme.of(context).colorScheme);
    final header = Text(
      '${record.level.name.toUpperCase()} · ${record.tag} · '
      '${record.time.toLocal().toIso8601String()}',
      style: TextStyle(
          fontSize: 12, color: color, fontWeight: FontWeight.w600),
    );
    final body = Text(
      record.error == null
          ? record.message
          : '${record.message}\n${record.error}',
      style: const TextStyle(fontSize: 15),
    );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.5)),
      ),
      child: record.stackTrace == null
          ? Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [header, const SizedBox(height: 4), body],
              ),
            )
          : ExpansionTile(
              title: header,
              subtitle: body,
              childrenPadding: const EdgeInsets.all(12.0),
              children: [
                SelectableText(
                  record.stackTrace!,
                  style:
                      const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ],
            ),
    );
  }
}
