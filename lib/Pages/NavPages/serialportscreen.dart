import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../constants/global.dart';
import '../../constants/theme.dart';
import 'channel.dart';

// A mutable version of the Channel class to hold state like color
class ActiveChannel {
  final String startingCharacter;
  final String channelName;
  final int decimalPlaces;
  final String unit;
  Color graphLineColour;

  ActiveChannel({
    required this.startingCharacter,
    required this.channelName,
    required this.decimalPlaces,
    required this.unit,
    required this.graphLineColour,
  });

  factory ActiveChannel.fromChannel(Channel channel) {
    return ActiveChannel(
      startingCharacter: channel.startingCharacter,
      channelName: channel.channelName,
      decimalPlaces: channel.decimalPlaces,
      unit: channel.unit,
      graphLineColour: Color(channel.graphLineColour),
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

  // Data & Business Logic
  late final List<ActiveChannel> _activeChannels;
  late final Map<String, ActiveChannel> _channelMap;
  final Map<String, List<FlSpot>> _graphData = {};
  final Map<String, double> _lastChannelValues = {};
  final List<Map<String, dynamic>> _tableData = [];
  Timer? _scanRateTimer;
  DateTime? _connectionStartTime;

  // UI & User Inputs
  late final TextEditingController _filenameController;
  final _operatorController = TextEditingController(text: "Operator");
  final ScrollController _tableScrollController = ScrollController();
  final ScrollController _tableHorizontalScrollController = ScrollController(); // For synced table scroll
  Duration _testDuration = const Duration(days: 1);
  Duration _scanRate = const Duration(seconds: 1);
  Duration _graphTimeWindow = const Duration(minutes: 5);
  Duration _graphTimeOffset = Duration.zero; // For graph segment navigation

  // Graph
  double _minY = 0.0, _maxY = 100.0;
  String _yAxisUnit = 'Value';
  late Set<String> _visibleGraphChannels; // For filtering channels on graph
  bool _showDataPoints = false;
  bool _showPeakValue = false;

  @override
  void initState() {
    super.initState();
    _activeChannels = widget.selectedChannels.map((c) => ActiveChannel.fromChannel(c)).toList();
    _channelMap = {for (var channel in _activeChannels) channel.startingCharacter: channel};
    _visibleGraphChannels = _activeChannels.map((c) => c.startingCharacter).toSet();

    // Generate the initial informative filename
    final initialFilename = "Test_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}";
    _filenameController = TextEditingController(text: initialFilename);

    for (var channel in _activeChannels) {
      _graphData[channel.startingCharacter] = [];
      _lastChannelValues[channel.startingCharacter] = 0.0;
    }
    _updateYAxisUnit();
  }

  void _updateYAxisUnit() {
    if (_activeChannels.isEmpty) {
      _yAxisUnit = 'Value';
      return;
    }
    final firstUnit = _activeChannels.first.unit;
    if (_activeChannels.every((c) => c.unit == firstUnit)) {
      _yAxisUnit = firstUnit;
    } else {
      _yAxisUnit = 'Mixed Values';
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
      if (!_port!.openReadWrite()) {
        throw Exception("Failed to open port $portName");
      }

      // On successful connection, cancel any reconnect attempts
      _reconnectTimer?.cancel();
      _isAttemptingReconnect = false;

      final config = SerialPortConfig()..baudRate = 2400..bits = 8..parity = SerialPortParity.none..stopBits = 1;
      _port!.config = config;

      _reader = SerialPortReader(_port!);
      _serialSubscription = _reader!.stream.listen((data) {
        if (_statusMessage != "Receiving Data...") {
          if (mounted) setState(() => _statusMessage = "Receiving Data...");
        }
        _buffer += String.fromCharCodes(data);
        _processBuffer();
      }, onError: _handleConnectionError);

      if (mounted) {
        setState(() {
          _isPortOpen = true;
          _statusMessage = "Connected. Waiting for data...";
          _connectionStartTime ??= DateTime.now();
          _scanRateTimer?.cancel();
          _scanRateTimer = Timer.periodic(_scanRate, _onScanRateTick);
        });
      }
    } catch (e) {
      print('[SerialPortScreen] ❌ Connection Error: $e');
      if (mounted && !_isAttemptingReconnect) {
        setState(() => _statusMessage = "Error: Could not connect.");
      }
      // If the connection fails during a reconnect attempt, the timer will simply try again.
    }
  }

  void _disconnectPort() {
    print('[SerialPortScreen] 🛑 Disconnecting port...');
    _reconnectTimer?.cancel();
    _scanRateTimer?.cancel();
    _serialSubscription?.cancel();
    _reader?.close();
    if (_port?.isOpen ?? false) _port?.close();
    _port?.dispose();

    if (mounted) {
      setState(() {
        _port = null;
        _reader = null;
        _isPortOpen = false;
        _isAttemptingReconnect = false;
        _statusMessage = "Disconnected";
        _connectionStartTime = null;
      });
    }
  }

  void _startReconnectProcedure() {
    if (_isAttemptingReconnect || !mounted) return;

    setState(() {
      _isPortOpen = false;
      _statusMessage = "Connection lost. Reconnecting...";
      _isAttemptingReconnect = true;
    });

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      print("[SerialPortScreen] Attempting to reconnect...");
      if (!_isPortOpen) {
        _connectAndRead();
      } else {
        // Port is now open, procedure successful.
        timer.cancel();
        if (mounted) {
          setState(() => _isAttemptingReconnect = false);
        }
      }
    });
  }

