import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';


class SessionDatabaseManager {
  static final SessionDatabaseManager _instance = SessionDatabaseManager._internal();
  factory SessionDatabaseManager() => _instance;
  SessionDatabaseManager._internal();

  final Map<String, Database> _openDatabases = {};

  // Open a session database and track it
  Future<Database> openSessionDatabase(String sessionDbName) async {
    final appSupportDir = await getApplicationSupportDirectory();
    final dataFolderPath = path.join(appSupportDir.path, 'CountronicsData');
    final dbPath = path.join(dataFolderPath, sessionDbName);

    // Check if already open and tracked to return existing instance
    if (_openDatabases.containsKey(dbPath) && _openDatabases[dbPath]!.isOpen) {
      print("[SessionDatabaseManager] Database already open and tracked: $dbPath");
      return _openDatabases[dbPath]!;
    }

    try {
      final db = await databaseFactoryFfi.openDatabase(dbPath);
      _openDatabases[dbPath] = db;
      print("[SessionDatabaseManager] Opened and tracked database: $dbPath");
      return db;
    } catch (e) {
      print("[SessionDatabaseManager] Error opening database $dbPath: $e");
      rethrow;
    }
  }

  // NEW: Method to register an already open database from another manager (e.g., DatabaseManager)
  // This is crucial for SessionDatabaseManager to know about the main database.
  void addManagedDatabase(String dbPath, Database db) {
    // Only add if not already present or if the existing entry is for a closed database.
    if (!_openDatabases.containsKey(dbPath) || !_openDatabases[dbPath]!.isOpen) {
      _openDatabases[dbPath] = db;
      print("[SessionDatabaseManager] Registered externally managed database: $dbPath");
    } else {
      // Optional: Log if already registered, can be useful for debugging hot reloads
      print("[SessionDatabaseManager] Database already registered and open: $dbPath");
    }
  }

  // NEW: Method to unregister a database when it's explicitly closed elsewhere (e.g., by DatabaseManager)
  void removeManagedDatabase(String dbPath) {
    if (_openDatabases.remove(dbPath) != null) {
      print("[SessionDatabaseManager] Unregistered database: $dbPath");
    } else {
      print("[SessionDatabaseManager] Database not found for unregistration: $dbPath");
    }
  }

  // Close all tracked session databases
  Future<void> closeAllSessionDatabases() async {
    print("[SessionDatabaseManager] Closing all managed databases...");
    // Create a list from keys to avoid concurrent modification during iteration
    final List<String> pathsToClose = _openDatabases.keys.toList();

    for (var dbPath in pathsToClose) {
      final db = _openDatabases[dbPath];
      if (db != null) {
        try {
          if (db.isOpen) { // Check if it's actually open before trying to close
            await db.close();
            print("[SessionDatabaseManager] Closed database: $dbPath");
          } else {
            print("[SessionDatabaseManager] Database already closed or not open: $dbPath");
          }
        } catch (e) {
          print("[SessionDatabaseManager] Error closing database $dbPath: $e");
        }
      }
      // Always remove from map regardless of close success/failure.
      // The `remove` method of Map ensures it's gone from tracking.
      _openDatabases.remove(dbPath);
    }
    print("[SessionDatabaseManager] All managed databases closed. Remaining open: ${_openDatabases.length}");
  }

  // Check if any databases are still open
  bool get hasOpenDatabases => _openDatabases.isNotEmpty;
}