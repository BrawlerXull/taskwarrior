import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:taskwarrior/app/utils/debug_logger/app_logger.dart';
import 'package:taskwarrior/app/utils/permissions/permissions_manager.dart';

class PermissionController extends GetxController {
  static const AppLogger _log = AppLogger('Permissions');

  final RxBool isStorageGranted = false.obs;
  final RxBool isNotificationGranted = false.obs;
  final RxBool isExteternalStorageGranted = false.obs;
  final RxBool isLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    checkPermissions();
  }

  Future<void> checkPermissions() async {
    try {
      isStorageGranted.value = await Permission.storage.status.isGranted;
      isNotificationGranted.value =
          await Permission.notification.status.isGranted;
      isExteternalStorageGranted.value =
          await Permission.manageExternalStorage.status.isGranted;
    } catch (e, s) {
      _log.warning('Checking permission status failed', e, s);
    }
  }

  Future<void> requestPermissions() async {
    try {
      isLoading.value = true;

      if (!isStorageGranted.value &&
          !isNotificationGranted.value &&
          !isExteternalStorageGranted.value) {
        await PermissionsManager.requestAllPermissions();
      }
      Get.offNamed('/home');
    } catch (e, s) {
      _log.error('Requesting permissions failed', e, s);
    } finally {
      isLoading.value = false;
    }
  }

  void gotoHome() async {
    try {
      await Get.offNamed('/home');
    } catch (e, s) {
      _log.error('Opening the home screen failed', e, s);
    }
  }
}
