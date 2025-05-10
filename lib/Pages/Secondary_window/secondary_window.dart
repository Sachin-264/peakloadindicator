import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart'; // Added for debugPrint
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../constants/colors.dart';
import '../../constants/global.dart';
import '../NavPages/channel.dart';

class MultiWindowGraph extends StatefulWidget {
  final String windowId;
  final Map<String, List<Map<String, dynamic>>> initialData;
  final Map<String, Color> channelColors;
  final Map<String, Channel> channelConfigs;
  final OverlayEntry entry;
  final Function(Offset)? onPositionUpdate;
  final Function(OverlayEntry)? onClose;

  const MultiWindowGraph({
    super.key,
    required this.windowId,
    required this.initialData,
    required this.channelColors,
    required this.channelConfigs,
    required this.entry,
    this.onPositionUpdate,
    this.onClose,
  });

  @override
  State<MultiWindowGraph> createState() => _MultiWindowGraphState();
}

class _MultiWindowGraphState extends State<MultiWindowGraph> {
  late Map<String, List<Map<String, dynamic>>> dataByChannel;
  late Map<String, Color> channelColors;
  late Map<String, Channel> channelConfigs;
  double windowWidth = 600;
  double windowHeight = 450;
  Offset position = const Offset(100, 100);
  StreamSubscription<Map<String, dynamic>>? _subscription;

