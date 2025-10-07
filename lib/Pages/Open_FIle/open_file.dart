import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../../constants/database_manager.dart';
import '../../constants/export.dart';
import '../../constants/global.dart';
import '../../constants/message_utils.dart';
import '../../constants/sessionmanager.dart';
import '../../constants/theme.dart';
import '../NavPages/channel.dart';
import '../Secondary_window/save_secondary_window.dart';
import '../homepage.dart';
import '../logScreen/log.dart';

// Helper class for Syncfusion Chart data points, consistent with SerialPortScreen
class ChartData {
  final DateTime time;
  final double? value;
  ChartData(this.time, this.value);
}

class OpenFilePage extends StatefulWidget {
  final String fileName;
  final VoidCallback onExit;

  const OpenFilePage({
    super.key,
    required this.fileName,
    required this.onExit,
  });

  @override
  State<OpenFilePage> createState() => _OpenFilePageState();
}

class _OpenFilePageState extends State<OpenFilePage> {
  // --- STATE VARIABLES ---
  final _fileNameController = TextEditingController();
  final _operatorController = TextEditingController();
  final GlobalKey _graphKey = GlobalKey();

  // Controllers for fetched metadata display
  final _scanRateHrController = TextEditingController();
  final _scanRateMinController = TextEditingController();
  final _scanRateSecController = TextEditingController();
  final _testDurationDayController = TextEditingController();
  final _testDurationHrController = TextEditingController();
  final _testDurationMinController = TextEditingController();
  final _testDurationSecController = TextEditingController();
  final _graphVisibleHrController = TextEditingController();
  final _graphVisibleMinController = TextEditingController();

  final ScrollController _tableVerticalScrollController = ScrollController();
  final ScrollController _tableHeaderHorizontalScrollController = ScrollController();
  final ScrollController _tableBodyHorizontalScrollController = ScrollController();

  // Database & Data Fetching
  late Database _database;
  bool _isDatabaseInitialized = false;
  bool _isLoading = true;
  String? _fetchError;
  String get _currentTime => DateTime.now().toIso8601String().substring(0, 19);

  // Data & Business Logic
  List<Map<String, dynamic>> _tableData = [];
  Map<int, String> _channelNames = {};
  Map<int, Color> _graphLineColours = {};
  Map<String, Channel> _channelSetupData = {};
  DateTime? _firstDataTimestamp;
  DateTime? _lastDataTimestamp;
  final Map<int, List<ChartData>> _graphData = {};
  final Map<int, ChartData> _globalPeakValues = {};

  // Graph & UI State
  late TrackballBehavior _trackballBehavior;
  late ZoomPanBehavior _zoomPanBehavior;
  late Set<int> _visibleGraphChannels;
  bool _showDataPoints = false;
  bool _showPeakValue = false;
  Duration _graphTimeWindow = const Duration(minutes: 60);

  // Segment and Graph Axis logic
  int _currentSegment = 1;
  int _maxSegments = 1;
  DateTime? _chartVisibleMin;
  DateTime? _chartVisibleMax;

  // Multi-Window Management
  final List<OverlayEntry> _windowEntries = [];
  int _windowCounter = 0;


  @override
  void initState() {
    super.initState();
    _trackballBehavior = TrackballBehavior(
        enable: true,
        activationMode: ActivationMode.singleTap,
        tooltipDisplayMode: TrackballDisplayMode.groupAllPoints,
        tooltipSettings: const InteractiveTooltip(enable: true, format: 'series.name : point.y'),
        shouldAlwaysShow: false
    );
    _zoomPanBehavior = ZoomPanBehavior(
        enablePinching: true,
        enablePanning: true,
        zoomMode: ZoomMode.x
    );

    _tableHeaderHorizontalScrollController.addListener(() {
      if (_tableHeaderHorizontalScrollController.hasClients &&
          _tableBodyHorizontalScrollController.hasClients &&
          _tableHeaderHorizontalScrollController.offset != _tableBodyHorizontalScrollController.offset) {
        _tableBodyHorizontalScrollController.jumpTo(_tableHeaderHorizontalScrollController.offset);
      }
    });

    _tableBodyHorizontalScrollController.addListener(() {
      if (_tableBodyHorizontalScrollController.hasClients &&
          _tableHeaderHorizontalScrollController.hasClients &&
          _tableBodyHorizontalScrollController.offset != _tableHeaderHorizontalScrollController.offset) {
        _tableHeaderHorizontalScrollController.jumpTo(_tableBodyHorizontalScrollController.offset);
      }
    });

    _initializeListeners();
    _initializeAndFetchData();
    LogPage.addLog('[$_currentTime] [INIT_STATE] Initialized OpenFilePage with fileName: ${widget.fileName}');
  }

  void _initializeListeners() {
    Global.selectedRecNo?.addListener(_onRecNoChanged);
    Global.isDarkMode.addListener(() => setState(() {}));
  }

  Future<void> _initializeAndFetchData() async {
    setState(() { _isLoading = true; _fetchError = null; });
    try {
      await _initializeDatabase();
      await _fetchChannelSetupData();
      setState(() { _isDatabaseInitialized = true; });
      await fetchData();
    } catch (e, s) {
      LogPage.addLog('[$_currentTime] Error during initialization or initial fetch: $e\n$s');
      if (mounted) {
        setState(() { _fetchError = 'Error initializing: $e'; _isLoading = false; });
      }
    }
  }

  Future<void> _initializeDatabase() async {
    final dbName = Global.selectedDBName.value;
    if (dbName == null || dbName.isEmpty) {
      throw Exception("Database name (DBName) not provided. Cannot open session database.");
    }
    _database = await SessionDatabaseManager().openSessionDatabase(dbName);
    LogPage.addLog('[$_currentTime] [DB_INIT] Session database opened: $dbName');
  }

