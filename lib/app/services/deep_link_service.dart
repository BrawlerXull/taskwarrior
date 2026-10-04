import 'dart:async'; // Add this import at the top
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:app_links/app_links.dart';
import 'package:taskwarrior/app/modules/home/views/add_task_bottom_sheet_new.dart';
import 'package:taskwarrior/app/modules/home/controllers/home_controller.dart';
import 'package:taskwarrior/app/routes/app_pages.dart';
import 'package:taskwarrior/app/utils/debug_logger/app_logger.dart';

class DeepLinkService extends GetxService {
  static const AppLogger _log = AppLogger('DeepLink');

  late AppLinks _appLinks;
  String? _queuedUri; // Made private
  String? get queuedUri => _queuedUri; // Added getter
  StreamSubscription<Uri>? _linkSubscription; // Added stream subscription

  Future<void> init() async {
    _appLinks = AppLinks();

    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _queuedUri = initialUri.toString();
        _log.info('Queued initial deep link ${_describe(initialUri)}.');
      }
    } catch (e, s) {
      _log.warning('Deep link init failed', e, s);
    }

    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _log.info('Received deep link ${_describe(uri)}.');
      _handleWidgetUri(uri);
    }, onError: (Object err, StackTrace s) {
      _log.warning('Deep link stream reported an error', err, s);
    });
  }

  @override
  void onClose() {
    _linkSubscription?.cancel();
    super.onClose();
  }

  void _handleWidgetUri(Uri uri) {
    if (Get.isRegistered<HomeController>()) {
      _executeAction(uri, Get.find<HomeController>());
    } else {
      _log.debug('HomeController is not ready, so the deep link was queued.');
      _queuedUri = uri.toString();
    }
  }

  void consumePendingActions(HomeController controller) {
    if (_queuedUri != null) {
      _log.debug('Executing the queued deep link action.');
      try {
        _executeAction(Uri.parse(_queuedUri!), controller);
      } catch (e, s) {
        _log.warning('Failed to execute the queued deep link', e, s);
      }
      _queuedUri = null;
    }
  }

  /// Scheme, host and path only: the query string can carry task text.
  static String _describe(Uri uri) => '${uri.scheme}://${uri.host}${uri.path}';

  void _executeAction(Uri uri, HomeController controller) {
    final bool isTaskChampion = controller.taskchampion.value;
    final bool isReplica = controller.taskReplica.value;

    if (uri.host == "cardclicked") {
      if (uri.queryParameters["uuid"] != null &&
          uri.queryParameters["uuid"] != "NO_TASK" &&
          !isTaskChampion &&
          !isReplica) {
        String uuid = uri.queryParameters["uuid"] as String;
        Get.toNamed(Routes.DETAIL_ROUTE, arguments: ["uuid", uuid]);
      }
    } else if (uri.host == "addclicked") {
      if (Get.context != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Get.dialog(
            Material(
              child: AddTaskBottomSheet(
                homeController: controller,
                forTaskC: isTaskChampion,
                forReplica: isReplica,
              ),
            ),
          );
        });
      }
    }
  }
}
