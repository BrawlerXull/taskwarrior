// ignore_for_file: use_build_context_synchronously, unrelated_type_equality_checks

import 'dart:collection';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:loggy/loggy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskwarrior/app/models/filters.dart';

import 'package:taskwarrior/app/models/json/task.dart';
import 'package:taskwarrior/app/models/storage.dart';
import 'package:taskwarrior/app/models/storage/client.dart';
import 'package:taskwarrior/app/models/tag_meta_data.dart';
import 'package:taskwarrior/app/modules/splash/controllers/splash_controller.dart';
import 'package:taskwarrior/app/services/tag_filter.dart';
import 'package:taskwarrior/app/utils/taskfunctions/comparator.dart';
import 'package:taskwarrior/app/utils/taskfunctions/projects.dart';
import 'package:taskwarrior/app/utils/taskfunctions/query.dart';
import 'package:taskwarrior/app/utils/taskfunctions/tags.dart';

class HomeController extends GetxController {
  final SplashController splashController = Get.find<SplashController>();
  late Storage storage;
  final RxBool pendingFilter = false.obs;
  final RxBool waitingFilter = false.obs;
  final RxString projectFilter = ''.obs;
  final RxBool tagUnion = false.obs;
  final RxString selectedSort = ''.obs;
  final RxSet<String> selectedTags = <String>{}.obs;
  final RxList<Task> queriedTasks = <Task>[].obs;
  final RxList<Task> searchedTasks = <Task>[].obs;
  final RxMap<String, TagMetadata> pendingTags = <String, TagMetadata>{}.obs;
  final RxMap<String, ProjectNode> projects = <String, ProjectNode>{}.obs;
  final RxBool sortHeaderVisible = false.obs;
  final RxBool searchVisible = false.obs;
  final TextEditingController searchController = TextEditingController();
  late RxBool serverCertExists;

  @override
  void onInit() {
    super.onInit();
    storage = Storage(
      Directory(
        '${splashController.baseDirectory.value.path}/profiles/${splashController.currentProfile.value}',
      ),
    );
    serverCertExists = RxBool(storage.guiPemFiles.serverCertExists());
    _profileSet();
    loadDelayTask();
  }

  void _profileSet() {
    pendingFilter.value = Query(storage.tabs.tab()).getPendingFilter();
    waitingFilter.value = Query(storage.tabs.tab()).getWaitingFilter();
    projectFilter.value = Query(storage.tabs.tab()).projectFilter();
    tagUnion.value = Query(storage.tabs.tab()).tagUnion();
    selectedSort.value = Query(storage.tabs.tab()).getSelectedSort();
    selectedTags.addAll(Query(storage.tabs.tab()).getSelectedTags());

    _refreshTasks();
    pendingTags.value = _pendingTags();
    projects.value = _projects();
    if (searchVisible.value) {
      toggleSearch();
    }
  }

  void _refreshTasks() {
    if (pendingFilter.value) {
      queriedTasks.value = storage.data
          .pendingData()
          .where((task) => task.status == 'pending')
          .toList();
    } else {
      queriedTasks.value = storage.data.completedData();
    }

    if (waitingFilter.value) {
      var currentTime = DateTime.now();
      queriedTasks.value = queriedTasks
          .where((task) => task.wait != null && task.wait!.isAfter(currentTime))
          .toList();
    }

    if (projectFilter.value.isNotEmpty) {
      queriedTasks.value = queriedTasks.where((task) {
        if (task.project == null) {
          return false;
        } else {
          return task.project!.startsWith(projectFilter.value);
        }
      }).toList();
    }

    queriedTasks.value = queriedTasks.where((task) {
      var tags = task.tags?.toSet() ?? {};
      if (tagUnion.value) {
        if (selectedTags.isEmpty) {
          return true;
        }
        return selectedTags.any((tag) => (tag.startsWith('+'))
            ? tags.contains(tag.substring(1))
            : !tags.contains(tag.substring(1)));
      } else {
        return selectedTags.every((tag) => (tag.startsWith('+'))
            ? tags.contains(tag.substring(1))
            : !tags.contains(tag.substring(1)));
      }
    }).toList();

    var sortColumn =
        selectedSort.value.substring(0, selectedSort.value.length - 1);
    var ascending = selectedSort.value.endsWith('+');
    queriedTasks.sort((a, b) {
      int result;
      if (sortColumn == 'id') {
        result = a.id!.compareTo(b.id!);
      } else {
        result = compareTasks(sortColumn)(a, b);
      }
      return ascending ? result : -result;
    });

    searchedTasks.assignAll(queriedTasks);
    var searchTerm = searchController.text;
    if (searchVisible.value) {
      searchedTasks.value = searchedTasks
          .where((task) =>
              task.description.contains(searchTerm) ||
              (task.annotations?.asList() ?? []).any(
                  (annotation) => annotation.description.contains(searchTerm)))
          .toList();
    }
    pendingTags.value = _pendingTags();
    projects.value = _projects();
  }

