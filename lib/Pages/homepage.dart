import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart'; // Add this import
import 'package:peakloadindicator/Pages/setup/channel_setup_screen.dart';
import '../constants/message_utils.dart';
import '../constants/global.dart';
import 'Backup/backup_restore_service.dart';
import 'Help/HelpPage.dart';
import 'NavPages/new_file.dart';
import 'NavPages/serialportscreen.dart';
import 'Open_FIle/file_browser_page.dart';
import 'Open_FIle/open_file.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WindowListener { // Add WindowListener
  int _selectedIndex = -1; // -1 means initial state with centered text
  late List<Widget> _pages; // Made late to initialize in initState
  late Widget _originalNewTestPage; // Store the original NewTestPage
  final TextEditingController _fileNameController = TextEditingController();
  final BackupRestoreService _backupRestoreService = BackupRestoreService(); // Initialize service

  @override
  void initState() {
    super.initState();
    _originalNewTestPage = NewTestPage(onSubmit: _handleNewTestSubmit); // Store original
    _pages = [
      _originalNewTestPage, // Initially NewTestPage
      const Placeholder(), // Open File (will be replaced dynamically)
      const Placeholder(), // Table Mode
      const ChannelSetupScreen(), // Setup (no page, uses dialog)
      const Placeholder(), // Backup (no page, uses dialog)
      const Placeholder(), // Exit (no page)
      const HelpPage(), // Help
    ];
    windowManager.addListener(this); // Add listener for window events
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    windowManager.removeListener(this); // Clean up listener
    super.dispose();
  }

  // Callback to handle submission from NewTestPage
  void _handleNewTestSubmit(List<dynamic> selectedChannels) {
    setState(() {
      _pages[0] = SerialPortScreen(
        selectedChannels: selectedChannels,
      ); // Update to SerialPortScreen
      _selectedIndex = 0; // Stay on index 0
    });
  }

  // Callback to reset _pages[0] to NewTestPage
  void _resetToNewTestPage() {
    setState(() {
      _pages[0] = _originalNewTestPage; // Reset to original NewTestPage
      _selectedIndex = 0; // Stay on index 0 to show NewTestPage
    });
  }

  // Method to show the Backup/Restore dialog
  void _showBackupDialog(BuildContext context) {
    bool isLoading = false; // Track loading state
    showDialog(
      context: context,
      barrierDismissible: !isLoading, // Prevent dismissal during loading
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 10,
              backgroundColor: Colors.transparent,
              child: Container(
                width: 350,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.white, const Color(0xFFECEFF1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Backup & Restore',
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF455A64),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Choose an action to manage your data:',
                      style: GoogleFonts.roboto(
                        fontSize: 16,
                        color: const Color(0xFF78909C),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    if (isLoading)
                      const Column(
                        children: [
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF455A64)),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Processing...',
                            style: TextStyle(color: Color(0xFF455A64)),
                          ),
                        ],
                      )
                    else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            onPressed: () async {
                              setDialogState(() {
                                isLoading = true; // Show loading indicator
                              });
                              final result = await _backupRestoreService.backupDatabase();
                              setDialogState(() {
                                isLoading = false; // Hide loading indicator
                              });
                              Navigator.of(context).pop();
                              MessageUtils.showMessage(
                                context,
                                result,
                                isError: result.contains('failed') || result.contains('cancelled'),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4CAF50),
                              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 5,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(LucideIcons.archive, color: Colors.white, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Backup',
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () async {
                              setDialogState(() {
                                isLoading = true; // Show loading indicator
                              });
                              final result = await _backupRestoreService.restoreDatabase();
                              setDialogState(() {
                                isLoading = false; // Hide loading indicator
                              });
                              Navigator.of(context).pop();
                              MessageUtils.showMessage(
                                context,
                                result,
                                isError: result.contains('failed') || result.contains('cancelled'),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2196F3),
                              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 5,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(LucideIcons.refreshCw, color: Colors.white, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Restore',
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 20),
                    if (!isLoading)
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: const Color(0xFFEF5350),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Method to show the Setup dialog
  void _showSetupDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 10,
          backgroundColor: Colors.transparent,
          child: Container(
            width: 350,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.white, const Color(0xFFECEFF1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Setup Display Mode',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF455A64),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Select your preferred display mode:',
                  style: GoogleFonts.roboto(
                    fontSize: 16,
                    color: const Color(0xFF78909C),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Column(
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        Global.selectedMode.value = 'Graph'; // Updated for ValueNotifier
                        Navigator.of(context).pop();
                        MessageUtils.showMessage(context, 'Graph Mode selected!');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0288D1),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 5,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.barChart2, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Graph Mode',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () {
                        Global.selectedMode.value = 'Table'; // Updated for ValueNotifier
                        Navigator.of(context).pop();
                        MessageUtils.showMessage(context, 'Table Mode selected!');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7B1FA2),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 5,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.table, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Table Mode',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () {
                        Global.selectedMode.value = 'Combined'; // Updated for ValueNotifier
                        Navigator.of(context).pop();
                        MessageUtils.showMessage(context, 'Combined Mode selected!');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD81B60),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 5,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.layout, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Combined Mode',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: const Color(0xFFEF5350),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            color: const Color(0xFFB0BEC5),
            child: Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildNavButton(context, 'New Test', LucideIcons.plusCircle, 0),
                  _buildNavButton(context, 'Open File', LucideIcons.folderOpen, 1),
                  _buildNavButton(context, 'Select Mode', LucideIcons.table, 2),
                  _buildNavButton(context, 'Setup', LucideIcons.settings, 3),
                  _buildNavButton(context, 'Backup', LucideIcons.cloud, 4),
                  _buildNavButton(context, 'Exit', LucideIcons.logOut, 5),
                  _buildNavButton(context, 'Help', LucideIcons.helpCircle, 6),
                ],
              ),
            ),
          ),
          Expanded(
            child: _selectedIndex == -1
                ? Center(
              child: Container(
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFB0BEC5), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Text(
                  'COUNTRON SMART LOGGER',
                  style: GoogleFonts.poppins(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF455A64),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
                : _pages[_selectedIndex],
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton(BuildContext context, String label, IconData icon, int index) {
    return TextButton.icon(
      onPressed: () async {
        if (index == 5) {
          await windowManager.destroy(); // Close the application window
        } else if (index == 4) {
          _showBackupDialog(context);
        } else if (index == 2) {
          _showSetupDialog(context);
        } else if (index == 1) {
          _showOpenFileDialog(context);
        } else if (index == 0) {
          // Special handling for "New Test" button
          setState(() {
            _pages[0] = _originalNewTestPage; // Reset to NewTestPage
            _selectedIndex = 0; // Show NewTestPage
          });
        } else {
          setState(() => _selectedIndex = index);
        }
      },
      icon: Icon(icon, color: const Color(0xFF37474F), size: 20),
      label: Text(
        label,
        style: GoogleFonts.poppins(
          color: const Color(0xFF37474F),
          fontSize: 16,
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
        side: const BorderSide(color: Color(0xFFB0BEC5)),
      ),
    );
  }
}