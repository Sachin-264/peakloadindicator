import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';
import '../constants/database_manager.dart';
import '../constants/message_utils.dart';
import '../constants/global.dart';
import '../constants/colors.dart';
import '../constants/theme.dart';
import '../main.dart';
import 'Backup/backup_restore_service.dart';
import 'Help/HelpPage.dart';
import 'NavPages/new_file.dart';
import 'NavPages/serialportscreen.dart';
import 'Open_FIle/file_browser_page.dart';
import 'Open_FIle/open_file.dart';

import 'logScreen/log.dart';
import 'setup/Autocomplete.dart';
import 'setup/channel_setup_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with WindowListener, SingleTickerProviderStateMixin {
  int _selectedIndex = -1;
  late List<Widget> _pages;
  late Widget _originalNewTestPage;
  final TextEditingController _fileNameController = TextEditingController();
  final BackupRestoreService _backupRestoreService = BackupRestoreService();
  Timer? _autoStartTimer;
  final ValueNotifier<bool> _isSidebarExpanded = ValueNotifier<bool>(false);
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  static final DateTime _appStartTime = DateTime.now();
  Map<String, dynamic>? _autoStartData;
  int _activeChannels = 0;

  @override
  void initState() {
    super.initState();
    _originalNewTestPage = NewTestPage(onSubmit: _handleNewTestSubmit);
    _pages = [
      _originalNewTestPage,
      const Placeholder(),
      const Placeholder(),
      const ChannelSetupScreen(),
      const Placeholder(),
      const LogPage(),
      const HelpPage(),
    ];
    windowManager.addListener(this);
    _loadSystemData();
    _startAutoStartCheck();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _logActivity('HomePage initialized');
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    _autoStartTimer?.cancel();
    _isSidebarExpanded.dispose();
    _animationController.dispose();
    windowManager.removeListener(this);
    super.dispose();
  }

  void _logActivity(String message) {
    LogPage.addLog('[$_currentTime] $message');
  }

  String get _currentTime => DateTime.now().toString().substring(0, 19);

  Future<void> _loadSystemData() async {
    final dbManager = DatabaseManager();
    final autoStartData = await dbManager.getAutoStartData();
    final channels = await dbManager.getSelectedChannels();
    if (mounted) {
      setState(() {
        _autoStartData = autoStartData;
        _activeChannels = channels.length;
      });
    }
  }

  void _startAutoStartCheck() {
    final dbManager = DatabaseManager();
    _autoStartTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final autoStartData = await dbManager.getAutoStartData();
      if (autoStartData == null) {
        print('[HomePage] No AutoStart data found, stopping timer');
        timer.cancel();
        return;
      }
      final startTimeHr = (autoStartData['StartTimeHr'] as num?)?.toDouble() ?? 0.0;
      final startTimeMin = (autoStartData['StartTimeMin'] as num?)?.toDouble() ?? 0.0;
      final endTimeHr = (autoStartData['EndTimeHr'] as num?)?.toDouble() ?? 0.0;
      final endTimeMin = (autoStartData['EndTimeMin'] as num?)?.toDouble() ?? 0.0;
      final scanTimeSec = (autoStartData['ScanTimeSec'] as num?)?.toDouble() ?? 0.0;
      final now = DateTime.now();
      final currentHr = now.hour.toDouble();
      final currentMin = now.minute.toDouble();
      print('[HomePage] Checking time: Current=$currentHr:$currentMin, Start=$startTimeHr:$startTimeMin');
      if (currentHr == startTimeHr.floor() && currentMin == startTimeMin.floor()) {
        print('[HomePage] Time match found, fetching channels');
        final channels = await dbManager.getSelectedChannels();
        if (channels.isEmpty) {
          print('[HomePage] No channels found in SelectChannel, skipping AutoStart');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'No channels configured in SelectChannel',
                style: GoogleFonts.poppins(
                  color: ThemeColors.getColor('sidebarText', Global.isDarkMode.value),
                ),
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        print('[HomePage] Switching to AutoStartScreen with ${channels.length} channels');
        timer.cancel();
        if (mounted) {
          setState(() {
            _pages[0] = AutoStartScreen(
              selectedChannels: channels,
              endTimeHr: endTimeHr,
              endTimeMin: endTimeMin,
              scanTimeSec: scanTimeSec,
            );
            _selectedIndex = 0;
          });
          _logActivity('AutoStart triggered with ${channels.length} channels');
        }
      }
    });
  }

  void _handleNewTestSubmit(List<dynamic> selectedChannels) {
    setState(() {
      _pages[0] = SerialPortScreen(selectedChannels: selectedChannels);
      _selectedIndex = 0;
    });
    _logActivity('New Test started with ${selectedChannels.length} channels');
  }

  void _resetToNewTestPage() {
    setState(() {
      _pages[0] = _originalNewTestPage;
      _selectedIndex = 0;
    });
    _startAutoStartCheck();
    _logActivity('Reset to New Test page');
  }

  void _showBackupDialog(BuildContext context) {
    bool isLoading = false;
    showDialog(
      context: context,
      barrierDismissible: !isLoading,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (BuildContext context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: ThemeColors.getColor('dialogBackground', Global.isDarkMode.value),
            child: Container(
              width: 400,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: [
                    ThemeColors.getColor('dialogBackground', Global.isDarkMode.value),
                    ThemeColors.getColor('dialogBackground', Global.isDarkMode.value).withOpacity(0.9),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: StatefulBuilder(
                builder: (context, setState) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Backup & Restore',
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: ThemeColors.getColor('dialogText', Global.isDarkMode.value),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Securely manage your data',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: ThemeColors.getColor('dialogSubText', Global.isDarkMode.value),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (isLoading)
                        Column(
                          children: [
                            CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                ThemeColors.getColor('buttonGradientStart', Global.isDarkMode.value),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Processing...',
                              style: GoogleFonts.poppins(
                                color: ThemeColors.getColor('dialogText', Global.isDarkMode.value),
                                fontSize: 16,
                              ),
                            ),
                          ],
                        )
                      else
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildDialogButton(
                              text: 'Backup',
                              icon: LucideIcons.archive,
                              gradient: ThemeColors.getDialogButtonGradient(Global.isDarkMode.value, 'backup'),
                              onPressed: () async {
                                setState(() => isLoading = true);
                                final result = await _backupRestoreService.backupDatabase();
                                setState(() => isLoading = false);
                                Navigator.of(context).pop();
                                MessageUtils.showMessage(
                                  context,
                                  result,
                                  isError: result.contains('failed') || result.contains('cancelled'),
                                );
                                _logActivity('Backup initiated: $result');
                              },
                            ),
                            _buildDialogButton(
                              text: 'Restore',
                              icon: LucideIcons.refreshCw,
                              gradient: ThemeColors.getDialogButtonGradient(Global.isDarkMode.value, 'restore'),
                              onPressed: () async {
                                setState(() => isLoading = true);
                                final result = await _backupRestoreService.restoreDatabase();
                                setState(() => isLoading = false);
                                Navigator.of(context).pop();
                                MessageUtils.showMessage(
                                  context,
                                  result,
                                  isError: result.contains('failed') || result.contains('cancelled'),
                                );
                                _logActivity('Restore initiated: $result');
                              },
                            ),
                          ],
                        ),
                      const SizedBox(height: 24),
                      if (!isLoading)
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
    _logActivity('Backup dialog opened');
  }

  void _showSetupDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (BuildContext context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: ThemeColors.getColor('dialogBackground', Global.isDarkMode.value),
            child: Container(
              width: 350,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: [
                    ThemeColors.getColor('dialogBackground', Global.isDarkMode.value),
                    ThemeColors.getColor('dialogBackground', Global.isDarkMode.value).withOpacity(0.9),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Select Display Mode',
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: ThemeColors.getColor('dialogText', Global.isDarkMode.value),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Choose your preferred visualization',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: ThemeColors.getColor('dialogSubText', Global.isDarkMode.value),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Column(
                    children: [
                      _buildDialogButton(
                        text: 'Graph Mode',
                        icon: LucideIcons.barChart2,
                        gradient: ThemeColors.getDialogButtonGradient(Global.isDarkMode.value, 'graph'),
                        onPressed: () {
                          Global.selectedMode.value = 'Graph';
                          Navigator.of(context).pop();
                          MessageUtils.showMessage(context, 'Graph mode selected!');
                          _logActivity('Graph mode selected');
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildDialogButton(
                        text: 'Table Mode',
                        icon: LucideIcons.table,
                        gradient: ThemeColors.getDialogButtonGradient(Global.isDarkMode.value, 'table'),
                        onPressed: () {
                          Global.selectedMode.value = 'Table';
                          Navigator.of(context).pop();
                          MessageUtils.showMessage(context, 'Table mode selected!');
                          _logActivity('Table mode selected');
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildDialogButton(
                        text: 'Combined Mode',
                        icon: LucideIcons.layoutGrid,
                        gradient: ThemeColors.getDialogButtonGradient(Global.isDarkMode.value, 'combined'),
                        onPressed: () {
                          Global.selectedMode.value = 'Combined';
                          Navigator.of(context).pop();
                          MessageUtils.showMessage(context, 'Combined mode selected!');
                          _logActivity('Combined mode selected');
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    _logActivity('Setup dialog opened');
  }

  void _showOpenFileDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return FileSelectionDialog(
          controller: _fileNameController,
          onOpenPressed: () {
            if (_fileNameController.text.isNotEmpty) {
              Navigator.of(context).pop();
              setState(() {
                _selectedIndex = 1;
                _pages[1] = OpenFilePage(fileName: _fileNameController.text);
              });
              _fileNameController.clear();
            } else {
              MessageUtils.showMessage(context, 'Please select or enter a file name!', isError: true);
            }
          },
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Global.isDarkMode,
      builder: (context, isDarkMode, child) {
        print('[HomePage] Building with isDarkMode: $isDarkMode');
        return Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  ThemeColors.getColor('appBackground', isDarkMode),
                  ThemeColors.getColor('appBackgroundSecondary', isDarkMode),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: ThemeColors.getColor('dialogBackground', isDarkMode).withOpacity(0.95),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: CustomTitleBar(title: 'Countronics Smart Logger'),
                ),
                Expanded(
                  child: Row(
                    children: [
                      MouseRegion(
                        onEnter: (_) => _isSidebarExpanded.value = true,
                        onExit: (_) => _isSidebarExpanded.value = false,
                        child: ValueListenableBuilder<bool>(
                          valueListenable: _isSidebarExpanded,
                          builder: (context, isExpanded, child) {
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutQuart,
                              width: isExpanded ? 260.0 : 80.0,
                              decoration: BoxDecoration(
                                gradient: ThemeColors.getSidebarGradient(isDarkMode),
                                borderRadius: const BorderRadius.only(
                                  topRight: Radius.circular(24),
                                  bottomRight: Radius.circular(24),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 12,
                                    offset: const Offset(4, 0),
                                  ),
                                ],
                              ),
                              child: child,
                            );
                          },
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                SidebarLogo(
                                  onTap: () {
                                    setState(() {
                                      _selectedIndex = -1;
                                    });
                                    _animationController.forward(from: 0.0);
                                    _logActivity('Navigated to Dashboard');
                                  },
                                  isSidebarExpanded: _isSidebarExpanded,
                                  isDarkMode: isDarkMode,
                                ),
                                const SizedBox(height: 16),
                                _buildSidebarButton(
                                  icon: LucideIcons.activity,
                                  index: 0,
                                  label: 'New Test',
                                  isDarkMode: isDarkMode,
                                  context: context,
                                ),
                                _buildSidebarButton(
                                  icon: LucideIcons.folderSearch,
                                  index: 1,
                                  label: 'Open File',
                                  isDarkMode: isDarkMode,
                                  context: context,
                                ),
                                _buildSidebarButton(
                                  icon: LucideIcons.monitor,
                                  index: 2,
                                  label: 'Select Mode',
                                  isDarkMode: isDarkMode,
                                  context: context,
                                ),
                                _buildSidebarButton(
                                  icon: LucideIcons.settings,
                                  index: 3,
                                  label: 'Setup',
                                  isDarkMode: isDarkMode,
                                  context: context,
                                ),
                                _buildSidebarButton(
                                  icon: LucideIcons.databaseBackup,
                                  index: 4,
                                  label: 'Backup',
                                  isDarkMode: isDarkMode,
                                  context: context,
                                ),
                                _buildSidebarButton(
                                  icon: LucideIcons.fileText,
                                  index: 5,
                                  label: 'Log',
                                  isDarkMode: isDarkMode,
                                  context: context,
                                ),
                                _buildSidebarButton(
                                  icon: LucideIcons.lifeBuoy,
                                  index: 6,
                                  label: 'Help',
                                  isDarkMode: isDarkMode,
                                  context: context,
                                ),
                                const Divider(
                                  color: Colors.white54,
                                  indent: 10,
                                  endIndent: 10,
                                ),
                                SidebarButton(
                                  icon: isDarkMode ? LucideIcons.sun : LucideIcons.moon,
                                  label: isDarkMode ? 'Light Mode' : 'Dark Mode',
                                  isSelected: false,
                                  onTap: () {
                                    Global.saveTheme(!isDarkMode);
                                    _animationController.forward(from: 0.0);
                                    _logActivity('Toggled theme to ${isDarkMode ? 'Light' : 'Dark'} mode');
                                  },
                                  isSidebarExpanded: _isSidebarExpanded,
                                  isDarkMode: isDarkMode,
                                ),
                                const SizedBox(height: 10),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder: (child, animation) {
                              return SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.1, 0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                              );
                            },
                            child: _selectedIndex == -1
                                ? _buildDashboard(isDarkMode)
                                : _pages[_selectedIndex],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSidebarButton({
    required IconData icon,
    required int index,
    required String label,
    required bool isDarkMode,
    required BuildContext context,
  }) {
    return SidebarButton(
      icon: icon,
      label: label,
      isSelected: _selectedIndex == index,
      onTap: () {
        if (index == 4) {
          _showBackupDialog(context);
        } else if (index == 2) {
          _showSetupDialog(context);
        } else if (index == 1) {
          _showOpenFileDialog(context);
        } else {
          setState(() {
            _selectedIndex = index;
            if (index == 0) {
              _pages[0] = _originalNewTestPage;
            } else if (index == 5) {
              _pages[5] = const LogPage();
            }
          });
          _animationController.forward(from: 0.0);
          _logActivity('Navigated to $label page');
        }
      },
      isSidebarExpanded: _isSidebarExpanded,
      isDarkMode: isDarkMode,
    );
  }

  Widget _buildDialogButton({
    required String text,
    required IconData icon,
    required LinearGradient gradient,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 140,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboard(bool isDarkMode) {
    final uptime = DateTime.now().difference(_appStartTime);
    final uptimeStr = '${uptime.inHours}h ${uptime.inMinutes % 60}m';
    final startTime = _autoStartData != null
        ? '${_autoStartData!['StartTimeHr'].toInt().toString().padLeft(2, '0')}:${_autoStartData!['StartTimeMin'].toInt().toString().padLeft(2, '0')}'
        : 'N/A';
    final endTime = _autoStartData != null
        ? '${_autoStartData!['EndTimeHr'].toInt().toString().padLeft(2, '0')}:${_autoStartData!['EndTimeMin'].toInt().toString().padLeft(2, '0')}'
        : 'N/A';
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dashboard',
              style: GoogleFonts.poppins(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: ThemeColors.getColor('dialogText', isDarkMode),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Monitor and control your system',
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: ThemeColors.getColor('dialogSubText', isDarkMode),
              ),
            ),
            const SizedBox(height: 24),
            GridView.count(
              crossAxisCount: MediaQuery.of(context).size.width > 1200 ? 4 : 2,
              crossAxisSpacing: 24,
              mainAxisSpacing: 24,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.2,
              children: [
                _buildDashboardCard(
                  title: 'System Status',
                  icon: LucideIcons.monitor,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatusRow('Active Channels', '$_activeChannels', isDarkMode),
                      _buildStatusRow('AutoStart Time', startTime, isDarkMode),
                      _buildStatusRow('AutoEnd Time', endTime, isDarkMode),
                      _buildStatusRow('Uptime', uptimeStr, isDarkMode),
                      const Spacer(),
                      LinearProgressIndicator(
                        value: _activeChannels > 0 ? _activeChannels / 50.0 : 0.0,
                        backgroundColor: ThemeColors.getColor('cardBorder', isDarkMode),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          ThemeColors.getColor('buttonGradientStart', isDarkMode),
                        ),
                      ),
                    ],
                  ),
                  isDarkMode: isDarkMode,
                ),
                _buildDashboardCard(
                  title: 'Recent Logs',
                  icon: LucideIcons.fileText,
                  content: SizedBox(
                    height: 120,
                    child: ListView(
                      children: LogPage.getRecentLogs(3)
                          .map((log) => _buildLogItem(log, isDarkMode))
                          .toList(),
                    ),
                  ),
                  isDarkMode: isDarkMode,
                ),
                _buildDashboardCard(
                  title: 'Quick Actions',
                  icon: LucideIcons.activity,
                  content: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _buildActionButton(
                        text: 'Start Scan',
                        icon: LucideIcons.play,
                        onPressed: () {
                          setState(() {
                            _selectedIndex = 0;
                            _pages[0] = _originalNewTestPage;
                          });
                          _animationController.forward(from: 0.0);
                          _logActivity('Quick Action: Start Scan');
                        },
                        isDarkMode: isDarkMode,
                      ),
                      _buildActionButton(
                        text: 'View Data',
                        icon: LucideIcons.eye,
                        onPressed: () => _showOpenFileDialog(context),
                        isDarkMode: isDarkMode,
                      ),
                    ],
                  ),
                  isDarkMode: isDarkMode,
                ),
                _buildDashboardCard(
                  title: 'System Info',
                  icon: LucideIcons.info,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatusRow('Version', '2.1.3', isDarkMode),
                      _buildStatusRow('Theme', isDarkMode ? 'Dark' : 'Light', isDarkMode),
                      const Spacer(),
                      Text(
                        'Last Updated: 05/26/2025',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: ThemeColors.getColor('cardText', isDarkMode).withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                  isDarkMode: isDarkMode,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardCard({
    required String title,
    required IconData icon,
    required Widget content,
    required bool isDarkMode,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ThemeColors.getColor('cardBackground', isDarkMode),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: ThemeColors.getColor('cardBorder', isDarkMode),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: ThemeColors.getColor('cardIcon', isDarkMode).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: ThemeColors.getColor('CardIcon', isDarkMode),
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: ThemeColors.getColor('dialogText', isDarkMode),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: ThemeColors.getColor('cardText', isDarkMode).withOpacity(0.8),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ThemeColors.getColor('cardText', isDarkMode),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogItem(String text, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ThemeColors.getColor('buttonGradientStart', isDarkMode),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: ThemeColors.getColor('cardText', isDarkMode),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String text,
    required IconData icon,
    required VoidCallback onPressed,
    required bool isDarkMode,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 140,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: ThemeColors.getButtonGradient(isDarkMode),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SidebarButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final ValueNotifier<bool> isSidebarExpanded;
  final bool isDarkMode;

  const SidebarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.isSidebarExpanded,
    required this.isDarkMode,
  });

  @override
  State<SidebarButton> createState() => _SidebarButtonState();
}

class _SidebarButtonState extends State<SidebarButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _glowAnimation = Tween<double>(begin: 0.0, end: 0.3).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onEnter(PointerEvent _) {
    setState(() => _isHovered = true);
    _controller.forward();
  }

  void _onExit(PointerEvent _) {
    setState(() => _isHovered = false);
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _onEnter,
      onExit: _onExit,
      child: GestureDetector(
        onTap: () {
          _controller.forward(from: 0.0).then((_) {
            _controller.reverse();
            widget.onTap();
          });
        },
        child: ValueListenableBuilder<bool>(
          valueListenable: widget.isSidebarExpanded,
          builder: (context, isExpanded, child) {
            return Tooltip(
              message: isExpanded ? '' : widget.label,
              textStyle: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 12,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: widget.isSelected
                      ? ThemeColors.getColor('sidebarIconSelected', widget.isDarkMode).withOpacity(0.2)
                      : _isHovered
                      ? ThemeColors.getColor('sidebarGlow', widget.isDarkMode).withOpacity(0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: ThemeColors.getColor('sidebarGlow', widget.isDarkMode)
                          .withOpacity(_glowAnimation.value),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    ScaleTransition(
                      scale: _scaleAnimation,
                      child: Icon(
                        widget.icon,
                        color: widget.isSelected
                            ? ThemeColors.getColor('sidebarIconSelected', widget.isDarkMode)
                            : _isHovered
                            ? ThemeColors.getColor('sidebarText', widget.isDarkMode)
                            : ThemeColors.getColor('sidebarIcon', widget.isDarkMode),
                        size: 24,
                      ),
                    ),
                    AnimatedSlide(
                      offset: isExpanded ? Offset.zero : const Offset(0.2, 0),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      child: AnimatedOpacity(
                        opacity: isExpanded ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                        child: isExpanded
                            ? Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: Text(
                            widget.label,
                            style: GoogleFonts.poppins(
                              color: ThemeColors.getColor('sidebarText', widget.isDarkMode),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class SidebarLogo extends StatefulWidget {
  final VoidCallback onTap;
  final ValueNotifier<bool> isSidebarExpanded;
  final bool isDarkMode;

  const SidebarLogo({
    super.key,
    required this.onTap,
    required this.isSidebarExpanded,
    required this.isDarkMode,
  });

  @override
  State<SidebarLogo> createState() => _SidebarLogoState();
}

class _SidebarLogoState extends State<SidebarLogo> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;
  late Animation<double> _textAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600), // Faster animation
    )..forward();
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.3, curve: Curves.easeOut)),
    );
    _glowAnimation = Tween<double>(begin: 0.0, end: 0.3).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.3, curve: Curves.easeInOut)),
    );
    _textAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.2, 1.0, curve: Curves.easeOut)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onEnter(PointerEvent _) {
    setState(() => _isHovered = true);
    _controller.forward();
  }

  void _onExit(PointerEvent _) {
    setState(() => _isHovered = false);
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    const String logoText = 'Countronics';
    return MouseRegion(
      onEnter: _onEnter,
      onExit: _onExit,
      child: GestureDetector(
        onTap: () {
          _controller.forward(from: 0.0).then((_) {
            _controller.reverse();
            widget.onTap();
          });
        },
        child: ValueListenableBuilder<bool>(
          valueListenable: widget.isSidebarExpanded,
          builder: (context, isExpanded, child) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _isHovered
                    ? ThemeColors.getColor('sidebarGlow', widget.isDarkMode).withOpacity(0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: ThemeColors.getColor('sidebarGlow', widget.isDarkMode)
                        .withOpacity(_glowAnimation.value),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScaleTransition(
                    scale: _scaleAnimation,
                    child: Icon(
                      LucideIcons.cpu,
                      color: _isHovered
                          ? ThemeColors.getColor('sidebarText', widget.isDarkMode)
                          : ThemeColors.getColor('sidebarIcon', widget.isDarkMode),
                      size: 24,
                    ),
                  ),
                  AnimatedSlide(
                    offset: isExpanded ? Offset.zero : const Offset(0.2, 0),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: AnimatedOpacity(
                      opacity: isExpanded ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      child: isExpanded
                          ? Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Row(
                          children: List.generate(logoText.length, (index) {
                            return AnimatedBuilder(
                              animation: _textAnimation,
                              builder: (context, child) {
                                double t = (_textAnimation.value * logoText.length - index).clamp(0.0, 1.0);
                                return Opacity(
                                  opacity: t,
                                  child: Transform.translate(
                                    offset: Offset(0, (1.0 - t) * 8),
                                    child: Text(
                                      logoText[index],
                                      style: GoogleFonts.poppins(
                                        color: ThemeColors.getColor('sidebarText', widget.isDarkMode),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          }),
                        ),
                      )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}