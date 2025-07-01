import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'Pages/LoginPage/loginpage.dart';
import 'Pages/homepage.dart';
import 'SplashScreen.dart';
import 'constants/database_manager.dart';
import 'constants/global.dart';
import 'constants/theme.dart'; // Ensure this file defines ThemeColors correctly
import 'constants/sessionmanager.dart'; // Import the SessionDatabaseManager

class CustomTitleBar extends StatefulWidget {
  final String title;
  final Color? customColor; // Optional custom color for title and icon

  const CustomTitleBar({
    super.key,
    required this.title,
    this.customColor,
  });

  @override
  State<CustomTitleBar> createState() => _CustomTitleBarState();
}

class _CustomTitleBarState extends State<CustomTitleBar> with SingleTickerProviderStateMixin {
  late Stream<DateTime> _timeStream;
  bool _isHovered = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _timeFadeAnimation;


  @override
  void initState() {
    super.initState();
    _timeStream = Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
    _timeFadeAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
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
    return ValueListenableBuilder<bool>(
      valueListenable: Global.isDarkMode,
      builder: (context, isDarkMode, _) {
        final titleBarTextColor = widget.customColor != null ? Colors.black : ThemeColors.getColor('titleBarText', isDarkMode);
        final iconColor = widget.customColor != null ? Colors.black : ThemeColors.getColor('titleBarText', isDarkMode);

        return MouseRegion(
          onEnter: (_) {
            setState(() => _isHovered = true);
            _controller.forward();
          },
          onExit: (_) {
            setState(() => _isHovered = false);
            _controller.reverse();
          },
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: widget.customColor,
              gradient: widget.customColor == null ? ThemeColors.getTitleBarGradient(isDarkMode) : null,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(_isHovered ? 0.3 : 0.2),
                  blurRadius: 12,
                  spreadRadius: _isHovered ? 2 : 0,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: _isHovered
                            ? [
                          BoxShadow(
                            color: ThemeColors.getColor('sidebarGlow', isDarkMode).withOpacity(0.4),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ]
                            : [],
                      ),
                      child: Icon(
                        LucideIcons.cpu,
                        color: iconColor,
                        size: 28,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: MoveWindow(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            widget.title,
                            style: GoogleFonts.poppins(
                              color: titleBarTextColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                              letterSpacing: 0.8,
                            ),
                          ),
                          FadeTransition(
                            opacity: _timeFadeAnimation,
                            child: StreamBuilder<DateTime>(
                              stream: _timeStream,
                              builder: (context, snapshot) {
                                final time = snapshot.data?.toString().substring(11, 19) ?? '00:00:00';
                                return Padding(
                                  padding: const EdgeInsets.only(right: 16),
                                  child: Text(
                                    time,
                                    style: GoogleFonts.poppins(
                                      color: titleBarTextColor,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 16,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                WindowButton(
                  icon: Icons.remove,
                  onPressed: () => appWindow.minimize(),
                  tooltip: 'Minimize',
                  isDarkMode: isDarkMode,
                ),
                WindowButton(
                  icon: appWindow.isMaximized ? Icons.filter_none : Icons.crop_square,
                  onPressed: () => appWindow.maximizeOrRestore(),
                  tooltip: appWindow.isMaximized ? 'Restore' : 'Maximize',
                  isDarkMode: isDarkMode,
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: Global.isScanningNotifier,
                  builder: (context, isScanning, child) {
                    return WindowButton(
                      icon: Icons.close,
                      onPressed: () async { // Make the onPressed callback async
                        if (isScanning) {
                          final shouldClose = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(
                                'Confirm Close',
                                style: GoogleFonts.poppins(
                                  color: ThemeColors.getColor('dialogText', isDarkMode),
                                ),
                              ),
                              content: Text(
                                'Scanning is active. Are you sure you want to close the application?',
                                style: GoogleFonts.poppins(
                                  color: ThemeColors.getColor('dialogSubText', isDarkMode),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(false),
                                  child: Text(
                                    'Cancel',
                                    style: GoogleFonts.poppins(
                                      color: ThemeColors.getColor('submitButton', isDarkMode),
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(true),
                                  child: Text(
                                    'Close',
                                    style: GoogleFonts.poppins(
                                      color: ThemeColors.getColor('resetButton', isDarkMode),
                                    ),
                                  ),
                                ),
                              ],
                              backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          );
                          if (shouldClose == true) {
                            // --- Close all databases before exiting ---
                            await SessionDatabaseManager().closeAllManagedDatabases();
                            await DatabaseManager().close();
                            appWindow.close();
                          }
                        } else {
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          } else {
                            // --- Close all databases before exiting ---
                            await SessionDatabaseManager().closeAllManagedDatabases();
                            await DatabaseManager().close();
                            appWindow.close();
                          }
                        }
                      },
                      tooltip: 'Close',
                      isClose: true,
                      isDarkMode: isDarkMode,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final bool isClose;
  final bool isDarkMode;

  const WindowButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.isClose = false,
    required this.isDarkMode,
  });

  @override
  State<WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<WindowButton> with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _colorAnimation = ColorTween(
      begin: ThemeColors.getColor('titleBarIcon', widget.isDarkMode),
      end: ThemeColors.getColor('submitButton', widget.isDarkMode),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic));

    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        _controller.forward();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _controller.reverse();
      },
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onPressed();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: Tooltip(
          message: widget.tooltip,
          textStyle: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 12,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.8),
            borderRadius: BorderRadius.circular(8),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: widget.isClose
                  ? (_isHovered ? Colors.red[700] : Colors.red[600])
                  : (_isHovered
                  ? ThemeColors.getColor('submitButton', widget.isDarkMode).withOpacity(0.2)
                  : Colors.transparent),
              shape: BoxShape.circle,
              boxShadow: _isHovered
                  ? [
                BoxShadow(
                  color: ThemeColors.getColor('sidebarGlow', widget.isDarkMode).withOpacity(0.3),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
                  : [],
            ),
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Icon(
                widget.icon,
                color: widget.isClose
                    ? Colors.white.withOpacity(_isPressed ? 0.7 : 0.9)
                    : _colorAnimation.value,
                size: 18,
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

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  doWhenWindowReady(() {
    appWindow.minSize = const Size(800, 600); // Keep minSize for when it's restored
    appWindow.title = 'Peak Load Indicator';
    appWindow.maximize(); // <-- This is the key change to maximize
    appWindow.show();

    // The delayed re-render hack is typically not needed when maximizing,
    // as bitsdojo_window usually handles the maximized state correctly.
    // If you encounter a blank window issue after this change,
    // you might need to re-evaluate, but for maximization, it's usually fine without it.
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Peak Load Indicator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: Colors.black87,
        textTheme: GoogleFonts.poppinsTextTheme(),
      ),
      home: const HomePageWrapper(),
    );
  }
}

class HomePageWrapper extends StatefulWidget {
  const HomePageWrapper({super.key});

  @override
  State<HomePageWrapper> createState() => _HomePageWrapperState();
}

class _HomePageWrapperState extends State<HomePageWrapper> {
  // Cache the Future result to avoid re-running it on rebuild
  late final Future<bool> _authFuture;

  @override
  void initState() {
    super.initState();
    // Initialize the Future in initState so it only runs once
    _authFuture = _loadWithMinimumDuration();
  }

  Future<bool> _loadWithMinimumDuration() async {
    try {
      final results = await Future.wait([
        DatabaseManager().isAuthRequired(),
        Future.delayed(const Duration(seconds: 3)),
      ]);
      return results[0] as bool;
    } catch (e) {
      print('Error in _loadWithMinimumDuration: $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Global.isDarkMode,
      builder: (context, isDarkMode, child) {
        final scaffoldBgColor = ThemeColors.getColor('background', isDarkMode);

        return Scaffold(
          backgroundColor: scaffoldBgColor,
          body: FutureBuilder<bool>(
            future: _authFuture, // Use the cached Future
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SplashScreen();
              }
              if (snapshot.hasError) {
                print('Database error: ${snapshot.error}');
                return Center(
                  child: Text(
                    'Error loading database: ${snapshot.error}',
                    style: GoogleFonts.poppins(
                      color: ThemeColors.getColor('sidebarText', isDarkMode),
                      fontSize: 16,
                    ),
                  ),
                );
              }
              final requireAuth = snapshot.data ?? false;
              return requireAuth ? const LoginPage() : const HomePage();
            },
          ),
        );
      },
    );
  }
}