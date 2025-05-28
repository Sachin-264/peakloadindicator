import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// import 'dart:convert'; // Not used, can remove
import '../../constants/database_manager.dart';
import '../../constants/export.dart';
import '../../constants/global.dart';
import '../../constants/theme.dart';
import '../../constants/sessionmanager.dart'; // NEW: Import SessionDatabaseManager
import '../NavPages/channel.dart';
import '../Secondary_window/save_secondary_window.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:path/path.dart' as path;
import '../logScreen/log.dart';

class OpenFilePage extends StatefulWidget {
  final String fileName;
  const OpenFilePage({super.key, required this.fileName});

  @override
  State<OpenFilePage> createState() => _OpenFilePageState();
}

class _OpenFilePageState extends State<OpenFilePage> with SingleTickerProviderStateMixin {
  final _fileNameController = TextEditingController();
  final _operatorController = TextEditingController();
  final _scanRateHrController = TextEditingController(text: '0');
  final _scanRateMinController = TextEditingController(text: '0');
  final _scanRateSecController = TextEditingController(text: '1');
  final _testDurationDayController = TextEditingController(text: '0');
  final _testDurationHrController = TextEditingController(text: '0');
  final _testDurationMinController = TextEditingController(text: '0');
  final _testDurationSecController = TextEditingController(text: '0');
  final _graphVisibleHrController = TextEditingController(text: '0');
  final _graphVisibleMinController = TextEditingController(text: '60');
  final ScrollController _tableHorizontalScrollController = ScrollController();
  final ScrollController _tableVerticalScrollController = ScrollController();
  final GlobalKey _graphKey = GlobalKey();

  final List<OverlayEntry> _windowEntries = [];
  bool isDisplaying = false;
  String? selectedChannel;
  List<Map<String, dynamic>> tableData = [];
  Map<int, String> channelNames = {};
  Map<int, Color> graphLineColour = {};
  Map<String, Channel> _channelSetupData = {};

  int currentSegment = 0;
  int totalSegments = 1;
  double minYValue = 0;
  double maxYValue = 1000;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  Map<int, double?> maxLoadValues = {};
  double startTimeSeconds = 0;
  bool showDataPoints = false;
  double zoomLevel = 1.0;
  bool showPeak = false;
  late Database _database; // This will hold the reference to the session-specific DB
  bool _isDatabaseInitialized = false;
  bool _isLoading = true;
  String? _fetchError;
  String get _currentTime => DateTime.now().toIso8601String().substring(0, 19);


  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _animationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(_animationController);
    _graphVisibleMinController.addListener(_updateGraphSegments);

    Global.selectedRecNo?.addListener(_onRecNoChanged);
    Global.selectedFileName.addListener(_onGlobalChanged);
    Global.selectedDBName.addListener(_onGlobalChanged);
    Global.operatorName.addListener(_onGlobalChanged);
    Global.scanningRateHH.addListener(_onGlobalChanged);
    Global.scanningRateMM.addListener(_onGlobalChanged);
    Global.scanningRateSS.addListener(_onGlobalChanged);
    Global.testDurationDD?.addListener(_onGlobalChanged);
    Global.testDurationHH.addListener(_onGlobalChanged);
    Global.testDurationMM.addListener(_onGlobalChanged);
    Global.testDurationSS.addListener(_onGlobalChanged);
    Global.isDarkMode.addListener(_onThemeChanged);

