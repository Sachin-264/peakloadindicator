import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart'; // Import for date formatting
import 'package:peakloadindicator/constants/loader_widget.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../constants/global.dart';
import '../../constants/theme.dart';
import '../../constants/database_manager.dart';
import '../logScreen/log.dart';
import 'open_file.dart';

class FileSelectionDialog extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback? onOpenPressed;

  const FileSelectionDialog({
    super.key,
    required this.controller,
    this.onOpenPressed,
  });

  @override
  State<FileSelectionDialog> createState() => _FileSelectionDialogState();
}

class _FileSelectionDialogState extends State<FileSelectionDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allFiles = [];
  List<Map<String, dynamic>> _filteredFiles = [];
  bool _isLoading = true;
  String? _errorMessage;

  // Track the currently selected file's RecNo for visual feedback
  int? _selectedRecNo;

  @override
  void initState() {
    super.initState();
    _fetchAndSetFiles();
    // Search listener is now handled by the onChanged property in the dialog's TextField
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchAndSetFiles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      LogPage.addLog('[FileSelectionDialog] Fetching files from database...');
      final database = await DatabaseManager().database;

      final files = await database.query(
        'Test',
        columns: [
          'RecNo',
          'FName',
          'OperatorName',
          'TDate',
          'TTime',
          'ScanningRate',
          'ScanningRateHH',
          'ScanningRateMM',
          'ScanningRateSS',
          'TestDurationDD',
          'TestDurationHH',
          'TestDurationMM',
          'TestDurationSS',
          'GraphVisibleArea',
          'DBName'
        ],
        orderBy: 'RecNo DESC', // This correctly sorts the newest files to the top
      );
      LogPage.addLog('[FileSelectionDialog] Found ${files.length} files in database.');

      if (mounted) {
        setState(() {
          _allFiles = files;
          _filteredFiles = files;
          _isLoading = false;
          _selectedRecNo = null;
        });
      }
    } catch (e) {
      LogPage.addLog('[FileSelectionDialog] Error fetching files from database: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load data from database: $e';
          _isLoading = false;
        });
      }
    }
  }

  // This function now closes the dialog and updates the globals, triggering OpenFilePage
  void _onFileSelected(Map<String, dynamic> file, BuildContext dialogContext, bool isDarkMode) {
    LogPage.addLog('[FileSelectionDialog] Selected file: ${file['FName']}, RecNo: ${file['RecNo']}');
    try {
      setState(() {
        widget.controller.text = file['FName']?.toString() ?? '';
        _selectedRecNo = (file['RecNo'] as num?)?.toInt();

        // Initialize notifiers if they are null
        Global.selectedRecNo ??= ValueNotifier<int?>(null);
        Global.selectedFileName ??= ValueNotifier<String?>(null);
        Global.operatorName ??= ValueNotifier<String?>(null);
        Global.selectedDBName ??= ValueNotifier<String?>(null);
        Global.scanningRate ??= ValueNotifier<int?>(null);
        Global.scanningRateHH ??= ValueNotifier<int?>(null);
        Global.scanningRateMM ??= ValueNotifier<int?>(null);
        Global.scanningRateSS ??= ValueNotifier<int?>(null);
        Global.testDurationDD ??= ValueNotifier<int?>(null);
        Global.testDurationHH ??= ValueNotifier<int?>(null);
        Global.testDurationMM ??= ValueNotifier<int?>(null);
        Global.testDurationSS ??= ValueNotifier<int?>(null);
        Global.graphVisibleArea ??= ValueNotifier<String?>(null);

        // Update global notifiers - this will trigger the listener in OpenFilePage
        Global.selectedRecNo!.value = _selectedRecNo;
        Global.selectedFileName!.value = file['FName']?.toString();
        Global.operatorName!.value = file['OperatorName']?.toString();
        Global.selectedDBName!.value = file['DBName']?.toString();
        Global.scanningRate!.value = (file['ScanningRate'] as num?)?.toInt();
        Global.scanningRateHH!.value = (file['ScanningRateHH'] as num?)?.toInt();
        Global.scanningRateMM!.value = (file['ScanningRateMM'] as num?)?.toInt();
        Global.scanningRateSS!.value = (file['ScanningRateSS'] as num?)?.toInt();
        Global.testDurationDD!.value = (file['TestDurationDD'] as num?)?.toInt();
        Global.testDurationHH!.value = (file['TestDurationHH'] as num?)?.toInt();
        Global.testDurationMM!.value = (file['TestDurationMM'] as num?)?.toInt();
        Global.testDurationSS!.value = (file['TestDurationSS'] as num?)?.toInt();
        Global.graphVisibleArea!.value = file['GraphVisibleArea']?.toString();
        LogPage.addLog('[FileSelectionDialog] Updated Global variables successfully.');
      });

      Navigator.of(dialogContext).pop(); // Close ONLY the browse dialog.
    } catch (e) {
      LogPage.addLog('[FileSelectionDialog] Error setting global variables: $e');
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(
          content: Text('Error updating file details: $e', style: GoogleFonts.poppins(color: ThemeColors.getColor('errorText', isDarkMode))),
          backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
        ),
      );
    }
  }

  void _showBrowseDialog(BuildContext context) {
    LogPage.addLog('[FileSelectionDialog] Opening browse dialog...');
    // We need to pass the current filtered list to the dialog
    List<Map<String, dynamic>> dialogFilteredFiles = List.from(_filteredFiles);

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return ValueListenableBuilder<bool>(
          valueListenable: Global.isDarkMode,
          builder: (context, isDarkMode, child) {
            // StatefulBuilder is used to manage the state of the dialog's content locally
            return StatefulBuilder(
              builder: (context, setState) {
                // The search logic is now inside the dialog's state
                void onSearchChanged(String query) {
                  final lowerCaseQuery = query.toLowerCase();
                  LogPage.addLog('[FileSelectionDialog] Search query: "$lowerCaseQuery"');
                  setState(() {
                    dialogFilteredFiles = _allFiles.where((file) {
                      final fName = (file['FName']?.toString() ?? '').toLowerCase();
                      final operatorName = (file['OperatorName']?.toString() ?? '').toLowerCase();
                      final date = (file['TDate']?.toString() ?? '').toLowerCase();
                      return fName.contains(lowerCaseQuery) ||
                          operatorName.contains(lowerCaseQuery) ||
                          date.contains(lowerCaseQuery);
                    }).toList();
                  });
                }

                return Dialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
                  child: Container(
                    width: 750,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Select a File', style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold, color: ThemeColors.getColor('dialogText', isDarkMode))),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _searchController,
                          onChanged: onSearchChanged, // Using onChanged to trigger search
                          style: GoogleFonts.poppins(color: ThemeColors.getColor('dialogText', isDarkMode), fontSize: 16),
                          decoration: InputDecoration(
                            hintText: 'Search by file name, operator, or date...',
                            hintStyle: GoogleFonts.poppins(color: ThemeColors.getColor('dialogSubText', isDarkMode).withOpacity(0.6)),
                            prefixIcon: Icon(Icons.search, color: ThemeColors.getColor('dialogSubText', isDarkMode)),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                              icon: Icon(Icons.clear, color: ThemeColors.getColor('dialogSubText', isDarkMode)),
                              onPressed: () {
                                _searchController.clear();
                                onSearchChanged(''); // Update list when cleared
                              },
                            )
                                : null,
                            filled: true,
                            fillColor: ThemeColors.getColor('textFieldBackground', isDarkMode),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.7), width: 1)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.7), width: 1)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ThemeColors.getColor('submitButton', isDarkMode), width: 2)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _isLoading
                            ? const Padding(padding: EdgeInsets.all(40), child: LoaderWidget())
                            : _errorMessage != null
                            ? Padding(padding: const EdgeInsets.all(20.0), child: Text('Error loading files: $_errorMessage', textAlign: TextAlign.center, style: GoogleFonts.poppins(color: ThemeColors.getColor('errorText', isDarkMode))))
                            : dialogFilteredFiles.isEmpty && _searchController.text.isNotEmpty
                            ? Padding(padding: const EdgeInsets.all(20.0), child: Text('No matching files found for "${_searchController.text}".', textAlign: TextAlign.center, style: GoogleFonts.poppins(color: ThemeColors.getColor('dialogSubText', isDarkMode), fontSize: 16)))
                            : dialogFilteredFiles.isEmpty
                            ? Padding(padding: const EdgeInsets.all(20.0), child: Text('No files available in the database.', textAlign: TextAlign.center, style: GoogleFonts.poppins(color: ThemeColors.getColor('dialogSubText', isDarkMode), fontSize: 16)))
                            : Expanded(
                          child: AnimationLimiter(
                            child: ListView.builder(
                              itemCount: dialogFilteredFiles.length,
                              itemBuilder: (context, index) {
                                final file = dialogFilteredFiles[index];
                                final isSelected = _selectedRecNo == (file['RecNo'] as num?)?.toInt();
                                return AnimationConfiguration.staggeredList(
                                  position: index,
                                  duration: const Duration(milliseconds: 375),
                                  child: SlideAnimation(
                                    verticalOffset: 50.0,
                                    child: FadeInAnimation(
                                      child: _FileListItem(
                                        file: file,
                                        isDarkMode: isDarkMode,
                                        isSelected: isSelected,
                                        onTap: () => _onFileSelected(file, dialogContext, isDarkMode),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(dialogContext).pop(),
                              child: Text('Cancel', style: GoogleFonts.poppins(color: ThemeColors.getColor('resetButton', isDarkMode))),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    LogPage.addLog('[FileSelectionDialog] Building main dialog...');
    return ValueListenableBuilder<bool>(
      valueListenable: Global.isDarkMode,
      builder: (context, isDarkMode, child) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
          child: Container(
            width: 450,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Open File', style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold, color: ThemeColors.getColor('dialogText', isDarkMode))),
                const SizedBox(height: 12),
                Text('Select a file to open or enter the file path.', style: GoogleFonts.poppins(fontSize: 16, color: ThemeColors.getColor('dialogSubText', isDarkMode))),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: widget.controller,
                        style: GoogleFonts.poppins(color: ThemeColors.getColor('dialogText', isDarkMode), fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'File path...',
                          hintStyle: GoogleFonts.poppins(color: ThemeColors.getColor('dialogSubText', isDarkMode).withOpacity(0.6)),
                          filled: true,
                          fillColor: ThemeColors.getColor('textFieldBackground', isDarkMode),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode))),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: ThemeColors.getColor('submitButton', isDarkMode), width: 2)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () => _showBrowseDialog(context),
                      icon: Icon(Icons.folder_open, color: ThemeColors.getColor('sidebarIcon', isDarkMode)),
                      label: Text('Browse', style: GoogleFonts.poppins(color: ThemeColors.getColor('sidebarText', isDarkMode))),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: ThemeColors.getColor('buttonHover', isDarkMode),
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        elevation: 0,
                      ).copyWith(
                        backgroundBuilder: (context, states, child) {
                          return Container(
                            decoration: BoxDecoration(gradient: ThemeColors.getButtonGradient(isDarkMode), borderRadius: BorderRadius.circular(8)),
                            child: child,
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Cancel', style: GoogleFonts.poppins(color: ThemeColors.getColor('resetButton', isDarkMode))),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: widget.onOpenPressed ??
                              () {
                            LogPage.addLog('[FileSelectionDialog] Main "Open" button pressed. File name: ${widget.controller.text}, RecNo: ${Global.selectedRecNo?.value}');
                            if (widget.controller.text.isNotEmpty) {
                              Navigator.of(context).push(
                                PageRouteBuilder(
                                  transitionDuration: const Duration(milliseconds: 400),
                                  pageBuilder: (context, animation, secondaryAnimation) => OpenFilePage(fileName: widget.controller.text, onExit: () {}),
                                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                    return FadeTransition(
                                      opacity: animation,
                                      child: ScaleTransition(
                                        scale: Tween<double>(begin: 0.95, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                                        child: child,
                                      ),
                                    );
                                  },
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Please select a file or enter a file path.', style: GoogleFonts.poppins(color: ThemeColors.getColor('dialogText', isDarkMode))),
                                  backgroundColor: ThemeColors.getColor('resetButton', isDarkMode),
                                ),
                              );
                            }
                          },
                      child: Text('Open', style: GoogleFonts.poppins(color: ThemeColors.getColor('sidebarText', isDarkMode))),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: ThemeColors.getColor('buttonHover', isDarkMode),
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        elevation: 0,
                      ).copyWith(
                        backgroundBuilder: (context, states, child) {
                          return Container(
                            decoration: BoxDecoration(gradient: ThemeColors.getButtonGradient(isDarkMode), borderRadius: BorderRadius.circular(8)),
                            child: child,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FileListItem extends StatelessWidget {
  final Map<String, dynamic> file;
  final bool isDarkMode;
  final bool isSelected;
  final VoidCallback onTap;

  const _FileListItem({
    required this.file,
    required this.isDarkMode,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final String fileName = file['FName']?.toString() ?? 'N/A';
    final String operatorName = file['OperatorName']?.toString() ?? 'N/A';
    final String dateStr = file['TDate']?.toString() ?? '';
    final String timeStr = file['TTime']?.toString() ?? '';

    // Consistently format the date and time
    String formattedDateTime;
    try {
      if (dateStr.isNotEmpty && timeStr.isNotEmpty) {
        final parsedDateTime = DateTime.parse('$dateStr $timeStr');
        formattedDateTime = DateFormat('dd-MM-yyyy HH:mm').format(parsedDateTime);
      } else {
        formattedDateTime = 'No Date/Time';
      }
    } catch (e) {
      // Fallback if parsing fails
      formattedDateTime = '$dateStr $timeStr';
    }

    final Color backgroundColor = isSelected
        ? ThemeColors.getColor('submitButton', isDarkMode).withOpacity(0.2)
        : ThemeColors.getColor('textFieldBackground', isDarkMode);

    final Color textColor = ThemeColors.getColor('dialogText', isDarkMode);
    final Color subTextColor = ThemeColors.getColor('dialogSubText', isDarkMode);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: ThemeColors.getColor('dropdownHover', isDarkMode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? ThemeColors.getColor('submitButton', isDarkMode) : ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.5),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.05), blurRadius: 8, offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 3, child: Text(fileName, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16, color: textColor), overflow: TextOverflow.ellipsis)),
                Expanded(flex: 2, child: Text(operatorName, style: GoogleFonts.poppins(fontSize: 14, color: subTextColor), overflow: TextOverflow.ellipsis)),
                Expanded(flex: 2, child: Text(formattedDateTime, style: GoogleFonts.poppins(fontSize: 14, color: subTextColor), overflow: TextOverflow.ellipsis, textAlign: TextAlign.right)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}