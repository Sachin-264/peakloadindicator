import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../constants/colors.dart';
import '../../constants/global.dart';
import '../NavPages/channel.dart';

// Data model for Syncfusion Charts
class ChartData {
  final DateTime time;
  final double? value;
  final double? xValue; // For channel-vs-channel mode

  ChartData(this.time, this.value, {this.xValue});
}

// GraphDataNotifier for graph data updates
class GraphDataNotifier extends ChangeNotifier {
  Map<String, List<List<Map<String, dynamic>>>> _dataByChannelSegments;
  Map<String, Color> _channelColors;
  Map<String, Channel> _channelConfigs;

  GraphDataNotifier(this._dataByChannelSegments, this._channelColors, this._channelConfigs);

  Map<String, List<List<Map<String, dynamic>>>> get dataByChannelSegments => _dataByChannelSegments;
  Map<String, Color> get channelColors => _channelColors;
  Map<String, Channel> get channelConfigs => _channelConfigs;

  void updateData({
    required Map<String, List<List<Map<String, dynamic>>>> newData,
    required Map<String, Color> newColors,
    required Map<String, Channel> newConfigs,
  }) {
    _dataByChannelSegments = newData;
    _channelColors = newColors;
    _channelConfigs = newConfigs;
    notifyListeners();
  }
}

class SmoothScrollBehavior extends ScrollBehavior {
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const ClampingScrollPhysics();
  @override
  Widget buildViewportChrome(BuildContext context, Widget child, AxisDirection axisDirection) => child;
}

// Stream extension for throttling
extension StreamExtensions<T> on Stream<T> {
  Stream<T> throttle(Duration duration) {
    Timer? timer;
    T? latestData;
    bool hasData = false;

    return transform(
      StreamTransformer<T, T>.fromHandlers(
        handleData: (data, sink) {
          latestData = data;
          hasData = true;
          if (timer == null || !(timer?.isActive ?? false)) {
            timer = Timer.periodic(duration, (_) {
              if (hasData) {
                sink.add(latestData!);
                hasData = false;
              }
            });
          }
        },
        handleDone: (sink) {
          timer?.cancel();
          if (hasData) sink.add(latestData!);
          sink.close();
        },
        handleError: (error, stackTrace, sink) => sink.addError(error, stackTrace),
      ),
    );
  }
}

class SaveMultiWindowGraph extends StatefulWidget {
  final String windowId;
  final Map<String, List<Map<String, dynamic>>> initialData;
  final Map<String, Color> channelColors;
  final Map<String, Channel> channelConfigs;
  final OverlayEntry entry;
  final Function(OverlayEntry)? onClose;
  final Function(String channelId, Color newColor)? onColorChanged;

  const SaveMultiWindowGraph({
    super.key,
    required this.windowId,
    required this.initialData,
    required this.channelColors,
    required this.channelConfigs,
    required this.entry,
    this.onClose,
    this.onColorChanged,
  });

  @override
  State<SaveMultiWindowGraph> createState() => _SaveMultiWindowGraphState();
}

class _SaveMultiWindowGraphState extends State<SaveMultiWindowGraph> with SingleTickerProviderStateMixin {
  late GraphDataNotifier _dataNotifier;
  double windowWidth = 850;
  double windowHeight = 450;
  double? previousWidth;
  double? previousHeight;
  Offset position = const Offset(100, 100);
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Set<String> selectedChannels = {};
  String? xAxisChannel;
  final showPeaks = ValueNotifier<bool>(true);
  final showDataPoints = ValueNotifier<bool>(false);
  bool showXAxisOptions = true;
  bool isMinimized = false;
  bool isMaximized = false;
  final isChannelPanelOpen = ValueNotifier<bool>(true);
  final isLegendPanelOpen = ValueNotifier<bool>(true);
  AnimationController? _animationController;
  double timeRangeHours = 0.0;
  double timeRangeMinutes = 1.0;
  bool initialSelectionDone = false;
  int currentSegmentIndex = 0;
  Map<String, ChartData> peakValues = {};