  @override
  void initState() {
    super.initState();
    // Initialize with copies to avoid mutating widget properties
    dataByChannel = widget.initialData.map((key, value) => MapEntry(key, [...value]));
    channelColors = Map.from(widget.channelColors);
    channelConfigs = Map.from(widget.channelConfigs);

    debugPrint('[MultiWindowGraph] Window "${widget.windowId}" initialized with ${dataByChannel.length} channels');

    // Subscribe to the stream directly
    _subscription = Global.graphDataStream.listen(
          (update) {
        debugPrint('[MultiWindowGraph] Window "${widget.windowId}" received stream update with keys: ${update.keys}');
        if (update.containsKey('dataByChannel') &&
            update.containsKey('channelColors') &&
            update.containsKey('channelConfigs')) {
          setState(() {
            dataByChannel = Map<String, List<Map<String, dynamic>>>.from(update['dataByChannel']);
            channelColors = Map<String, Color>.from(update['channelColors']);
            channelConfigs = Map<String, Channel>.from(update['channelConfigs']);
          });
        } else {
          debugPrint('[MultiWindowGraph] Invalid stream update: missing required keys');
        }
      },
      onError: (error) {
        debugPrint('[MultiWindowGraph] Stream error in window "${widget.windowId}": $error');
      },
      onDone: () {
        debugPrint('[MultiWindowGraph] Stream closed for window "${widget.windowId}"');
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    debugPrint('[MultiWindowGraph] Disposed window "${widget.windowId}"');
    super.dispose();
  }

  void _updateSize(double width, double height) {
    setState(() {
      windowWidth = width.clamp(300, MediaQuery.of(context).size.width);
      windowHeight = height.clamp(200, MediaQuery.of(context).size.height);
      debugPrint('[MultiWindowGraph] Resized window "${widget.windowId}" to $windowWidth x $windowHeight');
    });
  }

  void _updatePosition(DragUpdateDetails details) {
    setState(() {
      position += details.delta;
      widget.onPositionUpdate?.call(position);
      debugPrint('[MultiWindowGraph] Moved window "${widget.windowId}" to $position');
    });
  }

  void _closeWindow() {
    widget.entry.remove();
    widget.onClose?.call(widget.entry);
    debugPrint('[MultiWindowGraph] Closed window "${widget.windowId}"');
  }

  Widget _buildGraph() {
    if (dataByChannel.isEmpty || dataByChannel.values.every((data) => data.isEmpty)) {
      return const Center(
        child: Text(
          'No data yet...',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    List<LineChartBarData> lineBarsData = [];
    double minX = double.infinity;
    double maxX = -double.infinity;
    double minY = double.infinity;
    double maxY = -double.infinity;

    for (var channel in channelConfigs.keys) {
      if (!channelConfigs.containsKey(channel) || !channelColors.containsKey(channel)) {
        debugPrint('[MultiWindowGraph] Skipping channel $channel: missing config or color');
        continue;
      }

      final config = channelConfigs[channel]!;
      final color = channelColors[channel]!;
      final channelData = dataByChannel[channel] ?? [];

      if (channelData.isEmpty) {
        debugPrint('[MultiWindowGraph] No data for channel $channel');
        continue;
      }

      List<FlSpot> spots = channelData
          .where((d) =>
      d['Timestamp'] != null &&
          d['Value'] != null &&
          d['Timestamp'] is num &&
          d['Value'] is num &&
          (d['Timestamp'] as num).isFinite &&
          (d['Value'] as num).isFinite)
          .map((d) => FlSpot(
        (d['Timestamp'] as num).toDouble(),
        (d['Value'] as num).toDouble(),
      ))
          .toList();

      if (spots.isEmpty) {
        debugPrint('[MultiWindowGraph] No valid spots for channel $channel');
        continue;
      }

      final xValues = spots.map((s) => s.x).where((x) => x.isFinite);
      final yValues = spots.map((s) => s.y).where((y) => y.isFinite);

      if (xValues.isNotEmpty && yValues.isNotEmpty) {
        minX = min(minX, xValues.reduce(min));
        maxX = max(maxX, xValues.reduce(max));
        minY = min(minY, yValues.reduce(min));
        maxY = max(maxY, yValues.reduce(max));
      }

      lineBarsData.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: color,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),
      );
    }

    if (lineBarsData.isEmpty) {
      debugPrint('[MultiWindowGraph] No valid data to plot');
      return const Center(
        child: Text(
          'No valid data to plot',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    // Ensure reasonable axis ranges
    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    minX = minX.isFinite ? minX : now - 60000; // 1 minute ago
    maxX = maxX.isFinite ? maxX : now;
    minY = minY.isFinite ? minY : 0;
    maxY = maxY.isFinite ? maxY : 100;

    // Add padding to Y-axis
    final yRange = maxY - minY;
    maxY += yRange * 0.1;
    minY -= yRange * 0.05;
    if (minY < 0) minY = 0; // Prevent negative Y-axis for most cases

    // Add padding to X-axis (e.g., 10 seconds)
    maxX += 10000;
    minX -= 10000;

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          drawHorizontalLine: true,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.grey.withOpacity(0.2),
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            axisNameWidget: Text(
              'Value (${channelConfigs.isNotEmpty ? channelConfigs.values.first.unit : "Unit"})',
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
            ),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.isFinite ? value.toStringAsFixed(2) : '',
                  style: const TextStyle(color: Colors.black, fontSize: 12),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            axisNameWidget: const Text(
              'Time',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
            ),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                if (!value.isFinite) return const SizedBox();
                final time = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                return Text(
                  "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}",
                  style: const TextStyle(color: Colors.black, fontSize: 12),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: Colors.grey.withOpacity(0.5), width: 1),
        ),
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        lineBarsData: lineBarsData,
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final channel = channelConfigs.keys.toList()[spot.barIndex];
                final channelName = channelConfigs[channel]?.channelName ?? 'Unknown';
                final time = DateTime.fromMillisecondsSinceEpoch(spot.x.toInt());
                return LineTooltipItem(
                    'Channel $channelName\n${spot.y.toStringAsFixed(2)} ${channelConfigs[channel]?.unit ?? ''}\n${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}',
                const TextStyle(color: Colors.white, fontSize: 12),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: windowWidth,
        height: windowHeight,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8),
          ],
        ),
        child: Column(
          children: [
            GestureDetector(
              onPanUpdate: _updatePosition,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.submitButton,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Live Graph - ${widget.windowId}",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.maximize, color: Colors.white),
                          onPressed: () => _updateSize(windowWidth + 50, windowHeight + 50),
                        ),
                        IconButton(
                          icon: const Icon(Icons.minimize, color: Colors.white),
                          onPressed: () => _updateSize(windowWidth - 50, windowHeight - 50),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: _closeWindow,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildGraph(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}