// ignore_for_file: file_names, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:intl/intl.dart';

import 'package:taskwarrior/app/utils/constants/constants.dart';
import 'package:taskwarrior/app/utils/theme/app_settings.dart';

class DateTimeWidget extends StatelessWidget {
  const DateTimeWidget({
    super.key,
    required this.name,
    required this.value,
    required this.callback,
  });

  final String name;

  final dynamic value;
  final void Function(dynamic) callback;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppSettings.isDarkMode
          ? const Color.fromARGB(255, 57, 57, 57)
          : Colors.white,
      child: ListTile(
        textColor: AppSettings.isDarkMode
            ? Colors.white
            : const Color.fromARGB(255, 48, 46, 46),
        title: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              RichText(
                text: TextSpan(
                  children: <TextSpan>[
                    TextSpan(
                      text: '$name:'.padRight(13),
                      style: GoogleFonts.poppins(
                        fontWeight: TaskWarriorFonts.bold,
                        fontSize: TaskWarriorFonts.fontSizeMedium,
                        color: AppSettings.isDarkMode
                            ? Colors.white
                            : Colors.black,
                      ),
                    ),
                    TextSpan(
                      text: value ?? "not selected",
                      style: GoogleFonts.poppins(
                        fontSize: TaskWarriorFonts.fontSizeMedium,
                        color: AppSettings.isDarkMode
                            ? Colors.white
                            : Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        onTap: () async {
          var initialDate = DateFormat("E, M/d/y h:mm:ss a").parse(
              value?.replaceAll(RegExp(r'\s+'), ' ') ??
                  DateFormat("E, M/d/y h:mm:ss a").format(DateTime.now()));

          var date = await showDatePicker(
            context: context,
            initialDate: initialDate,
            firstDate: DateTime
                .now(), // sets the earliest selectable date to the current date. This prevents the user from selecting a date in the past.
            lastDate: DateTime(2037, 12, 31), // < 2038-01-19T03:14:08.000Z
          );
          if (date != null) {
            var time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.now(),
            );
            if (time != null) {
              var dateTime = date.add(
                Duration(
                  hours: time.hour,
                  minutes: time.minute,
                ),
              );
              dateTime = dateTime.add(
                Duration(
                  hours: time.hour - dateTime.hour,
                ),
              );
              // Check if the selected time is in the past
              if (dateTime.isBefore(DateTime.now())) {
                // Show a message that past times can't be set
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      "Can't set times in the past",
                      style: TextStyle(
                        color: AppSettings.isDarkMode
                            ? TaskWarriorColors.kprimaryTextColor
                            : TaskWarriorColors.kLightPrimaryTextColor,
                      ),
                    ),
                    backgroundColor: AppSettings.isDarkMode
                        ? TaskWarriorColors.ksecondaryBackgroundColor
                        : TaskWarriorColors.kLightSecondaryBackgroundColor,
                    duration: const Duration(seconds: 2),
                  ),
                );
              } else {
                // If the time is not in the past, proceed as usual
                return callback(dateTime.toUtc());
              }
            }
          }
        },
        onLongPress: () => callback(null),
      ),
    );
  }
}

class StartWidget extends StatelessWidget {
  const StartWidget({
    required this.name,
    required this.value,
    required this.callback,
    super.key,
  });

  final String name;
  final dynamic value;
  final void Function(dynamic) callback;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppSettings.isDarkMode
          ? const Color.fromARGB(255, 57, 57, 57)
          : Colors.white,
      child: ListTile(
        textColor: AppSettings.isDarkMode
            ? Colors.white
            : const Color.fromARGB(255, 48, 46, 46),
        title: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              RichText(
                text: TextSpan(
                  children: <TextSpan>[
                    TextSpan(
                      text: '$name:'.padRight(13),
                      style: GoogleFonts.poppins(
                        fontWeight: TaskWarriorFonts.bold,
                        fontSize: TaskWarriorFonts.fontSizeMedium,
                        color: AppSettings.isDarkMode
                            ? Colors.white
                            : Colors.black,
                      ),
                    ),
                    TextSpan(
                      text: value ?? "not selected",
                      style: GoogleFonts.poppins(
                        fontSize: TaskWarriorFonts.fontSizeMedium,
                        color: AppSettings.isDarkMode
                            ? Colors.white
                            : Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        onTap: () {
          if (value != null) {
            callback(null);
          } else {
            var now = DateTime.now().toUtc();
            callback(DateTime.utc(
              now.year,
              now.month,
              now.day,
              now.hour,
              now.minute,
              now.second,
            ));
          }
        },
      ),
    );
  }
}
