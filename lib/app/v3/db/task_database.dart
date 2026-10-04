import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:taskwarrior/app/utils/debug_logger/app_logger.dart';
import 'package:taskwarrior/app/v3/models/task.dart';

class TaskDatabase {
  static const AppLogger _log = AppLogger('TaskDatabase');

  Database? _database;

  Future<void> open() async {
    String path = await getDatabasePathForCurrentProfile();
    await _open(path);
  }

  Future<void> _open(path) async {
    _database = await openDatabase(path, version: 2,
        onCreate: (Database db, version) async {
      await db.execute('''
            CREATE TABLE Tasks (
              uuid TEXT PRIMARY KEY,
              id INTEGER,
              description TEXT,
              project TEXT,
              status TEXT,
              urgency REAL,
              priority TEXT,
              due TEXT,
              end TEXT,
              entry TEXT,
              modified TEXT,
              start TEXT,
              wait TEXT,
              rtype TEXT,
              recur TEXT
            )
          ''');
      await db.execute('''
            CREATE TABLE Tags (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              task_uuid TEXT NOT NULL,
              task_id INTEGER NOT NULL,
              FOREIGN KEY (task_uuid, task_id) 
                REFERENCES Tasks (uuid, id) 
                ON DELETE CASCADE
                ON UPDATE CASCADE 
            )
          ''');
      await db.execute('''
            CREATE TABLE Annotations (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              entry TEXT NOT NULL,
              description TEXT NOT NULL,
              task_uuid TEXT NOT NULL,
              task_id INTEGER NOT NULL,
              FOREIGN KEY (task_uuid, task_id) 
                REFERENCES Tasks (uuid, id) 
                ON DELETE CASCADE
                ON UPDATE CASCADE 
            )
          ''');
      await db.execute('''
            CREATE TABLE Depends (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              d_uuid TEXT NOT NULL,
              task_uuid TEXT NOT NULL,
              task_id INTEGER NOT NULL,
              FOREIGN KEY (task_uuid, task_id) 
                REFERENCES Tasks (uuid, id) 
                ON DELETE CASCADE
                ON UPDATE CASCADE 
            )
          ''');
    });
    _log.debug('Opened task database at $path');
  }

  Future<void> openForProfile(String profile) async {
    String path = await getDatabasePathForProfile(profile);
    await _open(path);
  }

  Future<void> ensureDatabaseIsOpen() async {
    if (_database == null) {
      await open();
    }
  }

  Future<List<TaskForC>> fetchTasksFromDatabase() async {
    await ensureDatabaseIsOpen();

    final List<Map<String, dynamic>> maps = await _database!.query('Tasks');
    List<TaskForC> a = await Future.wait(
      maps.map((mapItem) => getObjectForTask(mapItem)).toList(),
    );
    _log.debug('Fetched ${a.length} tasks from the database');
    return a;
  }

  Future<void> deleteAllTasksInDB() async {
    await ensureDatabaseIsOpen();
    _log.info('Marking all tasks as deleted');
    await _database!.update(
      'Tasks',
      {'status': 'deleted'},
    );
  }