  Map<String, TagMetadata> _pendingTags() {
    var frequency = tagFrequencies(storage.data.pendingData());
    var modified = tagsLastModified(storage.data.pendingData());
    var setOfTags = tagSet(storage.data.pendingData());

    return SplayTreeMap.of({
      for (var tag in setOfTags)
        tag: TagMetadata(
          frequency: frequency[tag] ?? 0,
          lastModified: modified[tag]!,
          selected: selectedTags.contains('+$tag'),
        ),
    });
  }

  Map<String, ProjectNode> _projects() {
    var frequencies = <String, int>{};
    for (var task in storage.data.pendingData()) {
      if (task.project != null) {
        if (frequencies.containsKey(task.project)) {
          frequencies[task.project!] = (frequencies[task.project] ?? 0) + 1;
        } else {
          frequencies[task.project!] = 1;
        }
      }
    }
    return SplayTreeMap.of(sparseDecoratedProjectTree(frequencies));
  }

  void togglePendingFilter() {
    Query(storage.tabs.tab()).togglePendingFilter();
    pendingFilter.value = Query(storage.tabs.tab()).getPendingFilter();
    _refreshTasks();
  }

  void toggleWaitingFilter() {
    Query(storage.tabs.tab()).toggleWaitingFilter();
    waitingFilter.value = Query(storage.tabs.tab()).getWaitingFilter();
    _refreshTasks();
  }

  void toggleProjectFilter(String project) {
    Query(storage.tabs.tab()).toggleProjectFilter(project);
    projectFilter.value = Query(storage.tabs.tab()).projectFilter();
    _refreshTasks();
  }

  void toggleTagUnion() {
    Query(storage.tabs.tab()).toggleTagUnion();
    tagUnion.value = Query(storage.tabs.tab()).tagUnion();
    _refreshTasks();
  }

  void selectSort(String sort) {
    Query(storage.tabs.tab()).setSelectedSort(sort);
    selectedSort.value = Query(storage.tabs.tab()).getSelectedSort();
    _refreshTasks();
  }

  void toggleTagFilter(String tag) {
    if (selectedTags.contains('+$tag')) {
      selectedTags
        ..remove('+$tag')
        ..add('-$tag');
    } else if (selectedTags.contains('-$tag')) {
      selectedTags.remove('-$tag');
    } else {
      selectedTags.add('+$tag');
    }
    Query(storage.tabs.tab()).toggleTagFilter(tag);
    selectedTags.addAll(Query(storage.tabs.tab()).getSelectedTags());
    _refreshTasks();
  }

  Task getTask(String uuid) {
    return storage.data.getTask(uuid);
  }

  void mergeTask(Task task) {
    storage.data.mergeTask(task);

    _refreshTasks();
  }

