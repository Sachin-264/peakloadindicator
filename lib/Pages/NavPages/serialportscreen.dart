import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../../constants/global.dart';
import '../../constants/theme.dart';
import 'channel.dart';

// Helper class for Syncfusion Chart data points
class ChartData {
  final DateTime time;
  final double? value;
  ChartData(this.time, this.value);
}

// A mutable version of the Channel class to hold state like color
class ActiveChannel {
  final String startingCharacter;
  final String channelName;
  final int decimalPlaces;
  final String unit;
  Color graphLineColour;
  final double? targetAlarmMax;
  final double? targetAlarmMin;
  final int targetAlarmColour;

  ActiveChannel({
    required this.startingCharacter,
    required this.channelName,
    required this.decimalPlaces,
    required this.unit,
    required this.graphLineColour,
    this.targetAlarmMax,
    this.targetAlarmMin,
    required this.targetAlarmColour,
  });

  factory ActiveChannel.fromChannel(Channel channel) {
    return ActiveChannel(
      startingCharacter: channel.startingCharacter,
      channelName: channel.channelName,
      decimalPlaces: channel.decimalPlaces,
      unit: channel.unit,
      graphLineColour: Color(channel.graphLineColour),
      targetAlarmMax: channel.targetAlarmMax,
      targetAlarmMin: channel.targetAlarmMin,
      targetAlarmColour: channel.targetAlarmColour,
    );
  }
}

class SerialPortScreen extends StatefulWidget {
  final List<Channel> selectedChannels;
  final VoidCallback onBack;

  const SerialPortScreen({
    super.key,
    required this.selectedChannels,
    required this.onBack,
  });

  @override
  State<SerialPortScreen> createState() => _SerialPortScreenState();
}

class _SerialPortScreenState extends State<SerialPortScreen> {
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

  // Data Flow Watchdog
  bool _isDataFlowing = false;
  Timer? _dataStoppageTimer;

  // Data & Business Logic
  late final List<ActiveChannel> _activeChannels;
  late final Map<String, ActiveChannel> _channelMap;
  late final Map<String, ActiveChannel> _channelNameMap;
  final Map<String, List<ChartData>> _graphData = {};
  DateTime? _firstDataTimestamp;
  final Map<String, double?> _lastChannelValues = {};
  final List<Map<String, dynamic>> _tableData = [];
  Timer? _scanRateTimer;

  // UI & User Inputs
  late final TextEditingController _filenameController;
  final _operatorController = TextEditingController(text: "Operator");
  final ScrollController _tableScrollController = ScrollController();
  final ScrollController _tableHorizontalScrollController = ScrollController();
  Duration _testDuration = const Duration(days: 1);
  Duration _scanRate = const Duration(seconds: 1);
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
    _activeChannels = widget.selectedChannels.map((c) => ActiveChannel.fromChannel(c)).toList();
    _channelMap = {for (var channel in _activeChannels) channel.startingCharacter: channel};
    _channelNameMap = {for (var channel in _activeChannels) channel.channelName: channel};
    _visibleGraphChannels = _activeChannels.map((c) => c.startingCharacter).toSet();

    _trackballBehavior = TrackballBehavior(
      enable: true,
      activationMode: ActivationMode.singleTap,
      tooltipDisplayMode: TrackballDisplayMode.groupAllPoints,
      tooltipSettings: const InteractiveTooltip(
        enable: true,
        format: 'series.name : point.y', // Shows Time, then "Channel Name : Value"
      ),
      shouldAlwaysShow: false,
    );

    _zoomPanBehavior = ZoomPanBehavior(
      enablePinching: true,
      enablePanning: true,
      zoomMode: ZoomMode.x,
    );

    final initialFilename = "Test_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}";
    _filenameController = TextEditingController(text: initialFilename);