  double _parseTimeToTimestamp(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return DateTime.now().millisecondsSinceEpoch.toDouble();
    try {
      List<String> parts = timeStr.split(':');
      if (parts.length == 3) {
        int hours = int.parse(parts[0]);
        int minutes = int.parse(parts[1]);
        int seconds = int.parse(parts[2]);
        return DateTime.now().copyWith(hour: hours, minute: minutes, second: seconds, millisecond: 0, microsecond: 0).millisecondsSinceEpoch.toDouble();
      }
      throw FormatException('Invalid time format: $timeStr');
    } catch (e) {
      return DateTime.now().millisecondsSinceEpoch.toDouble();
    }
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));

    final timeRangeMs = (timeRangeHours + (timeRangeMinutes / 60)) * 3600000;
    final initialSegments = widget.initialData.map((channel, data) => MapEntry(channel, _createSegments(data, timeRangeMs)));
    _dataNotifier = GraphDataNotifier(initialSegments, Map.from(widget.channelColors), Map.from(widget.channelConfigs));
    selectedChannels.addAll(widget.channelConfigs.keys);
    initialSelectionDone = selectedChannels.isNotEmpty;

    _subscription = Global.graphDataStream.throttle(const Duration(milliseconds: 100)).listen((update) {
      if (update.containsKey('dataByChannel') && update.containsKey('channelColors') && update.containsKey('channelConfigs')) {
        final newData = Map<String, List<Map<String, dynamic>>>.from(update['dataByChannel']);
        final timeRangeMs = (timeRangeHours + (timeRangeMinutes / 60)) * 3600000;
        final updatedSegments = Map<String, List<List<Map<String, dynamic>>>>.from(_dataNotifier.dataByChannelSegments);

        newData.forEach((channel, data) {
          for (var point in data) {
            point['Timestamp'] ??= _parseTimeToTimestamp(point['time']);
            point['value'] ??= 0.0;
            point['time'] ??= DateTime.fromMillisecondsSinceEpoch(point['Timestamp'].toInt()).toIso8601String().split('T')[1].split('.')[0];
          }
          updatedSegments.putIfAbsent(channel, () => [[]]);
          final segments = updatedSegments[channel]!;
          for (var point in data) {
            final timestamp = (point['Timestamp'] as num).toDouble();
            if (segments.isEmpty || segments.last.isEmpty) {
              segments.add([point]);
            } else {
              final segmentStartTime = (segments.last.first['Timestamp'] as num).toDouble();
              if (timestamp >= segmentStartTime + timeRangeMs) {
                segments.add([point]);
              } else {
                segments.last.add(point);
                if (segments.last.length > 2000) segments.last.removeRange(0, segments.last.length - 2000);
              }
            }
          }
        });

        newData.forEach((channel, data) => updatedSegments[channel] = _createSegments(updatedSegments[channel]!.expand((s) => s).toList(), timeRangeMs));
        if (updatedSegments.values.where((s) => s.isNotEmpty).isNotEmpty) {
          currentSegmentIndex = updatedSegments.values.where((s) => s.isNotEmpty).map((s) => s.length - 1).reduce(max);
        }
        final broadcastColors = Map<String, Color>.from(update['channelColors']);
        final localColors = _dataNotifier.channelColors;
        final mergedColors = {...broadcastColors, ...localColors};
        _dataNotifier.updateData(newData: updatedSegments, newColors: mergedColors, newConfigs: Map<String, Channel>.from(update['channelConfigs']));
        if (selectedChannels.length != 2) {
          xAxisChannel = null;
          showXAxisOptions = true;
        }
      }
    }, onError: (error) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating graph data: $error'))); });
  }

  List<List<Map<String, dynamic>>> _createSegments(List<Map<String, dynamic>> data, double timeRangeMs) {
    if (data.isEmpty) return [[]];
    final segments = <List<Map<String, dynamic>>>[];
    final processedData = data.map((point) {
      final newPoint = Map<String, dynamic>.from(point);
      newPoint['Timestamp'] ??= _parseTimeToTimestamp(newPoint['time']);
      newPoint['value'] ??= 0.0;
      newPoint['time'] ??= DateTime.fromMillisecondsSinceEpoch(newPoint['Timestamp'].toInt()).toIso8601String().split('T')[1].split('.')[0];
      return newPoint;
    }).toList();
    final sortedData = processedData..sort((a, b) => (a['Timestamp'] as num).compareTo(b['Timestamp'] as num));
    double? segmentStartTime;
    segments.add([]);
    for (var point in sortedData) {
      final timestamp = (point['Timestamp'] as num).toDouble();
      if (segmentStartTime == null) {
        segmentStartTime = timestamp;
        segments.last.add(point);
        continue;
      }
      if (timestamp >= segmentStartTime + timeRangeMs) {
        segments.add([point]);
        segmentStartTime = timestamp;
      } else {
        segments.last.add(point);
      }
      if (segments.last.length > 2000) segments.last.removeRange(0, segments.last.length - 2000);
    }
    currentSegmentIndex = segments.isEmpty ? 0 : segments.length - 1;
    return segments.isEmpty ? [[]] : segments;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _animationController?.dispose();
    showPeaks.dispose();
    showDataPoints.dispose();
    isChannelPanelOpen.dispose();
    isLegendPanelOpen.dispose();
    super.dispose();
  }

  void _updateSize(double width, double height) => setState(() { windowWidth = width.clamp(isMinimized ? 280 : 400, 1920); windowHeight = height.clamp(isMinimized ? 40 : 200, 1080); });
  void _updatePosition(DragUpdateDetails details) { if (!isMaximized) setState(() => position += details.delta); }
  void _resizeWindow(DragUpdateDetails details, String edge) { if (!isMaximized) setState(() { double newWidth = windowWidth, newHeight = windowHeight; Offset newPosition = position; switch (edge) { case 'top': newHeight -= details.delta.dy; newPosition = Offset(position.dx, position.dy + details.delta.dy); break; case 'bottom': newHeight += details.delta.dy; break; case 'left': newWidth -= details.delta.dx; newPosition = Offset(position.dx + details.delta.dx, position.dy); break; case 'right': newWidth += details.delta.dx; break; case 'topLeft': newWidth -= details.delta.dx; newHeight -= details.delta.dy; newPosition = Offset(position.dx + details.delta.dx, position.dy + details.delta.dy); break; case 'topRight': newWidth += details.delta.dx; newHeight -= details.delta.dy; newPosition = Offset(position.dx, position.dy + details.delta.dy); break; case 'bottomLeft': newWidth -= details.delta.dx; newHeight += details.delta.dy; newPosition = Offset(position.dx + details.delta.dx, position.dy); break; case 'bottomRight': newWidth += details.delta.dx; newHeight += details.delta.dy; break; } _updateSize(newWidth, newHeight); position = newPosition; }); }
  void _minimizeWindow() => setState(() { if (!isMinimized) { previousWidth = windowWidth; previousHeight = windowHeight; _updateSize(280, 40); isMinimized = true; } else { _updateSize(previousWidth ?? 850, previousHeight ?? 450); isMinimized = false; } });
  void _maximizeWindow() => setState(() { if (!isMaximized) { previousWidth = windowWidth; previousHeight = windowHeight; _updateSize(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height); position = Offset.zero; isMaximized = true; } else { _updateSize(previousWidth ?? 850, previousHeight ?? 450); position = const Offset(100, 100); isMaximized = false; } });
  void _closeWindow() { widget.entry.remove(); widget.onClose?.call(widget.entry); }

  Widget _buildChannelPanel() {
    return ValueListenableBuilder<bool>(
      valueListenable: isChannelPanelOpen,
      builder: (context, open, _) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200), width: open ? 250 : 0,
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.95), borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)), boxShadow: [if (open) BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(2, 0))]),
          child: open ? ScrollConfiguration(
            behavior: SmoothScrollBehavior(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.all(12), child: Text('Channels', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87))),
                  ..._dataNotifier.channelConfigs.keys.map((channel) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), title: Text(_dataNotifier.channelConfigs[channel]?.channelName ?? channel, style: const TextStyle(fontSize: 14)),
                          leading: Checkbox(value: selectedChannels.contains(channel), onChanged: (value) => setState(() { if (value == true) { selectedChannels.add(channel); } else { if (selectedChannels.length <= 1) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('At least one channel must be selected.'))); return; } selectedChannels.remove(channel); peakValues.remove(channel); } if (selectedChannels.length != 2) { xAxisChannel = null; showXAxisOptions = true; } initialSelectionDone = selectedChannels.isNotEmpty; })),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: BlockPicker(
                            pickerColor: _dataNotifier.channelColors[channel] ?? Colors.blue,
                            onColorChanged: (color) {
                              final updatedColors = Map<String, Color>.from(_dataNotifier.channelColors).. [channel] = color;
                              setState(() {
                                _dataNotifier.updateData(newData: _dataNotifier.dataByChannelSegments, newColors: updatedColors, newConfigs: _dataNotifier.channelConfigs);
                                widget.onColorChanged?.call(channel, color);
                              });
                            },
                            availableColors: const [Colors.red, Colors.blue, Colors.green, Colors.yellow, Colors.purple, Colors.orange, Colors.cyan, Colors.pink],
                            layoutBuilder: (context, colors, picker) => Column(children: [Wrap(spacing: 8, runSpacing: 8, children: colors.map((color) => picker(color)).toList())]),
                          ),
                        ),
                      ],
                    );
                  }),
                  const SizedBox(height: 12),
                  if (!initialSelectionDone) const Padding(padding: EdgeInsets.all(12), child: Text('Please select at least one channel.', style: TextStyle(color: Colors.red, fontSize: 12))),
                ],
              ),
            ),
          ) : null,
        );
      },
    );
  }

  ({dynamic minX, dynamic maxX, double minY, double maxY}) _calculateAxisBounds(bool isXYMode, List<ChartData> allData) {
    if (allData.isEmpty) return (minX: 0, maxX: 100, minY: 0, maxY: 100);

    double minY = double.infinity, maxY = -double.infinity;
    if (isXYMode) {
      double minX = double.infinity, maxX = -double.infinity;
      for (var data in allData) {
        if (data.xValue != null) { minX = min(minX, data.xValue!); maxX = max(maxX, data.xValue!); }
        if (data.value != null) { minY = min(minY, data.value!); maxY = max(maxY, data.value!); }
      }
      double xPadding = (maxX - minX) * 0.1; if (xPadding == 0) xPadding = 10;
      double yPadding = (maxY - minY) * 0.1; if (yPadding == 0) yPadding = 10;
      return (minX: minX - xPadding, maxX: maxX + xPadding, minY: minY - yPadding, maxY: maxY + yPadding);
    } else {
      DateTime minX = allData.first.time, maxX = allData.first.time;
      for (var data in allData) {
        if (data.time.isBefore(minX)) minX = data.time;
        if (data.time.isAfter(maxX)) maxX = data.time;
        if (data.value != null) { minY = min(minY, data.value!); maxY = max(maxY, data.value!); }
      }
      double yPadding = (maxY - minY) * 0.1; if (yPadding == 0) yPadding = 10;
      return (minX: minX, maxX: maxX, minY: minY - yPadding, maxY: maxY + yPadding);
    }
  }

  Widget _buildGraph() {
    if (!initialSelectionDone || selectedChannels.isEmpty) {
      return const Center(child: Text('Please select at least one channel.', style: TextStyle(color: Colors.grey, fontSize: 16)));
    }

    return AnimatedBuilder(
      animation: _dataNotifier,
      builder: (context, _) {
        final dataByChannelSegments = _dataNotifier.dataByChannelSegments;
        final channelColors = _dataNotifier.channelColors;
        final channelConfigs = _dataNotifier.channelConfigs;
        peakValues.clear();

        if (dataByChannelSegments.isEmpty || dataByChannelSegments.values.every((s) => s.every((d) => d.isEmpty))) {
          return const Center(child: Text('No data available...', style: TextStyle(color: Colors.grey, fontSize: 16)));
        }

        List<CartesianSeries> series = [];
        List<ChartData> allDataForBoundsCalculation = [];
        bool isXYMode = xAxisChannel != null && selectedChannels.length == 2;

        if (isXYMode) {
          final yChannelId = selectedChannels.firstWhere((c) => c != xAxisChannel);
          final xDataSegment = (dataByChannelSegments[xAxisChannel] ?? [[]])[min(currentSegmentIndex, (dataByChannelSegments[xAxisChannel] ?? [[]]).length - 1)];
          final yDataSegment = (dataByChannelSegments[yChannelId] ?? [[]])[min(currentSegmentIndex, (dataByChannelSegments[yChannelId] ?? [[]]).length - 1)];
          final Map<int, double> xValueMap = { for (var p in xDataSegment) ((p['Timestamp'] as num?)?.toInt() ?? 0): ((p['value'] as num?)?.toDouble() ?? 0.0) };
          List<ChartData> xyPoints = [];
          for (var yPoint in yDataSegment) {
            final timestamp = (yPoint['Timestamp'] as num?)?.toInt();
            final yValue = (yPoint['value'] as num?)?.toDouble();
            if (timestamp != null && yValue != null && xValueMap.containsKey(timestamp)) {
              xyPoints.add(ChartData(DateTime.fromMillisecondsSinceEpoch(timestamp), yValue, xValue: xValueMap[timestamp]));
            }
          }
          if(xyPoints.isNotEmpty) {
            allDataForBoundsCalculation.addAll(xyPoints);
            series.add(LineSeries<ChartData, double>(
              dataSource: xyPoints, xValueMapper: (ChartData data, _) => data.xValue, yValueMapper: (ChartData data, _) => data.value,
              name: channelConfigs[yChannelId]?.channelName, color: channelColors[yChannelId]!, animationDuration: 0,
              markerSettings: MarkerSettings(isVisible: showDataPoints.value, height: 3, width: 3),
            ));
          }
        } else {
          for (var channelId in selectedChannels) {
            final segments = dataByChannelSegments[channelId] ?? [[]];
            final channelData = currentSegmentIndex < segments.length ? segments[currentSegmentIndex] : [];
            List<ChartData> timePoints = channelData.map((d) {
              final timestamp = (d['Timestamp'] as num?)?.toDouble() ?? _parseTimeToTimestamp(d['time']);
              return ChartData(DateTime.fromMillisecondsSinceEpoch(timestamp.toInt()), (d['value'] as num?)?.toDouble());
            }).toList();
            if (timePoints.isNotEmpty) {
              allDataForBoundsCalculation.addAll(timePoints);
              series.add(LineSeries<ChartData, DateTime>(
                dataSource: timePoints, xValueMapper: (ChartData data, _) => data.time, yValueMapper: (ChartData data, _) => data.value,
                name: channelConfigs[channelId]?.channelName, color: channelColors[channelId]!, animationDuration: 0,
                markerSettings: MarkerSettings(isVisible: showDataPoints.value, height: 3, width: 3),
              ));
            }
          }
        }

        if (showPeaks.value) {
          for (var channelId in selectedChannels) {
            if(isXYMode && channelId == xAxisChannel) continue;
            final segments = dataByChannelSegments[channelId] ?? [[]];
            final channelData = currentSegmentIndex < segments.length ? segments[currentSegmentIndex] : [];
            if (channelData.isNotEmpty) {
              Map<String, dynamic>? peakRawPoint;
              for(var p in channelData) { if(peakRawPoint == null || (p['value'] as num? ?? 0.0) > (peakRawPoint['value'] as num? ?? 0.0)) { peakRawPoint = p; } }
              if(peakRawPoint != null) {
                final peakValue = (peakRawPoint['value'] as num?)?.toDouble();
                final peakTimestamp = (peakRawPoint['Timestamp'] as num?)?.toInt();
                if (peakValue != null && peakTimestamp != null) {
                  ChartData peak;
                  if (isXYMode) {
                    final xDataSegment = (dataByChannelSegments[xAxisChannel] ?? [[]])[min(currentSegmentIndex, (dataByChannelSegments[xAxisChannel] ?? [[]]).length - 1)];
                    final xPeakPoint = xDataSegment.firstWhere((p) => (p['Timestamp'] as num?)?.toInt() == peakTimestamp, orElse: () => {'value': 0.0});
                    peak = ChartData(DateTime.fromMillisecondsSinceEpoch(peakTimestamp), peakValue, xValue: (xPeakPoint['value'] as num?)?.toDouble());
                  } else {
                    peak = ChartData(DateTime.fromMillisecondsSinceEpoch(peakTimestamp), peakValue);
                  }
                  peakValues[channelId] = peak;
                  series.add(ScatterSeries<ChartData, dynamic>(
                    dataSource: [peak], xValueMapper: (ChartData data, _) => isXYMode ? data.xValue : data.time, yValueMapper: (ChartData data, _) => data.value,
                    color: channelColors[channelId], animationDuration: 0,
                    markerSettings: MarkerSettings(isVisible: true, height: 10, width: 10, shape: DataMarkerType.circle, borderWidth: 2, borderColor: Colors.black.withOpacity(0.7)),
                    dataLabelSettings: DataLabelSettings(isVisible: true, labelAlignment: ChartDataLabelAlignment.top, builder: (d,p,s,pi,si) => Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: channelColors[channelId], borderRadius: BorderRadius.circular(4)), child: Text(peak.value!.toStringAsFixed(channelConfigs[channelId]?.decimalPlaces ?? 1), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))),
                  ));
                }
              }
            }
          }
        }

        final bounds = _calculateAxisBounds(isXYMode, allDataForBoundsCalculation);
        final yChannelId = isXYMode ? selectedChannels.firstWhere((c) => c != xAxisChannel) : selectedChannels.length == 1 ? selectedChannels.first : null;

        final yAxisTitle = isXYMode
            ? '${channelConfigs[yChannelId]?.channelName ?? 'Y-Axis'} (${channelConfigs[yChannelId]?.unit ?? ''})'
            : yChannelId != null
            ? '${channelConfigs[yChannelId]?.channelName ?? 'Value'} (${channelConfigs[yChannelId]?.unit ?? ''})'
            : 'Value';

        final xAxisTitle = isXYMode
            ? '${channelConfigs[xAxisChannel]?.channelName ?? 'X-Axis'} (${channelConfigs[xAxisChannel]?.unit ?? ''})'
            : 'Time (HH:mm:ss)';

        // FIX: Dynamically set the tooltip format
        final String tooltipFormat = isXYMode
            ? 'series.name : point.y\n${channelConfigs[xAxisChannel]?.channelName ?? 'X-Value'} : point.x'
            : 'series.name : point.y';

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(icon: const Icon(Icons.arrow_left, color: AppColors.submitButton, size: 16), onPressed: currentSegmentIndex > 0 ? () => setState(() => currentSegmentIndex--) : null),
                  Text('Graph Segment ${currentSegmentIndex + 1}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                  IconButton(icon: const Icon(Icons.arrow_right, color: AppColors.submitButton, size: 16), onPressed: currentSegmentIndex < dataByChannelSegments.values.where((s) => s.isNotEmpty).map((s) => s.length - 1).fold(0, max) ? () => setState(() => currentSegmentIndex++) : null),
                ],
              ),
            ),
            Expanded(
              child: SfCartesianChart(
                primaryXAxis: isXYMode ? NumericAxis(title: AxisTitle(text: xAxisTitle), minimum: bounds.minX, maximum: bounds.maxX) : DateTimeAxis(dateFormat: DateFormat('HH:mm:ss'), title: AxisTitle(text: xAxisTitle), minimum: bounds.minX, maximum: bounds.maxX),
                primaryYAxis: NumericAxis(title: AxisTitle(text: yAxisTitle), minimum: bounds.minY, maximum: bounds.maxY),
                series: series,
                trackballBehavior: TrackballBehavior(
                  enable: true,
                  activationMode: ActivationMode.singleTap,
                  // FIX: Use the dynamic format string
                  tooltipSettings: InteractiveTooltip(enable: true, format: tooltipFormat),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTitleBarButton({required IconData icon, required String tooltip, required VoidCallback onPressed, bool isClose = false}) {
    return MouseRegion(
      onEnter: (_) => _animationController?.forward(),
      onExit: (_) => _animationController?.reverse(),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: isClose ? Colors.red.withOpacity(0.8) : Colors.grey.withOpacity(0.3),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: AnimatedBuilder(
              animation: _animationController!,
              builder: (context, child) => Transform.scale(scale: 1.0 + (_animationController!.value * 0.1), child: SizedBox(width: 28, height: 28, child: Icon(icon, color: Colors.white, size: 18))),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeInputField(TextEditingController controller, String label) {
    return SizedBox(
      width: 60,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(fontSize: 12, color: Colors.black87), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true),
        style: const TextStyle(fontSize: 12),
        onChanged: (value) {
          setState(() {
            final hours = double.tryParse(_timeRangeHrController.text) ?? 0.0;
            final minutes = double.tryParse(_timeRangeMinController.text) ?? 0.0;
            timeRangeHours = hours.clamp(0.0, 24.0);
            timeRangeMinutes = minutes.clamp(0.0, 59.0);
            if (timeRangeHours == 0 && timeRangeMinutes == 0) { timeRangeMinutes = 1.0; _timeRangeMinController.text = '1'; }
            final timeRangeMs = (timeRangeHours + (timeRangeMinutes / 60)) * 3600000;
            final newSegments = _dataNotifier.dataByChannelSegments.map((channel, segments) => MapEntry(channel, _createSegments(segments.expand((s) => s).toList(), timeRangeMs)));
            _dataNotifier.updateData(newData: newSegments, newColors: _dataNotifier.channelColors, newConfigs: _dataNotifier.channelConfigs);
            if (newSegments.values.where((s) => s.isNotEmpty).isNotEmpty) { currentSegmentIndex = newSegments.values.where((s) => s.isNotEmpty).map((s) => s.length - 1).reduce(max); }
          });
        },
      ),
    );
  }

  final _timeRangeHrController = TextEditingController(text: '0');
  final _timeRangeMinController = TextEditingController(text: '1');

  Widget _buildLegend() {
    return ValueListenableBuilder<bool>(
      valueListenable: isLegendPanelOpen,
      builder: (context, open, _) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: open ? null : 0,
          constraints: BoxConstraints(maxWidth: windowWidth - (isChannelPanelOpen.value ? 250 : 0) - 32, maxHeight: 100),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.95), borderRadius: BorderRadius.circular(8), boxShadow: [if (open) BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))]),
          child: open ? AnimatedBuilder(
            animation: _dataNotifier,
            builder: (context, _) {
              return SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8, runSpacing: 4,
                        children: selectedChannels.map((channel) {
                          final color = _dataNotifier.channelColors[channel] ?? Colors.blue;
                          final peak = peakValues[channel];
                          final channelName = _dataNotifier.channelConfigs[channel]?.channelName ?? channel;
                          final peakText = peak != null && showPeaks.value ? ' (${peak.value!.toStringAsFixed(1)})' : '';
                          return GestureDetector(
                            onTap: () => setState(() { if (selectedChannels.contains(channel)) { if (selectedChannels.length <= 1) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('At least one channel must be selected.'))); return; } selectedChannels.remove(channel); peakValues.remove(channel); } else { selectedChannels.add(channel); } if (selectedChannels.length != 2) { xAxisChannel = null; showXAxisOptions = true; } initialSelectionDone = selectedChannels.isNotEmpty; }),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: selectedChannels.contains(channel) ? Colors.black : Colors.grey, width: selectedChannels.contains(channel) ? 1.5 : 1))),
                                const SizedBox(width: 4),
                                ConstrainedBox(constraints: const BoxConstraints(maxWidth: 150), child: Text('$channelName$peakText', style: TextStyle(fontSize: 11, color: selectedChannels.contains(channel) ? Colors.black : Colors.grey), overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Segment Duration:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
                          const SizedBox(width: 8),
                          _buildTimeInputField(_timeRangeHrController, 'Hr'),
                          const SizedBox(width: 8),
                          _buildTimeInputField(_timeRangeMinController, 'Min'),
                        ],
                      ),
                      if (selectedChannels.length == 2) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('X-Axis:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
                            const SizedBox(width: 8),
                            Wrap(
                              spacing: 8, runSpacing: 4,
                              children: [
                                if (showXAxisOptions) ...[
                                  TextButton(onPressed: () => setState(() { xAxisChannel = null; showXAxisOptions = false; }), child: Text('Time', style: TextStyle(fontSize: 12, color: xAxisChannel == null ? AppColors.submitButton : Colors.black87, fontWeight: xAxisChannel == null ? FontWeight.bold : FontWeight.normal))),
                                  ...selectedChannels.map((channel) => TextButton(onPressed: () => setState(() { xAxisChannel = channel; showXAxisOptions = false; }), child: Text(_dataNotifier.channelConfigs[channel]?.channelName ?? channel, style: TextStyle(fontSize: 12, color: xAxisChannel == channel ? AppColors.submitButton : Colors.black87, fontWeight: xAxisChannel == channel ? FontWeight.bold : FontWeight.normal)))),
                                ] else ...[
                                  TextButton(onPressed: () => setState(() => showXAxisOptions = true), child: const Text('Select X-Axis', style: TextStyle(fontSize: 12, color: AppColors.submitButton, fontWeight: FontWeight.bold))),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ) : null,
        );
      },
    );
  }

  Widget _buildResizeHandle(String edge, {double size = 10}) {
    return GestureDetector(
      onPanUpdate: (details) => _resizeWindow(details, edge),
      child: MouseRegion(
        cursor: edge.contains('top') && edge.contains('left') ? SystemMouseCursors.resizeUpLeft : edge.contains('top') && edge.contains('right') ? SystemMouseCursors.resizeUpRight : edge.contains('bottom') && edge.contains('left') ? SystemMouseCursors.resizeDownLeft : edge.contains('bottom') && edge.contains('right') ? SystemMouseCursors.resizeDownRight : edge.contains('top') ? SystemMouseCursors.resizeUp : edge.contains('bottom') ? SystemMouseCursors.resizeDown : edge.contains('left') ? SystemMouseCursors.resizeLeft : SystemMouseCursors.resizeRight,
        child: Container(
          width: edge.contains('top') || edge.contains('bottom') ? null : size,
          height: edge.contains('left') || edge.contains('right') ? null : size,
          color: Colors.transparent,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        color: Colors.transparent,
        child: Stack(
          children: [
            Container(
              width: windowWidth,
              height: windowHeight,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Colors.white, Color(0xFFF5F5F5)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Column(
                children: [
                  GestureDetector(
                    onPanUpdate: _updatePosition,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: isMinimized ? 4 : 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [AppColors.submitButton, AppColors.submitButton.withOpacity(0.8)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.show_chart, color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                              Text("Live Graph - ${widget.windowId}", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: isMinimized ? 12 : 14, letterSpacing: 1.1)),
                            ],
                          ),
                          Row(
                            children: [
                              _buildTitleBarButton(icon: isMinimized ? Icons.unfold_more : Icons.unfold_less, tooltip: isMinimized ? 'Restore' : 'Minimize', onPressed: _minimizeWindow),
                              _buildTitleBarButton(icon: isMaximized ? Icons.fullscreen_exit : Icons.fullscreen, tooltip: isMaximized ? 'Restore' : 'Maximize', onPressed: _maximizeWindow),
                              _buildTitleBarButton(icon: Icons.close, tooltip: 'Close', onPressed: _closeWindow, isClose: true),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!isMinimized)
                    Expanded(
                      child: Row(
                        children: [
                          _buildChannelPanel(),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      ValueListenableBuilder<bool>(valueListenable: isChannelPanelOpen, builder: (context, open, _) => Tooltip(message: open ? 'Hide Channel Panel' : 'Show Channel Panel', child: IconButton(icon: Icon(open ? Icons.arrow_left : Icons.arrow_right, color: AppColors.submitButton), onPressed: () => isChannelPanelOpen.value = !open))),
                                      ValueListenableBuilder<bool>(valueListenable: showPeaks, builder: (context, show, _) => Tooltip(message: show ? 'Hide Peaks' : 'Show Peaks', child: IconButton(icon: Icon(Icons.insights, color: show ? AppColors.submitButton : Colors.grey), onPressed: () => showPeaks.value = !show))),
                                      ValueListenableBuilder<bool>(valueListenable: showDataPoints, builder: (context, show, _) => Tooltip(message: show ? 'Hide Data Points' : 'Show Data Points', child: IconButton(icon: Icon(Icons.grain, color: show ? AppColors.submitButton : Colors.grey), onPressed: () => showDataPoints.value = !show))),
                                      ValueListenableBuilder<bool>(valueListenable: isLegendPanelOpen, builder: (context, open, _) => Tooltip(message: open ? 'Hide Legend Panel' : 'Show Legend Panel', child: IconButton(icon: Icon(open ? Icons.arrow_drop_down : Icons.arrow_drop_up, color: AppColors.submitButton), onPressed: () => isLegendPanelOpen.value = !open))),
                                    ],
                                  ),
                                  Expanded(child: _buildGraph()),
                                  _buildLegend(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (!isMinimized && !isMaximized) ...[
              Positioned(top: 0, left: 0, right: 0, child: _buildResizeHandle('top')),
              Positioned(bottom: 0, left: 0, right: 0, child: _buildResizeHandle('bottom')),
              Positioned(left: 0, top: 0, bottom: 0, child: _buildResizeHandle('left')),
              Positioned(right: 0, top: 0, bottom: 0, child: _buildResizeHandle('right')),
              Positioned(top: 0, left: 0, child: _buildResizeHandle('topLeft', size: 15)),
              Positioned(top: 0, right: 0, child: _buildResizeHandle('topRight', size: 15)),
              Positioned(bottom: 0, left: 0, child: _buildResizeHandle('bottomLeft', size: 15)),
              Positioned(bottom: 0, right: 0, child: _buildResizeHandle('bottomRight', size: 15)),
            ],
          ],
        ),
      ),
    );
  }
}