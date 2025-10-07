import 'dart:convert';
import 'dart:io'; // Required for File operations
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart'; // Using file_picker now
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../constants/global.dart';
import '../../constants/message_utils.dart';
import '../../constants/theme.dart';

class LogPage extends StatefulWidget {
  static final List<String> _logs = [];

  const LogPage({super.key});

  static void addLog(String log) {
    _logs.insert(0, log);
    if (_logs.length > 100) _logs.removeLast();
  }

  static List<String> getRecentLogs(int count) {
    return _logs.take(count).toList();
  }

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // --- REWRITTEN DOWNLOAD FUNCTION ---
  // This function now uses file_picker to let the user choose a location and filename.
  Future<void> _downloadLogs() async {
    print("--- Starting Log Download Process ---");

    if (LogPage._logs.isEmpty) {
      print("[DEBUG] No logs found. Aborting download.");
      MessageUtils.showMessage(context, 'No logs to download.', isError: true);
      return;
    }

    try {
      // 1. Prepare the log content
      final String logContent = LogPage._logs.reversed.join('\n');
      final Uint8List bytes = Uint8List.fromList(utf8.encode(logContent));
      print("[DEBUG] Log content prepared. Byte length: ${bytes.length}");

      // 2. Suggest a filename
      final now = DateTime.now();
      final String timestamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final String suggestedFileName = 'countron-log-$timestamp.txt';
      print("[DEBUG] Suggested filename: $suggestedFileName");

      // 3. Open the "Save As" dialog using FilePicker
      // This will return the full path including the name the user chooses.
      print("[DEBUG] Opening file browser (Save As dialog)...");
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Please select a location to save your log file:',
        fileName: suggestedFileName,
        allowedExtensions: ['txt'],
        type: FileType.custom,
      );

      // 4. Check the result and write the file
      if (outputFile != null) {
        // This block runs ONLY if the user selected a location and clicked "Save".
        print("[DEBUG] User selected a path: $outputFile");
        final file = File(outputFile);
        await file.writeAsBytes(bytes);
        print("[DEBUG] File successfully written to disk.");

        LogPage.addLog('[$_currentTime] Logs successfully downloaded to $outputFile');
        MessageUtils.showMessage(context, 'Logs downloaded successfully!');
      } else {
        // This block runs if the user closed the dialog without saving.
        print("[DEBUG] User cancelled the file browser dialog.");
        LogPage.addLog('[$_currentTime] Log download was cancelled by the user.');
        MessageUtils.showMessage(context, 'Log download cancelled.',
            isError: true);
      }
    } catch (e) {
      print("[ERROR] An exception occurred during log download: $e");
      LogPage.addLog('[$_currentTime] Failed to download logs: $e');
      MessageUtils.showMessage(context, 'Failed to download logs.',
          isError: true);
    }
    print("--- Ending Log Download Process ---");
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Global.isDarkMode,
      builder: (context, isDarkMode, child) {
        return Container(
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
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Activity Log',
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: ThemeColors.getColor('dialogText', isDarkMode),
                        ),
                      ),
                      Row(
                        children: [
                          Tooltip(
                            message: 'Download Logs',
                            child: IconButton(
                              icon: Icon(
                                LucideIcons.download,
                                color: ThemeColors.getColor(
                                    'dialogText', isDarkMode),
                                size: 20,
                              ),
                              onPressed: _downloadLogs,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: 'Clear Logs',
                            child: IconButton(
                              icon: Icon(
                                LucideIcons.trash2,
                                color: ThemeColors.getColor(
                                    'dialogText', isDarkMode),
                                size: 20,
                              ),
                              onPressed: () {
                                setState(() {
                                  LogPage._logs.clear();
                                });
                                LogPage.addLog(
                                    '[$_currentTime] Cleared all logs');
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Track all application activities',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: ThemeColors.getColor('dialogSubText', isDarkMode),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color:
                        ThemeColors.getColor('cardBackground', isDarkMode),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            spreadRadius: 1,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        border: Border.all(
                          color: ThemeColors.getColor('cardBorder', isDarkMode),
                          width: 1,
                        ),
                      ),
                      child: LogPage._logs.isEmpty
                          ? Center(
                        child: Text(
                          'No logs available',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: ThemeColors.getColor(
                                'cardText', isDarkMode)
                                .withOpacity(0.7),
                          ),
                        ),
                      )
                          : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: LogPage._logs.length,
                        itemBuilder: (context, index) {
                          return FadeTransition(
                            opacity: Tween<double>(begin: 0.0, end: 1.0)
                                .animate(
                              CurvedAnimation(
                                parent: _animationController,
                                curve: Interval(
                                  index / (LogPage._logs.length + 1),
                                  1.0,
                                  curve: Curves.easeOut,
                                ),
                              ),
                            ),
                            child: Padding(
                              padding:
                              const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    margin: const EdgeInsets.only(top: 4),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: ThemeColors.getColor(
                                          'buttonGradientStart',
                                          isDarkMode),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      LogPage._logs[index],
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        color: ThemeColors.getColor(
                                            'cardText', isDarkMode),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
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
  }

  String get _currentTime => DateTime.now().toString().substring(0, 19);
}