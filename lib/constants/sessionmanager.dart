// In constants/sessionmanager.dart

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../Pages/logScreen/log.dart'; // Ensure this is sqflite_common_ffi

class SessionDatabaseManager {
  static final SessionDatabaseManager _instance = SessionDatabaseManager._internal();
  factory SessionDatabaseManager() => _instance;
  SessionDatabaseManager._internal();

  // A dedicated version for session-specific databases.
  static const int _sessionDbVersion = 1; // Start at version 1 for session DBs

  final Map<String, Database> _managedDatabases = {};

  // Helper for consistent log timestamp
  static String _currentTimeForSessionManager() => DateTime.now().toIso8601String().substring(0, 19);

  Future<Database> openSessionDatabase(String sessionDbName) async {
    final appDocumentsDir = await getApplicationDocumentsDirectory();
    final dataFolderPath = path.join(appDocumentsDir.path, 'CountronicsData');
    final dbPath = path.join(dataFolderPath, sessionDbName);

    // Ensure the directory exists before attempting to open/create the database
    await Directory(dataFolderPath).create(recursive: true);

    // Check if database is already open and managed
    if (_managedDatabases.containsKey(dbPath) && _managedDatabases[dbPath]!.isOpen) {
      print("[${_currentTimeForSessionManager()}] Database already open and tracked: $dbPath");
      return _managedDatabases[dbPath]!;
    }

    try {
      final db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: _sessionDbVersion, // Use session specific version
          onCreate: (db, version) async {
            print("[${_currentTimeForSessionManager()}] Creating session database '$sessionDbName' version $version");
            await _initializeSessionDatabaseSchema(db); // <--- THIS IS THE KEY FIX
            _managedDatabases[dbPath] = db; // Register the database after creation
            print("[${_currentTimeForSessionManager()}] Session database '$sessionDbName' created and registered.");
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            print("[${_currentTimeForSessionManager()}] Upgrading session database '$sessionDbName' from $oldVersion to $newVersion");
            // Implement upgrade logic for session tables if needed in the future
            _managedDatabases[dbPath] = db; // Register the database after upgrade
          },
          onOpen: (db) {
            print("[${_currentTimeForSessionManager()}] Opening session database: '$sessionDbName'");
            _managedDatabases[dbPath] = db; // Register the database upon opening
          },
        ),
      );
      print("[${_currentTimeForSessionManager()}] Opened and tracked database: $dbPath");
      return db;
    } catch (e) {
      print("[${_currentTimeForSessionManager()}] ERROR opening session database $dbPath: $e");
      rethrow;
    }
  }

  // --- New method to define schema for session databases ---
  // This schema MUST match the tables (Test, Test1, Test2) inserted into
  // from AutoStartScreen's _saveData method.
  Future<void> _initializeSessionDatabaseSchema(Database db) async {
    print("[${_currentTimeForSessionManager()}] Initializing schema for session database.");
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Test (
        RecNo REAL PRIMARY KEY, FName TEXT, OperatorName TEXT, TDate TEXT, TTime TEXT,
        ScanningRate REAL, ScanningRateHH REAL, ScanningRateMM REAL, ScanningRateSS REAL,
        TestDurationDD REAL, TestDurationHH REAL, TestDurationMM REAL, TestDurationSS REAL,
        GraphVisibleArea REAL, BaseLine REAL, FullScale REAL, Descrip TEXT,
        AbsorptionPer REAL, NOR REAL, FLName TEXT, XAxis TEXT, XAxisRecNo REAL,
        XAxisUnit TEXT, XAxisCode REAL, TotalChannel INTEGER, MaxYAxis REAL, MinYAxis REAL, DBName TEXT
      )
    ''');
    print("[${_currentTimeForSessionManager()}] Created Test table.");

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Test1 (
        RecNo REAL, SNo REAL, SlNo REAL, ChangeTime TEXT, AbsDate TEXT, AbsTime TEXT,
        AbsDateTime TEXT, Shown TEXT, AbsAvg REAL,
        ${List.generate(100, (i) => 'AbsPer${i + 1} REAL').join(', ')}
      )
    ''');
    print("[${_currentTimeForSessionManager()}] Created Test1 table with 100 AbsPer columns.");

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Test2 (
        RecNo REAL PRIMARY KEY,
        ${List.generate(100, (i) => 'ChannelName${i + 1} TEXT').join(', ')}
      )
    ''');
    print("[${_currentTimeForSessionManager()}] Created Test2 table with 100 ChannelName columns.");

    print("[${_currentTimeForSessionManager()}] Session database schema initialized.");
  }

  // ... (rest of your SessionDatabaseManager methods: addManagedDatabase, removeManagedDatabase, closeAllManagedDatabases, hasOpenDatabases)
  // These should be copied directly from your last provided SessionDatabaseManager file.
  void addManagedDatabase(String dbPath, Database db) {
    if (!_managedDatabases.containsKey(dbPath) || !_managedDatabases[dbPath]!.isOpen) {
      _managedDatabases[dbPath] = db;
      print("[${_currentTimeForSessionManager()}] Registered externally managed database: $dbPath");
    } else {
      print("[${_currentTimeForSessionManager()}] Database already registered and open: $dbPath");
    }
  }

  void removeManagedDatabase(String dbPath) {
    if (_managedDatabases.remove(dbPath) != null) {
      print("[${_currentTimeForSessionManager()}] Unregistered database: $dbPath");
    } else {
      print("[${_currentTimeForSessionManager()}] Database not found for unregistration: $dbPath");
    }
  }

  Future<void> closeAllManagedDatabases() async {
    print("[${_currentTimeForSessionManager()}] Closing all managed databases...");
    final List<String> pathsToClose = _managedDatabases.keys.toList();

    for (var dbPath in pathsToClose) {
      final db = _managedDatabases[dbPath];
      if (db != null) {
        try {
          if (db.isOpen) {
            await db.close();
            print("[${_currentTimeForSessionManager()}] Closed database: $dbPath");
          } else {
            print("[${_currentTimeForSessionManager()}] Database already closed or not open: $dbPath");
          }
        } catch (e) {
          print("[${_currentTimeForSessionManager()}] Error closing database $dbPath: $e");
        }
      }
      _managedDatabases.remove(dbPath);
    }
    print("[${_currentTimeForSessionManager()}] All managed databases closed. Remaining open: ${_managedDatabases.length}");
  }

  bool get hasOpenDatabases => _managedDatabases.isNotEmpty;
}