  Future<void> _fetchChannelSetupData() async {
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
    }
  }

  Future<void> fetchData() async {
    if (!_isDatabaseInitialized || Global.selectedRecNo?.value == null) {
      if (mounted) setState(() { _isLoading = false; _fetchError = "No record selected to fetch data."; });
      return;
    }
    setState(() { _isLoading = true; _fetchError = null; });

    try {
      LogPage.addLog('[$_currentTime] Fetching data for RecNo: ${Global.selectedRecNo!.value}');

      final results = await Future.wait([
        _database.query('Test', where: 'RecNo = ?', whereArgs: [Global.selectedRecNo!.value]),
        _database.query('Test1', where: 'RecNo = ?', whereArgs: [Global.selectedRecNo!.value], orderBy: 'SNo ASC'),
        _database.query('Test2', where: 'RecNo = ?', whereArgs: [Global.selectedRecNo!.value]),
      ]);

      final testData = results[0];
      final test1Data = results[1] as List<Map<String, dynamic>>;
      final test2Data = results[2];

      _processTestMetadata(testData);
      _processChannelMetadata(test2Data);
      _processDataRows(test1Data);

      _calculateGlobalPeakValues();
      _calculateAndSetSegments();
      _setSegment(1);

    } catch (e, s) {
      LogPage.addLog('[$_currentTime] Error fetching data: $e\n$s');
      if (mounted) setState(() { _fetchError = 'Error fetching data: $e'; });
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  void _processTestMetadata(List<Map<String, dynamic>> testData) {
    if (testData.isEmpty) {
      LogPage.addLog('[$_currentTime] No metadata found in Test table.');
      return;
    }
    final testRow = testData.first;

    _fileNameController.text = (testRow['FName'] as String?) ?? widget.fileName;
    _operatorController.text = (testRow['OperatorName'] as String?) ?? '';

    _scanRateHrController.text = ((testRow['ScanningRateHH'] as num?)?.toInt() ?? 0).toString();
    _scanRateMinController.text = ((testRow['ScanningRateMM'] as num?)?.toInt() ?? 0).toString();
    _scanRateSecController.text = ((testRow['ScanningRateSS'] as num?)?.toInt() ?? 1).toString();

    _testDurationDayController.text = ((testRow['TestDurationDD'] as num?)?.toInt() ?? 0).toString();
    _testDurationHrController.text = ((testRow['TestDurationHH'] as num?)?.toInt() ?? 0).toString();
    _testDurationMinController.text = ((testRow['TestDurationMM'] as num?)?.toInt() ?? 0).toString();
    _testDurationSecController.text = ((testRow['TestDurationSS'] as num?)?.toInt() ?? 0).toString();

    final visibleSeconds = (testRow['GraphVisibleArea'] as num?)?.toInt() ?? 3600;
    _graphTimeWindow = Duration(seconds: visibleSeconds > 0 ? visibleSeconds : 3600);

    _graphVisibleHrController.text = _graphTimeWindow.inHours.toString();
    _graphVisibleMinController.text = _graphTimeWindow.inMinutes.remainder(60).toString();
  }


  void _processChannelMetadata(List<Map<String, dynamic>> test2Data) {
    _channelNames.clear();
    _graphLineColours.clear();
    final test2Row = test2Data.isNotEmpty ? test2Data[0] : {};

    for (int i = 1; i <= 100; i++) {
      String? name = test2Row['ChannelName$i']?.toString().trim();
      if (name != null && name.isNotEmpty && name != 'null') {
        _channelNames[i] = name;
        final setupChannel = _channelSetupData[name];
        Color color = _getDefaultColor(i);
        if (setupChannel != null) {
          try {
            final dbValue = setupChannel.graphLineColour;
            if (dbValue is int && dbValue != 0) {
              color = Color(dbValue);
            } else if (dbValue is String && dbValue.toString().isNotEmpty) {
              final colorString = dbValue.toString().replaceAll('#', '');
              if (colorString.length >= 6) {
                color = Color(int.parse('FF${colorString.substring(0,6)}', radix: 16));
              }
            }
          } catch(e) {
            LogPage.addLog('[$_currentTime] Could not parse color for channel $name. Value: ${setupChannel.graphLineColour}. Error: $e');
          }
        }
        _graphLineColours[i] = color;
      } else {
        break;
      }
    }
    _visibleGraphChannels = _channelNames.keys.toSet();
  }

  void _processDataRows(List<Map<String, dynamic>> test1Data) {
    _tableData = test1Data.map((row) => Map<String, dynamic>.from(row)).toList();
    _graphData.clear();
    _firstDataTimestamp = null;
    _lastDataTimestamp = null;

    if (_tableData.isEmpty) return;

    for (var row in _tableData) {
      DateTime? timestamp = _parseTimestamp(row['AbsDate'] as String?, row['AbsTime'] as String?);
      if (timestamp == null) continue;

      _firstDataTimestamp ??= timestamp;
      _lastDataTimestamp = timestamp;

      for (int channelIndex in _channelNames.keys) {
        final value = (row['AbsPer$channelIndex'] as num?)?.toDouble();
        _graphData.putIfAbsent(channelIndex, () => []).add(ChartData(timestamp, value));
      }
    }
  }

  DateTime? _parseTimestamp(String? dateStr, String? timeStr) {
    if (dateStr == null || timeStr == null || dateStr.isEmpty || timeStr.isEmpty) {
      return null;
    }
    try {
      final fullDateTimeStr = '$dateStr $timeStr';
      return DateTime.parse(fullDateTimeStr);
    } catch (e) {
      LogPage.addLog('[$_currentTime] Failed to parse timestamp: Date="$dateStr", Time="$timeStr". Error: $e');
      return null;
    }
  }

  void _calculateGlobalPeakValues() {
    _globalPeakValues.clear();
    _graphData.forEach((channelIndex, dataList) {
      final validData = dataList.where((d) => d.value != null).toList();
      if (validData.isNotEmpty) {
        _globalPeakValues[channelIndex] = validData.reduce((curr, next) => curr.value! > next.value! ? curr : next);
      }
    });
  }

  void _calculateAndSetSegments() {
    if (_firstDataTimestamp == null || _lastDataTimestamp == null) {
      _maxSegments = 1;
      return;
    }

    final totalDuration = _lastDataTimestamp!.difference(_firstDataTimestamp!);
    if (totalDuration.inSeconds <= 0 || _graphTimeWindow.inSeconds <= 0) {
      _maxSegments = 1;
    } else {
      _maxSegments = (totalDuration.inSeconds / _graphTimeWindow.inSeconds).ceil();
    }
    if (_maxSegments < 1) _maxSegments = 1;
    if (_currentSegment > _maxSegments) _currentSegment = _maxSegments;
  }

  void _setSegment(int segment) {
    if (_firstDataTimestamp == null) return;
    setState(() {
      _currentSegment = segment.clamp(1, _maxSegments);
      final segmentStartTime = _firstDataTimestamp!.add(Duration(seconds: (_currentSegment - 1) * _graphTimeWindow.inSeconds));
      _chartVisibleMin = segmentStartTime;
      _chartVisibleMax = segmentStartTime.add(_graphTimeWindow);
    });
  }

  void _onRecNoChanged() {

    if (ModalRoute.of(context)?.isCurrent == false) {
      LogPage.addLog('[OpenFilePage] Listener fired but ignored because a dialog is active.');
      return;
    }

    if (!mounted) return;
    LogPage.addLog('[$_currentTime] RecNo changed to ${Global.selectedRecNo?.value}, fetching new data');
    fetchData();
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    _operatorController.dispose();
    _scanRateHrController.dispose();
    _scanRateMinController.dispose();
    _scanRateSecController.dispose();
    _testDurationDayController.dispose();
    _testDurationHrController.dispose();
    _testDurationMinController.dispose();
    _testDurationSecController.dispose();
    _graphVisibleHrController.dispose();
    _graphVisibleMinController.dispose();

    _tableHeaderHorizontalScrollController.dispose();
    _tableBodyHorizontalScrollController.dispose();
    _tableVerticalScrollController.dispose();

    Global.selectedRecNo?.removeListener(_onRecNoChanged);
    Global.isDarkMode.removeListener(() {});

    for (var entry in _windowEntries) {
      entry.remove();
    }

    if (_isDatabaseInitialized && _database.isOpen) {
      _database.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Global.isDarkMode,
      builder: (context, isDarkMode, child) {
        if (_isLoading && !_isDatabaseInitialized) {
          return Scaffold(backgroundColor: ThemeColors.getColor('appBackground', isDarkMode), body: Center(child: CircularProgressIndicator(color: ThemeColors.getColor('submitButton', isDarkMode))));
        }
        if ((_fetchError != null && _tableData.isEmpty) || (Global.selectedRecNo?.value == null && !_isLoading)) {
          return _buildErrorState(isDarkMode);
        }

        return Scaffold(
          backgroundColor: ThemeColors.getColor('appBackground', isDarkMode),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(isDarkMode),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ValueListenableBuilder<String>(
                      valueListenable: Global.selectedMode,
                      builder: (context, mode, _) {
                        bool showLeft = mode == 'Table' || mode == 'Combined';
                        bool showRight = mode == 'Graph' || mode == 'Combined';
                        int leftFlex = mode == 'Combined' ? 5 : 1;
                        int rightFlex = mode == 'Combined' ? 7 : 1;

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
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ThemeColors.getColor('cardBackground', isDarkMode),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.7)),
      ),
      child: Row(
        children: [
          _buildExitButton(isDarkMode),
          const SizedBox(width: 16),
          _buildHeaderTextField('File Name', _fileNameController, isDarkMode, width: 200),
          const SizedBox(width: 12),
          _buildHeaderTextField('Operator', _operatorController, isDarkMode, width: 150),
          const Spacer(),
          _buildInfoDisplay('Scan Rate', [_scanRateHrController, _scanRateMinController, _scanRateSecController], ['h', 'm', 's'], isDarkMode),
          const SizedBox(width: 16),
          _buildInfoDisplay('Test Duration', [_testDurationDayController, _testDurationHrController, _testDurationMinController, _testDurationSecController], ['d', 'h', 'm', 's'], isDarkMode),
          const SizedBox(width: 16),
          _buildInfoDisplay('Graph Window', [_graphVisibleHrController, _graphVisibleMinController], ['h', 'm'], isDarkMode),
          const SizedBox(width: 24),
          _buildHeaderActionButton(
            isDarkMode,
            'Export',
            Icons.download_for_offline_outlined,
                () async {
              if (_tableData.isEmpty || _firstDataTimestamp == null || _lastDataTimestamp == null) {
                MessageUtils.showMessage(context, "No data available to export.", isError: true);
                return;
              }
              // This is the starting point of the export flow.
              _showExportDateRangePicker(context, isDarkMode, _firstDataTimestamp!, _lastDataTimestamp!);
            },
          ),
          const SizedBox(width: 8),
          _buildHeaderActionButton(isDarkMode, 'Add Window', Icons.add_chart_outlined, () => _openFloatingGraphWindow(isDarkMode)),
        ],
      ),
    );
  }

  // --- EXPORT DIALOGS ---
  // --- EXPORT DIALOGS (MODIFIED PORTION) ---

  /// Step 1 of Export: Show Date Picker with Editable Time Fields.
  /// On success, it calls Step 2: _showExportOptionsDialog.
  Future<void> _showExportDateRangePicker(BuildContext context, bool isDarkMode, DateTime initialStart, DateTime initialEnd) async {
    DateTime selectedStartDate = initialStart;
    DateTime selectedEndDate = initialEnd;

    // Controllers for editable time fields
    final startHhController = TextEditingController(text: DateFormat('HH').format(initialStart));
    final startMmController = TextEditingController(text: DateFormat('mm').format(initialStart));
    final startSsController = TextEditingController(text: DateFormat('ss').format(initialStart));
    final endHhController = TextEditingController(text: DateFormat('HH').format(initialEnd));
    final endMmController = TextEditingController(text: DateFormat('mm').format(initialEnd));
    final endSsController = TextEditingController(text: DateFormat('ss').format(initialEnd));

    final range = await showDialog<Map<String, DateTime>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
              title: Text('Select Export Range', style: TextStyle(color: ThemeColors.getColor('dialogText', isDarkMode))),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.35, // Adjust width for better layout
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('From', style: GoogleFonts.roboto(fontWeight: FontWeight.bold, fontSize: 16, color: ThemeColors.getColor('dialogText', isDarkMode))),
                    const SizedBox(height: 8),
                    // START DATE AND TIME ROW
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Date Picker (uses your existing helper)
                        Expanded(
                          flex: 3,
                          child: _buildDateTimePickerField(
                            label: 'Start Date', icon: Icons.calendar_today_outlined, isDarkMode: isDarkMode,
                            value: DateFormat('dd MMM yyyy').format(selectedStartDate),
                            onTap: () async {
                              final pickedDate = await showDatePicker(context: context, initialDate: selectedStartDate, firstDate: initialStart.subtract(const Duration(days: 3650)), lastDate: initialEnd.add(const Duration(days: 3650)));
                              if (pickedDate != null) {
                                // Update only the date part, preserving time from controllers
                                setDialogState(() => selectedStartDate = DateTime(pickedDate.year, pickedDate.month, pickedDate.day));
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Editable Time Fields
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Start Time (HH:MM:SS)", style: TextStyle(fontSize: 12, color: ThemeColors.getColor('dialogSubText', isDarkMode), fontWeight: FontWeight.w500)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  _buildTimeTextField(startHhController, 'HH', isDarkMode),
                                  Padding(padding: const EdgeInsets.symmetric(horizontal: 4.0), child: Text(":", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: ThemeColors.getColor('dialogSubText', isDarkMode)))),
                                  _buildTimeTextField(startMmController, 'MM', isDarkMode),
                                  Padding(padding: const EdgeInsets.symmetric(horizontal: 4.0), child: Text(":", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: ThemeColors.getColor('dialogSubText', isDarkMode)))),
                                  _buildTimeTextField(startSsController, 'SS', isDarkMode),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text('To', style: GoogleFonts.roboto(fontWeight: FontWeight.bold, fontSize: 16, color: ThemeColors.getColor('dialogText', isDarkMode))),
                    const SizedBox(height: 8),
                    // END DATE AND TIME ROW
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Date Picker
                        Expanded(
                          flex: 3,
                          child: _buildDateTimePickerField(
                            label: 'End Date', icon: Icons.calendar_today_outlined, isDarkMode: isDarkMode,
                            value: DateFormat('dd MMM yyyy').format(selectedEndDate),
                            onTap: () async {
                              final pickedDate = await showDatePicker(context: context, initialDate: selectedEndDate, firstDate: initialStart.subtract(const Duration(days: 3650)), lastDate: initialEnd.add(const Duration(days: 3650)));
                              if (pickedDate != null) {
                                setDialogState(() => selectedEndDate = DateTime(pickedDate.year, pickedDate.month, pickedDate.day));
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Editable Time Fields
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("End Time (HH:MM:SS)", style: TextStyle(fontSize: 12, color: ThemeColors.getColor('dialogSubText', isDarkMode), fontWeight: FontWeight.w500)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  _buildTimeTextField(endHhController, 'HH', isDarkMode),
                                  Padding(padding: const EdgeInsets.symmetric(horizontal: 4.0), child: Text(":", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: ThemeColors.getColor('dialogSubText', isDarkMode)))),
                                  _buildTimeTextField(endMmController, 'MM', isDarkMode),
                                  Padding(padding: const EdgeInsets.symmetric(horizontal: 4.0), child: Text(":", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: ThemeColors.getColor('dialogSubText', isDarkMode)))),
                                  _buildTimeTextField(endSsController, 'SS', isDarkMode),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
                TextButton(
                  child: Text('Next', style: TextStyle(color: ThemeColors.getColor('submitButton', isDarkMode), fontWeight: FontWeight.bold)),
                  onPressed: () {
                    try {
                      // Parse time from controllers, default to 0 if empty or invalid
                      final startH = int.tryParse(startHhController.text) ?? 0;
                      final startM = int.tryParse(startMmController.text) ?? 0;
                      final startS = int.tryParse(startSsController.text) ?? 0;

                      final endH = int.tryParse(endHhController.text) ?? 0;
                      final endM = int.tryParse(endMmController.text) ?? 0;
                      final endS = int.tryParse(endSsController.text) ?? 0;

                      // Basic validation for time values
                      if (startH < 0 || startH > 23 || startM < 0 || startM > 59 || startS < 0 || startS > 59 ||
                          endH < 0 || endH > 23 || endM < 0 || endM > 59 || endS < 0 || endS > 59) {
                        MessageUtils.showMessage(context, "Invalid time format. Please use HH (0-23), MM (0-59), SS (0-59).", isError: true);
                        return;
                      }

                      // Combine selected date with parsed time
                      final finalStartDate = DateTime(selectedStartDate.year, selectedStartDate.month, selectedStartDate.day, startH, startM, startS);
                      final finalEndDate = DateTime(selectedEndDate.year, selectedEndDate.month, selectedEndDate.day, endH, endM, endS);

                      if (finalEndDate.isBefore(finalStartDate)) {
                        MessageUtils.showMessage(context, "End date/time cannot be before start date/time.", isError: true);
                        return;
                      }
                      Navigator.of(dialogContext).pop({'start': finalStartDate, 'end': finalEndDate});
                    } catch (e) {
                      MessageUtils.showMessage(context, "Failed to parse time. Please check your input.", isError: true);
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      // IMPORTANT: Dispose controllers to prevent memory leaks
      startHhController.dispose();
      startMmController.dispose();
      startSsController.dispose();
      endHhController.dispose();
      endMmController.dispose();
      endSsController.dispose();
    });

    // If user cancelled the dialog, stop.
    if (range == null) return;

    // Proceed to the next dialog for header/footer options
    _showExportOptionsDialog(context, isDarkMode, range['start']!, range['end']!);
  }

  /// NEW HELPER WIDGET for creating a single time input field (HH, MM, or SS).
  Widget _buildTimeTextField(TextEditingController controller, String hint, bool isDarkMode) {
    return SizedBox(
      width: 55, // Fixed width for each time segment
      child: TextField(
        controller: controller,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(2),
        ],
        style: GoogleFonts.firaCode(fontSize: 14, color: ThemeColors.getColor('dialogText', isDarkMode)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: ThemeColors.getColor('dialogSubText', isDarkMode).withOpacity(0.7), fontSize: 12),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.8)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Theme.of(context).primaryColor),
          ),
        ),
      ),
    );
  }


  Future<void> _showExportOptionsDialog(BuildContext context, bool isDarkMode, DateTime selectedStart, DateTime selectedEnd) async {
    // Create controllers specifically for this dialog instance
    final headerLine1Controller = TextEditingController();
    final headerLine2Controller = TextEditingController();
    final headerLine3Controller = TextEditingController();
    final headerLine4Controller = TextEditingController();
    final footerLine1Controller = TextEditingController();
    final footerLine2Controller = TextEditingController();
    final footerLine3Controller = TextEditingController();
    final footerLine4Controller = TextEditingController();

    final options = await showDialog<Map<String, List<String>>>(
      context: context,
      barrierDismissible: false, // User must choose an action
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
          title: Text('Add Export Details', style: TextStyle(color: ThemeColors.getColor('dialogText', isDarkMode))),
          content: SingleChildScrollView(
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.4, // Make dialog wider
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Header Information", style: GoogleFonts.roboto(fontWeight: FontWeight.w600, fontSize: 16, color: ThemeColors.getColor('dialogText', isDarkMode))),
                  const SizedBox(height: 8),
                  _buildEditableField('Header Line 1...', headerLine1Controller, isDarkMode),
                  const SizedBox(height: 8),
                  _buildEditableField('Header Line 2...', headerLine2Controller, isDarkMode),
                  const SizedBox(height: 8),
                  _buildEditableField('Header Line 3...', headerLine3Controller, isDarkMode),
                  const SizedBox(height: 8),
                  _buildEditableField('Header Line 4...', headerLine4Controller, isDarkMode),
                  const Divider(height: 24),
                  Text("Footer Notes / Remarks", style: GoogleFonts.roboto(fontWeight: FontWeight.w600, fontSize: 16, color: ThemeColors.getColor('dialogText', isDarkMode))),
                  const SizedBox(height: 8),
                  _buildEditableField('Footer Line 1...', footerLine1Controller, isDarkMode),
                  const SizedBox(height: 8),
                  _buildEditableField('Footer Line 2...', footerLine2Controller, isDarkMode),
                  const SizedBox(height: 8),
                  _buildEditableField('Footer Line 3...', footerLine3Controller, isDarkMode),
                  const SizedBox(height: 8),
                  _buildEditableField('Footer Line 4...', footerLine4Controller, isDarkMode),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            ElevatedButton.icon(
              icon: const Icon(Icons.file_download_done),
              label: const Text('Confirm & Export'),
              style: ElevatedButton.styleFrom(
                backgroundColor: ThemeColors.getColor('submitButton', isDarkMode),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final headers = [
                  headerLine1Controller.text,
                  headerLine2Controller.text,
                  headerLine3Controller.text,
                  headerLine4Controller.text,
                ];
                final footers = [
                  footerLine1Controller.text,
                  footerLine2Controller.text,
                  footerLine3Controller.text,
                  footerLine4Controller.text,
                ];
                Navigator.of(dialogContext).pop({'headers': headers, 'footers': footers});
              },
            ),
          ],
        );
      },
    );

    // If user cancelled the options dialog, stop.
    if (options == null) return;

    // Filter the data based on the selected range
    final List<Map<String, dynamic>> filteredData = _tableData.where((row) {
      final timestamp = _parseTimestamp(row['AbsDate'], row['AbsTime']);
      return timestamp != null && !timestamp.isBefore(selectedStart) && !timestamp.isAfter(selectedEnd);
    }).toList();

    if (filteredData.isEmpty) {
      MessageUtils.showMessage(context, "No data found in the selected range.", isError: false);
      return;
    }

    // Proceed with export using all the collected data
    final String mode = Global.selectedMode.value;
    final Uint8List? graphImg = (mode == 'Graph' || mode == 'Combined') ? await _captureGraph(isDarkMode) : null;

    ExportUtils.exportBasedOnMode(
      context: context,
      mode: mode,
      tableData: filteredData,
      fileName: _fileNameController.text,
      operatorName: _operatorController.text,
      graphImage: graphImg,
      channelNames: _channelNames,
      firstTimestamp: selectedStart,
      lastTimestamp: selectedEnd,
      channelSetupData: _channelSetupData,
      headerLines: options['headers']!, // Pass headers
      footerLines: options['footers']!, // Pass footers
    );

    // Dispose controllers after use
    headerLine1Controller.dispose();
    headerLine2Controller.dispose();
    headerLine3Controller.dispose();
    headerLine4Controller.dispose();
    footerLine1Controller.dispose();
    footerLine2Controller.dispose();
    footerLine3Controller.dispose();
    footerLine4Controller.dispose();
  }

  /// Helper for building a tappable date/time field in a dialog.
  Widget _buildDateTimePickerField({
    required String label, required IconData icon, required String value, required VoidCallback onTap, required bool isDarkMode,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: ThemeColors.getColor('dialogSubText', isDarkMode), fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.8)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: ThemeColors.getColor('dialogSubText', isDarkMode)),
                const SizedBox(width: 10),
                Text(value, style: GoogleFonts.firaCode(fontSize: 14, color: ThemeColors.getColor('dialogText', isDarkMode))),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Helper for building an editable text field in a dialog.
  Widget _buildEditableField(String hintText, TextEditingController controller, bool isDarkMode) {
    return TextField(
      controller: controller,
      style: TextStyle(color: ThemeColors.getColor('dialogText', isDarkMode), fontSize: 13),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: ThemeColors.getColor('dialogSubText', isDarkMode).withOpacity(0.7), fontSize: 12),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.6))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Theme.of(context).primaryColor)),
      ),
    );
  }


  // --- UI WIDGETS (UNCHANGED FROM HERE) ---

  Widget _buildExitButton(bool isDarkMode) {
    return TextButton.icon(
      icon: const Icon(Icons.exit_to_app_rounded, size: 18),
      label: const Text("Exit"),
      onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const HomePage()), (Route<dynamic> route) => false),
      style: TextButton.styleFrom(
        foregroundColor: ThemeColors.getColor('dialogText', isDarkMode),
        backgroundColor: ThemeColors.getColor('cardBackground', isDarkMode).withOpacity(0.8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.5)),
        textStyle: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14),
      ),
    );
  }

  Widget _buildLeftSection(bool isDarkMode) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: ThemeColors.getColor('cardBackground', isDarkMode),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.7))),
      child: _buildDataTable(isDarkMode),
    );
  }

  Widget _buildRightSection(bool isDarkMode) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: ThemeColors.getColor('cardBackground', isDarkMode),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.7))),
      child: Column(
        children: [
          _buildChannelLegend(isDarkMode),
          const Divider(height: 1),
          Expanded(child: Padding(padding: const EdgeInsets.only(top: 8.0, right: 8.0), child: _buildRealTimeGraph(isDarkMode))),
          const Divider(height: 1),
          _buildGraphToolbar(isDarkMode),
        ],
      ),
    );
  }

  Widget _buildRealTimeGraph(bool isDarkMode) {
    final textColor = ThemeColors.getColor('dialogText', isDarkMode);
    final axisLineColor = ThemeColors.getColor('cardBorder', isDarkMode);
    List<CartesianSeries> series = [];
    List<PlotBand> plotBands = [];

    final visibleChannels = _channelNames.entries.where((entry) => _visibleGraphChannels.contains(entry.key)).toList();

    String yAxisTitleText = 'Value';
    if (visibleChannels.length == 1) {
      final channelName = visibleChannels.first.value;
      yAxisTitleText = '$channelName (${_getUnitForChannel(channelName)})';
    } else if (visibleChannels.isNotEmpty) {
      yAxisTitleText = 'Value';
    }

    for (var entry in visibleChannels) {
      final channelIndex = entry.key;
      final channelName = entry.value;
      final data = _graphData[channelIndex] ?? [];
      final setupChannel = _channelSetupData[channelName];

      if (setupChannel != null && setupChannel.targetAlarmMax != null && setupChannel.targetAlarmMin != null) {
        final alarmColor = Color(setupChannel.targetAlarmColour);
        if (setupChannel.targetAlarmMax! > 0) plotBands.add(PlotBand(start: setupChannel.targetAlarmMax!, end: setupChannel.targetAlarmMax!, borderWidth: 1.5, borderColor: alarmColor.withOpacity(0.8), dashArray: const <double>[5, 5]));
        if (setupChannel.targetAlarmMin! > 0) plotBands.add(PlotBand(start: setupChannel.targetAlarmMin!, end: setupChannel.targetAlarmMin!, borderWidth: 1.5, borderColor: alarmColor.withOpacity(0.8), dashArray: const <double>[5, 5]));
      }

      series.add(LineSeries<ChartData, DateTime>(
        animationDuration: 0, dataSource: data, name: channelName,
        color: _graphLineColours[channelIndex] ?? _getDefaultColor(channelIndex),
        xValueMapper: (ChartData d, _) => d.time,
        yValueMapper: (ChartData d, _) => d.value,
        markerSettings: MarkerSettings(isVisible: _showDataPoints, height: 3, width: 3, color: _graphLineColours[channelIndex]),
      ));

      if (_showPeakValue) {
        final peakData = _globalPeakValues[channelIndex];
        if (peakData != null) {
          series.add(ScatterSeries<ChartData, DateTime>(
            dataSource: [peakData], name: '$channelName (Peak)',
            color: _graphLineColours[channelIndex] ?? _getDefaultColor(channelIndex),
            markerSettings: const MarkerSettings(isVisible: true, height: 10, width: 10, shape: DataMarkerType.circle, borderWidth: 2, borderColor: Colors.black),
            xValueMapper: (ChartData d, _) => d.time,
            yValueMapper: (ChartData d, _) => d.value,
            dataLabelSettings: DataLabelSettings(
              isVisible: true,
              labelAlignment: ChartDataLabelAlignment.top,
              builder: (dynamic data, dynamic point, dynamic series, int pointIndex, int seriesIndex) {
                final decimalPlaces = setupChannel?.decimalPlaces ?? 2;
                return Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: _graphLineColours[channelIndex], borderRadius: BorderRadius.circular(4)),
                  child: Text(peakData.value!.toStringAsFixed(decimalPlaces), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                );
              },
            ),
          ));
        }
      }
    }

    return RepaintBoundary(
      key: _graphKey,
      child: Container(
        color: ThemeColors.getColor('cardBackground', isDarkMode),
        child: SfCartesianChart(
          primaryXAxis: DateTimeAxis(title: AxisTitle(text: 'Time (HH:mm:ss)', textStyle: TextStyle(color: textColor, fontSize: 12)), majorGridLines: MajorGridLines(width: 0.5, color: axisLineColor.withOpacity(0.5)), axisLine: AxisLine(width: 1, color: axisLineColor), labelStyle: TextStyle(color: textColor, fontSize: 10), minimum: _chartVisibleMin, maximum: _chartVisibleMax, dateFormat: DateFormat('HH:mm:ss'), intervalType: DateTimeIntervalType.auto),
          primaryYAxis: NumericAxis(title: AxisTitle(text: yAxisTitleText, textStyle: TextStyle(color: textColor, fontSize: 12)), majorGridLines: MajorGridLines(width: 0.5, color: axisLineColor.withOpacity(0.5)), axisLine: AxisLine(width: 1, color: axisLineColor), labelStyle: TextStyle(color: textColor, fontSize: 10), plotBands: plotBands),
          series: series,
          legend: Legend(isVisible: false),
          trackballBehavior: _trackballBehavior,
          zoomPanBehavior: _zoomPanBehavior,
        ),
      ),
    );
  }

  Widget _buildGraphToolbar(bool isDarkMode) {
    final iconColor = ThemeColors.getColor('dialogSubText', isDarkMode);
    final activeColor = Theme.of(context).primaryColor;
    final activeBgColor = activeColor.withOpacity(0.2);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      height: 48,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildSegmentNavigator(isDarkMode),
          Row(
            children: [
              TextButton(onPressed: () => _showChannelFilterDialog(isDarkMode), child: const Text("Select Channel")),
              const SizedBox(width: 8),
              Container(decoration: BoxDecoration(color: _showPeakValue ? activeBgColor : Colors.transparent, borderRadius: BorderRadius.circular(8)), child: IconButton(icon: Icon(Icons.show_chart, color: _showPeakValue ? activeColor : iconColor), onPressed: () => setState(() => _showPeakValue = !_showPeakValue), tooltip: 'Show Peak Value')),
              const SizedBox(width: 8),
              Container(decoration: BoxDecoration(color: _showDataPoints ? activeBgColor : Colors.transparent, borderRadius: BorderRadius.circular(8)), child: IconButton(icon: Icon(Icons.grain, color: _showDataPoints ? activeColor : iconColor), onPressed: () => setState(() => _showDataPoints = !_showDataPoints), tooltip: 'Toggle Data Points')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentNavigator(bool isDarkMode) {
    if (_firstDataTimestamp == null) return const SizedBox.shrink();

    final bool canGoOlder = _currentSegment > 1;
    final bool canGoNewer = _currentSegment < _maxSegments;
    final navButtonColor = isDarkMode ? Colors.white : Theme.of(context).primaryColor;
    final disabledColor = Colors.grey.shade600;

    return Row(
      children: [
        SizedBox(height: 30, child: TextButton(onPressed: canGoOlder ? () => _setSegment(_currentSegment - 1) : null, child: Text("< Older", style: TextStyle(color: canGoOlder ? navButtonColor : disabledColor)))),
        SizedBox(height: 30, child: TextButton(onPressed: null, child: Text("Segment $_currentSegment/$_maxSegments"))),
        SizedBox(height: 30, child: TextButton(onPressed: canGoNewer ? () => _setSegment(_currentSegment + 1) : null, child: Text("Newer >", style: TextStyle(color: canGoNewer ? navButtonColor : disabledColor)))),
      ],
    );
  }

  void _showChannelFilterDialog(bool isDarkMode) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final tempVisibleChannels = {..._visibleGraphChannels};
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
              title: Text('Select Channels', style: TextStyle(color: ThemeColors.getColor('dialogText', isDarkMode))),
              content: SizedBox(
                width: 250,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _channelNames.length,
                  itemBuilder: (context, index) {
                    final entry = _channelNames.entries.elementAt(index);
                    final channelId = entry.key;
                    final channelName = entry.value;
                    return CheckboxListTile(title: Text(channelName, style: TextStyle(color: ThemeColors.getColor('dialogText', isDarkMode))), value: tempVisibleChannels.contains(channelId), onChanged: (bool? value) => setDialogState(() => value == true ? tempVisibleChannels.add(channelId) : tempVisibleChannels.remove(channelId)));
                  },
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
                TextButton(child: Text('Apply', style: TextStyle(color: ThemeColors.getColor('submitButton', isDarkMode))), onPressed: () { setState(() => _visibleGraphChannels = tempVisibleChannels); Navigator.of(dialogContext).pop(); }),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildChannelLegend(bool isDarkMode) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _channelNames.entries.map((entry) {
            final channelIndex = entry.key;
            final channelName = entry.value;
            final isVisible = _visibleGraphChannels.contains(channelIndex);
            return InkWell(
              onTap: () => _showColorPicker(channelIndex, isDarkMode),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  children: [
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: isVisible ? (_graphLineColours[channelIndex] ?? _getDefaultColor(channelIndex)) : Colors.grey, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 8),
                    Text(channelName, style: TextStyle(fontSize: 12, color: isVisible ? ThemeColors.getColor('dialogText', isDarkMode) : Colors.grey, decoration: isVisible ? TextDecoration.none : TextDecoration.lineThrough)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildDataTable(bool isDarkMode) {
    if (_isLoading && _tableData.isEmpty) return Center(child: CircularProgressIndicator(color: ThemeColors.getColor('submitButton', isDarkMode)));
    if (_fetchError != null && _tableData.isEmpty) return Center(child: Text(_fetchError!, style: TextStyle(color: Colors.red.shade400)));
    if (_tableData.isEmpty) return const Center(child: Text('No tabular data available.'));

    final headerStyle = GoogleFonts.roboto(fontWeight: FontWeight.w600, color: ThemeColors.getColor('dialogText', isDarkMode), fontSize: 13);
    final cellStyle = GoogleFonts.firaCode(color: ThemeColors.getColor('dialogSubText', isDarkMode), fontSize: 12);

    const double snoColWidth = 80.0;
    const double timeColWidth = 100.0;
    const double dateColWidth = 120.0;
    const double channelColWidth = 150.0;

    final double totalWidth = snoColWidth + timeColWidth + dateColWidth + (_channelNames.length * channelColWidth);

    final List<DataColumn> columns = [
      DataColumn(label: SizedBox(width: snoColWidth, child: Padding(padding: const EdgeInsets.only(left: 16.0), child: Text('S.No', style: headerStyle)))),
      DataColumn(label: SizedBox(width: timeColWidth, child: Text('Time', style: headerStyle))),
      DataColumn(label: SizedBox(width: dateColWidth, child: Text('Date', style: headerStyle))),
      ..._channelNames.entries.map((entry) {
        final channelName = entry.value;
        final unit = _getUnitForChannel(channelName);
        return DataColumn(label: SizedBox(width: channelColWidth, child: Text('$channelName ($unit)', style: headerStyle, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)));
      }),
    ];

    return Column(
      children: [
        Scrollbar(
          controller: _tableHeaderHorizontalScrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _tableHeaderHorizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 48,
              dataRowMinHeight: 0,
              dataRowMaxHeight: 0,
              columnSpacing: 0,
              horizontalMargin: 0,
              headingRowColor: MaterialStateColor.resolveWith((states) => ThemeColors.getColor('tableHeaderBackground', isDarkMode)),
              columns: columns,
              rows: const [],
            ),
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: _tableVerticalScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _tableVerticalScrollController,
              scrollDirection: Axis.vertical,
              child: Scrollbar(
                controller: _tableBodyHorizontalScrollController,
                thumbVisibility: true,
                notificationPredicate: (notification) => notification.depth == 1,
                child: SingleChildScrollView(
                  controller: _tableBodyHorizontalScrollController,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: totalWidth,
                    child: DataTable(
                      headingRowHeight: 0,
                      dataRowMinHeight: 40,
                      dataRowMaxHeight: 40,
                      columnSpacing: 0,
                      horizontalMargin: 0,
                      columns: columns,
                      rows: _tableData.asMap().entries.map((entry) {
                        final int index = entry.key;
                        final Map<String, dynamic> data = entry.value;
                        return DataRow(
                          color: MaterialStateProperty.resolveWith<Color?>((states) => index.isOdd ? ThemeColors.getColor('serialPortTableRowOdd', isDarkMode) : null),
                          cells: [
                            DataCell(SizedBox(width: snoColWidth, child: Padding(padding: const EdgeInsets.only(left: 16.0), child: Text((data['SNo'] as num?)?.toInt().toString() ?? '', style: cellStyle)))),
                            DataCell(SizedBox(width: timeColWidth, child: Text(data['AbsTime'] as String? ?? '', style: cellStyle))),
                            DataCell(SizedBox(width: dateColWidth, child: Text((data['AbsDate'] as String?)?.split(' ').first ?? '', style: cellStyle))),
                            ..._channelNames.keys.map((channelIndex) {
                              double? value = (data['AbsPer$channelIndex'] as num?)?.toDouble();
                              final setupChannel = _channelSetupData[_channelNames[channelIndex]];
                              String displayValue = value == null ? '-' : value.toStringAsFixed(setupChannel?.decimalPlaces ?? 2);
                              return DataCell(SizedBox(width: channelColWidth, child: Center(child: Text(displayValue, style: cellStyle))));
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
        ),
      ],
    );
  }

  Widget _buildErrorState(bool isDarkMode) {
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

  // --- HELPERS & UTILS ---
  String _getUnitForChannel(String channelName) {
    return _channelSetupData[channelName]?.unit ?? '%';
  }

  void _showColorPicker(int channelIndex, bool isDarkMode) {
    Color currentColor = _graphLineColours[channelIndex] ?? _getDefaultColor(channelIndex);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
        title: Text('Select Color for ${_channelNames[channelIndex]}', style: TextStyle(color: ThemeColors.getColor('dialogText', isDarkMode))),
        content: SingleChildScrollView(child: ColorPicker(pickerColor: currentColor, onColorChanged: (c) => currentColor = c)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(
            child: Text('OK', style: TextStyle(color: ThemeColors.getColor('submitButton', isDarkMode))),
            onPressed: () {
              setState(() => _graphLineColours[channelIndex] = currentColor);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  Color _getDefaultColor(int index) {
    final bool isDarkMode = Global.isDarkMode.value;
    const List<Color> lightModeColors = [ Color(0xFF0288D1), Color(0xFFD81B60), Color(0xFF388E3C), Color(0xFFF57C00), Color(0xFF5E35B1), Color(0xFF00897B), Color(0xFFE53935), Color(0xFF3949AB), Color(0xFF7CB342), Color(0xFFC0CA33), ];
    const List<Color> darkModeColors = [ Color(0xFF90CAF9), Color(0xFFF48FB1), Color(0xFFA5D6A7), Color(0xFFFFCC80), Color(0xFFB39DDB), Color(0xFF80CBC4), Color(0xFFEF9A9A), Color(0xFF9FA8DA), Color(0xFFC5E1A5), Color(0xFFE6EE9C), ];
    return isDarkMode ? darkModeColors[(index - 1) % darkModeColors.length] : lightModeColors[(index - 1) % lightModeColors.length];
  }

  Future<Uint8List?> _captureGraph(bool isDarkMode) async {
    try {
      RenderRepaintBoundary? boundary = _graphKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      LogPage.addLog('[$_currentTime] [CAPTURE_GRAPH] Error: $e');
      MessageUtils.showMessage(context, "Error capturing graph: $e", isError: true);
      return null;
    }
  }

  Widget _buildHeaderTextField(String label, TextEditingController controller, bool isDarkMode, {double width = 150}) {
    return SizedBox(
      width: width,
      child: TextField(
        readOnly: true,
        controller: controller,
        style: TextStyle(color: ThemeColors.getColor('dialogText', isDarkMode), fontSize: 13, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: ThemeColors.getColor('dialogSubText', isDarkMode), fontSize: 12),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.6))),
        ),
      ),
    );
  }

  Widget _buildInfoDisplay(String label, List<TextEditingController> controllers, List<String> units, bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: ThemeColors.getColor('dialogSubText', isDarkMode), fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: ThemeColors.getColor('cardBorder', isDarkMode).withOpacity(0.6)),
          ),
          child: Row(
            children: List.generate(controllers.length, (index) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(controllers[index].text, style: GoogleFonts.firaCode(fontSize: 13, color: ThemeColors.getColor('dialogText', isDarkMode), fontWeight: FontWeight.w500)),
                  Text(units[index], style: GoogleFonts.firaCode(fontSize: 12, color: ThemeColors.getColor('dialogSubText', isDarkMode))),
                  if (index < controllers.length - 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.0),
                      child: Text(':', style: GoogleFonts.firaCode(fontSize: 13, color: ThemeColors.getColor('dialogSubText', isDarkMode))),
                    ),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderActionButton(bool isDarkMode, String label, IconData icon, VoidCallback onPressed) {
    return TextButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(label),
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: ThemeColors.getColor('submitButton', isDarkMode),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: ThemeColors.getColor('submitButton', isDarkMode).withOpacity(0.4)),
      ),
    );
  }

  void _openFloatingGraphWindow(bool isDarkMode) {
    _windowCounter++;
    final String windowId = 'Window $_windowCounter';

    Map<String, List<Map<String, dynamic>>> dataByChannel = {};
    for (var entry in _channelNames.entries) {
      final channelIndex = entry.key;
      dataByChannel[channelIndex.toString()] = _graphData[channelIndex]?.map((d) => {
        'time': DateFormat('HH:mm:ss').format(d.time),
        'value': d.value,
        'Timestamp': d.time.millisecondsSinceEpoch.toDouble(),
      }).toList() ?? [];
    }

    Map<String, Color> channelColors = {};
    _graphLineColours.forEach((key, value) {
      channelColors[key.toString()] = value;
    });

    Map<String, Channel> channelConfigs = {};
    for (var entry in _channelNames.entries) {
      final channelIndex = entry.key;
      final channelName = entry.value;
      final setup = _channelSetupData[channelName] ?? Channel(recNo: 0, channelName: '', startingCharacter: '', dataLength: 7, decimalPlaces: 2, unit: '%', chartMaximumValue: 100, chartMinimumValue: 0, graphLineColour: 0xFF000000, targetAlarmColour: 0xFFFF0000, targetAlarmMax: null, targetAlarmMin: null);
      channelConfigs[channelIndex.toString()] = setup.copyWith(
          channelName: channelName,
          graphLineColour: _graphLineColours[channelIndex]?.value
      );
    }
    OverlayEntry? overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: 100.0 + (_windowCounter * 20),
        top: 100.0 + (_windowCounter * 20),
        child: SaveMultiWindowGraph(
          key: ValueKey(windowId), windowId: windowId, initialData: dataByChannel, channelColors: channelColors,
          channelConfigs: channelConfigs, entry: overlayEntry!,
          onClose: (closedEntry) { _windowEntries.remove(closedEntry); },
        ),
      ),
    );
    Overlay.of(context).insert(overlayEntry);
    _windowEntries.add(overlayEntry);
  }
}