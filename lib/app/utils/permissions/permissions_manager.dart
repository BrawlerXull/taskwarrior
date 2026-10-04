import 'package:permission_handler/permission_handler.dart';
import 'package:taskwarrior/app/utils/constants/permissions.dart';
import 'package:taskwarrior/app/utils/debug_logger/app_logger.dart';

class PermissionsManager {
  static const AppLogger _log = AppLogger('Permissions');

  static Future<void> requestAllPermissions() async {
    try {
      for (var permission in permissions) {
        final status = await _requestPermission(permission);
        
        if (status) {
          _log.info(
              "Permission '${permission.toString().split('.').last}' granted.");
        } else {
          _log.info(
              "Permission '${permission.toString().split('.').last}' denied.");
        }
      }
    } catch (e, s) {
      _log.warning('Requesting permissions failed', e, s);
    }
  }

  static Future<bool> _requestPermission(Permission permission) async {
    final status = await permission.request();
    return status.isGranted;
  }
}