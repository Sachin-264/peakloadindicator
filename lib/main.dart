import 'dart:io';
import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'Pages/homepage.dart';
import 'constants/colors.dart'; // Assuming AppColors is defined here

// Global notifier for isScanning
ValueNotifier<bool> isScanningNotifier = ValueNotifier<bool>(false);

// Database manager for persistent storage
class DatabaseManager {
  static final DatabaseManager _instance = DatabaseManager._internal();
  Database? _database;

  factory DatabaseManager() => _instance;

  DatabaseManager._internal();

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;

    final appDocumentsDir = await getApplicationDocumentsDirectory();
    final dbPath = path.join(appDocumentsDir.path, 'Countronics.db');

    await Directory(path.dirname(dbPath)).create(recursive: true);
    _database = await databaseFactoryFfi.openDatabase(dbPath);
    await _initializeDatabase();
    return _database!;
  }

  Future<void> _initializeDatabase() async {
    final db = _database;
    if (db == null) return;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Test (
        RecNo REAL PRIMARY KEY,
        FName TEXT,
        OperatorName TEXT,
        TDate TEXT,
        TTime TEXT,
        ScanningRate REAL,
        ScanningRateHH REAL,
        ScanningRateMM REAL,
        ScanningRateSS REAL,
        TestDurationDD REAL,
        TestDurationHH REAL,
        TestDurationMM REAL,
        GraphVisibleArea REAL,
        BaseLine REAL,
        FullScale REAL,
        Descrip TEXT,
        AbsorptionPer REAL,
        NOR REAL,
        FLName TEXT,
        XAxis TEXT,
        XAxisRecNo REAL,
        XAxisUnit TEXT,
        XAxisCode REAL,
        TotalChannel INTEGER,
        MaxYAxis REAL,
        MinYAxis REAL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Test1 (
        RecNo REAL,
        SNo REAL,
        SlNo REAL,
        ChangeTime TEXT,
        AbsDate TEXT,
        AbsTime TEXT,
        AbsDateTime TEXT,
        Shown TEXT,
        AbsAvg REAL,
        ${List.generate(50, (i) => 'AbsPer${i + 1} REAL').join(', ')}
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Test2 (
        RecNo REAL PRIMARY KEY,
        ${List.generate(50, (i) => 'ChannelName${i + 1} TEXT').join(', ')}
      )
    ''');
  }

  Future<void> close() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
  }
}

// Custom Title Bar Widget
class CustomTitleBar extends StatelessWidget {
  final String title;

  const CustomTitleBar({
    super.key,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2D2D2D), Color(0xFF1A1A1A)], // Dark grey to black
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          // App Icon
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Icon(
              Icons.analytics, // Replace with your app icon (e.g., Image.asset)
              color: Colors.white.withOpacity(0.9),
              size: 24,
            ),
          ),
          // Title
          Expanded(
            child: MoveWindow(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    letterSpacing: 1.2,
                    shadows: [
                      Shadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 2,
                        offset: const Offset(1, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Minimize Button
          WindowButton(
            icon: Icons.remove,
            onPressed: () => appWindow.minimize(),
            tooltip: 'Minimize',
          ),
          // Maximize/Restore Button
          WindowButton(
            icon: appWindow.isMaximized ? Icons.filter_none : Icons.crop_square,
            onPressed: () => appWindow.maximizeOrRestore(),
            tooltip: appWindow.isMaximized ? 'Restore' : 'Maximize',
          ),
          // Close Button
          ValueListenableBuilder<bool>(
            valueListenable: isScanningNotifier,
            builder: (context, isScanning, child) {
              return WindowButton(
                icon: Icons.close,
                onPressed: () async {
                  if (isScanning) {
                    final shouldClose = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Confirm Close'),
                        content: const Text(
                            'Scanning is active. Are you sure you want to close the application?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                    if (shouldClose == true) {
                      appWindow.close();
                    }
                  } else {
                    appWindow.close();
                  }
                },
                tooltip: 'Close',
                isClose: true,
              );
            },
          ),
        ],
      ),
    );
  }
}

// Custom WindowButton Widget with Hover and Animation
class WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final bool isClose;

  const WindowButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.isClose = false,
  });

  @override
  State<WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<WindowButton> with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        _controller.forward();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _controller.reverse();
      },
      child: Tooltip(
        message: widget.tooltip,
        child: Material(
          color: widget.isClose
              ? (_isHovered ? Colors.redAccent : Colors.red)
              : (_isHovered ? Colors.white.withOpacity(0.2) : Colors.transparent),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: widget.onPressed,
            customBorder: const CircleBorder(),
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  widget.icon,
                  color: Colors.white.withOpacity(0.9),
                  size: 18,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize database
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Initialize bitsdojo_window
  doWhenWindowReady(() {
    const initialSize = Size(1280, 720);
    appWindow.minSize = const Size(800, 600);
    appWindow.size = initialSize;
    appWindow.alignment = Alignment.center;
    appWindow.title = 'Peak Load Indicator';
    appWindow.show();
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Peak Load Indicator',
      debugShowCheckedModeBanner: false, // Disable debug banner
      theme: ThemeData(
        primarySwatch: Colors.grey,
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: const HomePageWrapper(),
    );
  }
}

class HomePageWrapper extends StatelessWidget {
  const HomePageWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            (AppColors.background ?? Colors.grey[100]!).withOpacity(0.8),
            Colors.white,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border.all(
          color: Colors.grey[800]!, // Dark grey border
          width: 2,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      margin: const EdgeInsets.all(8),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            const CustomTitleBar(title: 'Peak Load Indicator'),
            Expanded(
              child: HomePage(), // Replace with SerialPortScreen if needed
            ),
          ],
        ),
      ),
    );
  }
}