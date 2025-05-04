import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants/colors.dart';
import 'channel.dart';

class FloatingGraphDialog extends StatefulWidget {
  final String? channel;
  final Map<String, dynamic> channelData;
  final Map<String, Channel> channelConfigs;
  final Map<String, Color> channelColors;
  final Map<String, List<List<Map<String, dynamic>>>> segmentedDataByChannel;
  final int currentGraphIndex;
  final TextEditingController graphVisibleHrController;
  final TextEditingController graphVisibleMinController;
  final VoidCallback onClose;
  final Function(String) onColorPicker;
  final ValueNotifier<Map<String, int>> zOrderNotifier;
  final Set<String> openDialogChannels;

  const FloatingGraphDialog({
    Key? key,
    required this.channel,
    required this.channelData,
    required this.channelConfigs,
    required this.channelColors,
    required this.segmentedDataByChannel,
    required this.currentGraphIndex,
    required this.graphVisibleHrController,
    required this.graphVisibleMinController,
    required this.onClose,
    required this.onColorPicker,
    required this.zOrderNotifier,
    required this.openDialogChannels,
  }) : super(key: key);

  @override
  _FloatingGraphDialogState createState() => _FloatingGraphDialogState();

  static void show(BuildContext context, {
    required String? channel,
    required Map<String, dynamic> channelData,
    required Map<String, Channel> channelConfigs,
    required Map<String, Color> channelColors,
    required Map<String, List<List<Map<String, dynamic>>>> segmentedDataByChannel,
    required int currentGraphIndex,
    required TextEditingController graphVisibleHrController,
    required TextEditingController graphVisibleMinController,
    required Function(String) onColorPicker,
    required ValueNotifier<Map<String, int>> zOrderNotifier,
    required Set<String> openDialogChannels,
  }) {
    final channelKey = channel ?? 'all';
    if (openDialogChannels.contains(channelKey)) {
      debugPrint('Dialog for channel $channelKey already open, skipping.');
      return;
    }

    debugPrint('Opening dialog for channel $channelKey');
    openDialogChannels.add(channelKey);

    OverlayEntry? overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) {
        debugPrint('Building OverlayEntry for channel $channelKey');
        return FloatingGraphDialog(
          channel: channel,
          channelData: channelData,
          channelConfigs: channelConfigs,
          channelColors: channelColors,
          segmentedDataByChannel: segmentedDataByChannel,
          currentGraphIndex: currentGraphIndex,
          graphVisibleHrController: graphVisibleHrController,
          graphVisibleMinController: graphVisibleMinController,
          onClose: () {
            debugPrint('Closing dialog for channel $channelKey');
            openDialogChannels.remove(channelKey);
            zOrderNotifier.value = {...zOrderNotifier.value}..remove(channelKey);
            overlayEntry?.remove();
            overlayEntry = null;
          },
          onColorPicker: onColorPicker,
          zOrderNotifier: zOrderNotifier,
          openDialogChannels: openDialogChannels,
        );
      },
    );

    try {
      Overlay.of(context)?.insert(overlayEntry!);
      debugPrint('OverlayEntry inserted for channel $channelKey');
    } catch (e) {
      debugPrint('Error inserting OverlayEntry: $e');
      openDialogChannels.remove(channelKey);
    }
  }
}

class _FloatingGraphDialogState extends State<FloatingGraphDialog> {
  Offset _offset = Offset(100, 100);
  Size _size = Size(400, 300);
  bool _isMinimized = false;
  bool _isHeaderHovered = false;

  @override
  void initState() {
    super.initState();
    _loadPosition();
  }

