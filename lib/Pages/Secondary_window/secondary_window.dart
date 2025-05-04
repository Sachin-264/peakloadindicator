import 'dart:convert';
import 'dart:math';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../constants/colors.dart';

class SecondaryWindowApp extends StatefulWidget {
  final String channel;
  final Map<String, dynamic> channelData;

  const SecondaryWindowApp({Key? key, required this.channel, required this.channelData}) : super(key: key);

  @override
  _SecondaryWindowAppState createState() => _SecondaryWindowAppState();
}

class _SecondaryWindowAppState extends State<SecondaryWindowApp> {
  bool _isLoading = true;
  String? _errorMessage;
  double zoomLevel = 1.0;
  bool showGrid = true;
  bool showDataPoints = false;
  bool showPeak = false;
  double minYValue = 0;
  double maxYValue = 1000;
  Map<String, double?> maxLoadValues = {};
  Map<String, Color> channelColors = {};
  Map<String, String> channelNames = {};
  int currentSegment = 0;
  int totalSegments = 1;
  double startTimeSeconds = 0;
  final TextEditingController _graphVisibleHrController = TextEditingController(text: '0');
  final TextEditingController _graphVisibleMinController = TextEditingController(text: '60');
  Map<String, dynamic> _currentChannelData;

  _SecondaryWindowAppState() : _currentChannelData = {};

  @override
  void initState() {
    super.initState();
    _currentChannelData = widget.channelData;
    _initializeChannelData();
    _setupMethodHandler();
    Future.delayed(const Duration(seconds: 1), () {
      setState(() {
        _isLoading = false;
        if (_errorMessage == null) {
          _calculateYRange();
          _calculateMaxLoadValues();
          _calculateGraphSegments();
        }
      });
    });
    _graphVisibleMinController.addListener(_updateGraphSegments);
    _graphVisibleHrController.addListener(_updateGraphSegments);
    print('[INIT_STATE] channel: ${widget.channel}, channelData: ${widget.channelData}');
  }

