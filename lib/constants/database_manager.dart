import 'package:peakloadindicator/constants/sessionmanager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../Pages/NavPages/channel.dart';
import '../Pages/logScreen/log.dart';
import 'Security.dart'; // Security.dart is still imported for other potential uses, but its encryption logic will be removed/simplified.


class DatabaseManager {
  static final DatabaseManager _instance = DatabaseManager._internal();
  Database? _database;

  // _dbVersion indicates schema version. Encryption is not tied to this version in this approach.
  static const int _dbVersion = 7; // No change needed for this version number, as schema changes are internal

  factory DatabaseManager() => _instance;

  DatabaseManager._internal();

  Future<Database> get database async {
    final databasesPath = await getDatabasesPath();
    final dbPath = path.join(databasesPath, 'Countronics.db');

    if (_database != null && _database!.isOpen) {
      SessionDatabaseManager().addManagedDatabase(dbPath, _database!);
      return _database!;
    }

    await Directory(path.dirname(dbPath)).create(recursive: true);

    try {
      _database = await databaseFactory.openDatabase( // Use the globally set databaseFactory (which is databaseFactoryFfi)
        dbPath,
        options: OpenDatabaseOptions(
          version: _dbVersion,
          // REMOVED: password: Security.encryptionKey, // No password parameter here
          onCreate: (db, version) async {
            print('[DatabaseManager] Creating database version $version');
            LogPage.addLog('[${_currentTime}] Creating database version $version');
            await _initializeDatabase(db);
            SessionDatabaseManager().addManagedDatabase(dbPath, db);
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            print('[DatabaseManager] Upgrading database from $oldVersion to $newVersion');
            LogPage.addLog('[${_currentTime}] Upgrading database from $oldVersion to $newVersion');

            // REMOVED: All PRAGMA rekey logic for SQLCipher
            // If oldVersion < _dbVersion && newVersion == _dbVersion,
            // this is just a schema upgrade. No encryption rekeying.

            // --- Your existing schema upgrade logic ---
            // Ensure these run for relevant version changes.
            if (oldVersion < 2) {
              await db.execute('''
                CREATE TABLE IF NOT EXISTS AuthSettings (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  isAuthEnabled INTEGER,
                  username TEXT,
                  password TEXT
                )
              ''');
              await db.execute('''
                CREATE TABLE IF NOT EXISTS ChannelSetup (
                  RecNo INTEGER PRIMARY KEY,
                  ChannelName TEXT,
                  StartingCharacter TEXT,
                  DataLength INTEGER,
                  Unit TEXT,
                  DecimalPlaces INTEGER
                )
              ''');
              LogPage.addLog('[${_currentTime}] Added AuthSettings and ChannelSetup tables');
            }
            if (oldVersion < 3) {
              await addColumnIfNotExists(db, 'AuthSettings', 'companyName', 'TEXT');
              await addColumnIfNotExists(db, 'AuthSettings', 'companyAddress', 'TEXT');
              await addColumnIfNotExists(db, 'AuthSettings', 'logoPath', 'TEXT');
            }
            if (oldVersion < 4) {
              await db.execute('''
                CREATE TABLE IF NOT EXISTS ChannelSetup_New (
                  RecNo INTEGER PRIMARY KEY,
                  ChannelName TEXT,
                  Unit TEXT,
                  TargetAlarmMax INTEGER,
                  TargetAlarmMin INTEGER,
                  TargetAlarmColour TEXT
                )
              ''');
              await db.execute('''
                INSERT INTO ChannelSetup_New (RecNo, ChannelName, Unit)
                SELECT RecNo, ChannelName, Unit
                FROM ChannelSetup
              ''');
              await db.execute('DROP TABLE ChannelSetup');
              await db.execute('ALTER TABLE ChannelSetup_New RENAME TO ChannelSetup');
              LogPage.addLog('[${_currentTime}] Updated ChannelSetup table schema (v4)');
            }
            if (oldVersion < 5) {
              await db.execute('''
                CREATE TABLE IF NOT EXISTS ChannelSetup_New (
                  RecNo INTEGER PRIMARY KEY,
                  ChannelName TEXT,
                  StartingCharacter TEXT,
                  DataLength INTEGER,
                  DecimalPlaces INTEGER,
                  Unit TEXT,
                  TargetAlarmMax INTEGER,
                  TargetAlarmMin INTEGER,
                  TargetAlarmColour TEXT,
                  graphLineColour TEXT,
                  ChartMaximumValue REAL,
                  ChartMinimumValue REAL
                )
              ''');
              await db.execute('''
                INSERT INTO ChannelSetup_New (
                  RecNo, ChannelName, Unit, TargetAlarmMax, TargetAlarmMin, TargetAlarmColour
                )
                SELECT
                  RecNo, ChannelName, Unit, TargetAlarmMax, TargetAlarmMin, TargetAlarmColour
                FROM ChannelSetup
              ''');
              await db.execute('''
                UPDATE ChannelSetup_New
                SET StartingCharacter = COALESCE(StartingCharacter, CASE
                  WHEN ChannelName = 'Load' THEN 'L'
                  WHEN ChannelName = 'Channel A' THEN 'A'
                  WHEN ChannelName = 'Channel B' THEN 'B'
                  WHEN ChannelName = 'Channel C' THEN 'C'
                  WHEN ChannelName = 'Channel D' THEN 'D'
                  WHEN ChannelName = 'Channel E' THEN 'E'
                  ELSE SUBSTR(ChannelName, 1, 1)
                END),
                DataLength = COALESCE(DataLength, 7),
                DecimalPlaces = COALESCE(DecimalPlaces, 1),
                graphLineColour = COALESCE(graphLineColour, 'FF0000'),
                ChartMaximumValue = COALESCE(ChartMaximumValue, 100.0),
                ChartMinimumValue = COALESCE(ChartMinimumValue, 0.0)
              ''');
              await db.execute('DROP TABLE ChannelSetup');
              await db.execute('ALTER TABLE ChannelSetup_New RENAME TO ChannelSetup');
              LogPage.addLog('[${_currentTime}] Updated ChannelSetup table schema (v5)');
            }
            if (oldVersion < 6) {
              await db.execute('''
                CREATE TABLE IF NOT EXISTS ComPort (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  selectedPort TEXT,
                  baudRate INTEGER,
                  dataBits INTEGER,
                  parity TEXT,
                  stopBits INTEGER
                )
              ''');
              LogPage.addLog('[${_currentTime}] Added ComPort table');
            }
            // This is the last schema change before v7, so it's good place to put it
            if (oldVersion < 7) {
              await addColumnIfNotExists(db, 'Test', 'TestDurationSS', 'REAL');
              LogPage.addLog('[${_currentTime}] Added TestDurationSS column to Test table');
            }
            // Add columns for Test1 and Test2 up to 100 channels during upgrade if necessary
            if (oldVersion < _dbVersion) { // This condition assumes _dbVersion means all schema up to 100 channels is included
              await _addTest1AndTest2Columns(db);
            }

            SessionDatabaseManager().addManagedDatabase(dbPath, db);
          },
          onOpen: (db) async {
            print('[DatabaseManager] Opening database');
            LogPage.addLog('[${_currentTime}] Opening database');
            SessionDatabaseManager().addManagedDatabase(dbPath, db);
          },
        ),
      );
      return _database!;
    } catch (e) {
      // Critical error: Database failed to open (e.g., corruption).
      print('[DatabaseManager] CRITICAL ERROR opening database $dbPath: $e');
      LogPage.addLog('[${_currentTime}] CRITICAL ERROR opening database $dbPath: $e');
      _database = null; // Clear the reference on failure
      rethrow; // Re-throw to inform the calling code
    }
  }