  void _handleConnectionError(dynamic error) {
    print('[SerialPortScreen] ❌ Connection Error/Device Unplugged: $error');
    _scanRateTimer?.cancel();
    _serialSubscription?.cancel();
    _reader?.close();
    if (_port?.isOpen ?? false) _port?.close();
    if (mounted) {
      _startReconnectProcedure();
    }
  }

  void _processBuffer() {
    final regex = RegExp(r'\.([A-Z0-9]{6})');
    int processIndex = 0;
    while (true) {
      final match = regex.firstMatch(_buffer.substring(processIndex));
      if (match == null) break;
      final extracted = match.group(1);
      if (extracted != null) _bufferLatestValue(extracted);
      processIndex = match.end + processIndex;
    }
    if (processIndex > 0) _buffer = _buffer.substring(processIndex);
  }

  void _bufferLatestValue(String point) {
    if (point.length != 6) return;
    final identifier = point[1];
    final channel = _channelMap[identifier];
    if (channel != null) {
      try {
        final hexValue = int.parse(point.substring(2), radix: 16);
        final finalValue = hexValue / pow(10, channel.decimalPlaces);
        _lastChannelValues[identifier] = finalValue;
      } catch (e) { /* silent fail */ }
    }
  }

  void _onScanRateTick(Timer timer) {
    if (!mounted || !_isPortOpen) return;

    if (_connectionStartTime != null && DateTime.now().difference(_connectionStartTime!) >= _testDuration) {
      print("[SerialPortScreen] ✅ Test duration reached. Disconnecting.");
      _disconnectPort();
      return;
    }

    if (!_isDataDirty) _isDataDirty = true;

    final now = DateTime.now();
    final newRow = <String, dynamic>{'Time': now};
    final Map<String, FlSpot> newSpots = {};

    for (var channel in _activeChannels) {
      final lastValue = _lastChannelValues[channel.startingCharacter]!;
      newRow[channel.channelName] = lastValue;
      newSpots[channel.startingCharacter] = FlSpot(now.millisecondsSinceEpoch.toDouble(), lastValue);
    }

    setState(() {
      _tableData.add(newRow);
      if (_tableData.length > 200) _tableData.removeAt(0);

      newSpots.forEach((channelId, spot) {
        final dataList = _graphData[channelId]!;
        dataList.add(spot);
        if (dataList.length > 2000) dataList.removeAt(0);
      });

      final newBounds = _getNewYAxisBounds();
      _minY = newBounds.$1;
      _maxY = newBounds.$2;
    });

    if (_tableScrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 50), () {
        _tableScrollController.animateTo(
          _tableScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  Future<void> _onClearPressed() async {
    bool canProceed = await _showUnsavedDataDialog();
    if (canProceed && mounted) {
      setState(() {
        _tableData.clear();
        _graphData.forEach((key, value) => value.clear());
        _minY = 0.0; _maxY = 100.0;
        _buffer = '';
        _isDataDirty = false;
        _filenameController.text = "Test_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}";
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

  (double, double) _getNewYAxisBounds() {
    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    final minX = now - _graphTimeWindow.inMilliseconds;
    double? currentMinY, currentMaxY;
    for (var channelId in _visibleGraphChannels) {
      final spotList = _graphData[channelId] ?? [];
      for (var spot in spotList.where((s) => s.x >= minX)) {
        currentMinY = (currentMinY == null) ? spot.y : min(currentMinY, spot.y);
        currentMaxY = (currentMaxY == null) ? spot.y : max(currentMaxY, spot.y);
      }
    }

    if (currentMinY == null || currentMaxY == null) return (_minY, _maxY);
    double range = (currentMaxY - currentMinY).abs();

    // If line is flat, apply a fixed padding
    if (range < 0.1) return (currentMinY - 5, currentMaxY + 5);

    // Use larger padding for single-channel view for better readability
    final padding = range * (_activeChannels.length == 1 ? 0.25 : 0.1);
    return (currentMinY - padding, currentMaxY + padding);
  }

  // --- UI BUILDERS ---

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

  // -- Header Panel & Its Widgets --
  Widget _buildHeaderPanel(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: ThemeColors.getColor('serialPortCardBackground', isDarkMode),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            spreadRadius: 2,
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2), width: 1)),
      ),
      child: Row(
        children: [
          _buildHeaderTextField('Filename', _filenameController, isDarkMode, width: 250),
          const SizedBox(width: 16),
          _buildHeaderTextField('Operator', _operatorController, isDarkMode, width: 150),
          const Spacer(),
          _buildGraphSegmentControl(isDarkMode),
          const SizedBox(width: 16),
          _buildEditableDuration('Test Duration', _testDuration, isDarkMode, (d) => setState(() => _testDuration = d), showDays: true),
          const SizedBox(width: 16),
          _buildEditableDuration('Scan Rate', _scanRate, isDarkMode, (d) => setState(() => _scanRate = d)),
        ],
      ),
    );
  }

  // -- Left Panel: Table & Controls --
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
    final headerStyle = GoogleFonts.poppins(
      color: ThemeColors.getColor('dialogText', isDarkMode), fontWeight: FontWeight.w600, fontSize: 14,
    );
    final cellStyle = GoogleFonts.firaCode(
      color: ThemeColors.getColor('dialogSubText', isDarkMode), fontSize: 13,
    );
    final timeFormat = DateFormat('HH:mm:ss');
    final double columnWidth = 120;
    final double totalWidth = columnWidth + (_activeChannels.length * columnWidth);

    return Card(
      color: ThemeColors.getColor('serialPortCardBackground', isDarkMode),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Fixed header
          SingleChildScrollView(
            controller: _tableHorizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: Container(
              width: totalWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
              color: ThemeColors.getColor('serialPortTableHeaderBackground', isDarkMode),
              child: Row(
                children: [
                  SizedBox(width: columnWidth, child: Text('Time', style: headerStyle)),
                  ..._activeChannels.map((c) => SizedBox(
                    width: columnWidth,
                    child: Text('${c.channelName} (${c.unit})', style: headerStyle, textAlign: TextAlign.center),
                  )),
                ],
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1),
          // Scrollable body
          Expanded(
            child: SingleChildScrollView(
              controller: _tableHorizontalScrollController, // Use the same controller here
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalWidth,
                child: ListView.builder(
                  controller: _tableScrollController,
                  itemCount: _tableData.length,
                  itemBuilder: (context, index) {
                    final rowData = _tableData[index];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      color: index.isOdd ? ThemeColors.getColor('serialPortTableRowOdd', isDarkMode) : null,
                      child: Row(
                        children: [
                          SizedBox(width: columnWidth, child: Text(timeFormat.format(rowData['Time']), style: cellStyle)),
                          ..._activeChannels.map((c) {
                            final value = rowData[c.channelName];
                            final text = value?.toStringAsFixed(c.decimalPlaces) ?? '0.0';
                            return SizedBox(width: columnWidth, child: Text(text, style: cellStyle, textAlign: TextAlign.center));
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

  // -- Right Panel: Graph & Legend --
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
            _buildGraphToolbar(isDarkMode),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 16, right: 24, bottom: 8, left: 8),
                child: _graphData.values.any((list) => list.isNotEmpty)
                    ? _buildRealTimeGraph(isDarkMode)
                    : Center(child: Text('Waiting for data...', style: TextStyle(fontSize: 18, color: ThemeColors.getColor('serialPortInputLabel', isDarkMode)))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGraphToolbar(bool isDarkMode) {
    final iconColor = ThemeColors.getColor('dialogSubText', isDarkMode);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      height: 48,
      child: Row(
        children: [
          Expanded(child: _buildHorizontalGraphLegend(isDarkMode)),
          const VerticalDivider(),
          // Channel Filter
          PopupMenuButton<String>(
            icon: Icon(Icons.filter_list, color: iconColor),
            tooltip: 'Filter Channels',
            onSelected: (String char) {
              setState(() {
                if (_visibleGraphChannels.contains(char)) {
                  _visibleGraphChannels.remove(char);
                } else {
                  _visibleGraphChannels.add(char);
                }
              });
            },
            itemBuilder: (BuildContext context) {
              return _activeChannels.map((channel) {
                return CheckedPopupMenuItem<String>(
                  value: channel.startingCharacter,
                  checked: _visibleGraphChannels.contains(channel.startingCharacter),
                  child: Text(channel.channelName),
                );
              }).toList();
            },
          ),
          // Toggle Peak Value
          IconButton(
            icon: Icon(Icons.show_chart, color: _showPeakValue ? Theme.of(context).primaryColor : iconColor),
            onPressed: () => setState(() => _showPeakValue = !_showPeakValue),
            tooltip: 'Show Peak Value',
          ),
          // Toggle Data Points
          IconButton(
            icon: Icon(Icons.grain, color: _showDataPoints ? Theme.of(context).primaryColor : iconColor),
            onPressed: () => setState(() => _showDataPoints = !_showDataPoints),
            tooltip: 'Toggle Data Points',
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: null, child: Text('Window')),
        ],
      ),
    );
  }

  Widget _buildHorizontalGraphLegend(bool isDarkMode) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
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
                    style: TextStyle(
                      fontSize: 12,
                      color: isVisible ? ThemeColors.getColor('dialogText', isDarkMode) : Colors.grey,
                      decoration: isVisible ? TextDecoration.none : TextDecoration.lineThrough,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRealTimeGraph(bool isDarkMode) {
    final timeFormat = DateFormat('HH:mm:ss');
    final axisLabelStyle = TextStyle(color: ThemeColors.getColor('serialPortGraphAxisLabel', isDarkMode), fontSize: 10);
    final visibleChannels = _activeChannels.where((c) => _visibleGraphChannels.contains(c.startingCharacter)).toList();

    List<LineChartBarData> lineBarsData = visibleChannels.map((channel) {
      return LineChartBarData(
        spots: _graphData[channel.startingCharacter] ?? [],
        isCurved: true,
        color: channel.graphLineColour,
        barWidth: 2,
        dotData: FlDotData(show: _showDataPoints),
        isStrokeCapRound: true,
      );
    }).toList();

    final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    final now = nowMs - _graphTimeOffset.inMilliseconds;
    final minX = now - _graphTimeWindow.inMilliseconds;

    // Find peak value if enabled
    List<ShowingTooltipIndicators> showingTooltipIndicators = [];
    if (_showPeakValue) {
      double? peakY;
      FlSpot? peakSpot;
      int peakBarIndex = -1;

      for (int i = 0; i < visibleChannels.length; i++) {
        final channel = visibleChannels[i];
        final spots = (_graphData[channel.startingCharacter] ?? []).where((s) => s.x >= minX && s.x <= now);
        for (final spot in spots) {
          if (peakY == null || spot.y > peakY) {
            peakY = spot.y;
            peakSpot = spot;
            peakBarIndex = i;
          }
        }
      }

      if (peakSpot != null && peakBarIndex != -1) {
        showingTooltipIndicators = [
          ShowingTooltipIndicators([LineBarSpot(lineBarsData[peakBarIndex], peakBarIndex, peakSpot)])
        ];
      }
    }

    return LineChart(
      LineChartData(
        clipData: FlClipData.all(),
        backgroundColor: isDarkMode ? Colors.black.withOpacity(0.2) : Colors.grey.shade50,
        lineBarsData: lineBarsData,
        minY: _minY, maxY: _maxY, minX: minX, maxX: now,
        showingTooltipIndicators: showingTooltipIndicators,
        gridData: FlGridData(
          show: true,
          horizontalInterval: (_maxY - _minY).abs() / 5,
          getDrawingHorizontalLine: (_) => FlLine(color: ThemeColors.getColor('serialPortCardBorder', isDarkMode).withOpacity(0.5), strokeWidth: 0.5),
          getDrawingVerticalLine: (_) => FlLine(color: ThemeColors.getColor('serialPortCardBorder', isDarkMode).withOpacity(0.5), strokeWidth: 0.5),
        ),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            axisNameWidget: Text(_yAxisUnit, style: axisLabelStyle.copyWith(fontWeight: FontWeight.bold)),
            axisNameSize: 24,
            sideTitles: SideTitles(showTitles: true, reservedSize: 50, getTitlesWidget: (v, m) => Text(v.toStringAsFixed(1), style: axisLabelStyle)),
          ),
          bottomTitles: AxisTitles(
              axisNameWidget: Text('Time (HH:MM:SS)', style: axisLabelStyle.copyWith(fontWeight: FontWeight.bold)),
              axisNameSize: 24,
              sideTitles: SideTitles(
                showTitles: true, reservedSize: 35, interval: _graphTimeWindow.inMilliseconds / 4,
                getTitlesWidget: (value, meta) => Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(timeFormat.format(DateTime.fromMillisecondsSinceEpoch(value.toInt())), style: axisLabelStyle)),
              )),
        ),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true, // Enables pan and zoom!
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.blueGrey.withOpacity(0.9),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final channel = _activeChannels[spot.barIndex];
                final timestamp = DateFormat('HH:mm:ss.SSS').format(DateTime.fromMillisecondsSinceEpoch(spot.x.toInt()));
                final text = '${channel.channelName}:\n${spot.y.toStringAsFixed(channel.decimalPlaces)} ${channel.unit}\n$timestamp';
                return LineTooltipItem(
                  text,
                  const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }

  // --- Control panel and other helpers ---
  Widget _buildControlPanel(bool isDarkMode) {
    Color statusColor;
    if (_statusMessage.startsWith("Error") || _statusMessage.contains("lost")) {
      statusColor = Colors.red.shade400;
    } else if (_isPortOpen) {
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
            Row(
              children: [
                Expanded(child: _buildControlButton(label: 'Connect', icon: Icons.power_settings_new, onPressed: _isPortOpen || _isAttemptingReconnect ? null : _connectAndRead, isDarkMode: isDarkMode)),
                const SizedBox(width: 10),
                Expanded(child: _buildControlButton(label: 'Disconnect', icon: Icons.link_off, onPressed: _isPortOpen || _isAttemptingReconnect ? _disconnectPort : null, color: ThemeColors.getColor('resetButton', isDarkMode), isDarkMode: isDarkMode)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _buildControlButton(label: 'Mode', icon: Icons.settings, onPressed: null, isDarkMode: isDarkMode, color: Colors.grey.shade600)),
                const SizedBox(width: 10),
                Expanded(child: _buildControlButton(label: 'Open', icon: Icons.folder_open, onPressed: null, isDarkMode: isDarkMode, color: Colors.grey.shade600)),
                const SizedBox(width: 10),
                Expanded(child: _buildControlButton(label: 'Save', icon: Icons.save, onPressed: null, isDarkMode: isDarkMode, color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _buildControlButton(label: 'Clear Data', icon: Icons.cleaning_services_rounded, onPressed: _onClearPressed, isDarkMode: isDarkMode, color: Colors.orange.shade800)),
                const SizedBox(width: 10),
                Expanded(child: _buildControlButton(label: 'Exit', icon: Icons.exit_to_app, onPressed: _isPortOpen ? null : _onExitPressed, isDarkMode: isDarkMode, color: Colors.red.shade700)),
              ],
            ),
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
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: ThemeColors.getColor('serialPortCardBorder', isDarkMode)),
          ),
        ),
      ),
    );
  }

  Widget _buildGraphSegmentControl(bool isDarkMode) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () {
            setState(() {
              _graphTimeOffset += _graphTimeWindow;
            });
          },
          tooltip: 'Previous Segment',
        ),
        _buildEditableDuration('Graph Segment', _graphTimeWindow, isDarkMode, (d) => setState(() => _graphTimeWindow = d), showSeconds: false),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: _graphTimeOffset == Duration.zero ? null : () {
            setState(() {
              _graphTimeOffset -= _graphTimeWindow;
              if (_graphTimeOffset.isNegative) {
                _graphTimeOffset = Duration.zero;
              }
            });
          },
          tooltip: 'Next Segment',
        ),
      ],
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
      if(showSeconds) parts.add('${d.inSeconds.remainder(60)}s');
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
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: ThemeColors.getColor('serialPortCardBorder', isDarkMode)),
            ),
            child: Text(
              formatDurationReadable(duration),
              style: GoogleFonts.firaCode(fontSize: 14, color: ThemeColors.getColor('dialogText', isDarkMode), fontWeight: FontWeight.w500),
            ),
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
        backgroundColor: buttonColor, foregroundColor: Colors.white,
        disabledBackgroundColor: buttonColor.withOpacity(0.4), disabledForegroundColor: Colors.white.withOpacity(0.7),
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
        actions: [
          TextButton(child: Text('OK', style: TextStyle(color: ThemeColors.getColor('submitButton', isDarkMode))), onPressed: () => Navigator.of(context).pop()),
        ],
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

    showDialog(context: context, builder: (context) => AlertDialog(
      backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
      title: Text('Set $title', style: TextStyle(color: ThemeColors.getColor('dialogText', isDarkMode))),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Preset chips
          Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            children: [
              ActionChip(label: const Text('1 min'), onPressed: () => setDuration(const Duration(minutes: 1))),
              ActionChip(label: const Text('5 min'), onPressed: () => setDuration(const Duration(minutes: 5))),
              ActionChip(label: const Text('10 min'), onPressed: () => setDuration(const Duration(minutes: 10))),
              ActionChip(label: const Text('30 min'), onPressed: () => setDuration(const Duration(minutes: 30))),
              ActionChip(label: const Text('1 hour'), onPressed: () => setDuration(const Duration(hours: 1))),
            ],
          ),
          const SizedBox(height: 20),
          // Manual input
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (showDays) ...[_durationTextField(dCtrl, 'DD', isDarkMode), Text(':', style: TextStyle(fontSize: 24, color: ThemeColors.getColor('dialogText', isDarkMode)))],
              _durationTextField(hCtrl, 'HH', isDarkMode),
              Text(':', style: TextStyle(fontSize: 24, color: ThemeColors.getColor('dialogText', isDarkMode))),
              _durationTextField(mCtrl, 'MM', isDarkMode),
              if (showSeconds) ...[Text(':', style: TextStyle(fontSize: 24, color: ThemeColors.getColor('dialogText', isDarkMode))),_durationTextField(sCtrl, 'SS', isDarkMode)],
            ],
          ),
        ],
      ),
      actions: [
        TextButton(child: const Text('Cancel'), onPressed: () => Navigator.of(context).pop()),
        TextButton(child: Text('OK', style: TextStyle(color: ThemeColors.getColor('submitButton', isDarkMode))), onPressed: () {
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