import 'dart:async';
import 'dart:typed_data';
import 'dart:ui'; // For BackdropFilter
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../../constants/database_manager.dart';
import '../../constants/global.dart';
import '../../constants/message_utils.dart';
import '../../constants/sessionmanager.dart';
import '../../constants/theme.dart';
import '../NavPages/channel.dart';
import '../Open_FIle/file_browser_page.dart';
import '../Open_FIle/open_file.dart';
import '../Secondary_window/save_secondary_window.dart';
import '../homepage.dart';
import '../logScreen/log.dart'; // Assuming homepage path

// Helper class for Syncfusion Chart data points
class ChartData {
    final DateTime time;
    final double? value;
    ChartData(this.time, this.value);
}

// A mutable version of the Channel class to hold state like color
class ActiveChannel {
    final Channel originalChannel;
    Color graphLineColour;

    ActiveChannel({
        required this.originalChannel,
        required this.graphLineColour,
    });

    String get startingCharacter => originalChannel.startingCharacter;
    String get channelName => originalChannel.channelName;
    int get decimalPlaces => originalChannel.decimalPlaces;
    String get unit => originalChannel.unit;
    double? get targetAlarmMax => originalChannel.targetAlarmMax;
    double? get targetAlarmMin => originalChannel.targetAlarmMin;
    int get targetAlarmColour => originalChannel.targetAlarmColour;
    double get recNo => originalChannel.recNo;

    factory ActiveChannel.fromChannel(Channel channel) {
        Color parsedColor = Colors.red; // Default color
        try {
            final dbValue = channel.graphLineColour;
            if (dbValue is int) {
                parsedColor = Color(dbValue);
            } else if (dbValue is String && dbValue.toString().isNotEmpty) {
                final colorString = (dbValue).replaceAll('#', '');
                final colorValue = int.parse('FF$colorString', radix: 16);
                parsedColor = Color(colorValue);
            }
        } catch (e) {
            LogPage.addLog("[COLOR PARSE ERROR] Could not parse color '${channel.graphLineColour}' for channel '${channel.channelName}'. Error: $e");
        }
        return ActiveChannel(
            originalChannel: channel,
            graphLineColour: parsedColor,
        );
    }
}

class AutoStartScreen extends StatefulWidget {
    final List<Channel> selectedChannels;
    final double endTimeHr;
    final double endTimeMin;
    final double scanTimeSec;
    final Duration testDuration;
    final VoidCallback onBack;
    final void Function(String fileName) onOpenFile;

    const AutoStartScreen({
        super.key,
        required this.selectedChannels,
        required this.endTimeHr,
        required this.endTimeMin,
        required this.scanTimeSec,
        required this.testDuration,
        required this.onBack,
        required this.onOpenFile,
    });

    @override
    State<AutoStartScreen> createState() => _AutoStartScreenState();
}

class _AutoStartScreenState extends State<AutoStartScreen> {
    // --- STATE VARIABLES ---

    // Serial Port & Connection
    SerialPort? _port;
    SerialPortReader? _reader;
    StreamSubscription<Uint8List>? _serialSubscription;
    bool _isPortOpen = false;
    String _buffer = '';
    String _statusMessage = "Disconnected";
    Timer? _reconnectTimer;
    bool _isAttemptingReconnect = false;
    bool _isDataDirty = false;

    String? _comPortName;
    int? _baudRate;
    int? _dataBits;
    String? _parity;
    int? _stopBits;

    // Save/Append Logic State
    bool _isSaving = false;
    String? _sessionDbName;
    int? _recNo;
    int _savedTableRowCount = 0;

    // Auto-Save State
    Timer? _autoSaveTimer;
    bool _isAutoSaveEnabled = false;
    int _autoSaveIntervalSeconds = 30;

    // Auto-Stop Timer
    Timer? _endTimeTimer;

    // Data Flow Watchdog
    bool _isDataFlowing = false;
    Timer? _dataStoppageTimer;

    // Display Mode state
    String _currentDisplayMode = 'Combined';

    // Data & Business Logic
    late final List<ActiveChannel> _activeChannels;
    late final Map<String, ActiveChannel> _channelMap;
    final Map<String, List<ChartData>> _graphData = {};
    DateTime? _firstDataTimestamp;
    final Map<String, double?> _lastChannelValues = {};
    final List<Map<String, dynamic>> _tableData = [];
    Timer? _scanRateTimer;

    // Multi-Window Management
    final List<OverlayEntry> _overlayEntries = [];
    int _windowCounter = 0;

    // UI & User Inputs
    late final TextEditingController _filenameController;
    final TextEditingController _openFileController = TextEditingController();
    final _operatorController = TextEditingController(text: "Operator");

    // --- Scroll Controllers for Sticky Header Table ---
    final ScrollController _tableVerticalScrollController = ScrollController();
    final ScrollController _tableHeaderHorizontalScrollController = ScrollController();
    final ScrollController _tableBodyHorizontalScrollController = ScrollController();

    Duration _testDuration = const Duration(days: 1);
    late Duration _scanRate;
    Duration _graphTimeWindow = const Duration(minutes: 5);

    // Segment and Graph Axis logic
    int _currentSegment = 1;
    int _maxSegments = 1;
    DateTime? _chartVisibleMin;
    DateTime? _chartVisibleMax;
    bool _isLive = true;

    // Graph
    late TrackballBehavior _trackballBehavior;
    late ZoomPanBehavior _zoomPanBehavior;
    late Set<String> _visibleGraphChannels;
    bool _showDataPoints = false;
    bool _showPeakValue = false;
    final Map<String, ChartData> _globalPeakValues = {};

    @override
    void initState() {
        super.initState();
        _testDuration = widget.testDuration;
        _scanRate = Duration(seconds: widget.scanTimeSec.toInt());

        _loadSettingsAndStart();

        _activeChannels = widget.selectedChannels.map((c) => ActiveChannel.fromChannel(c)).toList();
        _channelMap = {for (var channel in _activeChannels) channel.startingCharacter: channel};
        _visibleGraphChannels = _activeChannels.map((c) => c.startingCharacter).toSet();

        _trackballBehavior = TrackballBehavior(
            enable: true,
            activationMode: ActivationMode.singleTap,
            tooltipDisplayMode: TrackballDisplayMode.groupAllPoints,
            tooltipSettings: const InteractiveTooltip(enable: true, format: 'series.name : point.y'),
            shouldAlwaysShow: false
        );
        _zoomPanBehavior = ZoomPanBehavior(enablePinching: true, enablePanning: true, zoomMode: ZoomMode.x);

        final initialFilename = "Test_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}";
        _filenameController = TextEditingController(text: initialFilename);

        for (var channel in _activeChannels) {
            _graphData[channel.startingCharacter] = [];
            _lastChannelValues[channel.startingCharacter] = null;
        }

        // Add listeners to synchronize horizontal scroll controllers
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
    }

    Future<void> _loadSettingsAndStart() async {
        await _loadSettings();
        if (mounted) {
            _startEndTimeCheck();
            // Auto-start connection after loading settings
            WidgetsBinding.instance.addPostFrameCallback((_) {
                _connectAndRead();
            });
        }
    }

    Future<void> _loadSettings() async {
        LogPage.addLog("[LOG] Fetching settings from database...");
        final comPortSettings = await DatabaseManager().getComPortSettings();
        if (mounted && comPortSettings != null) {
            setState(() {
                _comPortName = comPortSettings['selectedPort'];
                _baudRate = comPortSettings['baudRate'];
                _dataBits = comPortSettings['dataBits'];
                _parity = comPortSettings['parity'];
                _stopBits = comPortSettings['stopBits'];
                LogPage.addLog("[LOG] Loaded COM settings: Port=$_comPortName, Baud=$_baudRate, DataBits=$_dataBits, Parity=$_parity, StopBits=$_stopBits");
            });
        } else {
            LogPage.addLog("[LOG] No COM port settings found in the database.");
        }

        final authSettings = await DatabaseManager().getAuthSettings();
        if (mounted && authSettings != null) {
            setState(() {
                _isAutoSaveEnabled = (authSettings['isAutoSaveEnabled'] ?? 0) == 1;
                _autoSaveIntervalSeconds = authSettings['autoSaveIntervalSeconds'] ?? 30;
                LogPage.addLog("[LOG] Loaded Auto-Save settings: Enabled=$_isAutoSaveEnabled, Interval=$_autoSaveIntervalSeconds");
            });
        }
    }

