import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager_plus/window_manager_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:synchronized/synchronized.dart';
import 'package:path/path.dart' as path;
import 'Pages/Secondary_window/Secondary_Bloc.dart';
import 'Pages/homepage.dart';
import 'Pages/NavPages/serialportscreen.dart';
import 'Pages/Secondary_window/secondary_window.dart';

// Singleton for database management
class DatabaseManager {
  static final DatabaseManager _instance = DatabaseManager._internal();
  Database? _database;

  factory DatabaseManager() => _instance;

  DatabaseManager._internal();

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    final databasesPath = await getDatabasesPath();
    final dbPath = path.join(databasesPath, 'Countronics.db');
    try {
      _database = await databaseFactoryFfi.openDatabase(dbPath);
      await _initializeDatabase();
      debugPrint('[DATABASE] Database opened at $dbPath');
    } catch (e) {
      debugPrint('[DATABASE] Error opening database: $e');
      rethrow;
    }
    return _database!;
  }

  Future<void> _initializeDatabase() async {
    final db = _database!;
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ChannelData (
          channel TEXT PRIMARY KEY,
          data TEXT,
          timestamp INTEGER
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS Windows (
          windowId INTEGER PRIMARY KEY,
          channel TEXT,
          subscribedChannels TEXT
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_channel ON ChannelData(channel)');
      debugPrint('[DATABASE] Initialized ChannelData and Windows tables');
    } catch (e) {
      debugPrint('[DATABASE] Error initializing tables: $e');
      rethrow;
    }
  }

  Future<void> close() async {
    if (_database != null && _database!.isOpen) {
      try {
        await _database!.close();
        _database = null;
        debugPrint('[DATABASE] Closed database');
      } catch (e) {
        debugPrint('[DATABASE] Error closing database: $e');
      }
    }
  }

  Future<void> setupDatabase() async {
    final databasesPath = await getDatabasesPath();
    final dbPath = path.join(databasesPath, 'Countronics.db');
    final directory = Directory(databasesPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
      debugPrint('[DATABASE] Created database directory at $databasesPath');
    }
    debugPrint('[DATABASE] Using database at $dbPath');
  }

  Future<void> updateChannelData(String channel, Map<String, dynamic> channelData) async {
    try {
      final db = await database;
      final dataJson = jsonEncode(channelData);
      await db.insert(
        'ChannelData',
        {
          'channel': channel,
          'data': dataJson,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint('[DATABASE] Updated channel data for $channel (points: ${channelData['dataPoints']?.length ?? 0})');
    } catch (e) {
      debugPrint('[DATABASE] Error updating channel data for $channel: $e');
      rethrow;
    }
  }

  Future<String> getDatabasesPath() async {
    return path.join(Directory.current.path, '.dart_tool', 'sqflite_common_ffi', 'databases');
  }
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final windowId = args.isEmpty ? 0 : int.tryParse(args[0]) ?? 0;
  try {
    await WindowManagerPlus.ensureInitialized(windowId);
  } catch (e) {
    debugPrint('[MAIN] Failed to initialize WindowManagerPlus: $e');
    return;
  }

  try {
    await DatabaseManager().setupDatabase();
  } catch (e) {
    debugPrint('[MAIN] Failed to set up database: $e');
    return;
  }

  final navigatorKey = GlobalKey<NavigatorState>();

  // Configure window options
  final windowOptions = WindowOptions(
    size: const Size(800, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );
  try {
    await WindowManagerPlus.current.waitUntilReadyToShow(windowOptions, () async {
      await WindowManagerPlus.current.show();
      await WindowManagerPlus.current.focus();
    });
  } catch (e) {
    debugPrint('[MAIN] Failed to configure window: $e');
  }

  if (args.length > 1) {
    try {
      final argsMap = jsonDecode(args[1]) as Map<String, dynamic>;
      if (argsMap.containsKey('channel') && argsMap.containsKey('channelData')) {
        runApp(
          BlocProvider(
            create: (_) => ChannelDataBloc(),
            child: MaterialApp(
              navigatorKey: navigatorKey,
              home: SecondaryWindowApp(
                channel: argsMap['channel'] as String,
                channelData: argsMap['channelData'] as Map<String, dynamic>,
                windowId: windowId,
                windowKey: argsMap['windowKey'] as String?,
              ),
            ),
          ),
        );
        debugPrint('[MAIN] Started secondary window for channel: ${argsMap['channel']}, ID: $windowId');
        return;
      }
    } catch (e) {
      debugPrint('[MAIN] Error parsing secondary window args: $e');
    }
  }

  final autoStartController = AutoStartController();
  autoStartController.startMonitoring(navigatorKey);
  runApp(
    BlocProvider(
      create: (_) => ChannelDataBloc(),
      child: MaterialApp(navigatorKey: navigatorKey, home: HomePage()),
    ),
  );
  debugPrint('[MAIN] Started primary window (ID: $windowId)');

  Timer.periodic(const Duration(minutes: 10), (timer) async {
    try {
      final db = await DatabaseManager().database;
      final threshold = DateTime.now().millisecondsSinceEpoch - 3600000; // 1 hour
      final deleted = await db.delete('ChannelData', where: 'timestamp < ?', whereArgs: [threshold]);
      debugPrint('[DATABASE] Cleaned $deleted old channel data entries');
    } catch (e) {
      debugPrint('[DATABASE] Error cleaning old channel data: $e');
    }
  });
}

class AutoStartController {
  Timer? _timer;

  void startMonitoring(GlobalKey<NavigatorState> navigatorKey) {
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      try {
        final db = await DatabaseManager().database;
        final autoStartResult = await db.query('AutoStart', limit: 1);
        if (autoStartResult.isNotEmpty) {
          final autoStart = autoStartResult.first;
          final startHr = autoStart['StartTimeHr'] as int?;
          final startMin = autoStart['StartTimeMin'] as int?;
          if (startHr != null && startMin != null) {
            final now = DateTime.now();
            if (now.hour == startHr && now.minute == startMin) {
              final selectResult = await db.query('SelectChannel');
              if (selectResult.isNotEmpty && navigatorKey.currentState != null) {
                navigatorKey.currentState!.push(
                  MaterialPageRoute(
                    builder: (context) => SerialPortScreen(selectedChannels: selectResult),
                  ),
                );
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[AUTOSTART] Error in AutoStart monitoring: $e');
      }
    });
  }

  void dispose() {
    _timer?.cancel();
  }
}

class SecondaryWindowManager {
  static final SecondaryWindowManager _instance = SecondaryWindowManager._internal();
  final Map<String, int> _windowIds = {}; // Map windowKey to windowId
  final Lock _lock = Lock();

  factory SecondaryWindowManager() => _instance;

  SecondaryWindowManager._internal();

  Future<void> createWindow(String channel, Map<String, dynamic> channelData, String windowKey) async {
    await _lock.synchronized(() async {
      try {
        debugPrint('[SECONDARY_WINDOW] Creating window with key $windowKey for channel: $channel');
        final newWindow = await WindowManagerPlus.createWindow([jsonEncode({
          'channel': channel,
          'channelData': channelData,
          'windowKey': windowKey,
        })]);
        if (newWindow != null) {
          final windowIds = await WindowManagerPlus.getAllWindowManagerIds();
          final windowId = windowIds.last; // Assume newest ID is the last
          _windowIds[windowKey] = windowId;
          await newWindow.setTitle('Channel $channel Data');
          await newWindow.setSize(const Size(800, 600));
          await newWindow.setPosition(const Offset(100, 100));
          await newWindow.center();
          await newWindow.show();
          debugPrint('[SECONDARY_WINDOW] Opened window with key $windowKey and ID $windowId for channel $channel');
        } else {
          debugPrint('[SECONDARY_WINDOW] Failed to create window for channel $channel');
        }
      } catch (e) {
        debugPrint('[SECONDARY_WINDOW] Error creating window for channel $channel: $e');
      }
    });
  }

  Future<void> removeWindow(String windowKey) async {
    await _lock.synchronized(() async {
      final windowId = _windowIds.remove(windowKey);
      if (windowId != null) {
        debugPrint('[SECONDARY_WINDOW] Removed window $windowId with key $windowKey');
      }
    });
  }

  Future<void> updateWindows(String? channel, Map<String, dynamic> channelData) async {
    final effectiveChannel = channel ?? 'All';
    await _lock.synchronized(() async {
      try {
        debugPrint('[SECONDARY_WINDOW] Updating windows for channel: $effectiveChannel (points: ${channelData['dataPoints']?.length ?? 0})');
        await DatabaseManager().updateChannelData(effectiveChannel, channelData);
        // Create a copy to avoid concurrent modification
        final windowIds = Map.from(_windowIds);
        for (var entry in windowIds.entries) {
          final windowKey = entry.key;
          final windowId = entry.value;
          try {
            final result = await WindowManagerPlus.current.invokeMethodToWindow(windowId, 'updateData', jsonEncode({
              'channel': effectiveChannel,
              'channelData': channelData,
              'windowKey': windowKey,
            }));
            debugPrint('[SECONDARY_WINDOW] Sent update to window $windowId (key $windowKey) for channel $effectiveChannel, result: $result');
          } catch (e) {
            debugPrint('[SECONDARY_WINDOW] Error updating window $windowKey: $e');
          }
        }
      } catch (e) {
        debugPrint('[SECONDARY_WINDOW] Error updating secondary windows for $effectiveChannel: $e');
      }
    });
  }
}