  Future<void> synchronize(BuildContext context, bool isDialogNeeded) async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
              'You are not connected to the internet. Please check your network connection.',
              style: TextStyle(
                  // color: AppSettings.isDarkMode
                  //     ? TaskWarriorColors.kprimaryTextColor
                  //     : TaskWarriorColors.kLightPrimaryTextColor,
                  ),
            ),
            // backgroundColor: AppSettings.isDarkMode
            //     ? TaskWarriorColors.ksecondaryBackgroundColor
            //     : TaskWarriorColors.kLightSecondaryBackgroundColor,
            duration: Duration(seconds: 2)));
      } else {
        if (isDialogNeeded) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) {
              return Dialog(
                elevation: 5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: Container(
                  padding: const EdgeInsets.all(16.0),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16.0),
                      Text(
                        "Syncing",
                        // style: GoogleFonts.poppins(
                        //   fontSize: TaskWarriorFonts.fontSizeLarge,
                        //   fontWeight: TaskWarriorFonts.bold,
                        // ),
                      ),
                      SizedBox(height: 8.0),
                      Text(
                        "Please wait...",
                        // style: GoogleFonts.poppins(
                        //   fontSize: TaskWarriorFonts.fontSizeSmall,
                        //   fontWeight: TaskWarriorFonts.regular,
                        // ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }

        var header = await storage.home.synchronize(await client());
        _refreshTasks();
        pendingTags.value = _pendingTags();
        projects.value = _projects();

        if (isDialogNeeded) {
          Get.back();
        }

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              '${header['code']}: ${header['status']}',
              style: const TextStyle(
                  // color: AppSettings.isDarkMode
                  //     ? TaskWarriorColors.kprimaryTextColor
                  //     : TaskWarriorColors.kLightPrimaryTextColor,
                  ),
            ),
            // backgroundColor: AppSettings.isDarkMode
            //     ? TaskWarriorColors.ksecondaryBackgroundColor
            //     : TaskWarriorColors.kLightSecondaryBackgroundColor,
            duration: const Duration(seconds: 2)));
      }
    } catch (e, trace) {
      if (isDialogNeeded) {
        Get.back();
      }
      logError(e, trace);
    }
  }

  void toggleSortHeader() {
    sortHeaderVisible.value = !sortHeaderVisible.value;
  }

  void toggleSearch() {
    searchVisible.value = !searchVisible.value;
    if (!searchVisible.value) {
      searchedTasks.assignAll(queriedTasks);
      searchController.text = '';
    }
  }

  void search(String term) {
    searchedTasks.assignAll(
      queriedTasks
          .where(
            (task) =>
                task.description.toLowerCase().contains(term.toLowerCase()),
          )
          .toList(),
    );
  }

  void setInitialTabIndex(int index) {
    storage.tabs.setInitialTabIndex(index);
    pendingFilter.value = Query(storage.tabs.tab()).getPendingFilter();
    waitingFilter.value = Query(storage.tabs.tab()).getWaitingFilter();
    selectedSort.value = Query(storage.tabs.tab()).getSelectedSort();
    selectedTags.addAll(Query(storage.tabs.tab()).getSelectedTags());
    projectFilter.value = Query(storage.tabs.tab()).projectFilter();
    _refreshTasks();
  }

  void addTab() {
    storage.tabs.addTab();
  }

  List<String> tabUuids() {
    return storage.tabs.tabUuids();
  }

  int initialTabIndex() {
    return storage.tabs.initialTabIndex();
  }

  void removeTab(int index) {
    storage.tabs.removeTab(index);
    pendingFilter.value = Query(storage.tabs.tab()).getPendingFilter();
    waitingFilter.value = Query(storage.tabs.tab()).getWaitingFilter();
    selectedSort.value = Query(storage.tabs.tab()).getSelectedSort();
    selectedTags.addAll(Query(storage.tabs.tab()).getSelectedTags());
    _refreshTasks();
  }

  void renameTab({
    required String tab,
    required String name,
  }) {
    storage.tabs.renameTab(tab: tab, name: name);
  }

  String? tabAlias(String tabUuid) {
    return storage.tabs.alias(tabUuid);
  }

  RxBool isSyncNeeded = false.obs;

  void checkForSync(BuildContext context) {
    if (!isSyncNeeded.value) {
      isNeededtoSyncOnStart(context);
      isSyncNeeded.value = true;
    }
  }

  isNeededtoSyncOnStart(BuildContext context) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    bool? value;
    value = prefs.getBool('sync-onStart') ?? false;

    if (value) {
      synchronize(context, false);
    } else {}
  }

  RxBool syncOnStart = false.obs;
  RxBool syncOnTaskCreate = false.obs;
  RxBool delaytask = false.obs;
  RxBool change24hr = false.obs;

  // dialogue box

  final formKey = GlobalKey<FormState>();
  final namecontroller = TextEditingController();
  var due = Rxn<DateTime>();
  RxString dueString = ''.obs;
  RxString priority = 'M'.obs;
  final tagcontroller = TextEditingController();
  RxList<String> tags = <String>[].obs;
  RxBool inThePast = false.obs;

  Filters getFilters() {
    var selectedTagsMap = {
      for (var tag in selectedTags) tag.substring(1): tag,
    };

    var keys = (pendingTags.keys.toSet()..addAll(selectedTagsMap.keys)).toList()
      ..sort();

    var tags = {
      for (var tag in keys)
        tag: TagFilterMetadata(
          display:
              '${selectedTagsMap[tag] ?? tag} ${pendingTags[tag]?.frequency ?? 0}',
          selected: selectedTagsMap.containsKey(tag),
        ),
    };

    var tagFilters = TagFilters(
      tagUnion: tagUnion.value,
      toggleTagUnion: toggleTagUnion,
      tags: tags,
      toggleTagFilter: toggleTagFilter,
    );
    var filters = Filters(
      pendingFilter: pendingFilter.value,
      waitingFilter: waitingFilter.value,
      togglePendingFilter: togglePendingFilter,
      toggleWaitingFilter: toggleWaitingFilter,
      projects: projects,
      projectFilter: projectFilter.value,
      toggleProjectFilter: toggleProjectFilter,
      tagFilters: tagFilters,
    );
    return filters;
  }

  // select profile
  void refreshTaskWithNewProfile() {
    storage = Storage(
      Directory(
        '${splashController.baseDirectory.value.path}/profiles/${splashController.currentProfile.value}',
      ),
    );
    _refreshTasks();
  }

  RxBool useDelayTask = false.obs;

  Future<void> loadDelayTask() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    useDelayTask.value = prefs.getBool('delaytask') ?? false;
  }
}
