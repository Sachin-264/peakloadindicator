import 'dart:async';
import 'dart:ui'; // For BackdropFilter
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:peakloadindicator/Pages/setup/Autocomplete.dart';
import 'package:window_manager/window_manager.dart';
import '../constants/database_manager.dart';
import '../constants/message_utils.dart';
import '../constants/global.dart';
import '../constants/theme.dart';
import '../main.dart'; // Needed for CustomTitleBar, WindowButton (assuming they are here)
import 'Backup/backup_restore_service.dart';
import 'Help/HelpPage.dart';
import 'NavPages/new_file.dart'; // Assuming this imports NewTestPage
import 'NavPages/serialportscreen.dart'; // Assuming this imports SerialPortScreen
import 'Open_FIle/file_browser_page.dart'; // Assuming this imports FileSelectionDialog
import 'Open_FIle/open_file.dart'; // Assuming this imports OpenFilePage
import 'logScreen/log.dart'; // Assuming this imports LogPage
import 'setup/channel_setup_screen.dart'; // Assuming this imports ChannelSetupScreen

// Ensure FilePicker is imported if you're using it directly here for restore
import 'package:file_picker/file_picker.dart';


class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with WindowListener, SingleTickerProviderStateMixin {
  int _selectedIndex = -1; // -1 represents the dashboard view
  late List<Widget> _pages;
  late Widget _originalNewTestPage;
  final TextEditingController _fileNameController = TextEditingController();
  final BackupRestoreService _backupRestoreService = BackupRestoreService();
  Timer? _autoStartTimer;
  final ValueNotifier<bool> _isSidebarExpanded = ValueNotifier<bool>(false);
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  static final DateTime _appStartTime = DateTime.now(); // Used for Uptime calculation
  Map<String, dynamic>? _autoStartData;
  int _activeChannels = 0;
  bool _isHovered = false; // For Dashboard button hover effect

  @override
  void initState() {
    super.initState();
    // Initialize the original NewTestPage to allow for resetting to it
    _originalNewTestPage = NewTestPage(onSubmit: _handleNewTestSubmit);

    // Define the list of pages that can be displayed in the main content area
    // Placeholders are used for pages that are handled by dialogs or dynamically replaced.
    _pages = [
      _originalNewTestPage,      // 0: New Test (or SerialPortScreen dynamically)
      const Placeholder(),       // 1: Open File (handled by dialog first, then OpenFilePage)
      const Placeholder(),       // 2: Select Mode (handled by dialog)
      const ChannelSetupScreen(),// 3: Setup (direct navigation)
      const Placeholder(),       // 4: Backup (handled by dialog)
      const LogPage(),           // 5: Log (direct navigation)
      const HelpPage(),          // 6: Help (direct navigation)
    ];

    windowManager.addListener(this); // Listen for window events (e.g., maximize, minimize)
    _loadSystemData();           // Initial load of dashboard data from DB
    _startAutoStartCheck();      // Start the periodic check for auto-start

    // Setup animations for page transitions
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward(); // Start animation immediately on init
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _logActivity('HomePage initialized'); // Log app startup
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    _autoStartTimer?.cancel(); // Cancel any active timers
    _isSidebarExpanded.dispose();
    _animationController.dispose();
    windowManager.removeListener(this); // Remove window listener
    super.dispose();
  }

  // Utility to log activity to the LogPage
  void _logActivity(String message) {
    LogPage.addLog('[$_currentTime] $message');
  }

  // Getter for current time string for logs
  String get _currentTime => DateTime.now().toString().substring(0, 19);

  // Loads system-wide data from the database for display on the dashboard
  Future<void> _loadSystemData() async {
    final autoStartData = await DatabaseManager().getAutoStartData();
    final channels = await DatabaseManager().getSelectedChannels();
    if (mounted) { // Check if the widget is still in the widget tree
      setState(() {
        _autoStartData = autoStartData;
        _activeChannels = channels.length;
      });
    }
  }

