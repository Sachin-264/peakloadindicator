import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:peakloadindicator/constants/loader_widget.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart'; // Import the animation package
import '../../constants/global.dart';
import '../../constants/theme.dart';
import '../../constants/database_manager.dart';
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
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchAndSetFiles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      print('[FileSelectionDialog] Fetching files from database...');
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
        orderBy: 'RecNo DESC',
      );
      print('[FileSelectionDialog] Found ${files.length} files in database.');

      setState(() {
        _allFiles = files;
        _filteredFiles = files; // Initially, all files are filtered
        _isLoading = false;
        _selectedRecNo = null; // Clear selection on new data load
      });
    } catch (e) {
      print('[FileSelectionDialog] Error fetching files from database: $e');
      setState(() {
        _errorMessage = 'Failed to load data from database: $e';
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    print('[FileSelectionDialog] Search query: "$query"');
    setState(() {
      _filteredFiles = _allFiles.where((file) {
        final fName = (file['FName']?.toString() ?? '').toLowerCase();
        final operatorName = (file['OperatorName']?.toString() ?? '').toLowerCase();
        final date = (file['TDate']?.toString() ?? '').toLowerCase(); // Include date in search
        return fName.contains(query) || operatorName.contains(query) || date.contains(query);
      }).toList();
      print('[FileSelectionDialog] Filtered results count: ${_filteredFiles.length}');
    });
  }

  // Function to handle file selection from the list (only fills text field and closes browse dialog)
  void _onFileSelected(Map<String, dynamic> file, BuildContext dialogContext, bool isDarkMode) {
    print('[FileSelectionDialog] Selected file: ${file['FName']}, RecNo: ${file['RecNo']}');
    try {
      setState(() {
        widget.controller.text = file['FName']?.toString() ?? '';
        _selectedRecNo = (file['RecNo'] as num?)?.toInt(); // Set selected for visual feedback

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

        print('[FileSelectionDialog] Updated Global testDurationSS: ${Global.testDurationSS!.value}');
        Global.graphVisibleArea!.value = file['GraphVisibleArea']?.toString();

        print('[FileSelectionDialog] Updated Global variables successfully.');
      });

      Navigator.of(dialogContext).pop(); // Close ONLY the current browse dialog.

    } catch (e) {
      print('[FileSelectionDialog] Error setting global variables: $e');
      ScaffoldMessenger.of(dialogContext).showSnackBar( // Use dialogContext's context for SnackBar
        SnackBar(
          content: Text(
            'Error updating file details: $e',
            style: GoogleFonts.poppins(
              color: ThemeColors.getColor('errorText', isDarkMode),
            ),
          ),
          backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
        ),
      );
    }
  }

  void _showBrowseDialog(BuildContext context) {
    print('[FileSelectionDialog] Opening browse dialog...');
    showDialog(
      context: context, // This is the context of the main FileSelectionDialog
      builder: (BuildContext dialogContext) { // This is the context of the new dialog
        return ValueListenableBuilder<bool>(
          valueListenable: Global.isDarkMode,
          builder: (context, isDarkMode, child) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
              child: Container(
                width: 750, // Adjusted width for more space
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Select a File',
                      style: GoogleFonts.poppins(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: ThemeColors.getColor('dialogText', isDarkMode),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _searchController,
                      style: GoogleFonts.poppins(
                        color: ThemeColors.getColor('dialogText', isDarkMode),
                        fontSize: 16,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search by file name, operator, or date...',
                        hintStyle: GoogleFonts.poppins(
                          color: ThemeColors.getColor('dialogSubText', isDarkMode).withOpacity(0.6),
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: ThemeColors.getColor('dialogSubText', isDarkMode),
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                          icon: Icon(
                            Icons.clear,
                            color: ThemeColors.getColor('dialogSubText', isDarkMode),
                          ),
                          onPressed: () {
                            _searchController.clear();
                          },
                        )
                            : null,
                        filled: true,
                        fillColor: ThemeColors.getColor('textFieldBackground', isDarkMode),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.7),
                            width: 1,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.7),
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: ThemeColors.getColor('submitButton', isDarkMode),
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _isLoading
                        ? const Padding(
                      padding: EdgeInsets.all(40),
                      child: LoaderWidget(),
                    )
                        : _errorMessage != null
                        ? Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Text(
                        'Error loading files: $_errorMessage',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          color: ThemeColors.getColor('errorText', isDarkMode),
                        ),
                      ),
                    )
                        : _filteredFiles.isEmpty && _searchController.text.isNotEmpty
                        ? Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Text(
                        'No matching files found for "${_searchController.text}".',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          color: ThemeColors.getColor('dialogSubText', isDarkMode),
                          fontSize: 16,
                        ),
                      ),
                    )
                        : _filteredFiles.isEmpty
                        ? Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Text(
                        'No files available in the database.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          color: ThemeColors.getColor('dialogSubText', isDarkMode),
                          fontSize: 16,
                        ),
                      ),
                    )
                        : Expanded(
                      child: AnimationLimiter(
                        child: ListView.builder(
                          itemCount: _filteredFiles.length,
                          itemBuilder: (context, index) {
                            final file = _filteredFiles[index];
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
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.poppins(
                              color: ThemeColors.getColor('resetButton', isDarkMode),
                            ),
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    print('[FileSelectionDialog] Building main dialog...');
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
                Text(
                  'Open File',
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: ThemeColors.getColor('dialogText', isDarkMode),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Select a file to open or enter the file path.',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: ThemeColors.getColor('dialogSubText', isDarkMode),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: widget.controller,
                        style: GoogleFonts.poppins(
                          color: ThemeColors.getColor('dialogText', isDarkMode),
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'File path...',
                          hintStyle: GoogleFonts.poppins(
                            color: ThemeColors.getColor('dialogSubText', isDarkMode).withOpacity(0.6),
                          ),
                          filled: true,
                          fillColor: ThemeColors.getColor('textFieldBackground', isDarkMode),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: ThemeColors.getColor('cardBorder', isDarkMode),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: ThemeColors.getColor('cardBorder', isDarkMode),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: ThemeColors.getColor('submitButton', isDarkMode),
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () => _showBrowseDialog(context),
                      icon: Icon(
                        Icons.folder_open,
                        color: ThemeColors.getColor('sidebarIcon', isDarkMode),
                      ),
                      label: Text(
                        'Browse',
                        style: GoogleFonts.poppins(
                          color: ThemeColors.getColor('sidebarText', isDarkMode),
                        ),
                      ),
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
                            decoration: BoxDecoration(
                              gradient: ThemeColors.getButtonGradient(isDarkMode),
                              borderRadius: BorderRadius.circular(8),
                            ),
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
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.poppins(
                          color: ThemeColors.getColor('resetButton', isDarkMode),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      // This onPressed will now properly trigger the navigation with animation
                      onPressed: widget.onOpenPressed ??
                              () {
                            print(
                                '[FileSelectionDialog] Main "Open" button pressed. File name: ${widget.controller.text}, RecNo: ${Global.selectedRecNo?.value}');
                            if (widget.controller.text.isNotEmpty) {
                              // --- ANIMATION CHANGE HERE ---
                              Navigator.of(context).push(
                                PageRouteBuilder(
                                  transitionDuration: const Duration(milliseconds: 400), // Duration of the animation
                                  pageBuilder: (context, animation, secondaryAnimation) =>
                                      OpenFilePage(fileName: widget.controller.text),
                                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                    // Fade in and slight scale up animation
                                    return FadeTransition(
                                      opacity: animation,
                                      child: ScaleTransition(
                                        scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                                          CurvedAnimation(
                                            parent: animation,
                                            curve: Curves.easeOutCubic, // A nice smooth curve
                                          ),
                                        ),
                                        child: child, // The OpenFilePage widget
                                      ),
                                    );
                                  },
                                ),
                              );
                              // --- END ANIMATION CHANGE ---
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Please select a file or enter a file path.',
                                    style: GoogleFonts.poppins(
                                      color: ThemeColors.getColor('dialogText', isDarkMode),
                                    ),
                                  ),
                                  backgroundColor: ThemeColors.getColor('resetButton', isDarkMode),
                                ),
                              );
                            }
                          },
                      child: Text(
                        'Open',
                        style: GoogleFonts.poppins(
                          color: ThemeColors.getColor('sidebarText', isDarkMode),
                        ),
                      ),
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
                            decoration: BoxDecoration(
                              gradient: ThemeColors.getButtonGradient(isDarkMode),
                              borderRadius: BorderRadius.circular(8),
                            ),
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

// New Custom Widget for File List Item (unchanged, as its visual look was desired)
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
    final String date = file['TDate']?.toString() ?? 'N/A';
    final String time = file['TTime']?.toString() ?? 'N/A';
    final String dateTime = '$date $time';

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
                color: isSelected
                    ? ThemeColors.getColor('submitButton', isDarkMode)
                    : ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.5),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    fileName,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: textColor,),
                      overflow: TextOverflow.ellipsis,
                                     ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    operatorName,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: subTextColor,),
                      overflow: TextOverflow.ellipsis,

                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    dateTime,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: subTextColor,),
                      overflow: TextOverflow.ellipsis,

                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}