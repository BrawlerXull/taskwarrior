import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:taskwarrior/app/services/deep_link_service.dart';

import 'package:taskwarrior/app/utils/app_settings/app_settings.dart';
import 'package:taskwarrior/app/utils/debug_logger/app_logger.dart';
import 'package:taskwarrior/app/utils/debug_logger/log_database_helper.dart';
import 'package:taskwarrior/app/utils/themes/dark_theme.dart';
import 'package:taskwarrior/app/utils/themes/light_theme.dart';
import 'package:taskwarrior/rust_bridge/frb_generated.dart';
import 'app/routes/app_pages.dart';

const AppLogger _log = AppLogger('App');

DynamicLibrary loadNativeLibrary() {
  if (Platform.isIOS) {
    return DynamicLibrary.open('Frameworks/tc_helper.framework/tc_helper');
  } else if (Platform.isAndroid) {
    return DynamicLibrary.open('libtc_helper.so');
  } else if (Platform.isMacOS) {
    return DynamicLibrary.open('tc_helper.framework/tc_helper');
  }
  throw UnsupportedError(
      'Platform ${Platform.operatingSystem} is not supported');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Attach the log store before anything logs, so boot problems are kept.
  AppLogger.attachSink(LogDatabaseHelper.instance);
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _log.error('Uncaught Flutter error', details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _log.error('Uncaught async error', error, stack);
    return true;
  };

  _log.info('App starting');

  loadNativeLibrary();
  await RustLib.init();

  await AppSettings.init();

  // fix: Actually await the service initialization so the OS intent is caught BEFORE runApp.
  await Get.putAsync<DeepLinkService>(() async {
    final service = DeepLinkService();
    await service.init();
    return service;
  }, permanent: true);
  runApp(
    GetMaterialApp(
      darkTheme: darkTheme,
      theme: lightTheme,
      title: "Application",
      initialRoute: AppPages.INITIAL,
      unknownRoute: AppPages.routes.firstWhere(
        (page) => page.name == AppPages.INITIAL,
        orElse: () {
          _log.warning('Unknown route requested, falling back to default');
          return AppPages.routes.first;
        },
      ),
      getPages: AppPages.routes,
      themeMode: AppSettings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
    ),
  );
}
