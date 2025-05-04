import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../constants/colors.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../constants/export.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import '../../constants/global.dart';
import '../homepage.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

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
  final _testDurationDayController = TextEditingController(text: '0'); // Added day controller
  final _testDurationHrController = TextEditingController(text: '0');
  final _testDurationMinController = TextEditingController(text: '0');
  final _testDurationSecController = TextEditingController(text: '0');
  final _graphVisibleHrController = TextEditingController(text: '0');
  final _graphVisibleMinController = TextEditingController(text: '60');
  final ScrollController _tableHorizontalScrollController = ScrollController();
  final ScrollController _tableVerticalScrollController = ScrollController();
  final GlobalKey _graphKey = GlobalKey();

  bool isDisplaying = false;
  String? selectedChannel;
  List<Map<String, dynamic>> tableData = [];
  Map<int, String> channelNames = {};
  Map<int, Color> channelColors = {};
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

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _animationController = AnimationController(vsync: this, duration: Duration(milliseconds: 500));
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(_animationController);
    _graphVisibleMinController.addListener(_updateGraphSegments);

    Global.selectedRecNo?.addListener(_onRecNoChanged);
    Global.selectedFileName.addListener(_onGlobalChanged);
    Global.operatorName.addListener(_onGlobalChanged);
    Global.scanningRateHH.addListener(_onGlobalChanged);
    Global.scanningRateMM.addListener(_onGlobalChanged);
    Global.scanningRateSS.addListener(_onGlobalChanged);
    Global.testDurationDD?.addListener(_onGlobalChanged); // Added for day
    Global.testDurationHH.addListener(_onGlobalChanged);
    Global.testDurationMM.addListener(_onGlobalChanged);
    Global.testDurationSS.addListener(_onGlobalChanged);

    fetchData(showFull: true);
    print('[INIT_STATE] Initialized OpenFilePage with fileName: ${widget.fileName}');
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
    print('[INITIALIZE_CONTROLLERS] Controllers initialized with values: '
        'fileName=${_fileNameController.text}, '
        'operator=${_operatorController.text}, '
        'testDurationDay=${_testDurationDayController.text}');
  }

  void _onRecNoChanged() {
    if (!mounted) return;
    fetchData(showFull: true);
    print('[ON_REC_NO_CHANGED] RecNo changed, fetching new data');
  }

  void _onGlobalChanged() {
    if (!mounted) return;
    setState(() {
      _initializeControllers();
    });
    print('[ON_GLOBAL_CHANGED] Global values changed, reinitializing controllers');
  }

  Future<void> fetchData({bool showFull = false}) async {
    if (Global.selectedRecNo?.value == null) return;
    try {
      final test1Response = await http.get(
        Uri.parse('http://localhost/Table/getData.php?type=Test1&RecNo=${Global.selectedRecNo!.value}'),
      );
      print('[FETCH_DATA] Test1 response: ${test1Response.body}');
      final test2Response = await http.get(
        Uri.parse('http://localhost/Table/getData.php?type=Test2&RecNo=${Global.selectedRecNo!.value}'),
      );
      print('[FETCH_DATA] Test2 response: ${test2Response.body}');

      if (test1Response.statusCode == 200 && test2Response.statusCode == 200) {
        setState(() {
          var jsonData = json.decode(test1Response.body);
          if (jsonData['data'] is List) {
            tableData = (jsonData['data'] as List<dynamic>).map((item) => item as Map<String, dynamic>).toList();
          } else {
            tableData = [];
          }

          var test2Data = json.decode(test2Response.body)['data'];
          if (test2Data is List && test2Data.isNotEmpty) {
            test2Data = test2Data[0];
          } else {
            test2Data = {};
          }

          channelNames.clear();
          channelColors.clear();
          maxLoadValues.clear();
          List<int> channelIndices = [];
          for (int i = 1; i <= 50; i++) {
            String? name = test2Data['ChannelName$i']?.toString().trim();
            if (name != null && name.isNotEmpty && name != 'null') {
              channelIndices.add(i);
              channelNames[i] = name;
              channelColors[i] = _getDefaultColor(i);
              print('[FETCH_DATA] Loaded channel $i: $name');
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
              print('[FETCH_DATA] Channel $i is null or empty');
              break;
            }
          }

          selectedChannel = channelNames.isNotEmpty ? 'All' : null;
          _calculateGraphSegments();
          _calculateYRange();
          _initializeControllers();
        });
        print('[FETCH_DATA] Data fetched successfully, tableData length: ${tableData.length}, channels: ${channelNames.length}');
      }
    } catch (e) {
      print('[FETCH_DATA] Error fetching data: $e');
    }
  }

  Color _getDefaultColor(int index) {
    const List<Color> defaultColors = [
      Color(0xFF0288D1),
      Color(0xFFD81B60),
      Color(0xFF388E3C),
      Color(0xFFFFA500),
      Color(0xFF8E24AA),
      Color(0xFF7B1FA2),
      Color(0xFF1976D2),
      Color(0xFFE91E63),
      Color(0xFF009688),
      Color(0xFFFBC02D),
      Color(0xFF4CAF50),
      Color(0xFFF44336),
      Color(0xFF9C27B0),
      Color(0xFF673AB7),
      Color(0xFF3F51B5),
    ];
    return defaultColors[(index - 1) % defaultColors.length];
  }

  void _showColorPicker(int channelIndex) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select Color for ${channelNames[channelIndex]}'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: channelColors[channelIndex]!,
            onColorChanged: (Color color) {
              setState(() {
                channelColors[channelIndex] = color;
              });
            },
            showLabel: true,
            pickerAreaHeightPercent: 0.8,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Done', style: GoogleFonts.roboto(color: AppColors.submitButton)),
          ),
        ],
      ),
    );
    print('[SHOW_COLOR_PICKER] Opened color picker for channel $channelIndex');
  }

  void _updateGraphSegments() {
    setState(() {
      Global.graphVisibleArea.value = '${_graphVisibleHrController.text}:${_graphVisibleMinController.text}';
      _calculateGraphSegments();
    });
    print('[UPDATE_GRAPH_SEGMENTS] Updated graph segments, visible area: ${Global.graphVisibleArea.value}');
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
      } catch (e) {
        return 0.0;
      }
    }).toList();

    if (timeSecondsList.isEmpty) {
      startTimeSeconds = 0;
      totalSegments = 1;
      currentSegment = 0;
      return;
    }

    startTimeSeconds = timeSecondsList.reduce((a, b) => a < b ? a : b);
    double endTimeSeconds = timeSecondsList.reduce((a, b) => a > b ? a : b);
    double totalTimeSeconds = endTimeSeconds - startTimeSeconds;

    int segmentHours = int.tryParse(_graphVisibleHrController.text) ?? 0;
    int segmentMinutes = int.tryParse(_graphVisibleMinController.text) ?? 60;
    double segmentSeconds = (segmentHours * 3600) + (segmentMinutes * 60);

    totalSegments = (totalTimeSeconds / segmentSeconds).ceil();
    if (totalSegments < 1) totalSegments = 1;
    if (currentSegment >= totalSegments) currentSegment = totalSegments - 1;
    print('[CALCULATE_GRAPH_SEGMENTS] Segments calculated: total=$totalSegments, current=$currentSegment');
  }

  void _calculateYRange({List<Map<String, dynamic>>? data}) {
    final dataToUse = data ?? tableData;
    if (dataToUse.isEmpty || selectedChannel == null || channelNames.isEmpty) {
      minYValue = 0;
      maxYValue = 1000;
      return;
    }

    List<double> allValues = [];
    if (selectedChannel == 'All') {
      for (int channelIndex in channelNames.keys) {
        var values = dataToUse
            .map((row) => (row['AbsPer$channelIndex'] as num?)?.toDouble())
            .where((value) => value != null && value != 0)
            .cast<double>()
            .toList();
        allValues.addAll(values);
      }
    } else {
      if (int.tryParse(selectedChannel!) != null) {
        int channelIndex = int.parse(selectedChannel!);
        if (channelNames.containsKey(channelIndex)) {
          allValues = dataToUse
              .map((row) => (row['AbsPer$channelIndex'] as num?)?.toDouble())
              .where((value) => value != null && value != 0)
              .cast<double>()
              .toList();
        }
      }
    }

    if (allValues.isEmpty) {
      minYValue = 0;
      maxYValue = 1000;
      return;
    }

    minYValue = allValues.reduce((a, b) => a < b ? a : b);
    maxYValue = allValues.reduce((a, b) => a > b ? a : b);

    double padding = (maxYValue - minYValue) * 0.1 * zoomLevel;
    minYValue -= padding;
    maxYValue += padding;

    if (minYValue == maxYValue) {
      minYValue -= 10;
      maxYValue += 10;
    }
    print('[CALCULATE_Y_RANGE] Y range calculated: min=$minYValue, max=$maxYValue');
  }

  Future<Uint8List?> _captureGraph({List<Map<String, dynamic>>? filteredData}) async {
    try {
      if (filteredData != null && filteredData.isNotEmpty) {
        // Store original state
        final originalTableData = List<Map<String, dynamic>>.from(tableData);
        final originalSegment = currentSegment;
        final originalMinY = minYValue;
        final originalMaxY = maxYValue;

        // Update state for capture
        setState(() {
          tableData = filteredData;
          currentSegment = 0; // Show full range
          _calculateYRange(data: filteredData);
        });

        // Wait for the UI to render the updated graph
        await Future.delayed(Duration(milliseconds: 200));

        RenderRepaintBoundary? boundary = _graphKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary == null) {
          print('[CAPTURE_GRAPH] Error: RenderRepaintBoundary not found');
          // Restore original state
          setState(() {
            tableData = originalTableData;
            currentSegment = originalSegment;
            minYValue = originalMinY;
            maxYValue = originalMaxY;
          });
          return null;
        }

        ui.Image image = await boundary.toImage(pixelRatio: 3.0);
        ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

        // Restore original state
        setState(() {
          tableData = originalTableData;
          currentSegment = originalSegment;
          minYValue = originalMinY;
          maxYValue = originalMaxY;
        });

        return byteData?.buffer.asUint8List();
      } else {
        RenderRepaintBoundary? boundary = _graphKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary == null) {
          print('[CAPTURE_GRAPH] Error: RenderRepaintBoundary not found');
          return null;
        }
        ui.Image image = await boundary.toImage(pixelRatio: 3.0);
        ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        return byteData?.buffer.asUint8List();
      }
    } catch (e) {
      print('[CAPTURE_GRAPH] Error capturing graph: $e');
      return null;
    }
  }

  Widget _buildGraphNavigation() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              IconButton(
                icon: Icon(Icons.zoom_in, size: 24),
                onPressed: () {
                  setState(() {
                    zoomLevel *= 1.2;
                    _animationController.forward(from: 0);
                    _calculateYRange();
                  });
                  print('[ZOOM_IN] Zoom level increased to $zoomLevel');
                },
                tooltip: 'Zoom In',
              ),
              IconButton(
                icon: Icon(Icons.zoom_out, size: 24),
                onPressed: () {
                  setState(() {
                    zoomLevel /= 1.2;
                    if (zoomLevel < 1.0) zoomLevel = 1.0;
                    _animationController.forward(from: 0);
                    _calculateYRange();
                  });
                  print('[ZOOM_OUT] Zoom level decreased to $zoomLevel');
                },
                tooltip: 'Zoom Out',
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(Icons.chevron_left, size: 16, color: AppColors.textPrimary),
                      onPressed: currentSegment > 0 ? () => setState(() => currentSegment--) : null,
                      tooltip: 'Previous Segment',
                    ),
                    Text(
                      'Segment ${currentSegment + 1}/$totalSegments',
                      style: GoogleFonts.roboto(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.chevron_right, size: 16, color: AppColors.textPrimary),
                      onPressed: currentSegment < totalSegments - 1 ? () => setState(() => currentSegment++) : null,
                      tooltip: 'Next Segment',
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.arrow_circle_up, color: showPeak ? Colors.red : null),
                onPressed: () {
                  setState(() {
                    showPeak = !showPeak;
                    if (showPeak && selectedChannel != null && selectedChannel != 'All') {
                      int channelIndex = int.parse(selectedChannel!);
                      double? maxLoadValue = maxLoadValues[channelIndex];
                      if (maxLoadValue != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Peak Value: ${maxLoadValue.toStringAsFixed(2)} (${channelNames[channelIndex]})',
                              style: GoogleFonts.roboto(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            duration: Duration(seconds: 3),
                            backgroundColor: Colors.red.withOpacity(0.9),
                          ),
                        );
                        _highlightPeakOnGraph();
                      }
                    }
                  });
                  print('[SHOW_PEAK] Peak visibility toggled: $showPeak');
                },
                tooltip: 'Show Peak Value',
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: Icon(showDataPoints ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => showDataPoints = !showDataPoints),
                tooltip: 'Toggle Data Points',
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildChannelLegend(),
        ],
      ),
    );
  }

  Widget _buildChannelLegend() {
    return Wrap(
      spacing: 16,
      children: channelNames.entries.map((entry) {
        int channelIndex = entry.key;
        String channelName = entry.value;
        return GestureDetector(
          onTap: () => _showColorPicker(channelIndex),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: channelColors[channelIndex],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                channelName,
                style: GoogleFonts.roboto(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  void _highlightPeakOnGraph() {
    if (selectedChannel == null || selectedChannel == 'All' || int.tryParse(selectedChannel!) == null) return;

    int channelIndex = int.parse(selectedChannel!);
    double? maxLoadValue = maxLoadValues[channelIndex];
    if (maxLoadValue != null && tableData.isNotEmpty) {
      int peakIndex = tableData.indexWhere((row) => (row['AbsPer$channelIndex'] as num?)?.toDouble() == maxLoadValue);
      if (peakIndex != -1) {
        List<String> timeParts = (tableData[peakIndex]['AbsTime'] as String).split(':');
        double peakTimeSeconds = int.parse(timeParts[0]) * 3600 +
            int.parse(timeParts[1]) * 60 +
            double.parse(timeParts[2]);
        int segmentHours = int.tryParse(_graphVisibleHrController.text) ?? 0;
        int segmentMinutes = int.tryParse(_graphVisibleMinController.text) ?? 60;
        double segmentSeconds = (segmentHours * 3600) + (segmentMinutes * 60);
        int targetSegment = ((peakTimeSeconds - startTimeSeconds) / segmentSeconds).floor();
        if (targetSegment != currentSegment) {
          setState(() {
            currentSegment = targetSegment;
          });
          print('[HIGHLIGHT_PEAK] Moved to segment $targetSegment to highlight peak');
        }
      }
    }
  }

  String _getUnitForChannel(String channelName) {
    if (channelName.toLowerCase() == 'load') return 'kN';
    return '%';
  }

  Widget _buildGraph({List<Map<String, dynamic>>? filteredData}) {
    final dataToUse = filteredData ?? tableData;
    if (dataToUse.isEmpty) {
      return Center(
        child: Text(
          'No data available',
          style: TextStyle(fontSize: 16, color: Colors.black54),
        ),
      );
    }

    if (channelNames.isEmpty || selectedChannel == null) {
      return Center(
        child: Text(
          'No channel data available',
          style: TextStyle(fontSize: 16, color: Colors.black54),
        ),
      );
    }

    int segmentHours = int.tryParse(_graphVisibleHrController.text) ?? 0;
    int segmentMinutes = int.tryParse(_graphVisibleMinController.text) ?? 60;
    double segmentSeconds = (segmentHours * 3600) + (segmentMinutes * 60);
    double segmentStartTimeSeconds = startTimeSeconds + (currentSegment * segmentSeconds);
    double segmentEndTimeSeconds = segmentStartTimeSeconds + segmentSeconds;

    List<Map<String, dynamic>> segmentData = dataToUse.where((row) {
      try {
        List<String> timeParts = (row['AbsTime'] as String).split(':');
        double timeSeconds = int.parse(timeParts[0]) * 3600 +
            int.parse(timeParts[1]) * 60 +
            double.parse(timeParts[2]);
        return timeSeconds >= segmentStartTimeSeconds && timeSeconds < segmentEndTimeSeconds;
      } catch (e) {
        return false;
      }
    }).toList();

    List<LineChartBarData> lineBarsData = [];
    List<int> channelsToPlot = selectedChannel == 'All' ? channelNames.keys.toList() : (int.tryParse(selectedChannel!) != null ? [int.parse(selectedChannel!)] : []);

    Map<double, String> timeToLabel = {};
    List<FlSpot> allSpots = [];

    for (int channelIndex in channelsToPlot) {
      List<FlSpot> spots = [];
      for (int i = 0; i < segmentData.length; i++) {
        var row = segmentData[i];
        try {
          String absTime = row['AbsTime'] as String;
          if (!absTime.contains(RegExp(r'^\d{2}:\d{2}:\d{2}$'))) continue;
          List<String> timeParts = absTime.split(':');
          double timeSeconds = int.parse(timeParts[0]) * 3600 +
              int.parse(timeParts[1]) * 60 +
              double.parse(timeParts[2]);
          double xValue = timeSeconds - (filteredData != null ? startTimeSeconds : segmentStartTimeSeconds);
          timeToLabel[xValue] = absTime;
          double load = (row['AbsPer$channelIndex'] as num?)?.toDouble() ?? 0.0;
          if (load != 0) {
            spots.add(FlSpot(xValue, load));
            allSpots.add(FlSpot(xValue, load));
          }
        } catch (e) {
          continue;
        }
      }

      if (spots.isNotEmpty) {
        lineBarsData.add(
          LineChartBarData(
            spots: spots,
            isCurved: true,
            barWidth: 3,
            color: channelColors[channelIndex] ?? Colors.grey,
            dotData: FlDotData(
              show: showDataPoints || (showPeak && selectedChannel != 'All' && maxLoadValues[channelIndex] != null),
              getDotPainter: (spot, percent, barData, index) {
                if (spot.y == maxLoadValues[channelIndex] && showPeak && selectedChannel != 'All') {
                  return FlDotCirclePainter(
                    radius: 8,
                    color: Colors.red,
                    strokeWidth: 2,
                    strokeColor: Colors.white,
                  );
                }
                return FlDotCirclePainter(
                  radius: 4,
                  color: channelColors[channelIndex] ?? Colors.grey,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: selectedChannel != 'All',
              gradient: LinearGradient(
                colors: [
                  (channelColors[channelIndex] ?? Colors.grey).withOpacity(0.3),
                  (channelColors[channelIndex] ?? Colors.grey).withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        );
      }
    }

    if (lineBarsData.isEmpty) {
      return Center(
        child: Text(
          'No data in current segment',
          style: TextStyle(fontSize: 16, color: Colors.black54),
        ),
      );
    }

    double minX = 0;
    double maxX = allSpots.isNotEmpty
        ? allSpots.map((spot) => spot.x).reduce((a, b) => a > b ? a : b)
        : segmentSeconds;

    double labelInterval = maxX / 5;
    Map<double, String> displayTimeLabels = {};
    for (double x = 0; x <= maxX; x += labelInterval) {
      double absoluteTimeSeconds = (filteredData != null ? startTimeSeconds : segmentStartTimeSeconds) + x;
      int hours = (absoluteTimeSeconds / 3600).floor();
      int minutes = ((absoluteTimeSeconds % 3600) / 60).floor();
      int seconds = (absoluteTimeSeconds % 60).floor();
      String label = '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
      displayTimeLabels[x] = label;
    }

    return Card(
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, Colors.grey.shade50],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            _buildGraphNavigation(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: RepaintBoundary(
                  key: _graphKey,
                  child: LineChart(
                    LineChartData(
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (_) => Colors.white.withOpacity(0.9),
                          tooltipRoundedRadius: 8,
                          tooltipPadding: EdgeInsets.all(8),
                          getTooltipItems: (List<LineBarSpot> touchedSpots) {
                            return touchedSpots.map((touchedSpot) {
                              int barIndex = touchedSpot.barIndex;
                              int channelIndex = selectedChannel == 'All'
                                  ? channelNames.keys.toList()[barIndex]
                                  : int.parse(selectedChannel!);
                              String xText = timeToLabel[touchedSpot.x] ?? 'Unknown';
                              String unit = _getUnitForChannel(channelNames[channelIndex]!);
                              return LineTooltipItem(
                                '${touchedSpot.y.toStringAsFixed(2)} $unit\n$xText',
                                GoogleFonts.roboto(
                                  color: channelColors[channelIndex] ?? Colors.grey,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              );
                            }).toList();
                          },
                        ),
                        handleBuiltInTouches: true,
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawHorizontalLine: true,
                        drawVerticalLine: true,
                        horizontalInterval: (maxYValue - minYValue) / 5,
                        verticalInterval: labelInterval,
                        getDrawingHorizontalLine: (value) {
                          return FlLine(
                            color: Colors.grey.withOpacity(0.3),
                            strokeWidth: 1,
                            dashArray: [5, 5],
                          );
                        },
                        getDrawingVerticalLine: (value) {
                          return FlLine(
                            color: Colors.grey.withOpacity(0.3),
                            strokeWidth: 1,
                            dashArray: [5, 5],
                          );
                        },
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          axisNameWidget: Text(
                            'Value (${_getUnitForChannel(selectedChannel == 'All' ? 'Mixed' : channelNames[int.tryParse(selectedChannel!) ?? channelNames.keys.first]!)})',
                            style: GoogleFonts.roboto(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            interval: (maxYValue - minYValue) / 5,
                            getTitlesWidget: (value, meta) => Text(
                              value.toStringAsFixed(0),
                              style: GoogleFonts.roboto(
                                fontSize: 12,
                                color: AppColors.textPrimary.withOpacity(0.7),
                              ),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          axisNameWidget: Text(
                            'Time (HH:mm:ss)',
                            style: GoogleFonts.roboto(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            interval: labelInterval,
                            getTitlesWidget: (value, meta) {
                              if (displayTimeLabels.containsKey(value)) {
                                return Text(
                                  displayTimeLabels[value]!,
                                  style: GoogleFonts.roboto(
                                    fontSize: 12,
                                    color: AppColors.textPrimary.withOpacity(0.7),
                                  ),
                                );
                              }
                              return Text('');
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1),
                      ),
                      minX: minX,
                      maxX: maxX,
                      minY: minYValue,
                      maxY: maxYValue,
                      lineBarsData: lineBarsData,
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

  Widget _buildDataTable() {
    return Container(
      height: 400,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        color: Colors.white,
      ),
      child: tableData.isEmpty
          ? Center(
        child: Text(
          'No data available',
          style: GoogleFonts.roboto(
            fontSize: 18,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
      )
          : Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              controller: _tableVerticalScrollController,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: _tableHorizontalScrollController,
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.headerBackground,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      ),
                      child: Row(
                        children: [
                          _buildHeaderCell('No', width: 60, isNumeric: true),
                          _buildHeaderCell('Time', width: 100),
                          _buildHeaderCell('Date', width: 120),
                          ...channelNames.entries
                              .map((entry) => _buildHeaderCell(entry.value, width: 100, isNumeric: true)),
                        ],
                      ),
                    ),
                    ...tableData.map((data) {
                      String displayDate = 'N/A';
                      try {
                        if (data['AbsDate'] is String) {
                          displayDate = data['AbsDate'].toString().substring(0, 10);
                        } else if (data['AbsDate'] is Map) {
                          displayDate = data['AbsDate']['date']?.substring(0, 10) ?? 'N/A';
                        }
                      } catch (e) {
                        print('[BUILD_DATA_TABLE] Error parsing AbsDate: $e');
                      }

                      return Row(
                        children: [
                          _buildDataCell('${data['SNo']}', width: 60, isNumeric: true, isMax: false),
                          _buildDataCell(data['AbsTime'], width: 100, isMax: false),
                          _buildDataCell(displayDate, width: 120, isMax: false),
                          ...channelNames.keys.map((channelIndex) {
                            double? value = (data['AbsPer$channelIndex'] as num?)?.toDouble();
                            bool isMax = isDisplaying &&
                                value != null &&
                                value == maxLoadValues[channelIndex];
                            String displayValue =
                            value == null || value == 0.0 ? '-' : value.toStringAsFixed(2);
                            return _buildDataCell(
                              displayValue,
                              width: 100,
                              isNumeric: true,
                              isMax: isMax,
                            );
                          }),
                        ],
                      );
                    }).toList(),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_upward, color: AppColors.textPrimary, size: 20),
                  onPressed: () {
                    if (_tableVerticalScrollController.hasClients) {
                      _tableVerticalScrollController.animateTo(
                        _tableVerticalScrollController.offset - 50,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                      print('[TABLE_SCROLL] Scrolled up vertically');
                    }
                  },
                  tooltip: 'Scroll Up',
                ),
                IconButton(
                  icon: Icon(Icons.arrow_downward, color: AppColors.textPrimary, size: 20),
                  onPressed: () {
                    if (_tableVerticalScrollController.hasClients) {
                      _tableVerticalScrollController.animateTo(
                        _tableVerticalScrollController.offset + 50,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                      print('[TABLE_SCROLL] Scrolled down vertically');
                    }
                  },
                  tooltip: 'Scroll Down',
                ),
                IconButton(
                  icon: Icon(Icons.arrow_back, color: AppColors.textPrimary, size: 20),
                  onPressed: () {
                    if (_tableHorizontalScrollController.hasClients) {
                      _tableHorizontalScrollController.animateTo(
                        _tableHorizontalScrollController.offset - 50,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                      print('[TABLE_SCROLL] Scrolled left horizontally');
                    }
                  },
                  tooltip: 'Scroll Left',
                ),
                IconButton(
                  icon: Icon(Icons.arrow_forward, color: AppColors.textPrimary, size: 20),
                  onPressed: () {
                    if (_tableHorizontalScrollController.hasClients) {
                      _tableHorizontalScrollController.animateTo(
                        _tableHorizontalScrollController.offset + 50,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                      print('[TABLE_SCROLL] Scrolled right horizontally');
                    }
                  },
                  tooltip: 'Scroll Right',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text, {required double width, bool isNumeric = false}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
      child: Text(
        text,
        style: GoogleFonts.roboto(
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
          fontSize: 14,
        ),
        textAlign: isNumeric ? TextAlign.right : TextAlign.left,
      ),
    );
  }

  Widget _buildDataCell(String text, {required double width, bool isNumeric = false, bool isMax = false}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey[200]!, width: 0.5)),
      ),
      child: Text(
        text,
        style: GoogleFonts.roboto(
          color: isMax ? Colors.red : AppColors.textPrimary.withOpacity(0.8),
          fontSize: 13,
          fontWeight: isMax ? FontWeight.bold : FontWeight.normal,
        ),
        textAlign: isNumeric ? TextAlign.right : TextAlign.left,
      ),
    );
  }

  Widget _buildTimeInputField(TextEditingController controller, String label, {bool compact = false}) {
    return SizedBox(
      width: compact ? 50 : 60,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.roboto(
              color: AppColors.textPrimary.withOpacity(0.7), fontSize: compact ? 12 : 14),
          filled: true,
          fillColor: Colors.grey[50],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          contentPadding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: compact ? 8 : 12),
        ),
        style: GoogleFonts.roboto(color: AppColors.textPrimary, fontSize: compact ? 12 : 14),
        onChanged: (value) {
          switch (label) {
            case 'Day':
              if (controller == _testDurationDayController) Global.testDurationDD?.value = int.tryParse(value);
              break;
            case 'Hr':
              if (controller == _scanRateHrController) Global.scanningRateHH.value = int.tryParse(value);
              if (controller == _testDurationHrController) Global.testDurationHH.value = int.tryParse(value);
              if (controller == _graphVisibleHrController) _updateGraphSegments();
              break;
            case 'Min':
              if (controller == _scanRateMinController) Global.scanningRateMM.value = int.tryParse(value);
              if (controller == _testDurationMinController) Global.testDurationMM.value = int.tryParse(value);
              if (controller == _graphVisibleMinController) _updateGraphSegments();
              break;
            case 'Sec':
              if (controller == _scanRateSecController) Global.scanningRateSS.value = int.tryParse(value);
              if (controller == _testDurationSecController) Global.testDurationSS.value = int.tryParse(value);
              break;
          }
        },
      ),
    );
  }

  Widget _buildControlButton(String text, VoidCallback onPressed, {Color? color, bool? disabled}) {
    return ElevatedButton(
      onPressed: disabled == true ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color ?? AppColors.submitButton,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
      child: Text(
        text,
        style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildDateTimeDisplay() {
    final now = DateTime.now();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.1), spreadRadius: 1, blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.access_time, size: 16, color: AppColors.submitButton),
          const SizedBox(width: 8),
          Text(
            '${now.hour}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
            style: GoogleFonts.roboto(color: AppColors.textPrimary, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 16),
          Icon(Icons.calendar_today, size: 16, color: AppColors.submitButton),
          const SizedBox(width: 8),
          Text(
            '${now.day}/${now.month}/${now.year}',
            style: GoogleFonts.roboto(color: AppColors.textPrimary, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Future<Map<String, String>?> _showTimeRangeDialog() async {
    final fromController = TextEditingController();
    final toController = TextEditingController();
    String? errorMessage;

    String defaultFromTime = '00:00:00';
    String defaultToTime = '23:59:59';
    if (tableData.isNotEmpty) {
      List<double> timeSecondsList = tableData.map((row) {
        try {
          List<String> timeParts = (row['AbsTime'] as String).split(':');
          return int.parse(timeParts[0]) * 3600 + int.parse(timeParts[1]) * 60 + double.parse(timeParts[2]);
        } catch (e) {
          return double.infinity;
        }
      }).toList();
      if (timeSecondsList.isNotEmpty) {
        double minTimeSeconds = timeSecondsList.reduce((a, b) => a < b ? a : b);
        double maxTimeSeconds = timeSecondsList.reduce((a, b) => a > b ? a : b);
        int minHours = (minTimeSeconds / 3600).floor();
        int minMinutes = ((minTimeSeconds % 3600) / 60).floor();
        int minSeconds = (minTimeSeconds % 60).floor();
        int maxHours = (maxTimeSeconds / 3600).floor();
        int maxMinutes = ((maxTimeSeconds % 3600) / 60).floor();
        int maxSeconds = (maxTimeSeconds % 60).floor();
        defaultFromTime =
        '${minHours.toString().padLeft(2, '0')}:${minMinutes.toString().padLeft(2, '0')}:${minSeconds.toString().padLeft(2, '0')}';
        defaultToTime =
        '${maxHours.toString().padLeft(2, '0')}:${maxMinutes.toString().padLeft(2, '0')}:${maxSeconds.toString().padLeft(2, '0')}';
      }
    }

    fromController.text = defaultFromTime;
    toController.text = defaultToTime;

    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: Colors.white,
          title: Row(
            children: [
              Icon(Icons.access_time, color: AppColors.submitButton, size: 24),
              const SizedBox(width: 8),
              Text(
                'Select Time Range',
                style: GoogleFonts.roboto(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          content: Container(
            width: 350,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: fromController,
                  decoration: InputDecoration(
                    labelText: 'From Time (HH:mm:ss)',
                    hintText: 'e.g., 00:00:00',
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: Icon(Icons.schedule, color: AppColors.submitButton),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                  keyboardType: TextInputType.datetime,
                  style: GoogleFonts.roboto(color: AppColors.textPrimary, fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: toController,
                  decoration: InputDecoration(
                    labelText: 'To Time (HH:mm:ss)',
                    hintText: 'e.g., 23:59:59',
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: Icon(Icons.schedule, color: AppColors.submitButton),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                  keyboardType: TextInputType.datetime,
                  style: GoogleFonts.roboto(color: AppColors.textPrimary, fontSize: 14),
                ),
                if (errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    // child: Text(
                    //   errorMessage,
                    //   style: GoogleFonts.roboto(color: Colors.red, fontSize: 12),
                    // ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text(
                'Cancel',
                style: GoogleFonts.roboto(color: Colors.grey[600], fontWeight: FontWeight.w500),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                final timeFormat = RegExp(r'^\d{2}:\d{2}:\d{2}$');
                if (!timeFormat.hasMatch(fromController.text) || !timeFormat.hasMatch(toController.text)) {
                  setDialogState(() {
                    errorMessage = 'Please enter times in HH:mm:ss format';
                  });
                  return;
                }

                try {
                  List<String> fromParts = fromController.text.split(':');
                  List<String> toParts = toController.text.split(':');
                  double fromSeconds = int.parse(fromParts[0]) * 3600 +
                      int.parse(fromParts[1]) * 60 +
                      double.parse(fromParts[2]);
                  double toSeconds = int.parse(toParts[0]) * 3600 +
                      int.parse(toParts[1]) * 60 +
                      double.parse(toParts[2]);

                  if (fromSeconds >= toSeconds) {
                    setDialogState(() {
                      errorMessage = 'From time must be earlier than To time';
                    });
                    return;
                  }

                  Navigator.of(context).pop({
                    'from': fromController.text,
                    'to': toController.text,
                  });
                  print('[TIME_RANGE_DIALOG] Time range selected: ${fromController.text} to ${toController.text}');
                } catch (e) {
                  setDialogState(() {
                    errorMessage = 'Invalid time format';
                  });
                  print('[TIME_RANGE_DIALOG] Error in time format: $e');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.submitButton,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              child: Text(
                'OK',
                style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _filterDataByTimeRange(String fromTime, String toTime) {
    try {
      List<String> fromParts = fromTime.split(':');
      List<String> toParts = toTime.split(':');
      double fromSeconds = int.parse(fromParts[0]) * 3600 +
          int.parse(fromParts[1]) * 60 +
          double.parse(fromParts[2]);
      double toSeconds = int.parse(toParts[0]) * 3600 + int.parse(toParts[1]) * 60 + double.parse(toParts[2]);

      var filteredData = tableData.where((row) {
        try {
          List<String> timeParts = (row['AbsTime'] as String).split(':');
          double timeSeconds = int.parse(timeParts[0]) * 3600 +
              int.parse(timeParts[1]) * 60 +
              double.parse(timeParts[2]);
          return timeSeconds >= fromSeconds && timeSeconds <= toSeconds;
        } catch (e) {
          return false;
        }
      }).toList();

      print('[FILTER_DATA] Filtered data count: ${filteredData.length}');
      print('[FILTER_DATA] Time range: $fromTime to $toTime');
      print('[FILTER_DATA] Sample data: ${filteredData.take(5).toList()}');

      return filteredData;
    } catch (e) {
      print('[FILTER_DATA] Error filtering data: $e');
      return tableData;
    }
  }

  Map<String, dynamic> _prepareChannelData(String channel) {
    print('[CHANNEL_DATA] Preparing data for channel: $channel');
    Map<String, dynamic> data = {
      'channelName': channel == 'All' ? 'All Channels' : channelNames[int.parse(channel)],
      'dataPoints': [],
    };

    List<Map<String, dynamic>> segmentData = tableData.where((row) {
      try {
        List<String> timeParts = (row['AbsTime'] as String).split(':');
        double timeSeconds = int.parse(timeParts[0]) * 3600 +
            int.parse(timeParts[1]) * 60 +
            double.parse(timeParts[2]);
        double segmentStartTimeSeconds =
            startTimeSeconds + (currentSegment * ((int.tryParse(_graphVisibleHrController.text) ?? 0) * 3600 + (int.tryParse(_graphVisibleMinController.text) ?? 60) * 60));
        double segmentEndTimeSeconds = segmentStartTimeSeconds + ((int.tryParse(_graphVisibleHrController.text) ?? 0) * 3600 + (int.tryParse(_graphVisibleMinController.text) ?? 60) * 60);
        return timeSeconds >= segmentStartTimeSeconds && timeSeconds < segmentEndTimeSeconds;
      } catch (e) {
        return false;
      }
    }).toList();

    if (channel == 'All') {
      for (int channelIndex in channelNames.keys) {
        List<Map<String, dynamic>> points = segmentData.map((row) {
          return {
            'time': row['AbsTime'],
            'value': (row['AbsPer$channelIndex'] as num?)?.toDouble() ?? 0.0,
          };
        }).toList();
        data['dataPoints'].add({
          'channelIndex': channelIndex,
          'channelName': channelNames[channelIndex],
          'points': points,
        });
        print('[CHANNEL_DATA] Added ${points.length} points for channel ${channelNames[channelIndex]} (index $channelIndex)');
      }
    } else {
      int channelIndex = int.parse(channel);
      List<Map<String, dynamic>> points = segmentData.map((row) {
        return {
          'time': row['AbsTime'],
          'value': (row['AbsPer$channelIndex'] as num?)?.toDouble() ?? 0.0,
        };
      }).toList();
      data['dataPoints'] = points;
      print('[CHANNEL_DATA] Added ${points.length} points for channel ${channelNames[channelIndex]} (index $channelIndex)');
    }

    return data;
  }

  Widget _buildChannelSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.1), spreadRadius: 1, blurRadius: 5, offset: const Offset(0, 2)),
        ],
      ),
      child: DropdownButton<String>(
          value: selectedChannel,
          onChanged: (String? newValue) async {
            if (newValue != null) {
              setState(() {
                selectedChannel = newValue;
                _calculateYRange();
              });
              try {
                final channelData = _prepareChannelData(newValue);
                final window = await DesktopMultiWindow.createWindow(jsonEncode({
                  'channel': newValue,
                  'channelData': channelData,
                }));
                window.setFrame(const Offset(0, 0) & const Size(800, 600));
                window.center();
                final channelTitle = newValue == 'All' ? 'All Channels' : channelNames[int.parse(newValue)];
                window.setTitle('Graph for $channelTitle');
                window.show();
                print('[CHANNEL_SELECTOR] Opened new window for channel: $newValue');
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to open new window: $e')),
                );
                print('[CHANNEL_SELECTOR] Error opening new window: $e');
              }
            }
          },
          items: [
          if (channelNames.isNotEmpty)
      DropdownMenuItem<String>(
      value: 'All',
      child: Text(
        'All',
        style: GoogleFonts.roboto(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    ...channelNames.entries.map<DropdownMenuItem<String>>(
    (entry) => DropdownMenuItem<String>(
    value: entry.key.toString(),
    child: Text(
    entry.value,
    style: GoogleFonts.roboto(
    color: AppColors.textPrimary,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    ),
    ),
    ),
    ),
    ],
    underline: Container(),
    icon: Icon(Icons.arrow_drop_down, color: AppColors.textPrimary),
    ),
    );
  }

  Widget _buildFullInputSection() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[200]!)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _fileNameController,
                    decoration: InputDecoration(
                      labelText: 'File Name',
                      labelStyle: GoogleFonts.roboto(color: AppColors.textPrimary.withOpacity(0.7)),
                      filled: true,
                      fillColor: Colors.grey[50],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                    style: GoogleFonts.roboto(color: AppColors.textPrimary),
                    onChanged: (value) => Global.selectedFileName.value = value,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _operatorController,
                    decoration: InputDecoration(
                      labelText: 'Operator',
                      labelStyle: GoogleFonts.roboto(color: AppColors.textPrimary.withOpacity(0.7)),
                      filled: true,
                      fillColor: Colors.grey[50],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                    style: GoogleFonts.roboto(color: AppColors.textPrimary),
                    onChanged: (value) => Global.operatorName.value = value,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Scan Rate:', style: GoogleFonts.roboto(color: AppColors.textPrimary, fontWeight: FontWeight.w500, fontSize: 14)),
                      const SizedBox(width: 8),
                      _buildTimeInputField(_scanRateHrController, 'Hr'),
                      const SizedBox(width: 8),
                      _buildTimeInputField(_scanRateMinController, 'Min'),
                      const SizedBox(width: 8),
                      _buildTimeInputField(_scanRateSecController, 'Sec'),
                    ],
                  ),
                ),
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Test Duration:', style: GoogleFonts.roboto(color: AppColors.textPrimary, fontWeight: FontWeight.w500, fontSize: 14)),
                      const SizedBox(width: 4),
                      _buildTimeInputField(_testDurationDayController, 'Day'),
                      const SizedBox(width: 4),
                      _buildTimeInputField(_testDurationHrController, 'Hr'),
                      const SizedBox(width: 4),
                      _buildTimeInputField(_testDurationMinController, 'Min'),
                      const SizedBox(width: 4),
                      _buildTimeInputField(_testDurationSecController, 'Sec'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFullInputSection(),
        const SizedBox(height: 16),
        if (Global.selectedMode.value == 'Table' || Global.selectedMode.value == 'Combined')
          Expanded(
            child: Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[200]!)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Expanded(child: _buildDataTable()),
                    if (Global.selectedMode.value == 'Table')
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: _buildControlButton(
                          'Export Table',
                              () async {
                            final timeRange = await _showTimeRangeDialog();
                            List<Map<String, dynamic>> filteredData = tableData;
                            if (timeRange != null) {
                              filteredData = _filterDataByTimeRange(timeRange['from']!, timeRange['to']!);
                              print('[EXPORT_TABLE] Exporting table with ${filteredData.length} records from ${timeRange['from']} to ${timeRange['to']}');
                            } else {
                              print('[EXPORT_TABLE] Exporting full table with ${filteredData.length} records');
                            }
                            print('[EXPORT_TABLE] File name: ${_fileNameController.text}');
                            print('[EXPORT_TABLE] Channels included: ${channelNames.values.join(", ")}');
                            ExportUtils.exportBasedOnMode(
                              context: context,
                              mode: 'Table',
                              tableData: filteredData,
                              fileName: _fileNameController.text,
                              graphImage: null,
                            );
                          },
                          color: Colors.blue,
                        ),
                      ),
                    if (Global.selectedMode.value == 'Combined')
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: _buildControlButton(
                          'Export All',
                              () async {
                            final timeRange = await _showTimeRangeDialog();
                            List<Map<String, dynamic>> filteredData = tableData;
                            if (timeRange != null) {
                              filteredData = _filterDataByTimeRange(timeRange['from']!, timeRange['to']!);
                              print('[EXPORT_COMBINED] Exporting combined data with ${filteredData.length} records from ${timeRange['from']} to ${timeRange['to']}');
                            } else {
                              print('[EXPORT_COMBINED] Exporting full combined data with ${filteredData.length} records');
                            }
                            print('[EXPORT_COMBINED] File name: ${_fileNameController.text}');
                            print('[EXPORT_COMBINED] Channels included: ${channelNames.values.join(", ")}');

                            List<Map<String, dynamic>> originalData = List.from(tableData);
                            setState(() {
                              tableData = filteredData;
                              _calculateYRange();
                              _calculateGraphSegments();
                            });
                            print('[EXPORT_COMBINED] Temporarily set tableData to filtered data for graph capture');

                            Uint8List? graphImage = await _captureGraph();
                            print('[EXPORT_COMBINED] Graph image captured: ${graphImage != null ? 'Yes' : 'No'}');

                            setState(() {
                              tableData = originalData;
                              _calculateYRange();
                              _calculateGraphSegments();
                            });
                            print('[EXPORT_COMBINED] Restored original tableData');

                            ExportUtils.exportBasedOnMode(
                              context: context,
                              mode: 'Combined',
                              tableData: filteredData,
                              fileName: _fileNameController.text,
                              graphImage: graphImage,
                            );
                          },
                          color: Colors.blue,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRightSection() {
    if (Global.selectedMode.value == 'Graph') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[200]!)),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _fileNameController,
                        decoration: InputDecoration(
                          labelText: 'File Name',
                          labelStyle: GoogleFonts.roboto(color: AppColors.textPrimary.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.bold),
                          filled: true,
                          fillColor: Colors.grey[50],
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        ),
                        style: GoogleFonts.roboto(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                        onChanged: (value) => Global.selectedFileName.value = value,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _operatorController,
                        decoration: InputDecoration(
                          labelText: 'Operator',
                          labelStyle: GoogleFonts.roboto(color: AppColors.textPrimary.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.bold),
                          filled: true,
                          fillColor: Colors.grey[50],
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        ),
                        style: GoogleFonts.roboto(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                        onChanged: (value) => Global.operatorName.value = value,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Scan Rate:', style: GoogleFonts.roboto(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(width: 4),
                          _buildTimeInputField(_scanRateHrController, 'Hr', compact: true),
                          const SizedBox(width: 4),
                          _buildTimeInputField(_scanRateMinController, 'Min', compact: true),
                          const SizedBox(width: 4),
                          _buildTimeInputField(_scanRateSecController, 'Sec', compact: true),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Test Duration:', style: GoogleFonts.roboto(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(width: 4),
                          _buildTimeInputField(_testDurationDayController, 'Day', compact: true),
                          const SizedBox(width: 4),
                          _buildTimeInputField(_testDurationHrController, 'Hr', compact: true),
                          const SizedBox(width: 4),
                          _buildTimeInputField(_testDurationMinController, 'Min', compact: true),
                          const SizedBox(width: 4),
                          _buildTimeInputField(_testDurationSecController, 'Sec', compact: true),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Segment:', style: GoogleFonts.roboto(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(width: 4),
                          _buildTimeInputField(_graphVisibleHrController, 'Hr', compact: true),
                          const SizedBox(width: 4),
                          _buildTimeInputField(_graphVisibleMinController, 'Min', compact: true),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildChannelSelector(),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[200]!)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Expanded(child: _buildGraph()),
                    const SizedBox(height: 16),
                    _buildControlButton(
                      'Export Graph',
                          () async {
                        final timeRange = await _showTimeRangeDialog();
                        List<Map<String, dynamic>> filteredData = tableData;
                        if (timeRange != null) {
                          filteredData = _filterDataByTimeRange(timeRange['from']!, timeRange['to']!);
                          print('[EXPORT_GRAPH] Exporting graph with ${filteredData.length} records from ${timeRange['from']} to ${timeRange['to']}');
                        } else {
                          print('[EXPORT_GRAPH] Exporting full graph with ${filteredData.length} records');
                        }
                        print('[EXPORT_GRAPH] File name: ${_fileNameController.text}');
                        print('[EXPORT_GRAPH] Channels included: ${channelNames.values.join(", ")}');
                        print('[EXPORT_GRAPH] Sample data (first 5 rows): ${filteredData.take(5).toList()}');
                        Uint8List? graphImage = await _captureGraph(filteredData: filteredData);
                        print('[EXPORT_GRAPH] Graph image captured: ${graphImage != null ? 'Yes' : 'No'}');
                        ExportUtils.exportBasedOnMode(
                          context: context,
                          mode: 'Graph',
                          tableData: filteredData,
                          fileName: _fileNameController.text,
                          graphImage: graphImage,
                        );
                      },
                      color: Colors.blue,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Graph Segment:', style: GoogleFonts.roboto(color: AppColors.textPrimary, fontWeight: FontWeight.w500, fontSize: 14)),
                    const SizedBox(width: 8),
                    _buildTimeInputField(_graphVisibleHrController, 'Hr'),
                    const SizedBox(width: 8),
                    _buildTimeInputField(_graphVisibleMinController, 'Min'),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _buildDateTimeDisplay(),
              const SizedBox(width: 16),
              _buildChannelSelector(),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[200]!)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: _buildGraph(),
              ),
            ),
          ),
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ValueListenableBuilder<String>(
            valueListenable: Global.selectedMode,
            builder: (context, mode, child) {
              print('[BUILD] Building UI for mode: $mode');
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (mode == 'Table' || mode == 'Combined') Expanded(flex: 1, child: _buildLeftSection()),
                  if (mode == 'Graph' || mode == 'Combined') Expanded(flex: 1, child: _buildRightSection()),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    Global.selectedRecNo?.removeListener(_onRecNoChanged);
    Global.selectedFileName.removeListener(_onGlobalChanged);
    Global.operatorName.removeListener(_onGlobalChanged);
    Global.scanningRateHH.removeListener(_onGlobalChanged);
    Global.scanningRateMM.removeListener(_onGlobalChanged);
    Global.scanningRateSS.removeListener(_onGlobalChanged);
    Global.testDurationDD?.removeListener(_onGlobalChanged);
    Global.testDurationHH.removeListener(_onGlobalChanged);
    Global.testDurationMM.removeListener(_onGlobalChanged);
    Global.testDurationSS.removeListener(_onGlobalChanged);

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
    _graphVisibleMinController.removeListener(_updateGraphSegments);
    _graphVisibleMinController.dispose();
    _tableHorizontalScrollController.dispose();
    _tableVerticalScrollController.dispose();
    _animationController.dispose();
    print('[DISPOSE] Disposed all controllers and listeners');
    super.dispose();
  }
}