  Future<void> _loadPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final channelKey = widget.channel ?? 'all';
    setState(() {
      _offset = Offset(
        prefs.getDouble('dialog_${channelKey}_x') ?? 100,
        prefs.getDouble('dialog_${channelKey}_y') ?? 100,
      );
    });
  }

  Future<void> _savePosition() async {
    final prefs = await SharedPreferences.getInstance();
    final channelKey = widget.channel ?? 'all';
    await prefs.setDouble('dialog_${channelKey}_x', _offset.dx);
    await prefs.setDouble('dialog_${channelKey}_y', _offset.dy);
  }

  void _resize(DragUpdateDetails details) {
    setState(() {
      _size = Size(
        (_size.width + details.delta.dx).clamp(200.0, MediaQuery.of(context).size.width * 0.8),
        (_size.height + details.delta.dy).clamp(150.0, MediaQuery.of(context).size.height * 0.8),
      );
    });
  }

  void _toggleMinimize() {
    setState(() {
      _isMinimized = !_isMinimized;
      _size = _isMinimized ? Size(200, 50) : Size(400, 300);
    });
  }

  void _maximize() {
    setState(() {
      _isMinimized = false;
      _size = Size(MediaQuery.of(context).size.width * 0.6, MediaQuery.of(context).size.height * 0.6);
    });
  }

  void _bringToFront() {
    final channelKey = widget.channel ?? 'all';
    widget.zOrderNotifier.value = {
      ...widget.zOrderNotifier.value,
      channelKey: (widget.zOrderNotifier.value.values.isEmpty ? 0 : widget.zOrderNotifier.value.values.reduce((a, b) => a > b ? a : b) + 1),
    };
  }

  Widget _buildIconButton(IconData icon, VoidCallback onPressed, [IconData? hoverIcon]) {
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.all(4),
        transform: Matrix4.identity()..scale(1.0),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildDialogGraph() {
    List<LineChartBarData> lineBarsData = [];
    double minX = double.infinity;
    double maxX = -double.infinity;
    double minY = double.infinity;
    double maxY = -double.infinity;

    final channelsToPlot = widget.channel == null ? widget.channelConfigs.keys.toList() : [widget.channel!];

    for (var channel in channelsToPlot) {
      if (!widget.channelConfigs.containsKey(channel) || !widget.channelColors.containsKey(channel)) {
        debugPrint('Skipping channel $channel: Missing configuration or color');
        continue;
      }

      final config = widget.channelConfigs[channel];
      final color = widget.channelColors[channel];
      final channelData = widget.segmentedDataByChannel[channel]?[widget.currentGraphIndex] ?? [];

      if (channelData.isEmpty) {
        debugPrint('No data available for channel $channel');
        continue;
      }

      List<FlSpot> spots = channelData
          .where((d) => d['Value'] != null && d['Timestamp'] != null && (d['Value'] as double).isFinite && (d['Timestamp'] as double).isFinite)
          .map((d) => FlSpot(d['Timestamp'] as double, d['Value'] as double))
          .toList();

      if (spots.isNotEmpty) {
        final xValues = spots.map((s) => s.x).where((x) => x.isFinite);
        final yValues = spots.map((s) => s.y).where((y) => y.isFinite);

        if (xValues.isNotEmpty && yValues.isNotEmpty) {
          minX = min(minX, xValues.reduce((a, b) => a < b ? a : b));
          maxX = max(maxX, xValues.reduce((a, b) => a > b ? a : b));
          minY = min(minY, yValues.reduce((a, b) => a < b ? a : b));
          maxY = max(maxY, yValues.reduce((a, b) => a > b ? a : b));

          lineBarsData.add(
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: color,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                  radius: 4,
                  color: Colors.blue,
                  strokeWidth: 1,
                  strokeColor: Colors.white,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [color!.withOpacity(0.3), Colors.transparent],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          );
        }
      }
    }

    if (lineBarsData.isEmpty || minX == double.infinity || maxX == -double.infinity) {
      minX = DateTime.now().millisecondsSinceEpoch.toDouble();
      maxX = minX + 1000;
      minY = widget.channelConfigs.isNotEmpty ? widget.channelConfigs.values.first.chartMinimumValue.toDouble() : 0.0;
      maxY = widget.channelConfigs.isNotEmpty ? widget.channelConfigs.values.first.chartMaximumValue.toDouble() : 100.0;
    }

    int graphVisibleSeconds = ((int.tryParse(widget.graphVisibleHrController.text) ?? 0) * 3600) +
        ((int.tryParse(widget.graphVisibleMinController.text) ?? 0) * 60);
    if (graphVisibleSeconds > 0 && lineBarsData.isNotEmpty) {
      DateTime firstTime = DateTime.fromMillisecondsSinceEpoch(
          widget.segmentedDataByChannel[channelsToPlot.first]?[widget.currentGraphIndex].first['Timestamp']?.toInt() ?? DateTime.now().millisecondsSinceEpoch);
      maxX = firstTime.add(Duration(seconds: graphVisibleSeconds)).millisecondsSinceEpoch.toDouble();
    }

    double intervalY = (maxY - minY) / 5;
    if (intervalY == 0 || !intervalY.isFinite) intervalY = 1;
    double intervalX = 5000;

    Widget legend = Wrap(
      spacing: 16,
      runSpacing: 8,
      children: channelsToPlot
          .where((channel) => widget.channelConfigs.containsKey(channel) && widget.channelColors.containsKey(channel))
          .map((channel) {
        final color = widget.channelColors[channel];
        final channelName = widget.channelConfigs[channel]?.channelName ?? 'Unknown';
        return GestureDetector(
          onTap: () => widget.onColorPicker(channel),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 12, height: 12, color: color),
              const SizedBox(width: 4),
              Text('Channel $channelName', style: GoogleFonts.roboto(color: AppColors.textPrimary, fontSize: 12)),
            ],
          ),
        );
      }).toList(),
    );

    return Column(
      children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), child: legend),
        Expanded(
          child: LineChart(
            LineChartData(
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  tooltipBorder: BorderSide(color: Colors.grey[400]!, width: 1),
                  tooltipRoundedRadius: 8,
                  tooltipPadding: EdgeInsets.all(8),
                  getTooltipColor: (_) => Colors.white.withOpacity(0.9),
                  getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                    if (!spot.x.isFinite || !spot.y.isFinite) return null;
                    final channel = channelsToPlot[spot.barIndex];
                    final channelName = widget.channelConfigs[channel]?.channelName ?? 'Unknown';
                    final unit = widget.channelConfigs[channel]?.unit ?? '';
                    final timestamp = DateTime.fromMillisecondsSinceEpoch(spot.x.toInt());
                    return LineTooltipItem(
                      'Channel: $channelName\nValue: ${spot.y.toStringAsFixed(2)} $unit\nTime: ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}\nDate: ${timestamp.day}/${timestamp.month}/${timestamp.year}',
                      GoogleFonts.roboto(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 12),
                    );
                  }).where((item) => item != null).toList().cast<LineTooltipItem>(),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                horizontalInterval: intervalY,
                verticalInterval: intervalX,
                getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withOpacity(0.3), strokeWidth: 1),
                getDrawingVerticalLine: (value) => FlLine(color: Colors.grey.withOpacity(0.3), strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  axisNameWidget: Text(
                    'Load (${widget.channelConfigs.isNotEmpty ? widget.channelConfigs.values.first.unit : "Unit"})',
                    style: GoogleFonts.roboto(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 50,
                    interval: intervalY,
                    getTitlesWidget: (value, _) => Text(
                      value.isFinite ? value.toStringAsFixed(2) : '',
                      style: GoogleFonts.roboto(color: AppColors.textPrimary, fontSize: 12),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  axisNameWidget: Text(
                    'Time',
                    style: GoogleFonts.roboto(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    interval: intervalX,
                    getTitlesWidget: (value, _) {
                      if (!value.isFinite) return const SizedBox();
                      final dateTime = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}',
                          style: GoogleFonts.roboto(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey[300]!)),
              minX: minX,
              maxX: maxX,
              minY: minY,
              maxY: maxY,
              lineBarsData: lineBarsData,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: FocusNode(),
      onKey: (RawKeyEvent event) {
        if (event is RawKeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            widget.onClose();
          } else if (event.logicalKey == LogicalKeyboardKey.keyM) {
            _toggleMinimize();
          } else if (event.logicalKey == LogicalKeyboardKey.keyX) {
            _maximize();
          }
        }
      },
      child: ValueListenableBuilder<Map<String, int>>(
        valueListenable: widget.zOrderNotifier,
        builder: (context, zOrder, child) {
          final channelKey = widget.channel ?? 'all';
          return Positioned(
            left: _offset.dx,
            top: _offset.dy,
            child: GestureDetector(
              onTap: _bringToFront,
              onPanUpdate: (details) {
                if (!_isMinimized) {
                  setState(() {
                    _offset += details.delta;
                    _offset = Offset(
                      _offset.dx.clamp(0, MediaQuery.of(context).size.width - _size.width),
                      _offset.dy.clamp(0, MediaQuery.of(context).size.height - _size.height),
                    );
                  });
                }
              },
              onPanEnd: (_) => _savePosition(),
              child: MouseRegion(
                onEnter: (_) => setState(() => _isHeaderHovered = true),
                onExit: (_) => setState(() => _isHeaderHovered = false),
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: _size.width,
                    height: _size.height,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Stack(
                      children: [
                        Column(
                          children: [
                            AnimatedContainer(
                              duration: Duration(milliseconds: 200),
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: _isHeaderHovered ? AppColors.submitButton.withOpacity(0.8) : AppColors.submitButton,
                                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Graph: ${widget.channelData['channelName']}',
                                    style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.w600),
                                  ),
                                  Row(
                                    children: [
                                      _buildIconButton(_isMinimized ? Icons.expand : Icons.minimize, _toggleMinimize),
                                      _buildIconButton(Icons.zoom_out_map, _maximize),
                                      _buildIconButton(Icons.close, widget.onClose),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (!_isMinimized)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: _buildDialogGraph(),
                                ),
                              ),
                          ],
                        ),
                        if (!_isMinimized)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onPanUpdate: _resize,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: Colors.grey[400],
                                  borderRadius: BorderRadius.only(bottomRight: Radius.circular(12)),
                                ),
                                child: Icon(Icons.drag_indicator, size: 16, color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

