import 'dart:convert';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager_plus/window_manager_plus.dart';
import 'Secondary_Bloc.dart';
import '../homepage.dart';
import '../../main.dart';

class SecondaryWindowApp extends StatefulWidget {
  final String channel;
  final Map<String, dynamic> channelData;
  final int windowId;
  final String? windowKey;

  const SecondaryWindowApp({
    super.key,
    required this.channel,
    required this.channelData,
    required this.windowId,
    this.windowKey,
  });

  @override
  State<SecondaryWindowApp> createState() => _SecondaryWindowAppState();
}

class _SecondaryWindowAppState extends State<SecondaryWindowApp> with WindowListener {
  Map<String, dynamic> _currentChannelData = {};
  List<String> _availableChannels = [];
  List<String> _selectedChannels = [];
  String? _xAxisChannel;
  Map<String, List<FlSpot>> _channelData = {};
  double _minY = 0.0;
  double _maxY = 0.0;
  double _minX = 0.0;
  double _maxX = 0.0;
  Map<String, double> _maxLoadValues = {};
  Map<String, Color> _channelColors = {};
  List<Map<String, dynamic>> _graphSegments = [];
  final TextEditingController _graphVisibleMinController = TextEditingController();
  final TextEditingController _graphVisibleHrController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WindowManagerPlus.current.addListener(this);
    _currentChannelData = Map.from(widget.channelData);
    _initializeAvailableChannels();
    _initializeSelectedChannels();
    _initializeChannelData();
    _calculateYRange();
    _calculateMaxLoadValues();
    _calculateGraphSegments();
    _graphVisibleMinController.addListener(_updateGraphSegments);
    _graphVisibleHrController.addListener(_updateGraphSegments);
  }

  @override
  void dispose() {
    _graphVisibleMinController.dispose();
    _graphVisibleHrController.dispose();
    WindowManagerPlus.current.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowFocus([int? windowId]) {
    setState(() {});
    debugPrint('[SECONDARY_WINDOW] Window $windowId gained focus');
  }

  @override
  void onWindowClose([int? windowId]) {
    debugPrint('[SECONDARY_WINDOW] Window closing for ID $windowId');
    if (widget.windowKey != null) {
      SecondaryWindowManager().removeWindow(widget.windowKey!);
    }
  }

  @override
  Future<dynamic> onEventFromWindow(String eventName, int fromWindowId, dynamic arguments) async {
    if (eventName == 'updateData') {
      try {
        final argsMap = jsonDecode(arguments as String) as Map<String, dynamic>;
        final updatedChannel = argsMap['channel'] as String;
        final updatedData = argsMap['channelData'] as Map<String, dynamic>;
        if (updatedChannel == widget.channel || widget.channel == 'All') {
          debugPrint('[SECONDARY_WINDOW] Received update for channel $updatedChannel (points: ${updatedData['dataPoints']?.length ?? 0})');
          setState(() {
            _currentChannelData = updatedData;
            _initializeAvailableChannels();
            _selectedChannels = _selectedChannels
                .where((channel) => _availableChannels.contains(channel))
                .toList();
            if (_selectedChannels.isEmpty && _availableChannels.isNotEmpty) {
              _selectedChannels = [_availableChannels.first];
            }
            if (_xAxisChannel != null && !_selectedChannels.contains(_xAxisChannel)) {
              _xAxisChannel = null;
            }
            _initializeChannelData();
            _calculateYRange();
            _calculateMaxLoadValues();
            _calculateGraphSegments();
          });
          return 'Update received by window ${widget.windowId}';
        }
      } catch (e) {
        debugPrint('[SECONDARY_WINDOW] Error processing update: $e');
      }
    }
    return null;
  }

  void _initializeAvailableChannels() {
    final dataPoints = _currentChannelData['dataPoints'] as List<dynamic>? ?? [];
    _availableChannels = dataPoints
        .map((data) => (data['channelIndex'] ?? '').toString())
        .where((index) => index.isNotEmpty)
        .toSet()
        .toList();
    debugPrint('[SECONDARY_WINDOW] Initialized available channels: $_availableChannels');
  }

  void _initializeSelectedChannels() {
    if (_availableChannels.isNotEmpty) {
      _selectedChannels = [_availableChannels.first];
    }
  }

  void _initializeChannelData() {
    _channelData.clear();
    final dataPoints = _currentChannelData['dataPoints'] as List<dynamic>? ?? [];
    for (var data in dataPoints) {
      final channelIndex = (data['channelIndex'] ?? '').toString();
      if (channelIndex.isNotEmpty) {
        _channelData.putIfAbsent(channelIndex, () => []);
        final xValue = (data['timestamp'] as num?)?.toDouble() ?? 0.0;
        final yValue = (data['value'] as num?)?.toDouble() ?? 0.0;
        _channelData[channelIndex]!.add(FlSpot(xValue, yValue));
      }
    }

    _minX = _channelData.values
        .expand((spots) => spots)
        .map((spot) => spot.x)
        .fold(double.infinity, (a, b) => a < b ? a : b);
    _maxX = _channelData.values
        .expand((spots) => spots)
        .map((spot) => spot.x)
        .fold(double.negativeInfinity, (a, b) => a > b ? a : b);

    debugPrint('[SECONDARY_WINDOW] Building graph: minX=$_minX, maxX=$_maxX, minY=$_minY, maxY=$_maxY');
  }

  void _calculateYRange() {
    _minY = _channelData.values
        .expand((spots) => spots)
        .map((spot) => spot.y)
        .fold(double.infinity, (a, b) => a < b ? a : b);
    _maxY = _channelData.values
        .expand((spots) => spots)
        .map((spot) => spot.y)
        .fold(double.negativeInfinity, (a, b) => a > b ? a : b);

    if (_minY == _maxY) {
      _minY -= 1.0;
      _maxY += 1.0;
    }
  }

  void _calculateMaxLoadValues() {
    _maxLoadValues.clear();
    for (var channel in _availableChannels) {
      final maxLoad = _channelData[channel]
          ?.map((spot) => spot.y)
          .fold(double.negativeInfinity, (a, b) => a > b ? a : b);
      if (maxLoad != null && maxLoad != double.negativeInfinity) {
        _maxLoadValues[channel] = maxLoad;
      }
    }
  }

  void _calculateGraphSegments() {
    _graphSegments.clear();
    final minutesText = _graphVisibleMinController.text;
    final hoursText = _graphVisibleHrController.text;

    double? visibleMinutes = minutesText.isNotEmpty ? double.tryParse(minutesText) : null;
    double? visibleHours = hoursText.isNotEmpty ? double.tryParse(hoursText) : null;

    if (visibleMinutes == null && visibleHours == null) {
      for (var channel in _selectedChannels) {
        _graphSegments.add({
          'channel': channel,
          'spots': _channelData[channel] ?? [],
        });
      }
      return;
    }

    double visibleDuration = 0.0;
    if (visibleHours != null) {
      visibleDuration += visibleHours * 3600.0;
    }
    if (visibleMinutes != null) {
      visibleDuration += visibleMinutes * 60.0;
    }

    final latestTime = _maxX;
    final earliestTime = latestTime - visibleDuration;

    for (var channel in _selectedChannels) {
      final spots = _channelData[channel]?.where((spot) => spot.x >= earliestTime && spot.x <= latestTime).toList() ?? [];
      _graphSegments.add({
        'channel': channel,
        'spots': spots,
      });
    }
  }

  void _updateGraphSegments() {
    setState(() {
      _calculateGraphSegments();
    });
  }

  void _showChannelSelectionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        List<String> tempSelectedChannels = List.from(_selectedChannels);
        return AlertDialog(
          title: const Text('Select Channels'),
          content: SingleChildScrollView(
            child: Column(
              children: _availableChannels.map((channel) {
                return CheckboxListTile(
                  title: Text(channel),
                  value: tempSelectedChannels.contains(channel),
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        tempSelectedChannels.add(channel);
                      } else {
                        tempSelectedChannels.remove(channel);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedChannels = tempSelectedChannels;
                  if (_selectedChannels.isEmpty && _availableChannels.isNotEmpty) {
                    _selectedChannels = [_availableChannels.first];
                  }
                  if (_xAxisChannel != null && !_selectedChannels.contains(_xAxisChannel)) {
                    _xAxisChannel = null;
                  }
                  _calculateGraphSegments();
                });
                Navigator.of(dialogContext).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showColorPickerDialog(String channel) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        Color selectedColor = _channelColors[channel] ?? Colors.blue;
        return AlertDialog(
          title: Text('Select Color for $channel'),
          content: SingleChildScrollView(
            child: BlockPicker(
              pickerColor: selectedColor,
              onColorChanged: (color) {
                selectedColor = color;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _channelColors[channel] = selectedColor;
                });
                Navigator.of(dialogContext).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Channel ${widget.channel} Data',
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.blueAccent,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showChannelSelectionDialog,
            tooltip: 'Select Channels',
          ),
          IconButton(
            icon: const Icon(Icons.color_lens),
            onPressed: () {
              if (_selectedChannels.isNotEmpty) {
                _showColorPickerDialog(_selectedChannels.first);
              }
            },
            tooltip: 'Change Channel Color',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Max Load Values:',
              style: GoogleFonts.montserrat(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              children: _maxLoadValues.entries.map((entry) {
                return Text(
                  '${entry.key}: ${entry.value.toStringAsFixed(2)}',
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    color: _channelColors[entry.key] ?? Colors.black,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _graphVisibleMinController,
                    decoration: const InputDecoration(
                      labelText: 'Visible Minutes',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _graphVisibleHrController,
                    decoration: const InputDecoration(
                      labelText: 'Visible Hours',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: true),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toStringAsFixed(2),
                            style: GoogleFonts.montserrat(fontSize: 12),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toStringAsFixed(2),
                            style: GoogleFonts.montserrat(fontSize: 12),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: true),
                  minX: _minX,
                  maxX: _maxX,
                  minY: _minY,
                  maxY: _maxY,
                  lineBarsData: _graphSegments.map((segment) {
                    final channel = segment['channel'] as String;
                    final spots = segment['spots'] as List<FlSpot>;
                    return LineChartBarData(
                      spots: spots,
                      isCurved: false,
                      color: _channelColors[channel] ?? Colors.blue,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: false),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}