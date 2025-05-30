import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// REMOVED: import 'Security.dart'; // No longer needed here if password param is gone and no app-level encryption.


class SessionDatabaseManager {
  static final SessionDatabaseManager _instance = SessionDatabaseManager._internal();
  factory SessionDatabaseManager() => _instance;
  SessionDatabaseManager._internal();

  final Map<String, Database> _openDatabases = {};

  Future<Database> openSessionDatabase(String sessionDbName) async {
    final appDocumentsDir = await getApplicationDocumentsDirectory();
    final dataFolderPath = path.join(appDocumentsDir.path, 'CountronicsData');
    final dbPath = path.join(dataFolderPath, sessionDbName);

    await Directory(dataFolderPath).create(recursive: true);

    if (_openDatabases.containsKey(dbPath) && _openDatabases[dbPath]!.isOpen) {
      print("[SessionDatabaseManager] Database already open and tracked: $dbPath");
      return _openDatabases[dbPath]!;
    }

    try {
      final db = await databaseFactory.openDatabase( // Use databaseFactory
        dbPath,
        // REMOVED: password: Security.encryptionKey, // No password parameter here
      );
      _openDatabases[dbPath] = db;
      print("[SessionDatabaseManager] Opened and tracked database: $dbPath");
      return db;
    } catch (e) {
      print("[SessionDatabaseManager] Error opening session database $dbPath: $e");
      rethrow;
    }
  }

  void addManagedDatabase(String dbPath, Database db) {
    if (!_openDatabases.containsKey(dbPath) || !_openDatabases[dbPath]!.isOpen) {
      _openDatabases[dbPath] = db;
      print("[SessionDatabaseManager] Registered externally managed database: $dbPath");
    } else {
      print("[SessionDatabaseManager] Database already registered and open: $dbPath");
    }
  }

  void removeManagedDatabase(String dbPath) {
    if (_openDatabases.remove(dbPath) != null) {
      print("[SessionDatabaseManager] Unregistered database: $dbPath");
    } else {
      print("[SessionDatabaseManager] Database not found for unregistration: $dbPath");
    }
  }

  Future<void> closeAllSessionDatabases() async {
    print("[SessionDatabaseManager] Closing all managed databases...");
    final List<String> pathsToClose = _openDatabases.keys.toList();

    for (var dbPath in pathsToClose) {
      final db = _openDatabases[dbPath];
      if (db != null) {
        try {
          if (db.isOpen) {
            await db.close();
            print("[SessionDatabaseManager] Closed database: $dbPath");
          } else {
            print("[SessionDatabaseManager] Database already closed or not open: $dbPath");
          }
        } catch (e) {
          print("[SessionDatabaseManager] Error closing database $dbPath: $e");
        }
      }
      _openDatabases.remove(dbPath);
    }
    print("[SessionDatabaseManager] All managed databases closed. Remaining open: ${_openDatabases.length}");
  }

  bool get hasOpenDatabases => _openDatabases.isNotEmpty;
}