  Future<void> addColumnIfNotExists(Database db, String table, String column, String type) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final columnNames = columns.map((col) => col['name'] as String).toList();
    if (!columnNames.contains(column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
      LogPage.addLog('[${_currentTime}] Added $column to $table');
    } else {
      LogPage.addLog('[${_currentTime}] $column already exists in $table');
    }
  }

  // New helper to add columns for Test1 and Test2 up to 100 channels
  Future<void> _addTest1AndTest2Columns(Database db) async {
    print('[DatabaseManager] Ensuring Test1 and Test2 tables have 100 channels...');
    LogPage.addLog('[${_currentTime}] Ensuring Test1 and Test2 tables have 100 channels...');

    // For Test1 (AbsPer columns)
    final test1Columns = await db.rawQuery('PRAGMA table_info(Test1)');
    final test1ColumnNames = test1Columns.map((col) => col['name'] as String).toList();
    for (int i = 51; i <= 100; i++) { // Start from 51 as it was previously up to 50
      final columnName = 'AbsPer$i';
      if (!test1ColumnNames.contains(columnName)) {
        await db.execute('ALTER TABLE Test1 ADD COLUMN $columnName REAL');
        LogPage.addLog('[${_currentTime}] Added $columnName to Test1');
      }
    }

    // For Test2 (ChannelName columns)
    final test2Columns = await db.rawQuery('PRAGMA table_info(Test2)');
    final test2ColumnNames = test2Columns.map((col) => col['name'] as String).toList();
    for (int i = 51; i <= 100; i++) { // Start from 51 as it was previously up to 50
      final columnName = 'ChannelName$i';
      if (!test2ColumnNames.contains(columnName)) {
        await db.execute('ALTER TABLE Test2 ADD COLUMN $columnName TEXT');
        LogPage.addLog('[${_currentTime}] Added $columnName to Test2');
      }
    }
    print('[DatabaseManager] Test1 and Test2 tables updated for 100 channels.');
    LogPage.addLog('[${_currentTime}] Test1 and Test2 tables updated for 100 channels.');
  }