    _initializeAndFetchData();
    LogPage.addLog('[$_currentTime] [INIT_STATE] Initialized OpenFilePage with fileName: ${widget.fileName}');
  }

  void _onThemeChanged() {
    if (mounted) {
      setState(() {
        LogPage.addLog('[$_currentTime] Theme changed. DarkMode: ${Global.isDarkMode.value}');
      });
    }
  }

  Future<void> _initializeAndFetchData() async {
    setState(() {
      _isLoading = true;
      _fetchError = null;
    });
    try {
      await _initializeDatabase(); // This is where the core change will be
      await _fetchChannelSetupData();
      setState(() {
        _isDatabaseInitialized = true;
      });
      await fetchData(showFull: true);
    } catch (e) {
      LogPage.addLog('[$_currentTime] Error during initialization or initial fetch: $e');
      setState(() {
        _fetchError = 'Error initializing: $e';
        _isLoading = false;
      });
    }
  }

  // MODIFIED: This method now uses SessionDatabaseManager
  Future<void> _initializeDatabase() async {
    // These lines should typically be called once at app startup (e.g., in main.dart)
    // and are not needed here if sqflite_common_ffi is already initialized globally.
    // sqfliteFfiInit();
    // databaseFactory = databaseFactoryFfi;

    // Ensure the data folder exists if it doesn't already
    final appDocumentsDir = await getApplicationSupportDirectory();
    final dataDirPath = path.join(appDocumentsDir.path, 'CountronicsData');
    await Directory(dataDirPath).create(recursive: true);

    // Get the database name from Global.selectedDBName. This is the session-specific DB name.
    final dbName = Global.selectedDBName.value; // This should be populated before calling OpenFilePage
    if (dbName == null || dbName.isEmpty) {
      throw Exception("Database name (DBName) not provided in Global.selectedDBName. Cannot open session database.");
    }

    // CRITICAL CHANGE: Use SessionDatabaseManager to open the session-specific database.
    // This ensures it is tracked and will be closed by SessionDatabaseManager().closeAllSessionDatabases().
    // IMPORTANT: Session-specific databases in 'CountronicsData' are generally NOT encrypted
    // with the main app's PRAGMA key unless you specifically applied it when creating them.
    // Your SerialPortScreen._saveData does NOT apply a key to the session DBs, so remove PRAGMA key here.
    _database = await SessionDatabaseManager().openSessionDatabase(dbName);

    LogPage.addLog('[$_currentTime] [INITIALIZE_DATABASE] Session database opened and tracked: $dbName');
  }

  // This method still fetches from the main database (Countronics.db)
  // to get the ChannelSetup data, which is correct.
  Future<void> _fetchChannelSetupData() async {
    // We need to get the main application database for ChannelSetup data
    final mainDatabase = await DatabaseManager().database;
    try {
      final List<Map<String, dynamic>> channelSetupRaw = await mainDatabase.query('ChannelSetup');
      _channelSetupData.clear();
      for (var row in channelSetupRaw) {
        final channel = Channel.fromJson(row);
        if (channel.channelName.isNotEmpty) {
          _channelSetupData[channel.channelName] = channel;
        }
      }
      LogPage.addLog('[$_currentTime] Fetched ${_channelSetupData.length} entries from ChannelSetup');
    } catch (e) {
      LogPage.addLog('[$_currentTime] Error fetching ChannelSetup data: $e');
      // If ChannelSetup is critical and fails, you might want to throw or set an error state.
    }
  }

  Future<void> fetchData({bool showFull = false}) async {
    // This method now uses the _database instance which is the session-specific DB
    // opened and tracked by SessionDatabaseManager.
    if (!_isDatabaseInitialized || Global.selectedRecNo?.value == null) {
      LogPage.addLog('[$_currentTime] [FETCH_DATA] Skipping fetch: database not initialized or RecNo is null');
      setState(() {
        _isLoading = false;
        if (Global.selectedRecNo?.value == null) {
          _fetchError = "No record selected to fetch data.";
        } else {
          _fetchError = "Database not ready.";
        }
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _fetchError = null;
    });
    try {
      LogPage.addLog('[$_currentTime] [FETCH_DATA] Fetching data for RecNo: ${Global.selectedRecNo!.value}');

      // Using the _database which is the session-specific one
      final test1Data = await _database.query(
        'Test1',
        where: 'RecNo = ?',
        whereArgs: [Global.selectedRecNo!.value],
      );
      final test2Data = await _database.query(
        'Test2',
        where: 'RecNo = ?',
        whereArgs: [Global.selectedRecNo!.value],
      );

      setState(() {
        tableData = test1Data.map((row) {
          final newRow = Map<String, dynamic>.from(row);
          for (int i = 1; i <= 50; i++) {
            if (newRow.containsKey('AbsPer$i')) {
              newRow['AbsPer$i'] = (newRow['AbsPer$i'] as num?)?.toDouble();
            }
          }
          return newRow;
        }).toList();

        final test2Row = test2Data.isNotEmpty ? test2Data[0] : {};
        channelNames.clear();
        graphLineColour.clear();
        maxLoadValues.clear();

        for (int i = 1; i <= 50; i++) {
          String? name = test2Row['ChannelName$i']?.toString().trim();
          if (name != null && name.isNotEmpty && name != 'null') {
            channelNames[i] = name;
            final setupChannel = _channelSetupData[name]; // Get config from main DB
            if (setupChannel != null && setupChannel.graphLineColour != 0 && setupChannel.graphLineColour != const Color(0xFF000000).value) {
              graphLineColour[i] = Color(setupChannel.graphLineColour);
            } else {
              graphLineColour[i] = _getDefaultColor(i);
            }

            if (tableData.isNotEmpty) {
              var values = tableData
                  .map((row) => (row['AbsPer$i'] as num?)?.toDouble())
                  .where((value) => value != null)
                  .cast<double>()
                  .toList();
              if (values.isNotEmpty) {
                maxLoadValues[i] = values.reduce((a, b) => a > b ? a : b);
              }
            }
          } else {
            break;
          }
        }

        selectedChannel = channelNames.isNotEmpty ? 'All' : null;
        _calculateGraphSegments();
        _calculateYRange();
        _initializeControllers();
      });
      LogPage.addLog('[$_currentTime] [FETCH_DATA] Data fetched successfully.');
    } catch (e) {
      LogPage.addLog('[$_currentTime] [FETCH_DATA] Error fetching data: $e');
      setState(() {
        _fetchError = 'Error fetching data: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _initializeControllers() {
    _fileNameController.text = Global.selectedFileName.value ?? widget.fileName;
    _operatorController.text = Global.operatorName.value ?? '';
    _scanRateHrController.text = Global.scanningRateHH.value?.toString() ?? '0';
    _scanRateMinController.text = Global.scanningRateMM.value?.toString() ?? '0';
    _scanRateSecController.text = Global.scanningRateSS.value?.toString() ?? '1';
    _testDurationDayController.text = Global.testDurationDD?.value?.toString() ?? '0';
    _testDurationHrController.text = Global.testDurationHH.value?.toString() ?? '0';
    _testDurationMinController.text = Global.testDurationMM.value?.toString() ?? '0';
    _testDurationSecController.text = Global.testDurationSS.value?.toString() ?? '0';
  }

  void _onRecNoChanged() {
    if (!mounted) return;
    LogPage.addLog('[$_currentTime] [ON_REC_NO_CHANGED] RecNo changed to ${Global.selectedRecNo?.value}, fetching new data');
    fetchData(showFull: true);
  }

  void _onGlobalChanged() {
    if (!mounted) return;
    setState(() {
      _initializeControllers();
    });
  }

  Color _getDefaultColor(int index) {
    final bool isDarkMode = Global.isDarkMode.value;
    const List<Color> lightModeColors = [
      Color(0xFF0288D1), Color(0xFFD81B60), Color(0xFF388E3C), Color(0xFFF57C00),
      Color(0xFF5E35B1), Color(0xFF00897B), Color(0xFFE53935), Color(0xFF3949AB),
      Color(0xFF7CB342), Color(0xFFC0CA33), Color(0xFF8E24AA), Color(0xFFFB8C00),
      Color(0xFF43A047), Color(0xFF1E88E5), Color(0xFF6D4C41),
    ];
    const List<Color> darkModeColors = [
      Color(0xFF90CAF9), Color(0xFFF48FB1), Color(0xFFA5D6A7), Color(0xFFFFCC80),
      Color(0xFFB39DDB), Color(0xFF80CBC4), Color(0xFFEF9A9A), Color(0xFF9FA8DA),
      Color(0xFFC5E1A5), Color(0xFFE6EE9C), Color(0xFFCE93D8), Color(0xFFFFE082),
      Color(0xFF4DB6AC), Color(0xFF64B5F6), Color(0xFFA1887F),
    ];
    return isDarkMode
        ? darkModeColors[(index - 1) % darkModeColors.length]
        : lightModeColors[(index - 1) % lightModeColors.length];
  }

  void _showColorPicker(int channelIndex, bool isDarkMode) {
    Color currentColor = graphLineColour[channelIndex] ?? _getDefaultColor(channelIndex);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
        title: Text(
          'Select Color for ${channelNames[channelIndex]}',
          style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode)),
        ),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: currentColor,
            onColorChanged: (Color color) {
              currentColor = color;
            },
            colorPickerWidth: 300.0,
            pickerAreaHeightPercent: 0.7,
            enableAlpha: true,
            displayThumbColor: true,
            labelTypes: const [ColorLabelType.hex],
            pickerAreaBorderRadius: const BorderRadius.all(Radius.circular(8.0)),
            hexInputBar: true,
            colorHistory: [],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                graphLineColour[channelIndex] = currentColor;
              });
              Navigator.of(context).pop();
            },
            child: Text(
              'Done',
              style: GoogleFonts.roboto(color: ThemeColors.getColor('submitButton', isDarkMode)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogSubText', isDarkMode)),
            ),
          ),
        ],
      ),
    );
  }

  void _updateGraphSegments() {
    setState(() {
      Global.graphVisibleArea.value = '${_graphVisibleHrController.text}:${_graphVisibleMinController.text}';
      _calculateGraphSegments();
    });
  }

  void _calculateGraphSegments() {
    if (tableData.isEmpty) {
      startTimeSeconds = 0;
      totalSegments = 1;
      currentSegment = 0;
      return;
    }
    List<double> timeSecondsList = tableData.map((row) {
      try {
        List<String> timeParts = (row['AbsTime'] as String).split(':');
        return int.parse(timeParts[0]) * 3600 + int.parse(timeParts[1]) * 60 + double.parse(timeParts[2]);
      } catch (e) { return 0.0; }
    }).toList();

    final validTimeSecondsList = timeSecondsList.where((t) => t > 0.0 || !tableData[timeSecondsList.indexOf(t)]['AbsTime'].isEmpty).toList();
    if (validTimeSecondsList.isEmpty) {
      startTimeSeconds = 0; totalSegments = 1; currentSegment = 0; return;
    }

    startTimeSeconds = validTimeSecondsList.reduce((a, b) => a < b ? a : b);
    double endTimeSeconds = validTimeSecondsList.reduce((a, b) => a > b ? a : b);
    double totalTimeSeconds = endTimeSeconds - startTimeSeconds;
    if (totalTimeSeconds < 0) totalTimeSeconds = 0;

    int segmentHours = int.tryParse(_graphVisibleHrController.text) ?? 0;
    int segmentMinutes = int.tryParse(_graphVisibleMinController.text) ?? 60;
    double segmentSeconds = (segmentHours * 3600) + (segmentMinutes * 60);
    if (segmentSeconds <= 0) segmentSeconds = 3600;

    totalSegments = totalTimeSeconds > 0 && segmentSeconds > 0 ? (totalTimeSeconds / segmentSeconds).ceil() : 1;
    if (totalSegments < 1) totalSegments = 1;
    if (currentSegment >= totalSegments) currentSegment = totalSegments > 0 ? totalSegments - 1 : 0;
  }

  void _calculateYRange({List<Map<String, dynamic>>? data}) {
    final dataToUse = data ?? tableData;
    if (dataToUse.isEmpty || selectedChannel == null || channelNames.isEmpty) {
      minYValue = 0; maxYValue = 1000; return;
    }

    List<double> allValues = [];
    if (selectedChannel == 'All') {
      for (int channelIndex in channelNames.keys) {
        if (channelNames.containsKey(channelIndex)) {
          var values = dataToUse
              .map((row) => (row['AbsPer$channelIndex'] as num?)?.toDouble())
              .where((value) => value != null)
              .cast<double>().toList();
          allValues.addAll(values);
        }
      }
    } else {
      if (int.tryParse(selectedChannel!) != null) {
        int channelIndex = int.parse(selectedChannel!);
        if (channelNames.containsKey(channelIndex)) {
          allValues = dataToUse
              .map((row) => (row['AbsPer$channelIndex'] as num?)?.toDouble())
              .where((value) => value != null)
              .cast<double>().toList();
        }
      }
    }

    if (allValues.isEmpty) {
      minYValue = 0; maxYValue = 1000; return;
    }
    allValues.sort();
    minYValue = allValues.first; maxYValue = allValues.last;

    double padding = (maxYValue - minYValue) * 0.1 * zoomLevel;
    if (padding == 0 && maxYValue == minYValue) padding = 10 * zoomLevel;

    minYValue -= padding; maxYValue += padding;
    if (minYValue >= maxYValue) minYValue = maxYValue - (2 * padding > 0 ? 2 * padding : 20);
    if (minYValue == maxYValue) { minYValue -=10; maxYValue +=10; }
  }

  Future<Uint8List?> _captureGraph({List<Map<String, dynamic>>? filteredData, required bool isDarkMode}) async {
    try {
      final originalTableData = List<Map<String, dynamic>>.from(tableData);
      final originalSegment = currentSegment;
      final originalMinY = minYValue;
      final originalMaxY = maxYValue;

      if (filteredData != null && filteredData.isNotEmpty) {
        setState(() {
          tableData = filteredData;
          currentSegment = 0;
          _calculateYRange(data: filteredData);
        });
        await Future.delayed(const Duration(milliseconds: 300));
      }

      RenderRepaintBoundary? boundary = _graphKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        if (filteredData != null) {
          setState(() {
            tableData = originalTableData; currentSegment = originalSegment;
            minYValue = originalMinY; maxYValue = originalMaxY;
            _calculateYRange();
          });
        }
        return null;
      }

      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (filteredData != null) {
        setState(() {
          tableData = originalTableData; currentSegment = originalSegment;
          minYValue = originalMinY; maxYValue = originalMaxY;
          _calculateYRange();
        });
      }
      return byteData?.buffer.asUint8List();
    } catch (e) {
      LogPage.addLog('[$_currentTime] [CAPTURE_GRAPH] Error capturing graph: $e');
      return null;
    }
  }

  Widget _buildGraphNavigation(bool isDarkMode) {
    Color iconColor = ThemeColors.getColor('dialogText', isDarkMode);
    Color textColor = ThemeColors.getColor('dialogSubText', isDarkMode);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.zoom_in, size: 24, color: iconColor), // Increased
                    onPressed: () => setState(() { zoomLevel *= 1.2; _animationController.forward(from: 0); _calculateYRange(); }),
                    tooltip: 'Zoom In', splashRadius: 22,
                  ),
                  IconButton(
                    icon: Icon(Icons.zoom_out, size: 24, color: iconColor), // Increased
                    onPressed: () => setState(() { zoomLevel /= 1.2; if (zoomLevel < 0.1) zoomLevel = 0.1; _animationController.forward(from: 0); _calculateYRange(); }),
                    tooltip: 'Zoom Out', splashRadius: 22,
                  ),
                ],
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(Icons.chevron_left, size: 24, color: currentSegment > 0 ? iconColor : Colors.grey.withOpacity(0.7)), // Increased
                      onPressed: currentSegment > 0 ? () => setState(() => currentSegment--) : null,
                      tooltip: 'Previous Segment', splashRadius: 22,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        'Segment ${currentSegment + 1}/$totalSegments',
                        style: GoogleFonts.roboto(color: textColor, fontWeight: FontWeight.w500, fontSize: 13), // Increased
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.chevron_right, size: 24, color: currentSegment < totalSegments - 1 ? iconColor : Colors.grey.withOpacity(0.7)), // Increased
                      onPressed: currentSegment < totalSegments - 1 ? () => setState(() => currentSegment++) : null,
                      tooltip: 'Next Segment', splashRadius: 22,
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.analytics_outlined, color: showPeak ? ThemeColors.getColor('errorText', isDarkMode) : iconColor, size: 24), // Increased
                    onPressed: () {
                      setState(() => showPeak = !showPeak);
                      if (showPeak && selectedChannel != null && selectedChannel != 'All') {
                        // SnackBar logic...
                      }
                    },
                    tooltip: 'Show Peak Value', splashRadius: 22,
                  ),
                  IconButton(
                    icon: Icon(showDataPoints ? Icons.scatter_plot_outlined : Icons.show_chart_outlined, color: iconColor, size: 24), // Increased
                    onPressed: () => setState(() => showDataPoints = !showDataPoints),
                    tooltip: 'Toggle Data Points', splashRadius: 22,
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 10),
          _buildChannelLegend(isDarkMode),
        ],
      ),
    );
  }

  Widget _buildChannelLegend(bool isDarkMode) {
    if (channelNames.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Wrap(
        spacing: 10.0,
        runSpacing: 6.0,
        alignment: WrapAlignment.center,
        children: channelNames.entries.map((entry) {
          int channelIndex = entry.key;
          String channelName = entry.value;
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _showColorPicker(channelIndex, isDarkMode),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: ThemeColors.getColor('cardBackground', isDarkMode).withOpacity(0.6),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: (graphLineColour[channelIndex] ?? _getDefaultColor(channelIndex)).withOpacity(0.7), width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(
                          color: graphLineColour[channelIndex] ?? _getDefaultColor(channelIndex),
                          shape: BoxShape.circle,
                          border: Border.all(color: ThemeColors.getColor('dialogText', isDarkMode).withOpacity(0.3), width: 0.5)
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      channelName,
                      style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode), fontSize: 12, fontWeight: FontWeight.w500), // Increased
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _highlightPeakOnGraph() { /* Placeholder */ }

  String _getUnitForChannel(String channelName) {
    final setupChannel = _channelSetupData[channelName];
    if (setupChannel != null && setupChannel.unit.isNotEmpty) return setupChannel.unit;
    if (channelName.toLowerCase().contains('load')) return 'kN';
    if (channelName.toLowerCase() == 'mixed') return '-';
    return '%';
  }

  Widget _buildGraph({List<Map<String, dynamic>>? filteredData, required bool isDarkMode}) {
    final dataToUse = filteredData ?? tableData;

    if (_isLoading && dataToUse.isEmpty) return Center(child: CircularProgressIndicator(color: ThemeColors.getColor('submitButton', isDarkMode)));
    if (_fetchError != null) return Center(child: Text(_fetchError!, style: GoogleFonts.roboto(fontSize: 16, color: ThemeColors.getColor('errorText', isDarkMode)), textAlign: TextAlign.center));
    if (dataToUse.isEmpty) return Center(child: Text('No data available for graph.', style: GoogleFonts.roboto(fontSize: 16, color: ThemeColors.getColor('dialogSubText', isDarkMode)), textAlign: TextAlign.center));
    if (channelNames.isEmpty || selectedChannel == null) return Center(child: Text('No channels selected or data missing.', style: GoogleFonts.roboto(fontSize: 16, color: ThemeColors.getColor('dialogSubText', isDarkMode)), textAlign: TextAlign.center));

    int segmentHours = int.tryParse(_graphVisibleHrController.text) ?? 0;
    int segmentMinutes = int.tryParse(_graphVisibleMinController.text) ?? 60;
    if (segmentHours == 0 && segmentMinutes == 0) segmentMinutes = 1;
    double segmentDurationSeconds = (segmentHours * 3600) + (segmentMinutes * 60);
    if (segmentDurationSeconds <=0) segmentDurationSeconds = 60;

    double segmentStartTimeSeconds = startTimeSeconds + (currentSegment * segmentDurationSeconds);
    double segmentEndTimeSeconds = segmentStartTimeSeconds + segmentDurationSeconds;

    List<Map<String, dynamic>> segmentData = dataToUse.where((row) {
      try {
        String? timeStr = row['AbsTime'] as String?;
        if (timeStr == null || !timeStr.contains(':')) return false;
        List<String> timeParts = timeStr.split(':');
        if (timeParts.length != 3) return false;
        double timeSeconds = int.parse(timeParts[0]) * 3600 + int.parse(timeParts[1]) * 60 + double.parse(timeParts[2].split('.').first);
        return timeSeconds >= segmentStartTimeSeconds && timeSeconds < segmentEndTimeSeconds;
      } catch (e) { return false; }
    }).toList();

    List<LineChartBarData> lineBarsData = [];
    List<int> channelsToPlot = selectedChannel == 'All'
        ? channelNames.keys.toList()
        : (int.tryParse(selectedChannel!) != null ? [int.parse(selectedChannel!)] : []);
    Map<double, String> timeToLabel = {};
    List<FlSpot> allSpotsInView = [];

    for (int channelIndex in channelsToPlot) {
      if (!channelNames.containsKey(channelIndex)) continue;
      List<FlSpot> spots = [];
      for (int i = 0; i < segmentData.length; i++) {
        var row = segmentData[i];
        try {
          String absTime = row['AbsTime'] as String;
          if (!absTime.contains(RegExp(r'^\d{1,2}:\d{2}:\d{2}(\.\d+)?$'))) continue;
          List<String> timeParts = absTime.split(':');
          double timeSeconds = int.parse(timeParts[0]) * 3600 + int.parse(timeParts[1]) * 60 + double.parse(timeParts[2].split('.').first);
          double xValue = timeSeconds - segmentStartTimeSeconds;
          timeToLabel[xValue] = absTime;
          double? loadValue = (row['AbsPer$channelIndex'] as num?)?.toDouble();
          if (loadValue != null) {
            FlSpot spot = FlSpot(xValue, loadValue);
            spots.add(spot); allSpotsInView.add(spot);
          }
        } catch (e) { continue; }
      }
      if (spots.isNotEmpty) {
        lineBarsData.add(LineChartBarData(
          spots: spots, isCurved: true, barWidth: 2.2,
          color: graphLineColour[channelIndex] ?? _getDefaultColor(channelIndex),
          dotData: FlDotData(
            show: showDataPoints || (showPeak && selectedChannel != 'All' && maxLoadValues[channelIndex] != null && selectedChannel == channelIndex.toString()),
            getDotPainter: (spot, percent, barData, index) {
              if (showPeak && selectedChannel == channelIndex.toString() && spot.y == maxLoadValues[channelIndex]) {
                return FlDotCirclePainter(radius: 5, color: ThemeColors.getColor('errorText', isDarkMode), strokeWidth: 1.5, strokeColor: ThemeColors.getColor('cardBackground', isDarkMode));
              }
              return FlDotCirclePainter(radius: 2.5, color: barData.color ?? _getDefaultColor(channelIndex), strokeWidth: 0.5, strokeColor: ThemeColors.getColor('cardBackground', isDarkMode));
            },
          ),
          belowBarData: BarAreaData(
            show:false,
          ),
        ));
      }
    }

    if (lineBarsData.isEmpty) return Center(child: Text('No data for current graph segment.', style: GoogleFonts.roboto(fontSize: 16, color: ThemeColors.getColor('dialogSubText', isDarkMode)), textAlign: TextAlign.center));

    double minX = 0;
    double maxX = allSpotsInView.isNotEmpty ? allSpotsInView.map((spot) => spot.x).reduce((a, b) => a > b ? a : b) : segmentDurationSeconds;
    if (maxX <= minX) maxX = minX + 60;
    double yAxisInterval = (maxYValue - minYValue) / 5;
    if (yAxisInterval <= 0) yAxisInterval = (maxYValue.abs() + minYValue.abs() + 20) / 5;
    double xAxisInterval = maxX / 5;
    if (xAxisInterval <= 0) xAxisInterval = (maxX + 60) / 5;

    return Column(
      children: [
        _buildGraphNavigation(isDarkMode),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 0, left: 4.0, right: 8.0, bottom: 8.0),
            child: RepaintBoundary(
              key: _graphKey,
              child: Container(
                color: ThemeColors.getColor('cardBackground', isDarkMode),
                padding: const EdgeInsets.only(left: 8.0, right: 16.0, top: 12.0, bottom: 8.0),
                child: LineChart(
                  LineChartData(
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (spot) => ThemeColors.getColor('dialogBackground', isDarkMode).withOpacity(0.95),
                        tooltipRoundedRadius: 6,
                        tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                          int actualChannelIndex = channelsToPlot[spot.barIndex];
                          String xText = timeToLabel[spot.x] ?? 'Time: ${spot.x.toStringAsFixed(0)}s';
                          String unit = _getUnitForChannel(channelNames[actualChannelIndex]!);
                          return LineTooltipItem(
                            '${channelNames[actualChannelIndex]}: ${spot.y.toStringAsFixed(Global.selectedMode.value == 'Graph' ? 2:1)} $unit\n$xText',
                            GoogleFonts.roboto(color: graphLineColour[actualChannelIndex] ?? _getDefaultColor(actualChannelIndex), fontWeight: FontWeight.bold, fontSize: 10),
                          );
                        }).toList(),
                      ),
                      handleBuiltInTouches: true,
                    ),
                    gridData: FlGridData(
                      show: true, drawHorizontalLine: true, drawVerticalLine: true,
                      horizontalInterval: yAxisInterval > 0 ? yAxisInterval : null,
                      verticalInterval: xAxisInterval > 0 ? xAxisInterval : null,
                      getDrawingHorizontalLine: (value) => FlLine(color: ThemeColors.getColor('dialogSubText', isDarkMode).withOpacity(0.15), strokeWidth: 0.6),
                      getDrawingVerticalLine: (value) => FlLine(color: ThemeColors.getColor('dialogSubText', isDarkMode).withOpacity(0.15), strokeWidth: 0.6),
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        axisNameWidget: Text(
                          _getUnitForChannel(selectedChannel == 'All' ? 'Mixed' : channelNames[int.tryParse(selectedChannel!) ?? channelsToPlot.first]!),
                          style: GoogleFonts.roboto(fontSize: 9, fontWeight: FontWeight.w600, color: ThemeColors.getColor('dialogText', isDarkMode)),
                        ),
                        axisNameSize: 18,
                        sideTitles: SideTitles(
                          showTitles: true, reservedSize: 42, interval: yAxisInterval > 0 ? yAxisInterval : null,
                          getTitlesWidget: (value, meta) => Text(value.toStringAsFixed((maxYValue - minYValue) < 10 ? 1:0), style: GoogleFonts.roboto(fontSize: 8, color: ThemeColors.getColor('dialogSubText', isDarkMode))),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        axisNameWidget: Text(
                          'Time (Segment Relative)',
                          style: GoogleFonts.roboto(fontSize: 9, fontWeight: FontWeight.w600, color: ThemeColors.getColor('dialogText', isDarkMode)),
                        ),
                        axisNameSize: 18,
                        sideTitles: SideTitles(
                          showTitles: true, reservedSize: 28, interval: xAxisInterval > 0 ? xAxisInterval : null,
                          getTitlesWidget: (value, meta) {
                            int totalSeconds = value.toInt(); int h = totalSeconds ~/ 3600; int m = (totalSeconds % 3600) ~/ 60; int s = totalSeconds % 60;
                            String label = h > 0 ? '${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}' : '${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
                            return Text(label, style: GoogleFonts.roboto(fontSize: 8, color: ThemeColors.getColor('dialogSubText', isDarkMode)));
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: true, border: Border.all(color: ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.3), width: 0.8)),
                    minX: minX, maxX: maxX, minY: minYValue, maxY: maxYValue,
                    lineBarsData: lineBarsData,
                    clipData: const FlClipData.all(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDataTable(bool isDarkMode) {
    if (_isLoading && tableData.isEmpty) return Center(child: CircularProgressIndicator(color: ThemeColors.getColor('submitButton', isDarkMode)));
    if (_fetchError != null && tableData.isEmpty) return Center(child: Text(_fetchError!, style: GoogleFonts.roboto(fontSize: 16, color: ThemeColors.getColor('errorText', isDarkMode))));
    if (tableData.isEmpty) return Center(child: Text('No tabular data available.', style: GoogleFonts.roboto(fontSize: 16, color: ThemeColors.getColor('dialogSubText', isDarkMode))));

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.8)),
        color: ThemeColors.getColor('cardBackground', isDarkMode),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Column(
          children: [
            Expanded(
              child: Scrollbar(
                thumbVisibility: true, controller: _tableVerticalScrollController,
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical, controller: _tableVerticalScrollController,
                  child: Scrollbar(
                    thumbVisibility: true, controller: _tableHorizontalScrollController,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal, controller: _tableHorizontalScrollController,
                      child: DataTable(
                        headingRowColor: MaterialStateProperty.resolveWith((states) => ThemeColors.getColor('tableHeaderBackground', isDarkMode)),
                        headingTextStyle: GoogleFonts.roboto(fontWeight: FontWeight.w600, color: ThemeColors.getColor('dialogText', isDarkMode), fontSize: 13),
                        dataRowMinHeight: 38, dataRowMaxHeight: 44,
                        columnSpacing: 22, // MODIFIED from 18
                        border: TableBorder.all(color: ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.5), width: 0.5),
                        columns: [
                          DataColumn(label: Text('No'), numeric: true),
                          DataColumn(label: Text('Time')),
                          DataColumn(label: Text('Date')),
                          ...channelNames.entries.map((entry) => DataColumn(label: Text(entry.value), numeric: true)),
                        ],
                        rows: tableData.map((data) {
                          String displayDate = 'N/A';
                          try {
                            if (data['AbsDate'] is String && (data['AbsDate'] as String).isNotEmpty) {
                              DateTime parsedDate = DateTime.parse(data['AbsDate']);
                              displayDate = "${parsedDate.year.toString().padLeft(4, '0')}-${parsedDate.month.toString().padLeft(2, '0')}-${parsedDate.day.toString().padLeft(2, '0')}";
                            }
                          } catch (e) { /* Error parsing */ }
                          return DataRow(
                            cells: [
                              DataCell(Text('${data['SNo'] ?? ''}', style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogSubText', isDarkMode), fontSize: 12))),
                              DataCell(Text(data['AbsTime'] ?? '', style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogSubText', isDarkMode), fontSize: 12))),
                              DataCell(Text(displayDate, style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogSubText', isDarkMode), fontSize: 12))),
                              ...channelNames.keys.map((channelIndex) {
                                double? value = (data['AbsPer$channelIndex'] as num?)?.toDouble();
                                String displayValue = value == null ? '-' : value.toStringAsFixed(2);
                                return DataCell(Text(displayValue, style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogSubText', isDarkMode), fontSize: 12), textAlign: TextAlign.right));
                              }),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeInputField(TextEditingController controller, String label, {bool compact = false, required bool isDarkMode}) {
    double fieldWidth = compact ? 55 : 70; // Increased
    double fontSize = compact ? 11 : 13;   // Increased
    EdgeInsets contentPadding = compact
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 10) // Increased
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 14); // Increased

    return SizedBox(
      width: fieldWidth,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.roboto(color: ThemeColors.getColor('dialogSubText', isDarkMode), fontSize: fontSize), // No -1
          filled: true,
          fillColor: ThemeColors.getColor('textFieldBackground', isDarkMode),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.5))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: ThemeColors.getColor('submitButton', isDarkMode), width: 1.2)),
          contentPadding: contentPadding,
          isDense: true,
        ),
        style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode), fontSize: fontSize),
        onChanged: (value) {
          int? intValue = int.tryParse(value);
          switch (label) {
            case 'Day': if (controller == _testDurationDayController) Global.testDurationDD?.value = intValue; break;
            case 'Hr':
              if (controller == _scanRateHrController) Global.scanningRateHH.value = intValue;
              if (controller == _testDurationHrController) Global.testDurationHH.value = intValue;
              if (controller == _graphVisibleHrController) _updateGraphSegments();
              break;
            case 'Min':
              if (controller == _scanRateMinController) Global.scanningRateMM.value = intValue;
              if (controller == _testDurationMinController) Global.testDurationMM.value = intValue;
              if (controller == _graphVisibleMinController) _updateGraphSegments();
              break;
            case 'Sec':
              if (controller == _scanRateSecController) Global.scanningRateSS.value = intValue;
              if (controller == _testDurationSecController) Global.testDurationSS.value = intValue;
              break;
          }
        },
      ),
    );
  }

  Widget _buildControlButton(String text, VoidCallback onPressed, {Color? explicitColor, bool? disabled, required bool isDarkMode, IconData? icon}) {
    return ElevatedButton.icon(
      icon: icon != null ? Icon(icon, size: 20, color: Colors.white) : const SizedBox.shrink(), // Increased
      label: Text(text, style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14)), // Increased
      onPressed: disabled == true ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: explicitColor ?? ThemeColors.getColor('submitButton', isDarkMode),
        padding: EdgeInsets.symmetric(horizontal: icon != null ? 16 : 20, vertical: 12), // Increased
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 1,
        shadowColor: Colors.black.withOpacity(0.15),
      ),
    );
  }

  Future<Map<String, String>?> _showTimeRangeDialog(bool isDarkMode) async {
    final fromController = TextEditingController();
    final toController = TextEditingController();
    String? errorMessage;
    fromController.text = '00:00:00'; toController.text = '23:59:59';

    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          title: Row(children: [
            Icon(Icons.filter_list_alt, color: ThemeColors.getColor('submitButton', isDarkMode), size: 22),
            const SizedBox(width: 10),
            Text('Filter by Time Range', style: GoogleFonts.roboto(fontSize: 18, fontWeight: FontWeight.w600, color: ThemeColors.getColor('dialogText', isDarkMode))),
          ]),
          content: SizedBox(
            width: 320,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: fromController,
                decoration: InputDecoration(
                  labelText: 'From Time (HH:mm:ss)', hintText: '00:00:00',
                  labelStyle: GoogleFonts.roboto(color: ThemeColors.getColor('dialogSubText', isDarkMode), fontSize: 13),
                  hintStyle: GoogleFonts.roboto(color: ThemeColors.getColor('dialogSubText', isDarkMode).withOpacity(0.5), fontSize: 13),
                  filled: true, fillColor: ThemeColors.getColor('textFieldBackground', isDarkMode),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  prefixIcon: Icon(Icons.schedule_outlined, color: ThemeColors.getColor('submitButton', isDarkMode), size: 18),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), isDense: true,
                ),
                keyboardType: TextInputType.datetime, style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode), fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: toController,
                decoration: InputDecoration(
                  labelText: 'To Time (HH:mm:ss)', hintText: '23:59:59',
                  labelStyle: GoogleFonts.roboto(color: ThemeColors.getColor('dialogSubText', isDarkMode), fontSize: 13),
                  hintStyle: GoogleFonts.roboto(color: ThemeColors.getColor('dialogSubText', isDarkMode).withOpacity(0.5), fontSize: 13),
                  filled: true, fillColor: ThemeColors.getColor('textFieldBackground', isDarkMode),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  prefixIcon: Icon(Icons.update_outlined, color: ThemeColors.getColor('submitButton', isDarkMode), size: 18),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), isDense: true,
                ),
                keyboardType: TextInputType.datetime, style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode), fontSize: 14),
              ),
              if (errorMessage != null) Padding(padding: const EdgeInsets.only(top: 10.0), child: Text(errorMessage!, style: GoogleFonts.roboto(color: ThemeColors.getColor('errorText', isDarkMode), fontSize: 11.5))),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text('Cancel', style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogSubText', isDarkMode), fontWeight: FontWeight.w500, fontSize: 13)),
            ),
            ElevatedButton(
              onPressed: () {
                final timeFormat = RegExp(r'^\d{2}:\d{2}:\d{2}$');
                if (!timeFormat.hasMatch(fromController.text) || !timeFormat.hasMatch(toController.text)) {
                  setDialogState(() => errorMessage = 'Use HH:mm:ss format'); return;
                }
                try {
                  List<String> fromP = fromController.text.split(':'), toP = toController.text.split(':');
                  double fromS = int.parse(fromP[0])*3600 + int.parse(fromP[1])*60 + double.parse(fromP[2]);
                  double toS = int.parse(toP[0])*3600 + int.parse(toP[1])*60 + double.parse(toP[2]);
                  if (fromS >= toS) { setDialogState(() => errorMessage = 'From time must be earlier'); return; }
                  Navigator.of(context).pop({'from': fromController.text, 'to': toController.text});
                } catch (e) { setDialogState(() => errorMessage = 'Invalid time format'); }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: ThemeColors.getColor('submitButton', isDarkMode),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10)),
              child: Text('Apply Filter', style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _filterDataByTimeRange(String fromTime, String toTime) {
    try {
      List<String> fromP = fromTime.split(':'), toP = toTime.split(':');
      double fromS = int.parse(fromP[0])*3600 + int.parse(fromP[1])*60 + double.parse(fromP[2]);
      double toS = int.parse(toP[0])*3600 + int.parse(toP[1])*60 + double.parse(toP[2]);
      var filteredData = tableData.where((row) {
        try {
          List<String> timeP = (row['AbsTime'] as String).split(':');
          double timeS = int.parse(timeP[0])*3600 + int.parse(timeP[1])*60 + double.parse(timeP[2]);
          return timeS >= fromS && timeS <= toS;
        } catch (e) { return false; }
      }).toList();
      LogPage.addLog('[$_currentTime] [FILTER_DATA] Filtered data count: ${filteredData.length} for range $fromTime - $toTime');
      return filteredData;
    } catch (e) {
      LogPage.addLog('[$_currentTime] [FILTER_DATA] Error filtering data: $e');
      return tableData;
    }
  }

  Widget _buildChannelSelector(bool isDarkMode) {
    return Container(
      height: 42, // Increased
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0), // Increased
      decoration: BoxDecoration(
        color: ThemeColors.getColor('textFieldBackground', isDarkMode),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.6)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedChannel,
          isDense: true,
          style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode), fontSize: 14, fontWeight: FontWeight.w500), // Increased
          dropdownColor: ThemeColors.getColor('dropdownBackground', isDarkMode),
          icon: Icon(Icons.arrow_drop_down_rounded, color: ThemeColors.getColor('dialogText', isDarkMode), size: 24), // Increased
          onChanged: (String? newValue) {
            if (newValue != null) {
              setState(() { selectedChannel = newValue; _calculateYRange(); if (showPeak && selectedChannel != 'All') _highlightPeakOnGraph(); });
            }
          },
          items: [
            DropdownMenuItem<String>(value: 'All', child: Text('All Channels')),
            ...channelNames.entries.map<DropdownMenuItem<String>>((entry) => DropdownMenuItem<String>(value: entry.key.toString(), child: Text(entry.value))),
          ].map((item) => DropdownMenuItem<String>(
            value: item.value,
            child: Text(
              (item.child as Text).data!,
              style: GoogleFonts.roboto(
                  color: ThemeColors.getColor('dialogText', isDarkMode),
                  fontSize: 14, // Increased
                  fontWeight: FontWeight.w500
              ),
            ),
          )).toList(),
        ),
      ),
    );
  }

  void _openFloatingGraphWindow(bool isDarkMode) {
    late OverlayEntry entry;
    Offset position = const Offset(100, 100);

    Map<String, List<Map<String, dynamic>>> dataByChannel = {};
    for (var channelIndex in channelNames.keys) {
      List<Map<String, dynamic>> channelDataPoints = [];
      for (var row in tableData) {
        String timeStr = row['AbsTime'] as String? ?? "00:00:00";
        DateTime? parsedTime; try { List<String> parts = timeStr.split(':'); if (parts.length == 3) { parsedTime = DateTime.now().copyWith(hour: int.parse(parts[0]), minute: int.parse(parts[1]), second: int.parse(parts[2].split('.').first), millisecond: 0, microsecond: 0); } } catch (e) { /* ignore */ }
        channelDataPoints.add({'time': timeStr, 'value': (row['AbsPer$channelIndex'] as num?)?.toDouble() ?? 0.0, 'Timestamp': (parsedTime ?? DateTime.now()).millisecondsSinceEpoch.toDouble()});
      }
      dataByChannel[channelIndex.toString()] = channelDataPoints;
    }

    Map<String, Channel> channelConfigs = {};
    for (var entry in channelNames.entries) {
      final setupChannel = _channelSetupData[entry.value];
      channelConfigs[entry.key.toString()] = Channel(
        recNo: (Global.selectedRecNo?.value ?? 0).toDouble(), channelName: entry.value, startingCharacter: setupChannel?.startingCharacter ?? '', dataLength: setupChannel?.dataLength ?? 7, decimalPlaces: setupChannel?.decimalPlaces ?? 2, unit: setupChannel?.unit ?? _getUnitForChannel(entry.value), chartMaximumValue: setupChannel?.chartMaximumValue ?? maxLoadValues[entry.key]?.toDouble() ?? 1000.0, chartMinimumValue: setupChannel?.chartMinimumValue ?? 0.0, targetAlarmMax: setupChannel?.targetAlarmMax ?? 0.0, targetAlarmMin: setupChannel?.targetAlarmMin ?? 0.0, graphLineColour: graphLineColour[entry.key]?.value ?? _getDefaultColor(entry.key).value, targetAlarmColour: setupChannel?.targetAlarmColour ?? Colors.red.value,
      );
    }
    Map<String, Color> convertedgraphLineColour = { for (var entry in graphLineColour.entries) entry.key.toString(): entry.value };

    entry = OverlayEntry(builder: (context) => Positioned(
      left: position.dx, top: position.dy,
      child: SaveMultiWindowGraph(
        windowId: 'window_${_windowEntries.length}', initialData: dataByChannel, channelColors: convertedgraphLineColour, channelConfigs: channelConfigs, entry: entry,
        onPositionUpdate: (newPosition) => position = newPosition,
        onClose: (closedEntry) { if (mounted) setState(() { _windowEntries.remove(closedEntry); closedEntry.remove(); }); },
      ),
    ));
    Overlay.of(context).insert(entry);
    if (mounted) setState(() => _windowEntries.add(entry));
  }

  Widget _buildStyledAddButton(bool isDarkMode) {
    return SizedBox(
      height: 42, // Increased
      child: ElevatedButton.icon(
        icon: const Icon(Icons.add_chart_outlined, color: Colors.white, size: 20), // Increased
        label: Text('Add Window', style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5)), // Increased
        onPressed: () => _openFloatingGraphWindow(isDarkMode),
        style: ElevatedButton.styleFrom(
          backgroundColor: ThemeColors.getColor('submitButton', isDarkMode),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), // Increased
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 1.5,
          shadowColor: ThemeColors.getColor('submitButton', isDarkMode).withOpacity(0.3),
        ),
      ),
    );
  }

  Widget _buildFullInputSection(bool isDarkMode) {
    return Card(
      elevation: 0,
      color: ThemeColors.getColor('cardBackground', isDarkMode),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: TextField(
                  controller: _fileNameController,
                  decoration: InputDecoration(
                    labelText: 'File Name', labelStyle: GoogleFonts.roboto(color: ThemeColors.getColor('dialogSubText', isDarkMode), fontSize: 14), // Increased
                    filled: true, fillColor: ThemeColors.getColor('textFieldBackground', isDarkMode),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.5))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: ThemeColors.getColor('submitButton', isDarkMode), width: 1.2)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16), // Increased
                    isDense: true,
                  ),
                  style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode), fontSize: 15), // Increased
                  onChanged: (value) => Global.selectedFileName.value = value,
                )),
                const SizedBox(width: 12),
                Expanded(child: TextField(
                  controller: _operatorController,
                  decoration: InputDecoration(
                    labelText: 'Operator', labelStyle: GoogleFonts.roboto(color: ThemeColors.getColor('dialogSubText', isDarkMode), fontSize: 14), // Increased
                    filled: true, fillColor: ThemeColors.getColor('textFieldBackground', isDarkMode),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.5))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: ThemeColors.getColor('submitButton', isDarkMode), width: 1.2)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16), // Increased
                    isDense: true,
                  ),
                  style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode), fontSize: 15), // Increased
                  onChanged: (value) => Global.operatorName.value = value,
                )),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('Scan Rate:', style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode), fontWeight: FontWeight.w500, fontSize: 14)), const SizedBox(width: 6), // Increased
                    _buildTimeInputField(_scanRateHrController, 'Hr', compact: true, isDarkMode: isDarkMode), const SizedBox(width: 3), Text(":", style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode))), const SizedBox(width: 3),
                    _buildTimeInputField(_scanRateMinController, 'Min', compact: true, isDarkMode: isDarkMode), const SizedBox(width: 3), Text(":", style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode))), const SizedBox(width: 3),
                    _buildTimeInputField(_scanRateSecController, 'Sec', compact: true, isDarkMode: isDarkMode),
                  ]),
                  const SizedBox(width: 16),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('Test Duration:', style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode), fontWeight: FontWeight.w500, fontSize: 14)), const SizedBox(width: 6), // Increased
                    _buildTimeInputField(_testDurationDayController, 'Day', compact: true, isDarkMode: isDarkMode), const SizedBox(width: 3), Text(":", style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode))), const SizedBox(width: 3),
                    _buildTimeInputField(_testDurationHrController, 'Hr', compact: true, isDarkMode: isDarkMode), const SizedBox(width: 3), Text(":", style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode))), const SizedBox(width: 3),
                    _buildTimeInputField(_testDurationMinController, 'Min', compact: true, isDarkMode: isDarkMode), const SizedBox(width: 3), Text(":", style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode))), const SizedBox(width: 3),
                    _buildTimeInputField(_testDurationSecController, 'Sec', compact: true, isDarkMode: isDarkMode),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftSection(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFullInputSection(isDarkMode),
        const SizedBox(height: 12),
        if (Global.selectedMode.value == 'Table' || Global.selectedMode.value == 'Combined')
          Expanded(
            child: Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              color: ThemeColors.getColor('cardBackground', isDarkMode),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.7)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    Expanded(child: _buildDataTable(isDarkMode)),
                    const SizedBox(height: 12),
                    if (Global.selectedMode.value == 'Table' || Global.selectedMode.value == 'Combined')
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (Global.selectedMode.value == 'Table')
                            _buildControlButton('Export Table', () async {
                              final timeRange = await _showTimeRangeDialog(isDarkMode);
                              List<Map<String, dynamic>> data = timeRange != null ? _filterDataByTimeRange(timeRange['from']!, timeRange['to']!) : tableData;
                              ExportUtils.exportBasedOnMode(context: context, mode: 'Table', tableData: data, fileName: _fileNameController.text, graphImage: null, authSettings: await DatabaseManager().getAuthSettings(), channelNames: channelNames, isDarkMode: isDarkMode);
                            }, isDarkMode: isDarkMode, icon: Icons.table_chart_outlined),
                          if (Global.selectedMode.value == 'Combined')
                            _buildControlButton('Export All (Table & Graph)', () async {
                              final timeRange = await _showTimeRangeDialog(isDarkMode);
                              List<Map<String, dynamic>> data = timeRange != null ? _filterDataByTimeRange(timeRange['from']!, timeRange['to']!) : tableData;
                              Uint8List? graphImg = await _captureGraph(filteredData: timeRange != null ? data : null, isDarkMode: isDarkMode);
                              ExportUtils.exportBasedOnMode(context: context, mode: 'Combined', tableData: data, fileName: _fileNameController.text, graphImage: graphImg, authSettings: await DatabaseManager().getAuthSettings(), channelNames: channelNames, isDarkMode: isDarkMode);
                            }, isDarkMode: isDarkMode, icon: Icons.summarize_outlined),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRightSection(bool isDarkMode) {
    // Conditional elevation for the graph card
    double graphCardElevation = (selectedChannel == 'All') ? 0.0 : 2.0;

    if (Global.selectedMode.value == 'Graph') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 0, // Controls card always flat
            color: ThemeColors.getColor('cardBackground', isDarkMode),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.7))),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    SizedBox(width: 130, child: TextField( // Increased
                      controller: _fileNameController, style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode), fontSize: 13, fontWeight: FontWeight.w500), // Increased
                      decoration: InputDecoration(labelText: 'File', labelStyle: GoogleFonts.roboto(color: ThemeColors.getColor('dialogSubText', isDarkMode), fontSize: 12), filled: true, fillColor: ThemeColors.getColor('textFieldBackground', isDarkMode), border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), isDense: true), // Increased
                      onChanged: (v) => Global.selectedFileName.value = v,
                    )),
                    SizedBox(width: 110, child: TextField( // Increased
                      controller: _operatorController, style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode), fontSize: 13, fontWeight: FontWeight.w500), // Increased
                      decoration: InputDecoration(labelText: 'Operator', labelStyle: GoogleFonts.roboto(color: ThemeColors.getColor('dialogSubText', isDarkMode), fontSize: 12), filled: true, fillColor: ThemeColors.getColor('textFieldBackground', isDarkMode), border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), isDense: true), // Increased
                      onChanged: (v) => Global.operatorName.value = v,
                    )),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('Seg:', style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode), fontWeight: FontWeight.w500, fontSize: 13)), const SizedBox(width: 4), // Increased
                      _buildTimeInputField(_graphVisibleHrController, 'Hr', compact: true, isDarkMode: isDarkMode), const SizedBox(width: 2), Text(":", style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode))), const SizedBox(width: 2),
                      _buildTimeInputField(_graphVisibleMinController, 'Min', compact: true, isDarkMode: isDarkMode),
                    ]),
                    _buildChannelSelector(isDarkMode),
                    _buildStyledAddButton(isDarkMode),
                  ].expand((w) => [w, const SizedBox(width: 8)]).toList()..removeLast(), // Consistent spacing
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              elevation: graphCardElevation, // Conditional shadow
              margin: EdgeInsets.zero,
              color: ThemeColors.getColor('cardBackground', isDarkMode),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.7))),
              child: _buildGraph(isDarkMode: isDarkMode),
            ),
          ),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _buildControlButton('Export Graph', () async {
              final timeRange = await _showTimeRangeDialog(isDarkMode);
              List<Map<String, dynamic>> data = timeRange != null ? _filterDataByTimeRange(timeRange['from']!, timeRange['to']!) : tableData;
              Uint8List? graphImg = await _captureGraph(filteredData: timeRange != null ? data : null, isDarkMode: isDarkMode);
              ExportUtils.exportBasedOnMode(context: context, mode: 'Graph', tableData: [], fileName: _fileNameController.text, graphImage: graphImg, authSettings: await DatabaseManager().getAuthSettings(), channelNames: channelNames, isDarkMode: isDarkMode);
            }, isDarkMode: isDarkMode, icon: Icons.image_search_outlined),
          ]),
        ],
      );
    } else { // Combined View - Right Side (Graph)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('Graph Seg:', style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode), fontWeight: FontWeight.w500, fontSize: 14)), const SizedBox(width: 6), // Increased
                _buildTimeInputField(_graphVisibleHrController, 'Hr', compact: true, isDarkMode: isDarkMode), const SizedBox(width: 3), Text(":", style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode))), const SizedBox(width: 3),
                _buildTimeInputField(_graphVisibleMinController, 'Min', compact: true, isDarkMode: isDarkMode), const SizedBox(width: 12),
                _buildChannelSelector(isDarkMode), const SizedBox(width: 12),
                _buildStyledAddButton(isDarkMode),
              ],
            ),
          ),
          Expanded(
            child: Card(
              elevation: graphCardElevation, // Conditional shadow
              margin: EdgeInsets.zero,
              color: ThemeColors.getColor('cardBackground', isDarkMode),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.7))),
              child: _buildGraph(isDarkMode: isDarkMode),
            ),
          ),
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Global.isDarkMode,
      builder: (context, isDarkMode, child) {
        if (_isLoading && !_isDatabaseInitialized) {
          return Scaffold(backgroundColor: ThemeColors.getColor('appBackground', isDarkMode), body: Center(child: CircularProgressIndicator(color: ThemeColors.getColor('submitButton', isDarkMode))));
        }
        if ((_fetchError != null && tableData.isEmpty && channelNames.isEmpty) || (Global.selectedRecNo?.value == null && !_isLoading)) {
          return Scaffold(
            backgroundColor: ThemeColors.getColor('appBackground', isDarkMode),
            body: SafeArea(child: Center(child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.error_outline_rounded, color: ThemeColors.getColor('errorText', isDarkMode), size: 44), const SizedBox(height: 12),
                Text(_fetchError ?? "No data record selected or an error occurred.", textAlign: TextAlign.center, style: GoogleFonts.roboto(fontSize: 16, color: ThemeColors.getColor('dialogText', isDarkMode), fontWeight: FontWeight.w500)),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  icon: Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                  label: Text("Retry / Re-initialize", style: GoogleFonts.roboto(color: Colors.white, fontSize: 13)),
                  style: ElevatedButton.styleFrom(backgroundColor: ThemeColors.getColor('submitButton', isDarkMode), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                  onPressed: () => _initializeAndFetchData(),
                )
              ]),
            ))),
          );
        }

        return Scaffold(
          backgroundColor: ThemeColors.getColor('appBackground', isDarkMode),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: ValueListenableBuilder<String>(
                valueListenable: Global.selectedMode,
                builder: (context, mode, _) {
                  bool showLeft = mode == 'Table' || mode == 'Combined';
                  bool showRight = mode == 'Graph' || mode == 'Combined';
                  int leftFlex = mode == 'Combined' ? 1 : (mode == 'Table' ? 1 : 0);
                  int rightFlex = mode == 'Combined' ? (showLeft ? 1 : 2) : (mode == 'Graph' ? 1 : 0); // Give graph more space if it's alone or combined with table
                  if (mode == 'Table') rightFlex = 0;
                  if (mode == 'Graph') leftFlex = 0;


                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showLeft) Expanded(flex: leftFlex, child: _buildLeftSection(isDarkMode)),
                      if (showLeft && showRight) const SizedBox(width: 12),
                      if (showRight) Expanded(flex: rightFlex, child: _buildRightSection(isDarkMode)),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    // Dispose of all controllers and listeners as usual.
    _fileNameController.dispose(); _operatorController.dispose();
    _scanRateHrController.dispose(); _scanRateMinController.dispose(); _scanRateSecController.dispose();
    _testDurationDayController.dispose(); _testDurationHrController.dispose(); _testDurationMinController.dispose(); _testDurationSecController.dispose();
    _graphVisibleHrController.dispose(); _graphVisibleMinController.removeListener(_updateGraphSegments); _graphVisibleMinController.dispose();
    _tableHorizontalScrollController.dispose(); _tableVerticalScrollController.dispose();
    _animationController.dispose();

    Global.selectedRecNo?.removeListener(_onRecNoChanged);
    Global.selectedFileName.removeListener(_onGlobalChanged); Global.selectedDBName.removeListener(_onGlobalChanged);
    Global.operatorName.removeListener(_onGlobalChanged);
    Global.scanningRateHH.removeListener(_onGlobalChanged); Global.scanningRateMM.removeListener(_onGlobalChanged); Global.scanningRateSS.removeListener(_onGlobalChanged);
    Global.testDurationDD?.removeListener(_onGlobalChanged); Global.testDurationHH.removeListener(_onGlobalChanged); Global.testDurationMM.removeListener(_onGlobalChanged); Global.testDurationSS.removeListener(_onGlobalChanged);
    Global.isDarkMode.removeListener(_onThemeChanged);

    // CRITICAL: Close the session-specific database opened by this page.
    // This is explicitly done here because this widget is the one that opened it.
    // SessionDatabaseManager will also close it if it's still open during a global closure.
    if (_isDatabaseInitialized && _database.isOpen) {
      try {
        _database.close();
        LogPage.addLog('[$_currentTime] [DISPOSE] Session database for OpenFilePage explicitly closed.');
      } catch (e) {
        LogPage.addLog('[$_currentTime] [DISPOSE] Error closing session database for OpenFilePage: $e');
      }
    }
    _isDatabaseInitialized = false; // Reset flag

    LogPage.addLog('[$_currentTime] [DISPOSE] OpenFilePage disposed.');
    super.dispose();
  }
}