  void _setupMethodHandler() {
    DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
      if (call.method == 'updateData') {
        try {
          final args = jsonDecode(call.arguments as String) as Map<String, dynamic>;
          setState(() {
            _currentChannelData = args['channelData'] as Map<String, dynamic>;
            _initializeChannelData();
            _calculateYRange();
            _calculateMaxLoadValues();
            _calculateGraphSegments();
          });
          print('[SECONDARY_WINDOW] Received updated data: ${args['channelData']}');
        } catch (e) {
          print('[SECONDARY_WINDOW] Error processing update: $e');
          setState(() {
            _errorMessage = 'Error processing data update: $e';
          });
        }
      } else if (call.method == 'close') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.of(context).pop();
        });
      }
      return null;
    });
  }

  void _initializeChannelData() {
    channelColors.clear();
    channelNames.clear();
    maxLoadValues.clear();
    const List<Color> defaultColors = [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.purple,
      Colors.orange,
      Colors.teal,
      Colors.pink,
      Colors.cyan,
    ];

    try {
      if (widget.channel == 'All') {
        final dataPoints = _currentChannelData['dataPoints'] as List<dynamic>? ?? [];
        for (int i = 0; i < dataPoints.length; i++) {
          final channelData = dataPoints[i];
          final channelIndexRaw = channelData['channelIndex'];
          final channelIndex = channelIndexRaw is int ? channelIndexRaw.toString() : (channelIndexRaw as String? ?? 'Unknown_$i');
          final channelName = channelData['channelName'] as String? ?? 'Channel ${i + 1}';
          channelColors[channelIndex] = defaultColors[i % defaultColors.length];
          channelNames[channelIndex] = channelName;
        }
      } else {
        final channelIndexRaw = widget.channel;
        final channelIndex = channelIndexRaw is int ? channelIndexRaw.toString() : channelIndexRaw;
        channelColors[channelIndex] = defaultColors[0];
        channelNames[channelIndex] = _currentChannelData['channelName'] as String? ?? 'Channel $channelIndex';
      }
    } catch (e) {
      print('[SECONDARY_WINDOW] Error initializing channel data: $e');
      setState(() {
        _errorMessage = 'Error initializing channel data: $e';
      });
    }
  }

  double _parseTimeToSeconds(String time) {
    try {
      final parts = time.split(':');
      if (parts.length != 3) return 0.0;
      final hours = int.parse(parts[0]);
      final minutes = int.parse(parts[1]);
      final seconds = double.parse(parts[2]);
      return hours * 3600 + minutes * 60 + seconds;
    } catch (e) {
      print('[SECONDARY_WINDOW] Error parsing time $time: $e');
      return 0.0;
    }
  }

  void _calculateYRange() {
    minYValue = double.infinity;
    maxYValue = -double.infinity;

    try {
      if (widget.channel == 'All') {
        final dataPoints = _currentChannelData['dataPoints'] as List<dynamic>? ?? [];
        for (var channelData in dataPoints) {
          final points = channelData['points'] as List<dynamic>? ?? [];
          for (var point in points) {
            final value = (point['value'] as num?)?.toDouble();
            if (value != null && value.isFinite) {
              minYValue = min(minYValue, value);
              maxYValue = max(maxYValue, value);
            }
          }
        }
      } else {
        final points = _currentChannelData['dataPoints'] as List<dynamic>? ?? [];
        for (var point in points) {
          final value = (point['value'] as num?)?.toDouble();
          if (value != null && value.isFinite) {
            minYValue = min(minYValue, value);
            maxYValue = max(maxYValue, value);
          }
        }
      }

      if (minYValue == double.infinity || maxYValue == -double.infinity) {
        minYValue = 0;
        maxYValue = 1000;
      } else {
        final range = maxYValue - minYValue;
        minYValue -= range * 0.1;
        maxYValue += range * 0.1;
      }
    } catch (e) {
      print('[SECONDARY_WINDOW] Error calculating Y range: $e');
      setState(() {
        _errorMessage = 'Error calculating Y range: $e';
      });
    }
  }

  void _calculateMaxLoadValues() {
    maxLoadValues.clear();
    try {
      if (widget.channel == 'All') {
        final dataPoints = _currentChannelData['dataPoints'] as List<dynamic>? ?? [];
        for (var channelData in dataPoints) {
          final channelIndexRaw = channelData['channelIndex'];
          final channelIndex = channelIndexRaw is int ? channelIndexRaw.toString() : (channelIndexRaw as String? ?? '');
          final points = channelData['points'] as List<dynamic>? ?? [];
          double? maxValue;
          for (var point in points) {
            final value = (point['value'] as num?)?.toDouble();
            if (value != null && value.isFinite) {
              maxValue = maxValue == null ? value : max(maxValue, value);
            }
          }
          if (channelIndex.isNotEmpty && maxValue != null) {
            maxLoadValues[channelIndex] = maxValue;
          }
        }
      } else {
        final channelIndex = widget.channel is int ? widget.channel.toString() : widget.channel;
        final points = _currentChannelData['dataPoints'] as List<dynamic>? ?? [];
        double? maxValue;
        for (var point in points) {
          final value = (point['value'] as num?)?.toDouble();
          if (value != null && value.isFinite) {
            maxValue = maxValue == null ? value : max(maxValue, value);
          }
        }
        if (maxValue != null) {
          maxLoadValues[channelIndex] = maxValue;
        }
      }
    } catch (e) {
      print('[SECONDARY_WINDOW] Error calculating max load values: $e');
      setState(() {
        _errorMessage = 'Error calculating max load values: $e';
      });
    }
  }

  void _calculateGraphSegments() {
    int graphVisibleSeconds = _calculateDurationInSeconds();
    if (graphVisibleSeconds == 0) {
      totalSegments = 1;
      return;
    }

    try {
      double minTime = double.infinity;
      double maxTime = -double.infinity;

      if (widget.channel == 'All') {
        final dataPoints = _currentChannelData['dataPoints'] as List<dynamic>? ?? [];
        for (var channelData in dataPoints) {
          final points = channelData['points'] as List<dynamic>? ?? [];
          for (var point in points) {
            final timeStr = point['time'] as String?;
            if (timeStr != null) {
              final timeSeconds = _parseTimeToSeconds(timeStr);
              if (timeSeconds.isFinite) {
                minTime = min(minTime, timeSeconds);
                maxTime = max(maxTime, timeSeconds);
              }
            }
          }
        }
      } else {
        final points = _currentChannelData['dataPoints'] as List<dynamic>? ?? [];
        for (var point in points) {
          final timeStr = point['time'] as String?;
          if (timeStr != null) {
            final timeSeconds = _parseTimeToSeconds(timeStr);
            if (timeSeconds.isFinite) {
              minTime = min(minTime, timeSeconds);
              maxTime = max(maxTime, timeSeconds);
            }
          }
        }
      }

      if (minTime != double.infinity && maxTime != -double.infinity) {
        final duration = maxTime - minTime;
        totalSegments = (duration / graphVisibleSeconds).ceil();
        totalSegments = totalSegments == 0 ? 1 : totalSegments;
        startTimeSeconds = minTime + (currentSegment * graphVisibleSeconds);
      } else {
        totalSegments = 1;
        startTimeSeconds = 0;
      }
    } catch (e) {
      print('[SECONDARY_WINDOW] Error calculating graph segments: $e');
      setState(() {
        _errorMessage = 'Error calculating graph segments: $e';
      });
    }
  }

  int _calculateDurationInSeconds() {
    return ((int.tryParse(_graphVisibleHrController.text) ?? 0) * 3600) +
        ((int.tryParse(_graphVisibleMinController.text) ?? 0) * 60);
  }

  void _updateGraphSegments() {
    setState(() {
      _calculateGraphSegments();
    });
  }

  void _zoomIn() {
    setState(() {
      zoomLevel *= 1.2;
    });
  }

  void _zoomOut() {
    setState(() {
      zoomLevel /= 1.2;
      if (zoomLevel < 0.1) zoomLevel = 0.1;
    });
  }

  void _showPreviousSegment() {
    if (currentSegment > 0) {
      setState(() {
        currentSegment--;
        _calculateGraphSegments();
      });
    }
  }

  void _showNextSegment() {
    if (currentSegment < totalSegments - 1) {
      setState(() {
        currentSegment++;
        _calculateGraphSegments();
      });
    }
  }

  Widget _buildGraph() {
    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!, style: GoogleFonts.roboto(color: Colors.red)));
    }

    List<LineChartBarData> lineBarsData = [];
    double minX = double.infinity;
    double maxX = -double.infinity;

    int graphVisibleSeconds = _calculateDurationInSeconds();
    double segmentStart = startTimeSeconds;
    double segmentEnd = startTimeSeconds + graphVisibleSeconds;

    bool isSingleChannel = widget.channel != 'All';

    try {
      if (widget.channel == 'All') {
        final dataPoints = _currentChannelData['dataPoints'] as List<dynamic>? ?? [];
        for (var channelData in dataPoints) {
          final channelIndexRaw = channelData['channelIndex'];
          final channelIndex = channelIndexRaw is int ? channelIndexRaw.toString() : (channelIndexRaw as String? ?? '');
          if (channelIndex.isEmpty || !channelColors.containsKey(channelIndex)) continue;
          final points = channelData['points'] as List<dynamic>? ?? [];
          List<FlSpot> spots = points
              .where((point) {
            final timeStr = point['time'] as String?;
            if (timeStr == null) return false;
            final timeSeconds = _parseTimeToSeconds(timeStr);
            return timeSeconds >= segmentStart && timeSeconds < segmentEnd;
          })
              .map((point) {
            final timeStr = point['time'] as String?;
            final value = (point['value'] as num?)?.toDouble();
            if (timeStr == null || value == null || !value.isFinite) return null;
            final timeSeconds = _parseTimeToSeconds(timeStr);
            return FlSpot(timeSeconds, value);
          })
              .where((spot) => spot != null)
              .cast<FlSpot>()
              .toList();

          if (spots.isNotEmpty) {
            final xValues = spots.map((s) => s.x).where((x) => x.isFinite);
            if (xValues.isNotEmpty) {
              minX = min(minX, xValues.reduce((a, b) => a < b ? a : b));
              maxX = max(maxX, xValues.reduce((a, b) => a > b ? a : b));
              lineBarsData.add(
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: channelColors[channelIndex],
                  barWidth: 2.5,
                  dotData: FlDotData(show: showDataPoints),
                  belowBarData: BarAreaData(show: false),
                  shadow: const Shadow(
                    color: Colors.transparent,
                    blurRadius: 0,
                    offset: Offset(0, 0),
                  ),
                ),
              );
            }
          }
        }
      } else {
        final channelIndex = widget.channel is int ? widget.channel.toString() : widget.channel;
        final points = _currentChannelData['dataPoints'] as List<dynamic>? ?? [];
        List<FlSpot> spots = points
            .where((point) {
          final timeStr = point['time'] as String?;
          if (timeStr == null) return false;
          final timeSeconds = _parseTimeToSeconds(timeStr);
          return timeSeconds >= segmentStart && timeSeconds < segmentEnd;
        })
            .map((point) {
          final timeStr = point['time'] as String?;
          final value = (point['value'] as num?)?.toDouble();
          if (timeStr == null || value == null || !value.isFinite) return null;
          final timeSeconds = _parseTimeToSeconds(timeStr);
          return FlSpot(timeSeconds, value);
        })
            .where((spot) => spot != null)
            .cast<FlSpot>()
            .toList();

        if (spots.isNotEmpty) {
          final xValues = spots.map((s) => s.x).where((x) => x.isFinite);
          if (xValues.isNotEmpty) {
            minX = min(minX, xValues.reduce((a, b) => a < b ? a : b));
            maxX = max(maxX, xValues.reduce((a, b) => a > b ? a : b));
            lineBarsData.add(
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: channelColors[channelIndex],
                barWidth: 3,
                dotData: FlDotData(show: showDataPoints),
                belowBarData: BarAreaData(show: false),
                shadow: isSingleChannel
                    ? const Shadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(2, 2),
                )
                    : const Shadow(
                  color: Colors.transparent,
                  blurRadius: 0,
                  offset: Offset(0, 0),
                ),
              ),
            );
          }
        }
      }

      if (lineBarsData.isEmpty) {
        return Center(child: Text('No valid data to display', style: GoogleFonts.roboto(color: AppColors.textPrimary)));
      }

      if (minX == double.infinity || maxX == -double.infinity) {
        minX = 0;
        maxX = graphVisibleSeconds.toDouble();
      }

      // Calculate dynamic interval for Y-axis based on range
      final yRange = maxYValue - minYValue;
      final yInterval = yRange / 5; // Aim for ~5 labels

      return Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.grey[100]!, Colors.grey[200]!],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: LineChart(
              LineChartData(
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    tooltipBorder: BorderSide(color: Colors.grey[300]!, width: 1),
                    getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                      final channelIdx = lineBarsData[spot.barIndex].color!;
                      final channelIndex = channelColors.entries.firstWhere((e) => e.value == channelIdx).key;
                      final channelName = channelNames[channelIndex] ?? 'Unknown';
                      final timeSeconds = spot.x;
                      final hours = (timeSeconds ~/ 3600).toInt();
                      final minutes = ((timeSeconds % 3600) ~/ 60).toInt();
                      final seconds = (timeSeconds % 60).toInt();
                      final timeStr = '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
                      return LineTooltipItem(
                        '$channelName: ${spot.y.toStringAsFixed(2)}\nTime: $timeStr',
                        GoogleFonts.roboto(
                          color: channelIdx,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                gridData: FlGridData(
                  show: showGrid,
                  drawHorizontalLine: true,
                  drawVerticalLine: true,
                  getDrawingHorizontalLine: (value) {
                    if (value == minYValue) return const FlLine(color: Colors.transparent, strokeWidth: 0);
                    return FlLine(color: Colors.grey[300]!, strokeWidth: 0.5);
                  },
                  getDrawingVerticalLine: (value) {
                    if (value == minX) return const FlLine(color: Colors.transparent, strokeWidth: 0);
                    return FlLine(color: Colors.grey[300]!, strokeWidth: 0.5);
                  },
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      interval: yInterval,
                      getTitlesWidget: (value, _) {
                        if (value < minYValue || value > maxYValue) return const SizedBox();
                        return Text(
                          value.toStringAsFixed(1),
                          style: GoogleFonts.roboto(color: AppColors.textPrimary, fontSize: 12),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: graphVisibleSeconds / 4, // Aim for ~4 labels
                      getTitlesWidget: (value, _) {
                        if (!value.isFinite || value < minX || value > maxX) return const SizedBox();
                        final hours = (value ~/ 3600).toInt();
                        final minutes = ((value % 3600) ~/ 60).toInt();
                        return Text(
                          '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}',
                          style: GoogleFonts.roboto(color: AppColors.textPrimary, fontSize: 12),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey[400]!)),
                minX: minX,
                maxX: maxX,
                minY: minYValue,
                maxY: maxYValue,
                lineBarsData: lineBarsData,
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      );
    } catch (e) {
      print('[SECONDARY_WINDOW] Error building graph: $e');
      return Center(child: Text('Error rendering graph: $e', style: GoogleFonts.roboto(color: Colors.red)));
    }
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: channelColors.entries.map((entry) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () {
              // Optional: Add interaction, e.g., highlight channel
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: entry.value,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    channelNames[entry.key] ?? 'Channel ${entry.key}',
                    style: GoogleFonts.roboto(color: AppColors.textPrimary, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMaxLoadDisplay() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: maxLoadValues.entries.map((entry) {
        return Text(
          '${channelNames[entry.key] ?? 'Channel ${entry.key}'}: ${entry.value?.toStringAsFixed(2) ?? 'N/A'}',
          style: GoogleFonts.roboto(
            color: AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSegmentNavigation() {
    if (totalSegments <= 1) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildNavButton(
            icon: Icons.chevron_left,
            onPressed: currentSegment > 0 ? _showPreviousSegment : null,
          ),
          Text(
            'Segment ${currentSegment + 1}/$totalSegments',
            style: GoogleFonts.roboto(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
          _buildNavButton(
            icon: Icons.chevron_right,
            onPressed: currentSegment < totalSegments - 1 ? _showNextSegment : null,
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton({required IconData icon, required VoidCallback? onPressed}) {
    return MouseRegion(
      cursor: onPressed != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: onPressed != null ? Colors.grey[200] : Colors.grey[300],
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: onPressed != null ? AppColors.textPrimary : Colors.grey,
            size: 28,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Channel ${widget.channel == 'All' ? 'All Channels' : channelNames[widget.channel] ?? widget.channel}',
                    style: GoogleFonts.roboto(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Row(
                    children: [
                      _buildIconButton(Icons.zoom_in, _zoomIn),
                      _buildIconButton(Icons.zoom_out, _zoomOut),
                      _buildIconButton(
                        showGrid ? Icons.grid_off : Icons.grid_on,
                            () => setState(() => showGrid = !showGrid),
                      ),
                      _buildIconButton(
                        showDataPoints ? Icons.scatter_plot_outlined : Icons.scatter_plot,
                            () => setState(() => showDataPoints = !showDataPoints),
                      ),
                      _buildIconButton(
                        showPeak ? Icons.insights_outlined : Icons.insights,
                            () => setState(() => showPeak = !showPeak),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 60,
                    child: TextField(
                      controller: _graphVisibleHrController,
                      decoration: InputDecoration(
                        labelText: 'Hr',
                        filled: true,
                        fillColor: Colors.grey[50],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      ),
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.roboto(color: AppColors.textPrimary, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 60,
                    child: TextField(
                      controller: _graphVisibleMinController,
                      decoration: InputDecoration(
                        labelText: 'Min',
                        filled: true,
                        fillColor: Colors.grey[50],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      ),
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.roboto(color: AppColors.textPrimary, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildSegmentNavigation(),
              const SizedBox(height: 12),
              _buildLegend(),
              const SizedBox(height: 12),
              if (showPeak) _buildMaxLoadDisplay(),
              const SizedBox(height: 12),
              Expanded(child: _buildGraph()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onPressed) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: AppColors.textPrimary,
            size: 20,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    DesktopMultiWindow.setMethodHandler(null);
    _graphVisibleHrController.dispose();
    _graphVisibleMinController.removeListener(_updateGraphSegments);
    _graphVisibleMinController.dispose();
    print('[DISPOSE] Disposed controllers, listeners, and method handler');
    super.dispose();
  }
}