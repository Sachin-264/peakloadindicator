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

  // Close all tracked session databases
  Future<void> closeAllSessionDatabases() async {
    print("[SessionDatabaseManager] Closing all session databases...");
    for (var dbPath in _openDatabases.keys.toList()) {
      final db = _openDatabases[dbPath];
      if (db != null) {
        try {
          await db.close();
          print("[SessionDatabaseManager] Closed database: $dbPath");
        } catch (e) {
          print("[SessionDatabaseManager] Error closing database $dbPath: $e");
        }
      }
      _openDatabases.remove(dbPath);
    }
    print("[SessionDatabaseManager] All session databases closed. Open databases: ${_openDatabases.length}");
  }

  // Check if any databases are still open
  bool get hasOpenDatabases => _openDatabases.isNotEmpty;
}