    void _startEndTimeCheck() {
        _endTimeTimer?.cancel();
        _endTimeTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
            if (!mounted) {
                timer.cancel();
                return;
            }
            final now = DateTime.now();
            final endHour = widget.endTimeHr.toInt();
            final endMinute = widget.endTimeMin.toInt();

            DateTime endDateTime = DateTime(now.year, now.month, now.day, endHour, endMinute);
            if (now.isAfter(endDateTime)) {
                endDateTime = endDateTime.add(const Duration(days: 1));
            }

            if (now.isAtSameMomentAs(endDateTime) || now.isAfter(endDateTime)) {
                if (_isPortOpen) {
                    timer.cancel();
                    MessageUtils.showMessage(context, "End time reached. Stopping and saving data.");
                    _disconnectAndSave();
                } else {
                    timer.cancel();
                }
            }
        });
    }


    Future<void> _disconnectAndSave() async {

        if (_isDataDirty) {
            LogPage.addLog("[LOG] Test duration/end time reached. Saving data...");
            await _saveData();
        } else {
            LogPage.addLog("[LOG] Test duration/end time reached. No new data to save.");
        }

        _disconnectPort();

        if (mounted) {
            MessageUtils.showMessage(context, "Test finished. Data saved and port disconnected.");
        }
    }

    int _getParityFromString(String? parityString) {
        switch (parityString?.toLowerCase()) {
            case 'odd': return SerialPortParity.odd;
            case 'even': return SerialPortParity.even;
            case 'mark': return SerialPortParity.mark;
            case 'space': return SerialPortParity.space;
            case 'none': default: return SerialPortParity.none;
        }
    }

    void _addGraphWindow() {
        _windowCounter++;
        final String windowId = 'Window $_windowCounter';

        final Map<String, List<Map<String, dynamic>>> initialData = {};
        _graphData.forEach((channelId, chartDataList) {
            initialData[channelId] = chartDataList.map((chartData) {
                return {
                    'time': DateFormat('HH:mm:ss').format(chartData.time),
                    'value': chartData.value,
                    'Timestamp': chartData.time.millisecondsSinceEpoch.toDouble(),
                };
            }).toList();
        });

        final Map<String, Color> channelColors = {for (var activeChannel in _activeChannels) activeChannel.startingCharacter: activeChannel.graphLineColour};
        final Map<String, Channel> channelConfigs = {for (var activeChannel in _activeChannels) activeChannel.startingCharacter: activeChannel.originalChannel};

        OverlayEntry? entry;
        entry = OverlayEntry(
            builder: (context) {
                return Positioned(
                    left: 100.0 + (_windowCounter * 20),
                    top: 100.0 + (_windowCounter * 20),
                    child: SaveMultiWindowGraph(
                        key: ValueKey(windowId),
                        windowId: windowId,
                        initialData: initialData,
                        channelColors: channelColors,
                        channelConfigs: channelConfigs,
                        entry: entry!,
                        onClose: (closedEntry) {
                            _overlayEntries.remove(closedEntry);
                        },
                    ),
                );
            },
        );

        Overlay.of(context).insert(entry);
        _overlayEntries.add(entry);
    }

    void _showOpenFileDialog() {
        showDialog(
            context: context,
            builder: (BuildContext dialogContext) {
                return FileSelectionDialog(
                    controller: _openFileController,
                    onOpenPressed: () async {
                        final fileName = _openFileController.text;
                        if (fileName.isEmpty) {
                            MessageUtils.showMessage(context, 'Please select a file first.', isError: true);
                            return;
                        }
                        if (!await _showUnsavedDataDialog()) {
                            return;
                        }
                        Navigator.of(dialogContext).pop();
                        _disconnectPort();
                        widget.onOpenFile(fileName);
                    },
                );
            },
        );
    }

    void _connectAndRead() {
        if (_isPortOpen) return;

        final portName = _comPortName;
        if (portName == null || portName.isEmpty) {
            setState(() => _statusMessage = "Error: COM Port not configured.");
            MessageUtils.showMessage(context, "Please configure the COM Port in settings.", isError: true);
            LogPage.addLog("[LOG] Connect aborted: COM Port name is null or empty.");
            return;
        }

        if (!_isAttemptingReconnect) {
            setState(() => _statusMessage = "Connecting to $portName...");
        }

        try {
            _port = SerialPort(portName);
            if (!_port!.openReadWrite()) {
                throw SerialPortError("Failed to open port $portName");
            }

            _reconnectTimer?.cancel();
            _isAttemptingReconnect = false;

            final config = SerialPortConfig()
                ..baudRate = _baudRate ?? 9600
                ..bits = _dataBits ?? 8
                ..parity = _getParityFromString(_parity)
                ..stopBits = _stopBits ?? 1;

            LogPage.addLog("[LOG] Applying port configuration: Baud=${config.baudRate}, Bits=${config.bits}, Parity=${config.parity}, StopBits=${config.stopBits}");

            _port!.config = config;
            _reader = SerialPortReader(_port!);

            _serialSubscription = _reader!.stream.listen((data) {
                final receivedString = String.fromCharCodes(data);
                LogPage.addLog("[LOG DATA RECV] Raw: '$receivedString'");
                _buffer += receivedString;
                _processBuffer();
            }, onError: _handleConnectionError);

            if (mounted) {
                setState(() {
                    _isPortOpen = true;
                    _statusMessage = "Connected to $portName. Waiting for data...";
                    _scanRateTimer?.cancel();
                    _scanRateTimer = Timer.periodic(_scanRate, _onScanRateTick);
                    _startAutoSaveTimer();
                });
                LogPage.addLog("[LOG] Successfully connected to $portName.");
            }
        } catch (e) {
            LogPage.addLog("[LOG] Error during connection: $e");
            if (mounted && !_isAttemptingReconnect) {
                setState(() => _statusMessage = "Error: Could not connect to $portName. Check connection/settings.");
            }
        }
    }

    void _disconnectPort() {
        _reconnectTimer?.cancel();
        _scanRateTimer?.cancel();
        _dataStoppageTimer?.cancel();
        _serialSubscription?.cancel();
        _reader?.close();
        if (_port?.isOpen ?? false) _port?.close();
        _port?.dispose();
        _stopAutoSaveTimer();

        if (mounted) {
            setState(() {
                _port = null;
                _reader = null;
                _isPortOpen = false;
                _isDataFlowing = false;
                _isAttemptingReconnect = false;
                _statusMessage = "Disconnected";
            });
            LogPage.addLog("[LOG] Port disconnected.");
        }
    }

    void _startReconnectProcedure() {
        if (_isAttemptingReconnect || !mounted) return;
        _dataStoppageTimer?.cancel();
        _stopAutoSaveTimer();
        setState(() {
            _isPortOpen = false;
            _isDataFlowing = false;
            _statusMessage = "Connection lost to $_comPortName. Reconnecting...";
            _isAttemptingReconnect = true;
        });
        _reconnectTimer?.cancel();
        _reconnectTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
            if (!_isPortOpen) {
                _connectAndRead();
            } else {
                timer.cancel();
                if (mounted) setState(() => _isAttemptingReconnect = false);
            }
        });
    }

    void _handleConnectionError(dynamic error) {
        if (mounted) {
            _scanRateTimer?.cancel();
            _serialSubscription?.cancel();
            _reader?.close();
            if (_port?.isOpen ?? false) _port?.close();
            _startReconnectProcedure();
        }
    }

    void _processBuffer() {
        final RegExp identifierRegex = RegExp(r'[A-Z]');
        List<RegExpMatch> matches = identifierRegex.allMatches(_buffer).toList();

        if (matches.length < 2) return;

        for (int i = 0; i < matches.length - 1; i++) {
            final currentMatch = matches[i];
            final nextMatch = matches[i + 1];
            final String identifier = currentMatch.group(0)!;
            final String valueString = _buffer.substring(currentMatch.end, nextMatch.start);
            if (_channelMap.containsKey(identifier)) {
                _bufferLatestValue(identifier, valueString);
            }
        }
        _buffer = _buffer.substring(matches.last.start);
    }

    void _bufferLatestValue(String identifier, String valueString) {
        final channel = _channelMap[identifier];
        if (channel != null) {
            final double? finalValue = double.tryParse(valueString);
            if (finalValue != null) {
                _lastChannelValues[identifier] = finalValue;
                _dataStoppageTimer?.cancel();
                if (mounted) {
                    if (!_isDataFlowing) {
                        setState(() {
                            _isDataFlowing = true;
                            _statusMessage = "Receiving Data...";
                        });
                    }
                    _dataStoppageTimer = Timer(_scanRate * 3, () {
                        if (mounted) {
                            setState(() {
                                _isDataFlowing = false;
                                _statusMessage = "Data flow stopped.";
                            });
                        }
                    });
                }
            }
        }
    }

    void _onScanRateTick(Timer timer) {
        if (!mounted || !_isPortOpen || !_isDataFlowing) return;

        final now = DateTime.now();

        if (_firstDataTimestamp == null) {
            _firstDataTimestamp = now;
            _setSegment(1, goLive: true);
        }

        if (now.difference(_firstDataTimestamp!) >= _testDuration) {
            timer.cancel();
            _disconnectAndSave();
            return;
        }

        if (!_isDataDirty) {
            setState(() => _isDataDirty = true);
        }

        final newRow = <String, dynamic>{'Time': now};
        final Map<String, List<Map<String, dynamic>>> newDataForStream = {};

        for (var channel in _activeChannels) {
            final lastValue = _lastChannelValues[channel.startingCharacter];
            newRow[channel.channelName] = lastValue;
            _graphData[channel.startingCharacter]!.add(ChartData(now, lastValue));
            newDataForStream[channel.startingCharacter] = [
                {
                    'time': DateFormat('HH:mm:ss').format(now),
                    'value': lastValue,
                    'Timestamp': now.millisecondsSinceEpoch.toDouble()
                }
            ];
        }

        if (Global.hasGraphDataListener) {
            final Map<String, Color> channelColors = {for (var c in _activeChannels) c.startingCharacter: c.graphLineColour};
            final Map<String, Channel> channelConfigs = {for (var c in _activeChannels) c.startingCharacter: c.originalChannel};
            Global.graphDataSink.add({
                'dataByChannel': newDataForStream,
                'channelColors': channelColors,
                'channelConfigs': channelConfigs
            });
        }

        _tableData.add(newRow);

        if (_showPeakValue) _calculateGlobalPeakValues();

        final totalDuration = now.difference(_firstDataTimestamp!);
        final newMaxSegments = (totalDuration.inMilliseconds / _graphTimeWindow.inMilliseconds).floor() + 1;

        if (newMaxSegments > _maxSegments) {
            setState(() {
                _maxSegments = newMaxSegments;
                if (_isLive) {
                    _currentSegment = newMaxSegments;
                    _setSegment(_currentSegment, goLive: true);
                }
            });
        } else {
            if (mounted) setState(() {});
        }

        if (_tableVerticalScrollController.hasClients) {
            _tableVerticalScrollController.animateTo(
                _tableVerticalScrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
    }

    void _togglePeakValue() {
        setState(() {
            _showPeakValue = !_showPeakValue;
            if (_showPeakValue) {
                _calculateGlobalPeakValues();
            }
        });
    }

    void _calculateGlobalPeakValues() {
        _globalPeakValues.clear();
        for (var channel in _activeChannels) {
            final dataList = _graphData[channel.startingCharacter]?.where((d) => d.value != null).toList();
            if (dataList != null && dataList.isNotEmpty) {
                _globalPeakValues[channel.channelName] = dataList.reduce((c, n) => c.value! > n.value! ? c : n);
            }
        }
    }

    Future<void> _onClearPressed() async {
        if (await _showUnsavedDataDialog() && mounted) {
            _stopAutoSaveTimer();
            _dataStoppageTimer?.cancel();
            setState(() {
                _tableData.clear();
                _graphData.forEach((key, value) => value.clear());
                _lastChannelValues.updateAll((key, value) => null);
                _buffer = '';
                _isDataDirty = false;
                _isDataFlowing = false;
                if (_isPortOpen) _statusMessage = "Connected to $_comPortName. Waiting for data...";
                _firstDataTimestamp = null;
                _filenameController.text = "Test_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}";
                _currentSegment = 1;
                _maxSegments = 1;
                _isLive = true;
                _chartVisibleMin = null;
                _chartVisibleMax = null;
                _globalPeakValues.clear();
                _showPeakValue = false;
                _sessionDbName = null;
                _recNo = null;
                _savedTableRowCount = 0;
            });
        }
    }

    Future<void> _onBackPressed() async {
        if (await _showUnsavedDataDialog()) {
            _stopAutoSaveTimer();
            _endTimeTimer?.cancel(); // Cancel end time check on back
            _disconnectPort();
            widget.onBack();
        }
    }

    @override
    void dispose() {
        for (var entry in _overlayEntries) {
            entry.remove();
        }
        _overlayEntries.clear();
        _disconnectPort();
        _endTimeTimer?.cancel();
        _filenameController.dispose();
        _openFileController.dispose();
        _operatorController.dispose();
        _tableVerticalScrollController.dispose();
        _tableHeaderHorizontalScrollController.dispose();
        _tableBodyHorizontalScrollController.dispose();
        super.dispose();
    }

    @override
    Widget build(BuildContext context) {
        return ValueListenableBuilder<bool>(
            valueListenable: Global.isDarkMode,
            builder: (context, isDarkMode, child) {
                return Scaffold(
                    backgroundColor: ThemeColors.getColor('serialPortBackground', isDarkMode),
                    body: Column(
                        children: [
                            _buildHeaderPanel(isDarkMode),
                            Expanded(
                                child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: _currentDisplayMode == 'Combined'
                                        ? Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                            Expanded(flex: 5, child: _buildLeftPanel(context, isDarkMode)),
                                            const SizedBox(width: 12),
                                            Expanded(flex: 7, child: _buildRightPanel(context, isDarkMode)),
                                        ],
                                    )
                                        : Column(
                                        children: [
                                            Expanded(
                                                child: _currentDisplayMode == 'Graph'
                                                    ? _buildRightPanel(context, isDarkMode)
                                                    : _buildDataTable(context, isDarkMode),
                                            ),
                                            const SizedBox(height: 12),
                                            _buildCompactControlPanel(isDarkMode),
                                        ],
                                    ),
                                ),
                            ),
                        ],
                    ),
                );
            },
        );
    }

    Widget _buildAutoSaveStatus(bool isDarkMode) {
        if (!_isAutoSaveEnabled || _autoSaveIntervalSeconds <= 0) {
            return const SizedBox.shrink();
        }
        final String displayInterval = _formatDurationForDisplay(_autoSaveIntervalSeconds);
        final String tooltipMessage = _formatDurationForTooltip(_autoSaveIntervalSeconds);
        return Tooltip(
            message: 'Auto-saving every $tooltipMessage',
            child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green.shade300, width: 1),
                ),
                child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        Icon(LucideIcons.save, color: Colors.green.shade400, size: 14),
                        const SizedBox(width: 6),
                        Text('Auto-Save:', style: GoogleFonts.poppins(color: Colors.green.shade400, fontSize: 12, fontWeight: FontWeight.w500)),
                        const SizedBox(width: 8),
                        Text(displayInterval, style: GoogleFonts.poppins(color: Colors.green.shade300, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                ),
            ),
        );
    }

    Widget _buildHeaderPanel(bool isDarkMode) {
        return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
                color: ThemeColors.getColor('serialPortCardBackground', isDarkMode),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), spreadRadius: 2, blurRadius: 8, offset: const Offset(0, 3))],
                border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2), width: 1)),
            ),
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                    _buildHeaderTextField('Filename', _filenameController, isDarkMode, width: 250),
                    const SizedBox(width: 16),
                    _buildHeaderTextField('Operator', _operatorController, isDarkMode, width: 150),
                    const Spacer(),
                    _buildAutoSaveStatus(isDarkMode),
                    const SizedBox(width: 24),
                    _buildEditableDuration('Graph Window', _graphTimeWindow, isDarkMode, (d) {
                        setState(() => _graphTimeWindow = d);
                        _setSegment(_currentSegment, goLive: _isLive);
                    }),
                    const SizedBox(width: 16),
                    _buildEditableDuration('Test Duration', _testDuration, isDarkMode, (d) => setState(() => _testDuration = d), showDays: true),
                    const SizedBox(width: 16),
                    _buildEditableDuration('Scan Rate', _scanRate, isDarkMode, (d) => setState(() => _scanRate = d)),
                ],
            ),
        );
    }

    Widget _buildLeftPanel(BuildContext context, bool isDarkMode) {
        return Column(
            children: [
                Expanded(child: _buildDataTable(context, isDarkMode)),
                const SizedBox(height: 12),
                _buildControlPanel(isDarkMode),
            ],
        );
    }

    Widget _buildDataTable(BuildContext context, bool isDarkMode) {
        final headerStyle = GoogleFonts.poppins(color: ThemeColors.getColor('dialogText', isDarkMode), fontWeight: FontWeight.w600, fontSize: 14);
        final cellStyle = GoogleFonts.firaCode(color: ThemeColors.getColor('dialogSubText', isDarkMode), fontSize: 13);
        final timeFormat = DateFormat('HH:mm:ss');

        const double timeColWidth = 140.0;
        const double channelColWidth = 150.0;
        final double totalWidth = timeColWidth + (_activeChannels.length * channelColWidth);

        final List<DataColumn> columns = [
            DataColumn(
                label: SizedBox(
                    width: timeColWidth,
                    child: Padding(padding: const EdgeInsets.only(left: 16.0), child: Text('Time(HH:MM:SS)', style: headerStyle)),
                ),
            ),
            ..._activeChannels.map((c) => DataColumn(
                label: SizedBox(
                    width: channelColWidth,
                    child: Text('${c.channelName} (${c.unit})', style: headerStyle, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
                ),
            )),
        ];

        return Card(
            color: ThemeColors.getColor('serialPortCardBackground', isDarkMode),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            child: Column(
                children: [
                    Scrollbar(
                        controller: _tableHeaderHorizontalScrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                            controller: _tableHeaderHorizontalScrollController,
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                                headingRowHeight: 52,
                                dataRowMinHeight: 0,
                                dataRowMaxHeight: 0,
                                columnSpacing: 0,
                                horizontalMargin: 0,
                                headingRowColor: MaterialStateColor.resolveWith((states) => ThemeColors.getColor('serialPortTableHeaderBackground', isDarkMode)),
                                columns: columns,
                                rows: const [],
                            ),
                        ),
                    ),
                    const Divider(height: 1, thickness: 1),
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
                                                rows: List<DataRow>.generate(_tableData.length, (index) {
                                                    final rowData = _tableData[index];
                                                    return DataRow(
                                                        color: MaterialStateProperty.resolveWith<Color?>((states) {
                                                            if (index == _tableData.length - 1) {
                                                                return (isDarkMode ? Colors.teal.withOpacity(0.3) : Colors.teal.withOpacity(0.2));
                                                            }
                                                            return index.isOdd ? ThemeColors.getColor('serialPortTableRowOdd', isDarkMode) : null;
                                                        }),
                                                        cells: [
                                                            DataCell(
                                                                SizedBox(
                                                                    width: timeColWidth,
                                                                    child: Padding(
                                                                        padding: const EdgeInsets.only(left: 16.0),
                                                                        child: Text(timeFormat.format(rowData['Time']), style: cellStyle),
                                                                    ),
                                                                ),
                                                            ),
                                                            ..._activeChannels.map((c) {
                                                                final value = rowData[c.channelName];
                                                                final text = value != null ? value.toStringAsFixed(c.decimalPlaces) : '-';
                                                                bool isPeak = _showPeakValue && _globalPeakValues[c.channelName]?.time == rowData['Time'];
                                                                bool isAlarm = value != null && ((c.targetAlarmMax != null && value > c.targetAlarmMax!) || (c.targetAlarmMin != null && value < c.targetAlarmMin!));
                                                                return DataCell(
                                                                    SizedBox(
                                                                        width: channelColWidth,
                                                                        child: Container(
                                                                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                                                                            decoration: BoxDecoration(color: isPeak ? Theme.of(context).primaryColor.withOpacity(0.4) : Colors.transparent, borderRadius: BorderRadius.circular(4)),
                                                                            child: Text(
                                                                                text,
                                                                                style: cellStyle.copyWith(color: isAlarm ? Color(c.targetAlarmColour) : null, fontWeight: isAlarm ? FontWeight.bold : null),
                                                                                textAlign: TextAlign.center,
                                                                            ),
                                                                        ),
                                                                    ),
                                                                );
                                                            }),
                                                        ],
                                                    );
                                                }),
                                            ),
                                        ),
                                    ),
                                ),
                            ),
                        ),
                    ),
                ],
            ),
        );
    }

    Widget _buildRightPanel(BuildContext context, bool isDarkMode) {
        return Card(
            color: ThemeColors.getColor('serialPortCardBackground', isDarkMode),
            elevation: 2,
            shadowColor: Colors.black.withOpacity(isDarkMode ? 0.3 : 0.1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            clipBehavior: Clip.antiAlias,
            child: Column(
                children: [
                    _buildHorizontalGraphLegend(isDarkMode),
                    const Divider(height: 1),
                    Expanded(
                        child: Padding(
                            padding: const EdgeInsets.only(top: 8, right: 8),
                            child: _graphData.values.any((list) => list.isNotEmpty)
                                ? _buildRealTimeGraph(isDarkMode)
                                : Center(child: Text('Waiting for data...', style: TextStyle(fontSize: 18, color: ThemeColors.getColor('serialPortInputLabel', isDarkMode)))),
                        ),
                    ),
                    const Divider(height: 1),
                    _buildGraphToolbar(context, isDarkMode),
                ],
            ),
        );
    }

    Widget _buildGraphToolbar(BuildContext context, bool isDarkMode) {
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
                            TextButton(onPressed: () => _showChannelFilterDialog(context, isDarkMode), child: const Text("Select Channel")),
                            const SizedBox(width: 8),
                            TextButton(onPressed: () => _showModeDialog(context, isDarkMode), child: const Text("Mode")),
                            const SizedBox(width: 8),
                            TextButton(onPressed: _addGraphWindow, child: const Text("Add Window")),
                            const SizedBox(width: 8),
                            Container(
                                decoration: BoxDecoration(color: _showPeakValue ? activeBgColor : Colors.transparent, borderRadius: BorderRadius.circular(8)),
                                child: IconButton(icon: Icon(Icons.show_chart, color: _showPeakValue ? activeColor : iconColor), onPressed: _togglePeakValue, tooltip: 'Show Peak Value')),
                            const SizedBox(width: 8),
                            Container(
                                decoration: BoxDecoration(color: _showDataPoints ? activeBgColor : Colors.transparent, borderRadius: BorderRadius.circular(8)),
                                child: IconButton(icon: Icon(Icons.grain, color: _showDataPoints ? activeColor : iconColor), onPressed: () => setState(() => _showDataPoints = !_showDataPoints), tooltip: 'Toggle Data Points')),
                        ],
                    ),
                ],
            ),
        );
    }

    Widget _buildSegmentNavigator(bool isDarkMode) {
        if (_firstDataTimestamp == null) return const SizedBox.shrink();
        final bool canGoOlder = _currentSegment > 1;
        final bool canGoNewer = !_isLive && _currentSegment < _maxSegments;
        final navButtonColor = isDarkMode ? Colors.white : Theme.of(context).primaryColor;
        final disabledColor = Colors.grey.shade600;

        return Row(
            children: [
                SizedBox(height: 30, child: TextButton(onPressed: canGoOlder ? () => _setSegment(_currentSegment - 1) : null, child: Text("< Older", style: TextStyle(color: canGoOlder ? navButtonColor : disabledColor)))),
                SizedBox(height: 30, child: TextButton(style: TextButton.styleFrom(backgroundColor: _isLive ? Theme.of(context).primaryColor.withOpacity(0.2) : null), onPressed: () => _setSegment(_maxSegments, goLive: true), child: Text(_isLive ? "LIVE" : "Segment $_currentSegment"))),
                SizedBox(height: 30, child: TextButton(onPressed: canGoNewer ? () => _setSegment(_currentSegment + 1) : null, child: Text("Newer >", style: TextStyle(color: canGoNewer ? navButtonColor : disabledColor)))),
            ],
        );
    }

    void _setSegment(int segment, {bool goLive = false}) {
        if (_firstDataTimestamp == null) return;
        setState(() {
            _currentSegment = segment;
            _isLive = goLive || (_currentSegment == _maxSegments);
            final segmentStartTime = _firstDataTimestamp!.add(Duration(milliseconds: (_currentSegment - 1) * _graphTimeWindow.inMilliseconds));
            _chartVisibleMin = segmentStartTime;
            _chartVisibleMax = segmentStartTime.add(_graphTimeWindow);
        });
    }

    Widget _buildRealTimeGraph(bool isDarkMode) {
        final textColor = ThemeColors.getColor('dialogText', isDarkMode);
        final axisLineColor = ThemeColors.getColor('serialPortCardBorder', isDarkMode);
        List<CartesianSeries> series = [];
        List<PlotBand> plotBands = [];
        final visibleChannels = _activeChannels.where((c) => _visibleGraphChannels.contains(c.startingCharacter)).toList();

        String yAxisTitleText;
        if (visibleChannels.length == 1) {
            yAxisTitleText = '${visibleChannels.first.channelName} (${visibleChannels.first.unit})';
        } else {
            yAxisTitleText = 'Value';
        }

        for (var channel in visibleChannels) {
            final data = _graphData[channel.startingCharacter] ?? [];
            final alarmColor = Color(channel.targetAlarmColour);
            if (channel.targetAlarmMax != null) plotBands.add(PlotBand(start: channel.targetAlarmMax!, end: channel.targetAlarmMax!, borderWidth: 1.5, borderColor: alarmColor.withOpacity(0.8), dashArray: const <double>[5, 5]));
            if (channel.targetAlarmMin != null) plotBands.add(PlotBand(start: channel.targetAlarmMin!, end: channel.targetAlarmMin!, borderWidth: 1.5, borderColor: alarmColor.withOpacity(0.8), dashArray: const <double>[5, 5]));
            series.add(LineSeries<ChartData, DateTime>(
                animationDuration: 0,
                dataSource: data,
                name: channel.channelName,
                color: channel.graphLineColour,
                xValueMapper: (ChartData d, _) => d.time,
                yValueMapper: (ChartData d, _) => d.value,
                markerSettings: MarkerSettings(isVisible: _showDataPoints, height: 3, width: 3, color: channel.graphLineColour)));
        }

        if (_showPeakValue && _globalPeakValues.isNotEmpty) {
            for (var channel in visibleChannels) {
                final peakData = _globalPeakValues[channel.channelName];
                if (peakData != null) {
                    series.add(ScatterSeries<ChartData, DateTime>(
                        dataSource: [peakData],
                        name: '${channel.channelName} (Peak)',
                        color: channel.graphLineColour,
                        markerSettings: const MarkerSettings(isVisible: true, height: 10, width: 10, shape: DataMarkerType.circle, borderWidth: 2, borderColor: Colors.black),
                        xValueMapper: (ChartData d, _) => d.time,
                        yValueMapper: (ChartData d, _) => d.value,
                        dataLabelSettings: DataLabelSettings(
                            isVisible: true,
                            labelAlignment: ChartDataLabelAlignment.top,
                            builder: (dynamic data, dynamic point, dynamic series, int pointIndex, int seriesIndex) => Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(color: channel.graphLineColour, borderRadius: BorderRadius.circular(4)),
                                child: Text(peakData.value!.toStringAsFixed(channel.decimalPlaces), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))))));
                }
            }
        }

        return SfCartesianChart(
            primaryXAxis: DateTimeAxis(
                title: AxisTitle(text: 'Time (HH:mm:ss)', textStyle: TextStyle(color: textColor, fontSize: 12)),
                majorGridLines: MajorGridLines(width: 0.5, color: axisLineColor.withOpacity(0.5)),
                axisLine: AxisLine(width: 1, color: axisLineColor),
                labelStyle: TextStyle(color: textColor, fontSize: 10),
                minimum: _chartVisibleMin,
                maximum: _chartVisibleMax,
                dateFormat: DateFormat('HH:mm:ss'),
                intervalType: DateTimeIntervalType.auto),
            primaryYAxis: NumericAxis(
                title: AxisTitle(text: yAxisTitleText, textStyle: TextStyle(color: textColor, fontSize: 12)),
                majorGridLines: MajorGridLines(width: 0.5, color: axisLineColor.withOpacity(0.5)),
                axisLine: AxisLine(width: 1, color: axisLineColor),
                labelStyle: TextStyle(color: textColor, fontSize: 10),
                plotBands: plotBands),
            series: series,
            legend: Legend(isVisible: false),
            trackballBehavior: _trackballBehavior,
            zoomPanBehavior: _zoomPanBehavior);
    }

    void _showChannelFilterDialog(BuildContext context, bool isDarkMode) {
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
                                    itemCount: _activeChannels.length,
                                    itemBuilder: (context, index) {
                                        final channel = _activeChannels[index];
                                        return CheckboxListTile(
                                            title: Text(channel.channelName, style: TextStyle(color: ThemeColors.getColor('dialogText', isDarkMode))),
                                            value: tempVisibleChannels.contains(channel.startingCharacter),
                                            onChanged: (bool? value) => setDialogState(() => value == true ? tempVisibleChannels.add(channel.startingCharacter) : tempVisibleChannels.remove(channel.startingCharacter)));
                                    },
                                ),
                            ),
                            actions: [
                                TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
                                TextButton(
                                    child: Text('Apply', style: TextStyle(color: ThemeColors.getColor('submitButton', isDarkMode))),
                                    onPressed: () {
                                        setState(() => _visibleGraphChannels = tempVisibleChannels);
                                        Navigator.of(dialogContext).pop();
                                    }),
                            ],
                        );
                    },
                );
            },
        );
    }

    Widget _buildHorizontalGraphLegend(bool isDarkMode) {
        return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: _activeChannels.map((channel) {
                        final isVisible = _visibleGraphChannels.contains(channel.startingCharacter);
                        return InkWell(
                            onTap: () => _showColorPicker(channel, isDarkMode),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                child: Row(
                                    children: [
                                        Container(width: 12, height: 12, decoration: BoxDecoration(color: isVisible ? channel.graphLineColour : Colors.grey, borderRadius: BorderRadius.circular(2))),
                                        const SizedBox(width: 8),
                                        Text(channel.channelName, style: TextStyle(fontSize: 12, color: isVisible ? ThemeColors.getColor('dialogText', isDarkMode) : Colors.grey, decoration: isVisible ? TextDecoration.none : TextDecoration.lineThrough)),
                                    ],
                                ),
                            ),
                        );
                    }).toList(),
                ),
            ),
        );
    }

    Widget _buildControlPanel(bool isDarkMode) {
        Color statusColor;
        if (_statusMessage.startsWith("Error") || _statusMessage.contains("lost") || _statusMessage.contains("stopped")) {
            statusColor = Colors.red.shade400;
        } else if (_isPortOpen && _isDataFlowing) {
            statusColor = Colors.green.shade400;
        } else {
            statusColor = ThemeColors.getColor('dialogSubText', isDarkMode);
        }
        return Card(
            color: ThemeColors.getColor('serialPortCardBackground', isDarkMode),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
            child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                    children: [
                        Text('Status: $_statusMessage', style: GoogleFonts.firaCode(fontSize: 13, color: statusColor), textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        Row(children: [
                            Expanded(child: _buildControlButton(label: 'Start', icon: Icons.power_settings_new, onPressed: _isPortOpen || _isAttemptingReconnect ? null : _connectAndRead, isDarkMode: isDarkMode)),
                            const SizedBox(width: 10),
                            Expanded(child: _buildControlButton(label: 'Stop', icon: Icons.link_off, onPressed: _isPortOpen || _isAttemptingReconnect ? _disconnectPort : null, color: ThemeColors.getColor('resetButton', isDarkMode), isDarkMode: isDarkMode)),
                        ]),
                        const SizedBox(height: 10),
                        Row(children: [
                            Expanded(child: _buildControlButton(label: 'Open', icon: Icons.folder_open, onPressed: _showOpenFileDialog, isDarkMode: isDarkMode)),
                            const SizedBox(width: 10),
                            Expanded(child: _buildControlButton(label: 'Save', icon: Icons.save, onPressed: _isDataDirty ? _saveData : null, isDarkMode: isDarkMode, color: _isDataDirty ? ThemeColors.getColor('submitButton', isDarkMode) : Colors.grey.shade600)),
                        ]),
                        const SizedBox(height: 10),
                        Row(children: [
                            Expanded(child: _buildControlButton(label: 'Clear Data', icon: Icons.cleaning_services_rounded, onPressed: _onClearPressed, isDarkMode: isDarkMode, color: Colors.orange.shade800)),
                            const SizedBox(width: 10),
                            Expanded(child: _buildControlButton(label: 'Back', icon: Icons.arrow_back, onPressed: _isPortOpen ? null : _onBackPressed, isDarkMode: isDarkMode, color: Colors.red.shade700)),
                        ]),
                    ],
                ),
            ),
        );
    }

    Widget _buildCompactControlPanel(bool isDarkMode) {
        Color statusColor;
        if (_statusMessage.startsWith("Error") || _statusMessage.contains("lost") || _statusMessage.contains("stopped")) {
            statusColor = Colors.red.shade400;
        } else if (_isPortOpen && _isDataFlowing) {
            statusColor = Colors.green.shade400;
        } else {
            statusColor = ThemeColors.getColor('dialogSubText', isDarkMode);
        }
        return Card(
            color: ThemeColors.getColor('serialPortCardBackground', isDarkMode),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
            child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                    children: [
                        Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: Text('Status: $_statusMessage', style: GoogleFonts.firaCode(fontSize: 13, color: statusColor), textAlign: TextAlign.center),
                        ),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                                Expanded(child: _buildControlButton(label: 'Connect', icon: Icons.power_settings_new, onPressed: _isPortOpen || _isAttemptingReconnect ? null : _connectAndRead, isDarkMode: isDarkMode)),
                                const SizedBox(width: 10),
                                Expanded(child: _buildControlButton(label: 'Disconnect', icon: Icons.link_off, onPressed: _isPortOpen || _isAttemptingReconnect ? _disconnectPort : null, color: ThemeColors.getColor('resetButton', isDarkMode), isDarkMode: isDarkMode)),
                                const SizedBox(width: 10),
                                Expanded(child: _buildControlButton(label: 'Open', icon: Icons.folder_open, onPressed: _showOpenFileDialog, isDarkMode: isDarkMode)),
                                const SizedBox(width: 10),
                                Expanded(child: _buildControlButton(label: 'Save', icon: Icons.save, onPressed: _isDataDirty ? _saveData : null, isDarkMode: isDarkMode, color: _isDataDirty ? ThemeColors.getColor('submitButton', isDarkMode) : Colors.grey.shade600)),
                                const SizedBox(width: 10),
                                Expanded(child: _buildControlButton(label: 'Mode', icon: LucideIcons.layoutGrid, onPressed: () => _showModeDialog(context, isDarkMode), isDarkMode: isDarkMode)),
                                const SizedBox(width: 10),
                                Expanded(child: _buildControlButton(label: 'Clear Data', icon: Icons.cleaning_services_rounded, onPressed: _onClearPressed, isDarkMode: isDarkMode, color: Colors.orange.shade800)),
                                const SizedBox(width: 10),
                                Expanded(child: _buildControlButton(label: 'Back', icon: Icons.arrow_back, onPressed: _isPortOpen ? null : _onBackPressed, isDarkMode: isDarkMode, color: Colors.red.shade700)),
                            ],
                        ),
                    ],
                ),
            ),
        );
    }

    Widget _buildHeaderTextField(String label, TextEditingController controller, bool isDarkMode, {double width = 200}) =>
        SizedBox(
            width: width,
            child: TextField(
                controller: controller,
                onChanged: (v) => setState(() => _isDataDirty = true),
                style: TextStyle(color: ThemeColors.getColor('dialogText', isDarkMode), fontSize: 14, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                    labelText: label,
                    labelStyle: TextStyle(color: ThemeColors.getColor('dialogSubText', isDarkMode)),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: ThemeColors.getColor('serialPortCardBorder', isDarkMode))))));

    Widget _buildEditableDuration(String label, Duration duration, bool isDarkMode, ValueChanged<Duration> onDurationChanged, {bool showSeconds = true, bool showDays = false}) {
        String formatDurationReadable(Duration d) {
            if (d.inSeconds < 60 && !showDays) return '${d.inSeconds}s';
            if (d.inMinutes < 60 && !showDays) return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
            if (d.inHours < 24 && !showDays) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
            var parts = [];
            if (d.inDays > 0 || showDays) parts.add('${d.inDays}d');
            if (d.inHours.remainder(24) > 0 || parts.isNotEmpty) parts.add('${d.inHours.remainder(24)}h');
            parts.add('${d.inMinutes.remainder(60)}m');
            if (showSeconds) parts.add('${d.inSeconds.remainder(60)}s');
            return parts.join(' ');
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: ThemeColors.getColor('dialogSubText', isDarkMode), fontSize: 12)),
            const SizedBox(height: 4),
            InkWell(
                onTap: () => _showDurationPickerDialog(label, duration, isDarkMode, onDurationChanged, showSeconds, showDays),
                child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: ThemeColors.getColor('serialPortCardBorder', isDarkMode))),
                    child: Text(formatDurationReadable(duration), style: GoogleFonts.firaCode(fontSize: 14, color: ThemeColors.getColor('dialogText', isDarkMode), fontWeight: FontWeight.w500))))
        ]);
    }

    Widget _buildControlButton({required String label, required IconData icon, required VoidCallback? onPressed, required bool isDarkMode, Color? color}) {
        final buttonColor = color ?? ThemeColors.getColor('submitButton', isDarkMode);
        return ElevatedButton.icon(
            icon: Icon(icon, size: 16),
            label: Text(label, style: const TextStyle(fontSize: 13, overflow: TextOverflow.ellipsis)),
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                backgroundColor: buttonColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: buttonColor.withOpacity(0.4),
                disabledForegroundColor: Colors.white.withOpacity(0.7),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));
    }

    Future<bool> _showUnsavedDataDialog() async =>
        !_isDataDirty || (await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                title: const Text('Unsaved Data'),
                content: const Text('You have unsaved data. Are you sure you want to continue? All unsaved data will be lost.'),
                actions: [
                    TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text('Continue', style: TextStyle(color: Colors.red.shade400))),
                ],
            ),
        )) == true;

    void _showColorPicker(ActiveChannel channel, bool isDarkMode) {
        Color pickedColor = channel.graphLineColour;
        showDialog(
            context: context,
            builder: (context) {
                bool isDefault = false;
                return StatefulBuilder(
                    builder: (dialogContext, setDialogState) {
                        return AlertDialog(
                            backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
                            title: Text('Select Channel Color', style: TextStyle(color: ThemeColors.getColor('dialogText', isDarkMode))),
                            content: SingleChildScrollView(
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                        ColorPicker(pickerColor: pickedColor, onColorChanged: (color) => pickedColor = color),
                                        const Divider(),
                                        CheckboxListTile(
                                            title: Text("Set as default for this channel", style: TextStyle(color: ThemeColors.getColor('dialogText', isDarkMode))),
                                            value: isDefault,
                                            onChanged: (value) => setDialogState(() => isDefault = value ?? false),
                                            controlAffinity: ListTileControlAffinity.leading,
                                            activeColor: Theme.of(context).primaryColor,
                                        ),
                                    ],
                                ),
                            ),
                            actions: [
                                TextButton(child: const Text('Cancel'), onPressed: () => Navigator.of(context).pop()),
                                TextButton(
                                    child: Text('OK', style: TextStyle(color: ThemeColors.getColor('submitButton', isDarkMode))),
                                    onPressed: () {
                                        setState(() => channel.graphLineColour = pickedColor);
                                        if (isDefault) {
                                            _updateChannelColorInDatabase(channel);
                                        }
                                        Navigator.of(context).pop();
                                    },
                                ),
                            ],
                        );
                    },
                );
            },
        );
    }

    void _showDurationPickerDialog(String title, Duration initialDuration, bool isDarkMode, ValueChanged<Duration> onConfirm, bool showSeconds, bool showDays) {
        final dCtrl = TextEditingController(text: showDays ? initialDuration.inDays.toString() : '0');
        final hCtrl = TextEditingController(text: initialDuration.inHours.remainder(24).toString());
        final mCtrl = TextEditingController(text: initialDuration.inMinutes.remainder(60).toString());
        final sCtrl = TextEditingController(text: initialDuration.inSeconds.remainder(60).toString());
        void setDuration(Duration d) {
            dCtrl.text = showDays ? d.inDays.toString() : '0';
            hCtrl.text = d.inHours.remainder(24).toString();
            mCtrl.text = d.inMinutes.remainder(60).toString();
            sCtrl.text = d.inSeconds.remainder(60).toString();
        }
        showDialog(
            context: context,
            builder: (context) => AlertDialog(
                backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
                title: Text('Set $title', style: TextStyle(color: ThemeColors.getColor('dialogText', isDarkMode))),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                    Wrap(spacing: 8.0, runSpacing: 4.0, children: [
                        ActionChip(label: const Text('1 min'), onPressed: () => setDuration(const Duration(minutes: 1))),
                        ActionChip(label: const Text('5 min'), onPressed: () => setDuration(const Duration(minutes: 5))),
                        ActionChip(label: const Text('10 min'), onPressed: () => setDuration(const Duration(minutes: 10))),
                        ActionChip(label: const Text('30 min'), onPressed: () => setDuration(const Duration(minutes: 30))),
                        ActionChip(label: const Text('1 hour'), onPressed: () => setDuration(const Duration(hours: 1)))
                    ]),
                    const SizedBox(height: 20),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                        if (showDays) ...[
                            _durationTextField(dCtrl, 'DD', isDarkMode),
                            Text(':', style: TextStyle(fontSize: 24, color: ThemeColors.getColor('dialogText', isDarkMode)))
                        ],
                        _durationTextField(hCtrl, 'HH', isDarkMode),
                        Text(':', style: TextStyle(fontSize: 24, color: ThemeColors.getColor('dialogText', isDarkMode))),
                        _durationTextField(mCtrl, 'MM', isDarkMode),
                        if (showSeconds) ...[
                            Text(':', style: TextStyle(fontSize: 24, color: ThemeColors.getColor('dialogText', isDarkMode))),
                            _durationTextField(sCtrl, 'SS', isDarkMode)
                        ]
                    ])
                ]),
                actions: [
                    TextButton(child: const Text('Cancel'), onPressed: () => Navigator.of(context).pop()),
                    TextButton(
                        child: Text('OK', style: TextStyle(color: ThemeColors.getColor('submitButton', isDarkMode))),
                        onPressed: () {
                            final d = int.tryParse(dCtrl.text) ?? 0;
                            final h = int.tryParse(hCtrl.text) ?? 0;
                            final m = int.tryParse(mCtrl.text) ?? 0;
                            final s = int.tryParse(sCtrl.text) ?? 0;
                            onConfirm(Duration(days: d, hours: h, minutes: m, seconds: s));
                            Navigator.of(context).pop();
                        })
                ]));
    }

    Widget _durationTextField(TextEditingController controller, String label, bool isDarkMode) => SizedBox(
        width: 50,
        child: TextField(
            controller: controller,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            style: TextStyle(fontSize: 20, color: ThemeColors.getColor('dialogText', isDarkMode)),
            decoration: InputDecoration(labelText: label, labelStyle: TextStyle(color: ThemeColors.getColor('dialogSubText', isDarkMode)))));

    Widget _buildDialogButton({required String text, required IconData icon, required LinearGradient gradient, required VoidCallback onPressed}) => GestureDetector(
        onTap: onPressed,
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))]),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(text, style: GoogleFonts.poppins(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600), overflow: TextOverflow.visible, softWrap: false)
            ])));

    void _showModeDialog(BuildContext context, bool isDarkMode) {
        showDialog(
            context: context,
            barrierColor: Colors.black.withOpacity(0.4),
            builder: (BuildContext dialogContext) {
                return BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Dialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
                        child: Container(
                            width: 400,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                gradient: LinearGradient(colors: [ThemeColors.getColor('dialogBackground', isDarkMode), ThemeColors.getColor('dialogBackground', isDarkMode).withOpacity(0.9)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                    Text('Select Mode', style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w600, color: ThemeColors.getColor('dialogText', isDarkMode))),
                                    const SizedBox(height: 12),
                                    Text('Choose your preferred options', style: GoogleFonts.poppins(fontSize: 14, color: ThemeColors.getColor('dialogSubText', isDarkMode))),
                                    const SizedBox(height: 24),
                                    Column(
                                        children: [
                                            _buildDialogButton(
                                                text: 'Graph Mode',
                                                icon: LucideIcons.barChart2,
                                                gradient: ThemeColors.getDialogButtonGradient(isDarkMode, 'graph'),
                                                onPressed: () {
                                                    setState(() => _currentDisplayMode = 'Graph');
                                                    MessageUtils.showMessage(context, 'Switched to Graph mode!');
                                                    Navigator.of(dialogContext).pop();
                                                }),
                                            const SizedBox(height: 12),
                                            _buildDialogButton(
                                                text: 'Table Mode',
                                                icon: LucideIcons.table,
                                                gradient: ThemeColors.getDialogButtonGradient(isDarkMode, 'table'),
                                                onPressed: () {
                                                    setState(() => _currentDisplayMode = 'Table');
                                                    MessageUtils.showMessage(context, 'Switched to Table mode!');
                                                    Navigator.of(dialogContext).pop();
                                                }),
                                            const SizedBox(height: 12),
                                            _buildDialogButton(
                                                text: 'Combined Mode',
                                                icon: LucideIcons.layoutGrid,
                                                gradient: ThemeColors.getDialogButtonGradient(isDarkMode, 'combined'),
                                                onPressed: () {
                                                    setState(() => _currentDisplayMode = 'Combined');
                                                    MessageUtils.showMessage(context, 'Switched to Combined mode!');
                                                    Navigator.of(dialogContext).pop();
                                                }),
                                            const SizedBox(height: 12),
                                            _buildDialogButton(
                                                text: isDarkMode ? 'Light Theme' : 'Dark Theme',
                                                icon: isDarkMode ? LucideIcons.sun : LucideIcons.moon,
                                                gradient: ThemeColors.getDialogButtonGradient(isDarkMode, 'restore'),
                                                onPressed: () {
                                                    Global.saveTheme(!isDarkMode);
                                                    Navigator.of(dialogContext).pop();
                                                }),
                                        ],
                                    ),
                                    const SizedBox(height: 24),
                                    TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text('Cancel', style: GoogleFonts.poppins(fontSize: 16, color: Colors.redAccent, fontWeight: FontWeight.w600))),
                                ],
                            ),
                        ),
                    ),
                );
            },
        );
    }

    Future<void> _saveData() async {
        if (_isSaving || !_isDataDirty) return;
        setState(() => _isSaving = true);
        showDialog(context: context, barrierDismissible: false, builder: (BuildContext context) => const Dialog(child: Padding(padding: EdgeInsets.all(20.0), child: Row(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(width: 20), Text("Saving data...")]))));

        try {
            final prefs = await SharedPreferences.getInstance();
            final isFirstSave = _sessionDbName == null;

            if (isFirstSave) {
                _recNo = (prefs.getInt('recNo') ?? 0) + 1;
                final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
                _sessionDbName = 'serial_data_$timestamp.db';
            }

            final mainDb = await DatabaseManager().database;
            final sessionDb = await SessionDatabaseManager().openSessionDatabase(_sessionDbName!);

            final testPayload = _prepareTestPayload(_filenameController.text);
            final test1Payload = _prepareTest1Payload();

            await mainDb.insert('Test', testPayload, conflictAlgorithm: ConflictAlgorithm.replace);
            await sessionDb.insert('Test', testPayload, conflictAlgorithm: ConflictAlgorithm.replace);

            if (isFirstSave) {
                final test2Payload = _prepareTest2Payload();
                await sessionDb.insert('Test2', test2Payload, conflictAlgorithm: ConflictAlgorithm.ignore);
            }

            if (test1Payload.isNotEmpty) {
                final batch = sessionDb.batch();
                for (final row in test1Payload) {
                    batch.insert('Test1', row);
                }
                await batch.commit(noResult: true);
            }

            if (isFirstSave) await prefs.setInt('recNo', _recNo!);
            setState(() {
                _savedTableRowCount = _tableData.length;
                _isDataDirty = false;
            });

            if (mounted) MessageUtils.showMessage(context, "Data saved successfully to ${_filenameController.text}");
        } catch (e, s) {
            LogPage.addLog("Save Error: $e\n$s");
            if (mounted) MessageUtils.showMessage(context, "An error occurred while saving: $e", isError: true);
        } finally {
            if (mounted) Navigator.of(context).pop();
            setState(() => _isSaving = false);
        }
    }

    Map<String, dynamic> _prepareTestPayload(String userFacingFileName) {
        final now = DateTime.now();
        final testDuration = _firstDataTimestamp != null ? now.difference(_firstDataTimestamp!) : Duration.zero;

        double maxY = 0.0;
        double minY = 0.0;
        if (_activeChannels.isNotEmpty) {
            maxY = _activeChannels.map((c) => c.originalChannel.chartMaximumValue).reduce((a, b) => a > b ? a : b);
            minY = _activeChannels.map((c) => c.originalChannel.chartMinimumValue).reduce((a, b) => a < b ? a : b);
        }

        return {
            'RecNo': _recNo?.toDouble(),
            'FName': userFacingFileName,
            'OperatorName': _operatorController.text.isNotEmpty ? _operatorController.text : "Operator",
            'TDate': _firstDataTimestamp != null ? DateFormat('yyyy-MM-dd').format(_firstDataTimestamp!) : "",
            'TTime': _firstDataTimestamp != null ? DateFormat('HH:mm:ss').format(_firstDataTimestamp!) : "",
            'ScanningRate': _scanRate.inSeconds.toDouble(),
            'ScanningRateHH': _scanRate.inHours.toDouble(),
            'ScanningRateMM': _scanRate.inMinutes.remainder(60).toDouble(),
            'ScanningRateSS': _scanRate.inSeconds.remainder(60).toDouble(),
            'TestDurationDD': testDuration.inDays.toDouble(),
            'TestDurationHH': testDuration.inHours.remainder(24).toDouble(),
            'TestDurationMM': testDuration.inMinutes.remainder(60).toDouble(),
            'TestDurationSS': testDuration.inSeconds.remainder(60).toDouble(),
            'GraphVisibleArea': _graphTimeWindow.inSeconds.toDouble(),
            'TotalChannel': _activeChannels.length,
            'DBName': _sessionDbName,
            'BaseLine': 0.0,
            'FullScale': 0.0,
            'Descrip': "",
            'AbsorptionPer': 0.0,
            'NOR': 0.0,
            'FLName': "$userFacingFileName.csv",
            'XAxis': "Time",
            'XAxisRecNo': 1.0,
            'XAxisUnit': "s",
            'XAxisCode': 1.0,
            'MaxYAxis': maxY,
            'MinYAxis': minY,
        };
    }

    List<Map<String, dynamic>> _prepareTest1Payload() {
        if (_savedTableRowCount >= _tableData.length) return [];
        final newRows = _tableData.sublist(_savedTableRowCount);
        final sortedChannels = List<ActiveChannel>.from(_activeChannels)..sort((a, b) => a.recNo.compareTo(b.recNo));
        final List<Map<String, dynamic>> payload = [];
        for (int i = 0; i < newRows.length; i++) {
            final rowData = newRows[i];
            final overallRowIndex = _savedTableRowCount + i;
            final rowTimestamp = rowData['Time'] as DateTime;
            final Map<String, dynamic> rowPayload = {
                'RecNo': _recNo?.toDouble(),
                'SNo': (overallRowIndex + 1).toDouble(),
                'SlNo': (overallRowIndex + 1).toDouble(),
                'AbsDate': DateFormat('yyyy-MM-dd').format(rowTimestamp),
                'AbsTime': DateFormat('HH:mm:ss').format(rowTimestamp),
                'AbsDateTime': DateFormat('yyyy-MM-dd HH:mm:ss').format(rowTimestamp),
                'ChangeTime': DateFormat('HH:mm:ss').format(rowTimestamp),
                'Shown': "Y",
                'AbsAvg': 0.0,
            };
            for (int j = 0; j < sortedChannels.length; j++) {
                final channel = sortedChannels[j];
                final value = rowData[channel.channelName];
                rowPayload['AbsPer${j + 1}'] = (value is num) ? value.toDouble() : null;
            }
            payload.add(rowPayload);
        }
        return payload;
    }

    Map<String, dynamic> _prepareTest2Payload() {
        final sortedChannels = List<ActiveChannel>.from(_activeChannels)..sort((a, b) => a.recNo.compareTo(b.recNo));
        final Map<String, dynamic> payload = {'RecNo': _recNo?.toDouble()};
        for (int i = 0; i < 100; i++) {
            payload['ChannelName${i + 1}'] = (i < sortedChannels.length) ? sortedChannels[i].channelName : "";
        }
        return payload;
    }

    void _startAutoSaveTimer() {
        _stopAutoSaveTimer();
        if (_isAutoSaveEnabled && _isPortOpen && _autoSaveIntervalSeconds > 0) {
            _autoSaveTimer = Timer.periodic(Duration(seconds: _autoSaveIntervalSeconds), (timer) {
                if (_isDataDirty && !_isSaving) {
                    LogPage.addLog('[LOG] Auto-saving data...');
                    _saveData();
                }
            });
        }
    }

    void _stopAutoSaveTimer() {
        _autoSaveTimer?.cancel();
        _autoSaveTimer = null;
    }

    Future<void> _updateChannelColorInDatabase(ActiveChannel channel) async {
        try {
            final db = await DatabaseManager().database;
            final colorString = channel.graphLineColour.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();

            await db.update('ChannelSetup', {'graphLineColour': colorString}, where: 'RecNo = ?', whereArgs: [channel.recNo]);
            if (mounted) MessageUtils.showMessage(context, "'${channel.channelName}' default color updated to #$colorString.");
        } catch (e) {
            if (mounted) MessageUtils.showMessage(context, "Error updating color: $e", isError: true);
        }
    }

    String _formatDurationForTooltip(int totalSeconds) {
        if (totalSeconds <= 0) return "a very short interval";
        final duration = Duration(seconds: totalSeconds);
        final parts = <String>[];
        final days = duration.inDays;
        final hours = duration.inHours.remainder(24);
        final minutes = duration.inMinutes.remainder(60);
        final seconds = duration.inSeconds.remainder(60);
        if (days > 0) parts.add('$days day${days > 1 ? 's' : ''}');
        if (hours > 0) parts.add('$hours hour${hours > 1 ? 's' : ''}');
        if (minutes > 0) parts.add('$minutes minute${minutes > 1 ? 's' : ''}');
        if (seconds > 0) parts.add('$seconds second${seconds > 1 ? 's' : ''}');
        if (parts.isEmpty) return "a very short interval";
        return parts.join(', ');
    }

    String _formatDurationForDisplay(int totalSeconds) {
        if (totalSeconds <= 0) return "0s";
        final duration = Duration(seconds: totalSeconds);
        final days = duration.inDays;
        final hours = duration.inHours.remainder(24);
        final minutes = duration.inMinutes.remainder(60);
        final seconds = duration.inSeconds.remainder(60);
        if (days > 0) return '${days}d ${hours}h';
        if (hours > 0) return '${hours}h ${minutes}m';
        if (minutes > 0) return '${minutes}m ${seconds}s';
        return '${seconds}s';
    }
}