import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:loggy/loggy.dart';
import 'package:taskwarrior/app/models/storage/client.dart';
import 'package:taskwarrior/app/utils/constants/taskwarrior_colors.dart';
import 'package:taskwarrior/app/utils/constants/taskwarrior_fonts.dart';
import 'package:taskwarrior/app/utils/constants/utilites.dart';

import 'package:taskwarrior/app/utils/gen/fonts.gen.dart';
import 'package:taskwarrior/app/utils/theme/app_settings.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/manage_task_server_controller.dart';

class ManageTaskServerPageAppBar extends StatelessWidget implements PreferredSizeWidget{
  final ManageTaskServerController controller;
  const ManageTaskServerPageAppBar({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: TaskWarriorColors.kprimaryBackgroundColor,
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Configure TaskServer",
            style: TextStyle(
              fontFamily: FontFamily.poppins,
              color: TaskWarriorColors.white,
              fontSize: TaskWarriorFonts.fontSizeLarge,
            ),
          ),
          Text(
            controller.alias.value == ''
                ? controller.profile.value
                : controller.alias.value,
            // style: GoogleFonts.poppins(
            //   color: TaskWarriorColors.white,
            //   fontSize: TaskWarriorFonts.fontSizeSmall,
            // ),
            style: TextStyle(
              fontFamily: FontFamily.poppins,
              color: TaskWarriorColors.white,
              fontSize: TaskWarriorFonts.fontSizeSmall,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            Icons.info,
            color: TaskWarriorColors.white,
          ),
          onPressed: () async {
            String url =
                "https://github.com/CCExtractor/taskwarrior-flutter?tab=readme-ov-file#taskwarrior-mobile-app";
            if (!await launchUrl(Uri.parse(url))) {
              throw Exception('Could not launch $url');
            }
          },
        ),
        if (kDebugMode)
          IconButton(
            icon: Icon(
              Icons.bug_report,
              color: TaskWarriorColors.white,
            ),
            onPressed: controller.setConfigurationFromFixtureForDebugging,
          ),
        IconButton(
          icon: Icon(
            Icons.show_chart,
            color: TaskWarriorColors.white,
          ),
          onPressed: () async {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) {
                return Utils.showAlertDialog(
                  title: const Text('Fetching statistics...'),
                  content: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Please wait...'),
                    ],
                  ),
                );
              },
            );

            try {
              // Fetch statistics header from storage
              var header =
                  await controller.storage.home.statistics(await client());

              // Determine the maximum key length for formatting purposes
              var maxKeyLength = header.keys
                  .map<int>((key) => (key as String).length)
                  .reduce(max);

              // Dismiss the loading dialog
              // Navigator.of(context).pop();
              Get.back();

              // Show statistics in a dialog
              await showDialog(
                context: context,
                builder: (context) => Utils.showAlertDialog(
                  scrollable: true,
                  title: const Text(
                    'Statistics:',
                    style: TextStyle(),
                  ),
                  content: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Display each key-value pair in the statistics header
                            for (var key in header.keys.toList())
                              Text(
                                '${'$key:'.padRight(maxKeyLength + 1)} ${header[key]}',
                                style: TextStyle(
                                  color: AppSettings.isDarkMode
                                      ? TaskWarriorColors.white
                                      : TaskWarriorColors.black,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    ElevatedButton(
                      onPressed: () {
                        // Navigator.of(context).pop();
                        Get.back();
                      },
                      child: Text(
                        'Ok',
                        style: TextStyle(
                          color: AppSettings.isDarkMode
                              ? TaskWarriorColors.white
                              : TaskWarriorColors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            } on Exception catch (e, trace) {
              // Dismiss the loading dialog
              // Navigator.of(context).pop();
              Get.back();

              //Displaying Error message.
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(
                    trace.toString().startsWith("#0")
                        ? "Please set up your TaskServer."
                        : e.toString(),
                    style: TextStyle(
                      color: AppSettings.isDarkMode
                          ? TaskWarriorColors.kprimaryTextColor
                          : TaskWarriorColors.kLightPrimaryTextColor,
                    ),
                  ),
                  backgroundColor: AppSettings.isDarkMode
                      ? TaskWarriorColors.ksecondaryBackgroundColor
                      : TaskWarriorColors.kLightSecondaryBackgroundColor,
                  duration: const Duration(seconds: 2)));
              // Log the error and trace
              logError(e, trace);
              // Refresh the state of ProfilesWidget
            }
          },
        ),
      ],
      leading: BackButton(
        color: TaskWarriorColors.white,
      ),
    );
  }
  @override
  Size get preferredSize => AppBar().preferredSize;
}