  Future<void> _initializeDatabase(Database db) async {
    print('[DatabaseManager] Initializing database schema');
    LogPage.addLog('[${_currentTime}] Initializing database schema');
    // Schema creation for a brand new database.
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
    // Modified for 100 channels
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Test1 (
        RecNo REAL, SNo REAL, SlNo REAL, ChangeTime TEXT, AbsDate TEXT, AbsTime TEXT,
        AbsDateTime TEXT, Shown TEXT, AbsAvg REAL,
        ${List.generate(100, (i) => 'AbsPer${i + 1} REAL').join(', ')}
      )
    ''');
    // Modified for 100 channels
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Test2 (
        RecNo REAL PRIMARY KEY,
        ${List.generate(100, (i) => 'ChannelName${i + 1} TEXT').join(', ')}
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS AutoStart (
        id INTEGER PRIMARY KEY AUTOINCREMENT, StartTimeHr REAL, StartTimeMin REAL,
        EndTimeHr REAL, EndTimeMin REAL, ScanTimeSec REAL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS SelectChannel (
        RecNo REAL, ChannelName TEXT, StartingCharacter TEXT, DataLength INTEGER,
        Unit TEXT, DecimalPlaces INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ChannelSetup (
        RecNo INTEGER PRIMARY KEY, ChannelName TEXT, StartingCharacter TEXT,
        DataLength INTEGER, DecimalPlaces INTEGER, Unit TEXT, TargetAlarmMax INTEGER,
        TargetAlarmMin INTEGER, TargetAlarmColour TEXT, graphLineColour TEXT,
        ChartMaximumValue REAL, ChartMinimumValue REAL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS AuthSettings (
        id INTEGER PRIMARY KEY AUTOINCREMENT, isAuthEnabled INTEGER, username TEXT,
        password TEXT, companyName TEXT, companyAddress TEXT, logoPath TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ComPort (
        id INTEGER PRIMARY KEY AUTOINCREMENT, selectedPort TEXT, baudRate INTEGER,
        dataBits INTEGER, parity TEXT, stopBits INTEGER
      )
    ''');
    print('[DatabaseManager] Database schema initialized');
    LogPage.addLog('[${_currentTime}] Database schema initialized');
  }

  // --- Your existing data access methods (getAutoStartData, getSelectedChannels, etc.) ---

  Future<Map<String, dynamic>?> getAutoStartData() async {
    final db = await database;
    try {
      final result = await db.query('AutoStart', limit: 1, orderBy: 'ROWID DESC');
      if (result.isNotEmpty) {
        LogPage.addLog('[${_currentTime}] Fetched AutoStart data');
        return result.first;
      }
      print('[DatabaseManager] AutoStart table is empty');
      LogPage.addLog('[${_currentTime}] AutoStart table is empty');
      return null;
    } catch (e) {
      print('[DatabaseManager] Error querying AutoStart table: $e');
      LogPage.addLog('[${_currentTime}] Error querying AutoStart table: $e');
      return null;
    }
  }

  Future<List<Channel>> getSelectedChannels() async {
    final db = await database;
    try {
      final result = await db.query('SelectChannel');
      final channels = result.map((row) => Channel.fromJson(row)).toList();
      print('[DatabaseManager] Fetched ${channels.length} channels from SelectChannel');
      LogPage.addLog('[${_currentTime}] Fetched ${channels.length} channels from SelectChannel');
      return channels;
    } catch (e) {
      print('[DatabaseManager] Error querying SelectChannel table: $e');
      LogPage.addLog('[${_currentTime}] Error querying SelectChannel table: $e');
      return [];
    }
  }

  Future<bool> isAuthRequired() async {
    final db = await database;
    try {
      final authData = await db.query('AuthSettings', limit: 1);
      if (authData.isNotEmpty) {
        final isAuthEnabled = authData.first['isAuthEnabled'];
        LogPage.addLog('[${_currentTime}] Checked isAuthRequired: $isAuthEnabled');
        return isAuthEnabled == 1; // Assuming it's stored as INTEGER 0 or 1
      }
      LogPage.addLog('[${_currentTime}] No auth settings found');
      return false;
    } catch (e) {
      print('[DatabaseManager] Error checking auth settings: $e');
      LogPage.addLog('[${_currentTime}] Error checking auth settings: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getAuthSettings() async {
    final db = await database;
    try {
      final authData = await db.query('AuthSettings', limit: 1);
      if (authData.isNotEmpty) {
        final result = Map<String, dynamic>.from(authData.first);
        // REMOVED: Decryption logic
        print('[DatabaseManager] Fetched auth settings');
        return result;
      }
      print('[DatabaseManager] No auth settings found');
      LogPage.addLog('[${_currentTime}] No auth settings found');
      return null;
    } catch (e) {
      print('[DatabaseManager] Error fetching auth settings: $e');
      LogPage.addLog('[${_currentTime}] Error fetching auth settings: $e');
      return null;
    }
  }

  Future<void> saveAuthSettings(
      bool isAuthEnabled,
      String username,
      String password, {
        String? companyName,
        String? companyAddress,
        String? logoPath,
        bool? isAutoSaveEnabled,
        int? autoSaveIntervalSeconds,
      }) async {
    final db = await database;
    try {
      await db.delete('AuthSettings');
      await db.insert('AuthSettings', {
        'isAuthEnabled': isAuthEnabled ? 1 : 0,
        'username': username,
        'password': password,
        'companyName': companyName ?? '',
        'companyAddress': companyAddress ?? '',
        'logoPath': logoPath,
        'isAutoSaveEnabled': isAutoSaveEnabled ?? false ? 1 : 0, // Save the new setting
        'autoSaveIntervalSeconds': autoSaveIntervalSeconds ?? 30,
      });
      print('[DatabaseManager] Auth settings saved');
      LogPage.addLog('[${_currentTime}] Auth settings saved');
    } catch (e) {
      print('[DatabaseManager] Error saving auth settings: $e');
      LogPage.addLog('[${_currentTime}] Error saving auth settings: $e');
      throw e;
    }
  }


  Future<void> saveComPortSettings(String port, int baudRate, int dataBits, String parity, int stopBits) async {
    final db = await database;
    try {
      await db.delete('ComPort');
      await db.insert('ComPort', {
        'selectedPort': port,
        'baudRate': baudRate,
        'dataBits': dataBits,
        'parity': parity,
        'stopBits': stopBits,
      });
      print('[DatabaseManager] ComPort settings saved: $port');
      LogPage.addLog('[${_currentTime}] ComPort settings saved: $port');
    } catch (e) {
      print('[DatabaseManager] Error saving ComPort settings: $e');
      LogPage.addLog('[${_currentTime}] Error saving ComPort settings: $e');
      throw e;
    }
  }

  Future<Map<String, dynamic>?> getComPortSettings() async {
    final db = await database;
    try {
      final result = await db.query('ComPort', limit: 1);
      if (result.isNotEmpty) {
        print('[DatabaseManager] Fetched ComPort settings: ${result.first}');
        LogPage.addLog('[${_currentTime}] Fetched ComPort settings');
        return result.first;
      }
      print('[DatabaseManager] ComPort table is empty');
      LogPage.addLog('[${_currentTime}] ComPort table is empty');
      return null;
    } catch (e) {
      print('[DatabaseManager] Error querying ComPort table: $e');
      LogPage.addLog('[${_currentTime}] Error querying ComPort table: $e');
      return null;
    }
  }

  Future<void> close() async {
    final String mainDbPath = path.join(await getDatabasesPath(), 'Countronics.db');
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
      print('[DatabaseManager] Main database connection (Countronics.db) closed.');
      LogPage.addLog('[${_currentTime}] Main database closed');
    } else {
      print('[DatabaseManager] Main database connection was already closed or null.');
    }
    SessionDatabaseManager().removeManagedDatabase(mainDbPath);
    print('[DatabaseManager] Main DB unregistered from SessionDatabaseManager tracking.');
  }

  static String get _currentTime => DateTime.now().toIso8601String().substring(0, 19);
}