    for (var channel in _activeChannels) {
      _graphData[channel.startingCharacter] = [];
      _lastChannelValues[channel.startingCharacter] = null;
    }
  }

  // --- CORE LOGIC: CONNECTION & DATA HANDLING ---

  void _connectAndRead() {
    if (_isPortOpen) return;
    const portName = 'COM6';
    if (!_isAttemptingReconnect) {
      setState(() => _statusMessage = "Connecting to $portName...");
    }
    try {
      _port = SerialPort(portName);
      if (!_port!.openReadWrite()) throw Exception("Failed to open port $portName");

      _reconnectTimer?.cancel();
      _isAttemptingReconnect = false;

      final config = SerialPortConfig()..baudRate = 2400..bits = 8..parity = SerialPortParity.none..stopBits = 1;
      _port!.config = config;
      _reader = SerialPortReader(_port!);

      _serialSubscription = _reader!.stream.listen((data) {
        final receivedString = String.fromCharCodes(data);
        print('[SerialPort] RX: $receivedString');
        _buffer += receivedString;
        _processBuffer();
      }, onError: _handleConnectionError);

      if (mounted) {
        setState(() {
          _isPortOpen = true;
          _statusMessage = "Connected. Waiting for data...";
          _scanRateTimer?.cancel();
          _scanRateTimer = Timer.periodic(_scanRate, _onScanRateTick);
        });
      }
    } catch (e) {
      print('[SerialPortScreen] ❌ Connection Error: $e');
      if (mounted && !_isAttemptingReconnect) {
        setState(() => _statusMessage = "Error: Could not connect.");
      }
    }
  }

  void _disconnectPort() {
    print('[SerialPortScreen] 🛑 Disconnecting port...');
    _reconnectTimer?.cancel();
    _scanRateTimer?.cancel();
    _dataStoppageTimer?.cancel();
    _serialSubscription?.cancel();
    _reader?.close();
    if (_port?.isOpen ?? false) _port?.close();
    _port?.dispose();

    if (mounted) {
      setState(() {
        _port = null;
        _reader = null;
        _isPortOpen = false;
        _isDataFlowing = false;
        _isAttemptingReconnect = false;
        _statusMessage = "Disconnected";
      });
    }
  }

  void _startReconnectProcedure() {
    if (_isAttemptingReconnect || !mounted) return;
    _dataStoppageTimer?.cancel();
    setState(() {
      _isPortOpen = false;
      _isDataFlowing = false;
      _statusMessage = "Connection lost. Reconnecting...";
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
    print('[SerialPortScreen] ❌ Connection Error/Device Unplugged: $error');
    if (mounted) {
      _scanRateTimer?.cancel();
      _serialSubscription?.cancel();
      _reader?.close();
      if (_port?.isOpen ?? false) _port?.close();
      _startReconnectProcedure();
    }
  }

  void _processBuffer() {
    // Find all known identifiers and their indices in the current buffer
    final List<({String char, int index})> foundIdentifiers = [];
    for (int i = 0; i < _buffer.length; i++) {
      final char = _buffer[i];
      if (_channelMap.containsKey(char)) {
        foundIdentifiers.add((char: char, index: i));
      }
    }

    // We need at least two identifiers to delimit a value (e.g., from 'A' to 'B')
    if (foundIdentifiers.length < 2) {
      return; // Not enough data to parse a full value, wait for more.
    }

    print('[Parser] Found ${foundIdentifiers.length} identifiers in buffer of length ${_buffer.length}');

    // Parse values between each consecutive pair of identifiers
    for (int i = 0; i < foundIdentifiers.length - 1; i++) {
      final current = foundIdentifiers[i];
      final next = foundIdentifiers[i + 1];

      final identifier = current.char;
      // The value is the string of characters between the current identifier and the next one
      final valueStr = _buffer.substring(current.index + 1, next.index).trim();

      _bufferLatestValue(identifier, valueStr);
    }

    // The last identifier found marks the start of the next potential value.
    // We keep it and whatever follows it in the buffer for the next processing cycle.
    final lastIdentifierIndex = foundIdentifiers.last.index;
    _buffer = _buffer.substring(lastIdentifierIndex);
    print('[Parser] Processed. New buffer is now: "$_buffer"');
  }

  void _bufferLatestValue(String identifier, String valueString) {
    final channel = _channelMap[identifier];
    if (channel != null) {
      print('[Parser] Parsing: Identifier="$identifier", ValueString="$valueString"');
      final double? finalValue = double.tryParse(valueString);

      if (finalValue != null) {
        print('[Parser] ✅ Success! Parsed value: $finalValue for ${channel.channelName}');
        _lastChannelValues[identifier] = finalValue;

        // --- Data Watchdog Logic ---
        _dataStoppageTimer?.cancel();
        if (mounted) {
          if (!_isDataFlowing) {
            setState(() {
              _isDataFlowing = true;
              _statusMessage = "Receiving Data...";
            });
          }
          // Set a timer. If it fires, it means data flow has stopped.
          _dataStoppageTimer = Timer(_scanRate * 3, () {
            if (mounted) {
              setState(() {
                _isDataFlowing = false;
                _statusMessage = "Data flow stopped.";
              });
            }
          });
        }
      } else {
        print('[Parser] ❌ FAILED to parse double from "$valueString"');
      }
    } else {
      print('[Parser] ⚠️ Warning: Unmapped identifier "$identifier"');
    }
  }

  void _onScanRateTick(Timer timer) {
    if (!mounted || !_isPortOpen) return;

    // If data flow has stopped, do not add new (stale) data points.
    if (!_isDataFlowing && _firstDataTimestamp != null) {
      return;
    }
    // Don't add data if we haven't received any valid data yet.
    if (!_isDataFlowing) return;

    final now = DateTime.now();

    if (_firstDataTimestamp == null) {
      _firstDataTimestamp = now;
      _setSegment(1, goLive: true);
    }

    if (now.difference(_firstDataTimestamp!) >= _testDuration) {
      _disconnectPort();
      return;
    }
    if (!_isDataDirty) _isDataDirty = true;

    final newRow = <String, dynamic>{'Time': now};
    bool hasValidData = false;
    for (var channel in _activeChannels) {
      final lastValue = _lastChannelValues[channel.startingCharacter];
      if (lastValue != null) hasValidData = true;
      newRow[channel.channelName] = lastValue;
      _graphData[channel.startingCharacter]!.add(ChartData(now, lastValue));
    }

    if (hasValidData) {
      _tableData.add(newRow);
    }

    if (_showPeakValue) {
      _calculateGlobalPeakValues();
    }

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

    if (_tableScrollController.hasClients) {
      _tableScrollController.animateTo(
        _tableScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _togglePeakValue() {
    setState(() {
      _showPeakValue = !_showPeakValue;
      if (_showPeakValue) {
        _calculateGlobalPeakValues();
      } else {
        _globalPeakValues.clear();
      }
    });
  }

  void _calculateGlobalPeakValues() {
    _globalPeakValues.clear();
    for (var channel in _activeChannels) {
      final dataList = _graphData[channel.startingCharacter];
      if (dataList != null && dataList.isNotEmpty) {
        final validData = dataList.where((d) => d.value != null).toList();
        if (validData.isNotEmpty) {
          final peakData = validData.reduce((curr, next) => curr.value! > next.value! ? curr : next);
          _globalPeakValues[channel.channelName] = peakData;
        }
      }
    }
  }

  Future<void> _onClearPressed() async {
    bool canProceed = await _showUnsavedDataDialog();
    if (canProceed && mounted) {
      _dataStoppageTimer?.cancel();
      setState(() {
        _tableData.clear();
        _graphData.forEach((key, value) => value.clear());
        _lastChannelValues.updateAll((key, value) => null);
        _buffer = '';
        _isDataDirty = false;
        _isDataFlowing = false;

        if (_isPortOpen) {
          _statusMessage = "Connected. Waiting for data...";
        }

        _firstDataTimestamp = null;
        _filenameController.text = "Test_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}";
        _currentSegment = 1;
        _maxSegments = 1;
        _isLive = true;
        _chartVisibleMin = null;
        _chartVisibleMax = null;
        _globalPeakValues.clear();
        _showPeakValue = false;
      });
    }
  }

  Future<void> _onExitPressed() async {
    bool canProceed = await _showUnsavedDataDialog();
    if (canProceed) {
      widget.onBack();
    }
  }

  @override
  void dispose() {
    _disconnectPort();
    _filenameController.dispose();
    _operatorController.dispose();
    _tableScrollController.dispose();
    _tableHorizontalScrollController.dispose();
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
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLeftPanel(context, isDarkMode),
                      const SizedBox(width: 12),
                      _buildRightPanel(context, isDarkMode),
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

  Widget _buildHeaderPanel(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: ThemeColors.getColor('serialPortCardBackground', isDarkMode),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), spreadRadius: 2, blurRadius: 8, offset: const Offset(0, 3))],
        border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2), width: 1)),
      ),
      child: Row(
        children: [
          _buildHeaderTextField('Filename', _filenameController, isDarkMode, width: 250),
          const SizedBox(width: 16),
          _buildHeaderTextField('Operator', _operatorController, isDarkMode, width: 150),
          const Spacer(),
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
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.4,
      child: Column(
        children: [
          Expanded(child: _buildDataTable(context, isDarkMode)),
          const SizedBox(height: 12),
          _buildControlPanel(isDarkMode),
        ],
      ),
    );
  }

  Widget _buildDataTable(BuildContext context, bool isDarkMode) {
    final headerStyle = GoogleFonts.poppins(color: ThemeColors.getColor('dialogText', isDarkMode), fontWeight: FontWeight.w600, fontSize: 14);
    final cellStyle = GoogleFonts.firaCode(color: ThemeColors.getColor('dialogSubText', isDarkMode), fontSize: 13);
    final timeFormat = DateFormat('HH:mm:ss');
    final double columnWidth = 140;
    final double totalWidth = columnWidth + (_activeChannels.length * columnWidth);
    return Card(
      color: ThemeColors.getColor('serialPortCardBackground', isDarkMode),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SingleChildScrollView(
            controller: _tableHorizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: Container(
              width: totalWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
              color: ThemeColors.getColor('serialPortTableHeaderBackground', isDarkMode),
              child: Row(
                children: [
                  SizedBox(width: columnWidth, child: Text('Time(HH:MM:SS)', style: headerStyle)),
                  ..._activeChannels.map((c) => SizedBox(
                    width: columnWidth,
                    child: Text('${c.channelName} (${c.unit})', style: headerStyle, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
                  )),
                ],
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1),
          Expanded(
            child: SingleChildScrollView(
              controller: _tableHorizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalWidth,
                child: ListView.builder(
                  primary: false,
                  controller: _tableScrollController,
                  itemCount: _tableData.length,
                  itemBuilder: (context, index) {
                    final rowData = _tableData[index];
                    final bool isLatestRow = index == _tableData.length - 1;

                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
                      color: isLatestRow
                          ? (isDarkMode ? Colors.teal.withOpacity(0.3) : Colors.teal.withOpacity(0.2))
                          : (index.isOdd ? ThemeColors.getColor('serialPortTableRowOdd', isDarkMode) : null),
                      child: Row(
                        children: [
                          SizedBox(width: columnWidth, child: Text(timeFormat.format(rowData['Time']), style: cellStyle)),
                          ..._activeChannels.map((c) {
                            final value = rowData[c.channelName];
                            final text = value != null ? value.toStringAsFixed(c.decimalPlaces) : '-';

                            bool isPeakCell = false;
                            if (_showPeakValue) {
                              final peakData = _globalPeakValues[c.channelName];
                              if (peakData != null && peakData.time == rowData['Time']) {
                                isPeakCell = true;
                              }
                            }

                            TextStyle currentCellStyle = cellStyle;
                            bool isAlarm = false;
                            if (value != null) {
                              if (c.targetAlarmMax != null && value > c.targetAlarmMax!) isAlarm = true;
                              if (c.targetAlarmMin != null && value < c.targetAlarmMin!) isAlarm = true;
                            }
                            if (isAlarm) {
                              currentCellStyle = cellStyle.copyWith(color: Color(c.targetAlarmColour), fontWeight: FontWeight.bold);
                            }

                            return SizedBox(
                              width: columnWidth,
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 4.0),
                                decoration: BoxDecoration(
                                  color: isPeakCell ? Theme.of(context).primaryColor.withOpacity(0.4) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(text, style: currentCellStyle, textAlign: TextAlign.center),
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel(BuildContext context, bool isDarkMode) {
    return Expanded(
      child: Card(
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
              TextButton(
                child: const Text("Select Channel"),
                onPressed: () => _showChannelFilterDialog(context, isDarkMode),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: _showPeakValue ? activeBgColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon: Icon(Icons.show_chart, color: _showPeakValue ? activeColor : iconColor),
                  onPressed: _togglePeakValue,
                  tooltip: 'Show Peak Value',
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: _showDataPoints ? activeBgColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon: Icon(Icons.grain, color: _showDataPoints ? activeColor : iconColor),
                  onPressed: () => setState(() => _showDataPoints = !_showDataPoints),
                  tooltip: 'Toggle Data Points',
                ),
              ),
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
        SizedBox(
          height: 30,
          child: TextButton(
            onPressed: canGoOlder ? () => _setSegment(_currentSegment - 1) : null,
            child: Text("< Older", style: TextStyle(color: canGoOlder ? navButtonColor : disabledColor)),
          ),
        ),
        SizedBox(
          height: 30,
          child: TextButton(
            style: TextButton.styleFrom(backgroundColor: _isLive ? Theme.of(context).primaryColor.withOpacity(0.2) : null),
            onPressed: () => _setSegment(_maxSegments, goLive: true),
            child: Text(_isLive ? "LIVE" : "Segment $_currentSegment"),
          ),
        ),
        SizedBox(
          height: 30,
          child: TextButton(
            onPressed: canGoNewer ? () => _setSegment(_currentSegment + 1) : null,
            child: Text("Newer >", style: TextStyle(color: canGoNewer ? navButtonColor : disabledColor)),
          ),
        ),
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
      yAxisTitleText = 'Value (Mixed Units)';
    }

    for (var channel in visibleChannels) {
      final data = _graphData[channel.startingCharacter] ?? [];
      final alarmColor = Color(channel.targetAlarmColour);
      if (channel.targetAlarmMax != null) {
        plotBands.add(PlotBand(start: channel.targetAlarmMax!, end: channel.targetAlarmMax!, borderWidth: 1.5, borderColor: alarmColor.withOpacity(0.8), dashArray: const <double>[5, 5]));
      }
      if (channel.targetAlarmMin != null) {
        plotBands.add(PlotBand(start: channel.targetAlarmMin!, end: channel.targetAlarmMin!, borderWidth: 1.5, borderColor: alarmColor.withOpacity(0.8), dashArray: const <double>[5, 5]));
      }

      series.add(LineSeries<ChartData, DateTime>(
        animationDuration: 0,
        dataSource: data,
        name: channel.channelName,
        color: channel.graphLineColour,
        xValueMapper: (ChartData d, _) => d.time,
        yValueMapper: (ChartData d, _) => d.value,
        markerSettings: MarkerSettings(isVisible: _showDataPoints, height: 3, width: 3, color: channel.graphLineColour),
      ));
    }

    if (_showPeakValue && _globalPeakValues.isNotEmpty) {
      for (var channel in visibleChannels) {
        final peakData = _globalPeakValues[channel.channelName];
        if (peakData != null) {
          series.add(ScatterSeries<ChartData, DateTime>(
            dataSource: [peakData],
            name: '${channel.channelName} (Peak)', // This name will show in the standard tooltip
            color: channel.graphLineColour,
            markerSettings: const MarkerSettings(
              isVisible: true,
              height: 10,
              width: 10,
              shape: DataMarkerType.circle,
              borderWidth: 2,
              borderColor: Colors.black,
            ),
            xValueMapper: (ChartData d, _) => d.time,
            yValueMapper: (ChartData d, _) => d.value,
            dataLabelSettings: DataLabelSettings(
              isVisible: true,
              labelAlignment: ChartDataLabelAlignment.top,
              builder: (dynamic data, dynamic point, dynamic series, int pointIndex, int seriesIndex) {
                return Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: channel.graphLineColour, borderRadius: BorderRadius.circular(4)),
                  child: Text(peakData.value!.toStringAsFixed(channel.decimalPlaces), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                );
              },
            ),
          ));
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
        intervalType: DateTimeIntervalType.auto,
      ),
      primaryYAxis: NumericAxis(
        title: AxisTitle(text: yAxisTitleText, textStyle: TextStyle(color: textColor, fontSize: 12)),
        majorGridLines: MajorGridLines(width: 0.5, color: axisLineColor.withOpacity(0.5)),
        axisLine: AxisLine(width: 1, color: axisLineColor),
        labelStyle: TextStyle(color: textColor, fontSize: 10),
        plotBands: plotBands,
      ),
      series: series,
      legend: Legend(isVisible: false),
      trackballBehavior: _trackballBehavior,
      zoomPanBehavior: _zoomPanBehavior,
    );
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
                      onChanged: (bool? value) {
                        setDialogState(() {
                          if (value == true) {
                            tempVisibleChannels.add(channel.startingCharacter);
                          } else {
                            tempVisibleChannels.remove(channel.startingCharacter);
                          }
                        });
                      },
                    );
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
                  },
                ),
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
                    Text(
                      channel.channelName,
                      style: TextStyle(fontSize: 12, color: isVisible ? ThemeColors.getColor('dialogText', isDarkMode) : Colors.grey, decoration: isVisible ? TextDecoration.none : TextDecoration.lineThrough),
                    ),
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
              Expanded(child: _buildControlButton(label: 'Connect', icon: Icons.power_settings_new, onPressed: _isPortOpen || _isAttemptingReconnect ? null : _connectAndRead, isDarkMode: isDarkMode)),
              const SizedBox(width: 10),
              Expanded(child: _buildControlButton(label: 'Disconnect', icon: Icons.link_off, onPressed: _isPortOpen || _isAttemptingReconnect ? _disconnectPort : null, color: ThemeColors.getColor('resetButton', isDarkMode), isDarkMode: isDarkMode)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _buildControlButton(label: 'Window', icon: Icons.aspect_ratio, onPressed: null, isDarkMode: isDarkMode, color: Colors.grey.shade600)),
              const SizedBox(width: 10),
              Expanded(child: _buildControlButton(label: 'Open', icon: Icons.folder_open, onPressed: null, isDarkMode: isDarkMode, color: Colors.grey.shade600)),
              const SizedBox(width: 10),
              Expanded(child: _buildControlButton(label: 'Save', icon: Icons.save, onPressed: null, isDarkMode: isDarkMode, color: Colors.grey.shade600)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _buildControlButton(label: 'Clear Data', icon: Icons.cleaning_services_rounded, onPressed: _onClearPressed, isDarkMode: isDarkMode, color: Colors.orange.shade800)),
              const SizedBox(width: 10),
              Expanded(child: _buildControlButton(label: 'Exit', icon: Icons.exit_to_app, onPressed: _isPortOpen ? null : _onExitPressed, isDarkMode: isDarkMode, color: Colors.red.shade700)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderTextField(String label, TextEditingController controller, bool isDarkMode, {double width = 200}) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        style: TextStyle(color: ThemeColors.getColor('dialogText', isDarkMode), fontSize: 14, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: ThemeColors.getColor('dialogSubText', isDarkMode)),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: ThemeColors.getColor('serialPortCardBorder', isDarkMode))),
        ),
      ),
    );
  }

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: ThemeColors.getColor('dialogSubText', isDarkMode), fontSize: 12)),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => _showDurationPickerDialog(label, duration, isDarkMode, onDurationChanged, showSeconds, showDays),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: ThemeColors.getColor('serialPortCardBorder', isDarkMode))),
            child: Text(formatDurationReadable(duration), style: GoogleFonts.firaCode(fontSize: 14, color: ThemeColors.getColor('dialogText', isDarkMode), fontWeight: FontWeight.w500)),
          ),
        ),
      ],
    );
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<bool> _showUnsavedDataDialog() async {
    if (!_isDataDirty) return true;
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved Data'),
        content: const Text('You have unsaved data. Are you sure you want to continue? All unsaved data will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text('Continue', style: TextStyle(color: Colors.red.shade400))),
        ],
      ),
    ) ?? false;
  }

  void _showColorPicker(ActiveChannel channel, bool isDarkMode) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
        title: Text('Select Channel Color', style: TextStyle(color: ThemeColors.getColor('dialogText', isDarkMode))),
        content: SingleChildScrollView(child: ColorPicker(pickerColor: channel.graphLineColour, onColorChanged: (color) => setState(() => channel.graphLineColour = color))),
        actions: [TextButton(child: Text('OK', style: TextStyle(color: ThemeColors.getColor('submitButton', isDarkMode))), onPressed: () => Navigator.of(context).pop())],
      ),
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(spacing: 8.0, runSpacing: 4.0, children: [
                ActionChip(label: const Text('1 min'), onPressed: () => setDuration(const Duration(minutes: 1))),
                ActionChip(label: const Text('5 min'), onPressed: () => setDuration(const Duration(minutes: 5))),
                ActionChip(label: const Text('10 min'), onPressed: () => setDuration(const Duration(minutes: 10))),
                ActionChip(label: const Text('30 min'), onPressed: () => setDuration(const Duration(minutes: 30))),
                ActionChip(label: const Text('1 hour'), onPressed: () => setDuration(const Duration(hours: 1))),
              ]),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                if (showDays) ...[_durationTextField(dCtrl, 'DD', isDarkMode), Text(':', style: TextStyle(fontSize: 24, color: ThemeColors.getColor('dialogText', isDarkMode)))],
                _durationTextField(hCtrl, 'HH', isDarkMode),
                Text(':', style: TextStyle(fontSize: 24, color: ThemeColors.getColor('dialogText', isDarkMode))),
                _durationTextField(mCtrl, 'MM', isDarkMode),
                if (showSeconds) ...[Text(':', style: TextStyle(fontSize: 24, color: ThemeColors.getColor('dialogText', isDarkMode))), _durationTextField(sCtrl, 'SS', isDarkMode)],
              ]),
            ],
          ),
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
                }),
          ],
        ));
  }

  Widget _durationTextField(TextEditingController controller, String label, bool isDarkMode) => SizedBox(
    width: 50,
    child: TextField(
      controller: controller,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      style: TextStyle(fontSize: 20, color: ThemeColors.getColor('dialogText', isDarkMode)),
      decoration: InputDecoration(labelText: label, labelStyle: TextStyle(color: ThemeColors.getColor('dialogSubText', isDarkMode))),
    ),
  );
}