  // Starts a periodic timer to check for auto-start conditions
  void _startAutoStartCheck() {
    _autoStartTimer?.cancel(); // Cancel any existing timer to prevent duplicates
    _autoStartTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!mounted) {
        timer.cancel(); // Stop the timer if the widget is no longer mounted
        return;
      }
      // Fetch autoStartData and channels each time to ensure freshest data for auto-start logic
      final autoStartData = await DatabaseManager().getAutoStartData();
      if (autoStartData == null) {
        print('[HomePage] No AutoStart data found, stopping timer');
        timer.cancel(); // If no auto-start configuration, no need to keep checking
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

      // Check if current time matches the auto-start time
      if (currentHr == startTimeHr.floor() && currentMin == startTimeMin.floor()) {
        print('[HomePage] Time match found for AutoStart, fetching channels');
        final channels = await DatabaseManager().getSelectedChannels();
        if (channels.isEmpty) {
          print('[HomePage] No channels found in SelectChannel for AutoStart, skipping.');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'AutoStart: No channels selected. Please configure channels in Setup.',
                  style: GoogleFonts.poppins(color: ThemeColors.getColor('sidebarText', Global.isDarkMode.value)),
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }

        print('[HomePage] AutoStart triggered: Switching to AutoStartScreen with ${channels.length} channels');
        timer.cancel(); // Stop this timer once auto-start is triggered to prevent re-triggering immediately
        if (mounted) {
          setState(() {
            _pages[0] = AutoStartScreen(
              selectedChannels: channels,
              endTimeHr: endTimeHr,
              endTimeMin: endTimeMin,
              scanTimeSec: scanTimeSec,
            );
            _selectedIndex = 0; // Show the AutoStartScreen
          });
          _logActivity('AutoStart triggered with ${channels.length} channels');
        }
      }
    });
  }

  // Callback from NewTestPage when channels are submitted
  void _handleNewTestSubmit(List<dynamic> selectedChannels) {
    setState(() {
      // Replace the NewTestPage at index 0 with SerialPortScreen to start scanning
      _pages[0] = SerialPortScreen(selectedChannels: selectedChannels);
      _selectedIndex = 0; // Keep selected index at 0 to display SerialPortScreen
    });
    _logActivity('New Test started with ${selectedChannels.length} channels');
  }

  // Resets the view back to the initial NewTestPage
  void _resetToNewTestPage() {
    setState(() {
      _pages[0] = _originalNewTestPage;
      _selectedIndex = 0;
    });
    // The periodic _startAutoStartCheck() is still running, so no need to restart it here.
    _logActivity('Reset to New Test page');
  }

  // Shows the Backup & Restore dialog
  void _showBackupDialog(BuildContext context) {
    bool isLoading = false; // State for loading indicator within the dialog
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing while loading
      barrierColor: Colors.black.withOpacity(0.4), // Darken background
      builder: (BuildContext dialogContext) { // Use dialogContext to pop the dialog
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8), // Blur background
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
              child: StatefulBuilder( // Use StatefulBuilder to manage dialog's internal state
                builder: (context, setState) { // Local setState for the dialog
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
                      if (isLoading) // Show loading indicator if processing
                        Column(
                          children: [
                            AnimatedLoadingIndicator(isDarkMode: Global.isDarkMode.value), // Custom animation
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
                      else // Show buttons if not loading
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildDialogButton(
                              text: 'Backup',
                              icon: LucideIcons.archive,
                              gradient: ThemeColors.getDialogButtonGradient(Global.isDarkMode.value, 'backup'),
                              onPressed: () async {
                                setState(() => isLoading = true); // Set loading true
                                final result = await _backupRestoreService.backupDatabase();
                                setState(() => isLoading = false); // Set loading false
                                Navigator.of(dialogContext).pop(); // Pop the dialog
                                MessageUtils.showMessage(
                                  context, // Use widget's context for ScaffoldMessenger
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
                                // 1. Trigger file picker WITHOUT setting loading state yet
                                FilePickerResult? filePickerResult = await FilePicker.platform.pickFiles(
                                  type: FileType.custom,
                                  allowedExtensions: ['zip'], // Only allow .zip files for restore
                                );

                                if (filePickerResult == null) {
                                  // User cancelled file picking, do not show loading and return
                                  MessageUtils.showMessage(context, 'Restore cancelled by user.', isError: true);
                                  _logActivity('Restore cancelled by user (file picker).');
                                  return; // Stay in the dialog
                                }

                                String? filePath = filePickerResult.files.single.path;
                                if (filePath == null) {
                                  MessageUtils.showMessage(context, 'Selected file path is null.', isError: true);
                                  _logActivity('Restore failed: Selected file path is null.');
                                  return; // Stay in the dialog
                                }

                                // 2. File picked, NOW set loading state and proceed with actual restore
                                setState(() => isLoading = true); // Set loading true
                                final result = await _backupRestoreService.performRestore(filePath);
                                setState(() => isLoading = false); // Set loading false
                                Navigator.of(dialogContext).pop(); // Pop the dialog
                                MessageUtils.showMessage(
                                  context, // Use widget's context for ScaffoldMessenger
                                  result,
                                  isError: result.contains('failed'),
                                );
                                _logActivity('Restore initiated: $result');
                              },
                            ),
                          ],
                        ),
                      const SizedBox(height: 24),
                      if (!isLoading) // Show Cancel button only if not loading
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(), // Pop the dialog
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

  // Shows the "Select Display Mode" dialog
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
              width: 400, // Adjusted width for better layout
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
                          Global.selectedMode.value = 'Graph'; // Update global mode
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
                          Global.selectedMode.value = 'Table'; // Update global mode
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
                          Global.selectedMode.value = 'Combined'; // Update global mode
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

  // Shows the "Open File" dialog
  void _showOpenFileDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        // FileSelectionDialog is assumed to be in file_browser_page.dart
        return FileSelectionDialog(
          controller: _fileNameController,
          onOpenPressed: () {
            if (_fileNameController.text.isNotEmpty) {
              Navigator.of(context).pop(); // Close the dialog
              setState(() {
                _selectedIndex = 1; // Set index to "Open File"
                // Replace the placeholder at index 1 with the actual OpenFilePage
                _pages[1] = OpenFilePage(fileName: _fileNameController.text);
              });
              _fileNameController.clear(); // Clear controller after use
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
      valueListenable: Global.isDarkMode, // Rebuilds when theme changes
      builder: (context, isDarkMode, child) {
        print('[HomePage] Building with isDarkMode: $isDarkMode');

        // Determine if SerialPortScreen OR AutoStartScreen is currently active
        // These pages should occupy the full screen without the sidebar.
        final bool shouldHideSidebar = (_selectedIndex == 0 && (
            _pages[0] is SerialPortScreen ||
                _pages[0] is AutoStartScreen // ADDED: Check for AutoStartScreen
        ));

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
                // Custom title bar for window controls and branding
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
            child: CustomTitleBar(title: 'Countronics Smart Logger'), // Assumed from main.dart
          ),
          Expanded(
            // MODIFIED: Use shouldHideSidebar to control sidebar visibility
            child: shouldHideSidebar
                ? _pages[_selectedIndex] // If a special fullscreen page is active, show only it
                : Row( // Otherwise, show sidebar + main content area
              children: [
                // Sidebar: Expands on hover
                MouseRegion(
                  onEnter: (_) => _isSidebarExpanded.value = true,
                  onExit: (_) => _isSidebarExpanded.value = false,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _isSidebarExpanded,
                    builder: (context, isExpanded, child) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutQuart,
                        width: isExpanded ? 260.0 : 80.0, // Expanded vs. collapsed width
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
                    child: SingleChildScrollView( // Allows scrolling if many buttons
                      child: Column(
                        children: [
                          // Sidebar Logo (Home Button)
                          SidebarLogo(
                            onTap: () async { // <<--- MODIFIED: Make async and load data
                              await _loadSystemData(); // Fetch latest data for dashboard before displaying
                              setState(() {
                                _selectedIndex = -1; // Navigate to dashboard
                              });
                              _animationController.forward(from: 0.0); // Trigger page transition animation
                              _logActivity('Navigated to Dashboard');
                            },
                            isSidebarExpanded: _isSidebarExpanded,
                            isDarkMode: isDarkMode,
                          ),
                          const SizedBox(height: 16),
                          // Sidebar navigation buttons
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
                          // Theme toggle button
                          SidebarButton(
                            icon: isDarkMode ? LucideIcons.sun : LucideIcons.moon,
                            label: isDarkMode ? 'Light Mode' : 'Dark Mode',
                            isSelected: false, // This button is never "selected" in the main nav
                            onTap: () {
                              Global.saveTheme(!isDarkMode); // Toggle and save theme preference
                              _animationController.forward(from: 0.0); // Trigger transition
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
                // Main content area, displays the selected page or dashboard
                Expanded(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: AnimatedSwitcher( // Smoothly switches between pages
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
                      // Display either the Dashboard or the selected page
                      child: _selectedIndex == -1
                          ? _buildDashboard(isDarkMode) // Dashboard content
                          : _pages[_selectedIndex],      // Selected page content
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

  // Helper method to build sidebar buttons, handles navigation and dialogs
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
        if (index == 4) { // Backup button: shows dialog
          _showBackupDialog(context);
        } else if (index == 2) { // Select Mode button: shows dialog
          _showSetupDialog(context);
        } else if (index == 1) { // Open File button: shows dialog
          _showOpenFileDialog(context);
        } else {
          // For regular navigation pages:
          // If navigating to 'New Test' (index 0), ensure it's the initial channel selection page
          if (index == 0) {
            _pages[0] = _originalNewTestPage;
          }
          // If navigating to 'Log' (index 5), ensure it's a fresh LogPage instance
          // This might be desired if LogPage manages its own state that needs resetting.
          else if (index == 5) {
            _pages[5] = const LogPage();
          }

          setState(() {
            _selectedIndex = index; // Update the selected index to show the new page
          });
          _animationController.forward(from: 0.0); // Trigger page transition animation
          _logActivity('Navigated to $label page');
        }
      },
      isSidebarExpanded: _isSidebarExpanded,
      isDarkMode: isDarkMode,
    );
  }

  // Helper method to build buttons used within dialogs
  Widget _buildDialogButton({
    required String text,
    required IconData icon,
    required LinearGradient gradient,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
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
          mainAxisSize: MainAxisSize.min, // Shrink to fit content
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
              overflow: TextOverflow.visible,
              softWrap: false, // Prevent wrapping for single line buttons
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to build prominent action buttons on the dashboard
  Widget _buildProminentActionButton({
    required String text,
    required IconData icon,
    required VoidCallback onPressed,
    required bool isDarkMode,
  }) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true), // Set hover state
      onExit: (_) => setState(() => _isHovered = false), // Reset hover state
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: 180, // Fixed width for consistency
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            gradient: ThemeColors.getButtonGradient(isDarkMode), // Dynamic gradient based on theme
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(_isHovered ? 0.3 : 0.2), // Larger shadow on hover
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 10),
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
      ),
    );
  }

  // Builds the main dashboard content view
  Widget _buildDashboard(bool isDarkMode) {
    final uptime = DateTime.now().difference(_appStartTime); // Calculate app uptime
    final uptimeStr = '${uptime.inHours}h ${uptime.inMinutes % 60}m';
    // Format auto-start/end times, default to 'N/A' if data is null
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
            // Section for quick action buttons
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: ThemeColors.getColor('cardBackground', isDarkMode).withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildProminentActionButton(
                    text: 'Start Scan',
                    icon: LucideIcons.play,
                    onPressed: () {
                      setState(() {
                        _selectedIndex = 0;
                        _pages[0] = _originalNewTestPage; // Ensure it goes to channel selection first
                      });
                      _animationController.forward(from: 0.0);
                      _logActivity('Quick Action: Start Scan');
                    },
                    isDarkMode: isDarkMode,
                  ),
                  _buildProminentActionButton(
                    text: 'Open File',
                    icon: LucideIcons.folderOpen,
                    onPressed: () => _showOpenFileDialog(context),
                    isDarkMode: isDarkMode,
                  ),
                  _buildProminentActionButton(
                    text: 'Mode',
                    icon: LucideIcons.monitor,
                    onPressed: () => _showSetupDialog(context),
                    isDarkMode: isDarkMode,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Grid of information cards
            GridView.count(
              crossAxisCount: MediaQuery.of(context).size.width > 1200 ? 3 : 2, // Responsive grid
              crossAxisSpacing: 24,
              mainAxisSpacing: 24,
              shrinkWrap: true, // Take only necessary space
              physics: const NeverScrollableScrollPhysics(), // Disable internal scrolling
              childAspectRatio: 1.2, // Aspect ratio for cards
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
                      const Spacer(), // Pushes the progress bar to the bottom
                      LinearProgressIndicator(
                        value: _activeChannels > 0 ? _activeChannels / 50.0 : 0.0, // Max 50 channels?
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
                    height: 120, // Fixed height for log list
                    child: ListView(
                      physics: const ClampingScrollPhysics(), // Prevent "bouncy" scrolling
                      children: LogPage.getRecentLogs(3) // Get latest 3 logs
                          .map((log) => _buildLogItem(log, isDarkMode))
                          .toList(),
                    ),
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
                        'Last Updated: 05/26/2025', // Placeholder for actual update date
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

  // Helper method to build individual dashboard info cards
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
        border: Border.all( // Subtle border for definition
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
                  overflow: TextOverflow.ellipsis, // Truncate long titles
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: content), // Content widget takes remaining space
        ],
      ),
    );
  }

  // Helper method to build a row for status information within a card
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

  // Helper method to build a single log item for the Recent Logs card
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
              overflow: TextOverflow.ellipsis, // Truncate long log messages
            ),
          ),
        ],
      ),
    );
  }
}

// ====================================================================
// START: Reusable Sidebar Components (SidebarButton, SidebarLogo)
// These widgets are part of the HomePage file but could be extracted.
// ====================================================================

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

  // Handle mouse enter event for hover effects
  void _onEnter(PointerEvent _) {
    setState(() => _isHovered = true);
    _controller.forward();
  }

  // Handle mouse exit event for hover effects
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
          // Play a quick animation on tap before executing the callback
          _controller.forward(from: 0.0).then((_) {
            _controller.reverse();
            widget.onTap();
          });
        },
        child: ValueListenableBuilder<bool>(
          valueListenable: widget.isSidebarExpanded,
          builder: (context, isExpanded, child) {
            return Tooltip(
              message: isExpanded ? '' : widget.label, // Show tooltip only when collapsed
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
                  color: widget.isSelected // Highlight if selected
                      ? ThemeColors.getColor('sidebarIconSelected', widget.isDarkMode).withOpacity(0.2)
                      : _isHovered // Highlight on hover
                      ? ThemeColors.getColor('sidebarGlow', widget.isDarkMode).withOpacity(0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: ThemeColors.getColor('sidebarGlow', widget.isDarkMode)
                          .withOpacity(_glowAnimation.value), // Glow effect
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    ScaleTransition( // Icon scales on hover/tap
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
                    AnimatedSlide( // Text slides in/out based on expansion
                      offset: isExpanded ? Offset.zero : const Offset(0.2, 0),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      child: AnimatedOpacity( // Text fades in/out based on expansion
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
                            : const SizedBox.shrink(), // Hide text when collapsed
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
      duration: const Duration(milliseconds: 600),
    )..forward(); // Start animation on init
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
            widget.onTap(); // Execute the provided onTap callback
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
                      LucideIcons.cpu, // Logo icon
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
                          // Animate each character of the logo text
                          children: List.generate(logoText.length, (index) {
                            return AnimatedBuilder(
                              animation: _textAnimation,
                              builder: (context, child) {
                                double t = (_textAnimation.value * logoText.length - index).clamp(0.0, 1.0);
                                return Opacity(
                                  opacity: t,
                                  child: Transform.translate(
                                    offset: Offset(0, (1.0 - t) * 8), // Slide in from bottom
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

// ====================================================================
// END: Reusable Sidebar Components
// ====================================================================


// Custom Animated Loading Indicator Widget for dialogs
class AnimatedLoadingIndicator extends StatefulWidget {
  final bool isDarkMode;
  const AnimatedLoadingIndicator({Key? key, required this.isDarkMode}) : super(key: key);

  @override
  _AnimatedLoadingIndicatorState createState() => _AnimatedLoadingIndicatorState();
}

class _AnimatedLoadingIndicatorState extends State<AnimatedLoadingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotationAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(); // Repeat indefinitely for continuous loading

    _rotationAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.linear), // Linear rotation
    );

    _scaleAnimation = TweenSequence<double>([ // Pulsating scale effect
      TweenSequenceItem(tween: Tween<double>(begin: 0.8, end: 1.2), weight: 1),
      TweenSequenceItem(tween: Tween<double>(begin: 1.2, end: 0.8), weight: 1),
    ]).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _colorAnimation = ColorTween( // Color oscillates between two theme colors
      begin: ThemeColors.getColor('buttonGradientStart', widget.isDarkMode),
      end: ThemeColors.getColor('buttonGradientEnd', widget.isDarkMode),
    ).animate(
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(
                valueColor: _colorAnimation, // Animated color for indicator
                strokeWidth: 4,
              ),
            ),
            ScaleTransition(
              scale: _scaleAnimation, // Animated scale for icon
              child: RotationTransition(
                turns: _rotationAnimation, // Animated rotation for icon
                child: Icon(
                  LucideIcons.hardDrive, // Icon related to data/storage
                  size: 40,
                  color: _colorAnimation.value, // Animated color for icon
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}