  Future<void> insertTask(TaskForC task) async {
    await ensureDatabaseIsOpen();
    List<String> taskTags = task.tags ?? [];
    List<String> taskDepends = task.depends ?? [];
    List<Map<String, String?>> taskAnnotations = task.annotations != null
        ? task.annotations!
            .map((a) => {"entry": a.entry, "description": a.description})
            .toList()
        : [];
    _log.debug('Inserting task ${task.uuid} with ${taskTags.length} tags');
    var map = task.toJson();
    map.remove("tags");
    map.remove("depends");
    map.remove("annotations");
    await _database!.insert(
      'Tasks',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (taskTags.isNotEmpty) {
      // Use the ID from the task object itself for consistency
      await setTagsForTask(task.uuid ?? '', task.id, taskTags.toList());
    }
    if (taskDepends.isNotEmpty) {
      await setDependsForTask(task.uuid ?? '', task.id, taskDepends.toList());
    }
    if (taskAnnotations.isNotEmpty) {
      await setAnnotationsForTask(
          task.uuid ?? '', task.id, taskAnnotations.toList());
    }
  }

  Future<void> updateTask(TaskForC task) async {
    await ensureDatabaseIsOpen();
    List<String> taskTags = task.tags?.map((e) => e.toString()).toList() ?? [];
    List<String> taskDepends =
        task.depends?.map((e) => e.toString()).toList() ?? [];
    _log.debug('Updating task ${task.uuid} with ${taskTags.length} tags and '
        '${taskDepends.length} dependencies');
    List<Map<String, String?>> taskAnnotations = task.annotations != null
        ? task.annotations!
            .map((a) => {"entry": a.entry, "description": a.description})
            .toList()
        : [];
    var map = task.toJson();
    map.remove("tags");
    map.remove("depends");
    map.remove("annotations");
    await _database!.update(
      'Tasks',
      map,
      where: 'uuid = ?',
      whereArgs: [task.uuid],
    );
    if (taskTags.isNotEmpty) {
      await setTagsForTask(task.uuid ?? '', task.id, taskTags.toList());
    }
    if (taskDepends.isNotEmpty) {
      await setDependsForTask(task.uuid ?? '', task.id, taskDepends.toList());
    }
    if (taskAnnotations.isNotEmpty) {
      await setAnnotationsForTask(
          task.uuid ?? '', task.id, taskAnnotations.toList());
    }
  }

  Future<TaskForC?> getTaskByUuid(String uuid) async {
    await ensureDatabaseIsOpen();

    List<Map<String, dynamic>> maps = await _database!.query(
      'Tasks',
      where: 'uuid = ?',
      whereArgs: [uuid],
    );

    if (maps.isNotEmpty) {
      return await getObjectForTask(maps.first);
    } else {
      return null;
    }
  }

  Future<void> markTaskAsCompleted(String uuid) async {
    await ensureDatabaseIsOpen();

    await _database!.update(
      'Tasks',
      {'modified': (DateTime.now()).toIso8601String(), 'status': 'completed'},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
    _log.debug('Marked task $uuid as completed');
  }

  Future<void> markTaskAsDeleted(String uuid) async {
    await ensureDatabaseIsOpen();

    await _database!.update(
      'Tasks',
      {'status': 'deleted'},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
    _log.debug('Marked task $uuid as deleted');
  }

  Future<void> saveEditedTaskInDB(
    String uuid,
    String newDescription,
    String newProject,
    String newStatus,
    String newPriority,
    String newDue,
    List<String> newTags,
  ) async {
    await ensureDatabaseIsOpen();

    await _database!.update(
      'Tasks',
      {
        'description': newDescription,
        'project': newProject,
        'status': newStatus,
        'priority': newPriority,
        'due': newDue,
        'modified': DateTime.now().toIso8601String(),
      },
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
    _log.debug('Saved edits to task $uuid');
    if (newTags.isNotEmpty) {
      TaskForC? task = await getTaskByUuid(uuid);
      await setTagsForTask(uuid, task?.id ?? 0, newTags.toList());
    }
  }

  Future<List<TaskForC>> findTasksWithoutUUIDs() async {
    await ensureDatabaseIsOpen();

    List<Map<String, dynamic>> maps = await _database!.query(
      'Tasks',
      where: 'uuid IS NULL OR uuid = ?',
      whereArgs: [''],
    );
    _log.debug('Found ${maps.length} tasks without a UUID');
    return await Future.wait(
      maps.map((mapItem) => getObjectForTask(mapItem)).toList(),
    );
  }

  Future<List<TaskForC>> getTasksByProject(String project) async {
    List<Map<String, dynamic>> maps = await _database!.query(
      'Tasks',
      where: 'project = ?',
      whereArgs: [project],
    );
    return await Future.wait(
      maps.map((mapItem) => getObjectForTask(mapItem)).toList(),
    );
  }

  Future<List<String>> fetchUniqueProjects() async {
    var taskDatabase = TaskDatabase();
    await taskDatabase.open();
    await taskDatabase.ensureDatabaseIsOpen();

    final List<
        Map<String,
            dynamic>> result = await taskDatabase._database!.rawQuery(
        'SELECT DISTINCT project FROM Tasks WHERE project IS NOT NULL AND status IS NOT "deleted"');

    return result.map((row) => row['project'] as String).toList();
  }

  Future<List<TaskForC>> searchTasks(String query) async {
    final List<Map<String, dynamic>> maps = await _database!.query(
      'tasks',
      where: 'description LIKE ? OR project LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
    );
    return await Future.wait(
      maps.map((mapItem) => getObjectForTask(mapItem)).toList(),
    );
  }

  Future<void> close() async {
    await _database!.close();
  }

  Future<void> deleteTask({description, due, project, priority}) async {
    await _database!.delete(
      'Tasks',
      where: 'description = ? AND due = ? AND project = ? AND priority = ?',
      whereArgs: [description, due, project, priority],
    );
  }

// Get tags using a composite key
  Future<List<String>> getTagsForTask(String uuid, int id) async {
    await ensureDatabaseIsOpen();
    final db = _database;
    if (db == null) {
      return <String>[];
    }
    final List<Map<String, dynamic>> maps = await db.query(
      'Tags',
      columns: ['name'],
      where: 'task_uuid = ? AND task_id = ?',
      whereArgs: [uuid, id],
    );
    return List.generate(maps.length, (i) {
      return maps[i]['name'] as String;
    });
  }

  // Set tags using a composite key
  Future<void> setTagsForTask(String uuid, int id, List<String> tags) async {
    try {
      await ensureDatabaseIsOpen();
      final db = _database;
      if (db == null) {
        return;
      }
      await db.transaction((txn) async {
        // Delete existing tags for the task
        await txn.delete(
          'Tags',
          where: 'task_uuid = ? AND task_id = ?',
          whereArgs: [uuid, id],
        );
        // Insert new tags
        for (String tag in tags) {
          if (tag.trim().isNotEmpty) {
            await txn.insert(
              'Tags',
              {'name': tag, 'task_uuid': uuid, 'task_id': id},
            );
          }
        }
      });
    } catch (e, s) {
      _log.error('Could not save tags for task $uuid', e, s);
    }
  }

  // depends methods
  Future<List<String>> getDependsForTask(String uuid, int id) async {
    await ensureDatabaseIsOpen();
    final db = _database;
    if (db == null) {
      return <String>[];
    }
    final List<Map<String, dynamic>> maps = await db.query(
      'Depends',
      columns: ['d_uuid'],
      where: 'task_uuid = ? AND task_id = ?',
      whereArgs: [uuid, id],
    );
    return List.generate(maps.length, (i) {
      return maps[i]['d_uuid'] as String;
    });
  }

  Future<void> setDependsForTask(
      String uuid, int id, List<String> depends) async {
    try {
      await ensureDatabaseIsOpen();
      final db = _database;
      if (db == null) {
        return;
      }
      await db.transaction((txn) async {
        await txn.delete(
          'Depends',
          where: 'task_uuid = ? AND task_id = ?',
          whereArgs: [uuid, id],
        );
        for (String dUuid in depends) {
          if (dUuid.trim().isNotEmpty) {
            await txn.insert(
              'Depends',
              {'d_uuid': dUuid, 'task_uuid': uuid, 'task_id': id},
            );
          }
        }
      });
    } catch (e, s) {
      _log.error('Could not save dependencies for task $uuid', e, s);
    }
  }

  // annotations methods
  Future<List<Map<String, String>>> getAnnotationsForTask(
      String uuid, int id) async {
    await ensureDatabaseIsOpen();
    final db = _database;
    if (db == null) {
      return <Map<String, String>>[];
    }
    final List<Map<String, dynamic>> maps = await db.query(
      'Annotations',
      columns: ['entry', 'description'],
      where: 'task_uuid = ? AND task_id = ?',
      whereArgs: [uuid, id],
    );
    return List.generate(maps.length, (i) {
      return {
        'entry': maps[i]['entry'] as String,
        'description': maps[i]['description'] as String,
      };
    });
  }

  Future<void> setAnnotationsForTask(
      String uuid, int id, List<Map<String, String?>> annotations) async {
    try {
      await ensureDatabaseIsOpen();
      final db = _database;
      if (db == null) {
        return;
      }
      await db.transaction((txn) async {
        await txn.delete(
          'Annotations',
          where: 'task_uuid = ? AND task_id = ?',
          whereArgs: [uuid, id],
        );
        for (Map<String, String?> annotation in annotations) {
          if (annotation['entry'] != null &&
              annotation['description'] != null) {
            await txn.insert(
              'Annotations',
              {
                'entry': annotation['entry'],
                'description': annotation['description'],
                'task_uuid': uuid,
                'task_id': id
              },
            );
          }
        }
      });
    } catch (e, s) {
      _log.error('Could not save annotations for task $uuid', e, s);
    }
  }

  // Assemble TaskForC object
  Future<TaskForC> getObjectForTask(Map<String, dynamic> map) async {
    final mutableMap = Map<String, dynamic>.from(map);
    mutableMap['tags'] =
        await getTagsForTask(mutableMap['uuid'], mutableMap['id']);
    mutableMap['depends'] =
        await getDependsForTask(mutableMap['uuid'], mutableMap['id']);
    mutableMap['annotations'] =
        await getAnnotationsForTask(mutableMap['uuid'], mutableMap['id']);
    TaskForC task = TaskForC.fromJson(mutableMap);
    return task;
  }

  Future<String> exportAllTasks() async {
    await ensureDatabaseIsOpen();
    final List<Map<String, dynamic>> maps = await _database!.query('Tasks');
    List<Map<String, dynamic>> tasksJson = [];
    for (var map in maps) {
      TaskForC task = await getObjectForTask(map);
      tasksJson.add(task.toJson());
    }
    _log.info('Exported ${tasksJson.length} tasks');
    return tasksJson.toString();
  }

  Future<String> getDatabasePathForCurrentProfile() async {
    var databasesPath = await getDatabasesPath();
    String profile = await getCurrentProfile() ?? 'default';
    return join(databasesPath, '$profile.db');
  }

  Future<String> getDatabasePathForProfile(String profile) async {
    var databasesPath = await getDatabasesPath();
    return join(databasesPath, '$profile.db');
  }

  Future<String?> getCurrentProfile() async {
    Directory base = await getBaseDire();
    if (File('${base.path}/current-profile').existsSync()) {
      return File('${base.path}/current-profile').readAsStringSync();
    }
    return null;
  }

  Future<Directory> getBaseDire() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? directory = prefs.getString('baseDirectory');
    Directory dir = (directory != null)
        ? Directory(directory)
        : await getDefaultDirectory();
    return dir;
  }

  Future<Directory> getDefaultDirectory() async {
    return await getApplicationDocumentsDirectory();
  }
}
