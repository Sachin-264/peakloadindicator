import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../constants/colors.dart';
import '../../constants/global.dart';
import '../NavPages/channel.dart';

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
if (hasData) {
sink.add(latestData!);
}
sink.close();
},
handleError: (error, stackTrace, sink) {
sink.addError(error, stackTrace);
},
),
);
}
}

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

class _MultiWindowGraphState extends State<MultiWindowGraph> with SingleTickerProviderStateMixin {
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
Map<String, Map<String, dynamic>> peakValues = {};

@override
void initState() {
super.initState();
_animationController = AnimationController(
vsync: this,
duration: const Duration(milliseconds: 150),
);

// Initialize data notifier
final timeRangeMs = (timeRangeHours + (timeRangeMinutes / 60)) * 3600000;
final initialSegments = widget.initialData.map((channel, data) => MapEntry(
channel,
_createSegments(data, timeRangeMs),
));
_dataNotifier = GraphDataNotifier(
initialSegments,
Map.from(widget.channelColors),
Map.from(widget.channelConfigs),
);

// Throttled stream listener
_subscription = Global.graphDataStream.throttle(const Duration(milliseconds: 100)).listen(
(update) {
if (update.containsKey('dataByChannel') &&
update.containsKey('channelColors') &&
update.containsKey('channelConfigs')) {
final newData = Map<String, List<Map<String, dynamic>>>.from(update['dataByChannel']);
final timeRangeMs = (timeRangeHours + (timeRangeMinutes / 60)) * 3600000;
final updatedSegments = Map<String, List<List<Map<String, dynamic>>>>.from(_dataNotifier.dataByChannelSegments);

newData.forEach((channel, data) {
updatedSegments.putIfAbsent(channel, () => [[]]);
final segments = updatedSegments[channel]!;
for (var point in data) {
final timestamp = (point['Timestamp'] as num?)?.toDouble() ?? 0;
if (segments.isEmpty || segments.last.isEmpty) {
segments.add([point]);
} else {
final segmentStartTime = (segments.last.first['Timestamp'] as num?)?.toDouble() ?? 0;
if (timestamp >= segmentStartTime + timeRangeMs) {
segments.add([point]);
} else {
segments.last.add(point);
// Cap segment size to 2000 points
if (segments.last.length > 2000) {
segments.last.removeRange(0, segments.last.length - 2000);
}
}
}
}
});

// Recreate segments to ensure correct start times
newData.forEach((channel, data) {
updatedSegments[channel] = _createSegments(
updatedSegments[channel]!.expand((s) => s).toList(),
timeRangeMs,
);
});

currentSegmentIndex = updatedSegments.values
    .where((segments) => segments.isNotEmpty)
    .map((segments) => segments.length - 1)
    .reduce(max);

final newColors = Map<String, Color>.from(update['channelColors']);
final updatedColors = Map<String, Color>.from(_dataNotifier.channelColors)..addAll(newColors);
_dataNotifier.updateData(
newData: updatedSegments,
newColors: updatedColors,
newConfigs: Map<String, Channel>.from(update['channelConfigs']),
);

// Reset xAxisChannel if selectedChannels changes
if (selectedChannels.length != 2) {
xAxisChannel = null;
showXAxisOptions = true;
}
}
},
onError: (error) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(content: Text('Error updating graph data: $error')),
);
},
);
}

List<List<Map<String, dynamic>>> _createSegments(List<Map<String, dynamic>> data, double timeRangeMs) {
if (data.isEmpty) return [[]];
final segments = <List<Map<String, dynamic>>>[];
final sortedData = data..sort((a, b) => ((a['Timestamp'] as num?) ?? 0).compareTo((b['Timestamp'] as num?) ?? 0));

double? segmentStartTime;
segments.add([]);

for (var point in sortedData) {
final timestamp = (point['Timestamp'] as num?)?.toDouble() ?? 0;

if (segmentStartTime == null) {
segmentStartTime = timestamp;
segments.last.add(point);
continue;
}

if (timestamp >= segmentStartTime + timeRangeMs) {
segments.add([point]);
segmentStartTime = timestamp; // Update start time to new segment's first point
} else {
segments.last.add(point);
}

// Cap segment size
if (segments.last.length > 2000) {
segments.last.removeRange(0, segments.last.length - 2000);
}
}

currentSegmentIndex = segments.isEmpty ? 0 : segments.length - 1;
return segments.isEmpty ? [[]] : segments;
}

@override
void dispose() {
_subscription?.cancel();
_animationController?.dispose();
showPeaks.dispose();
isChannelPanelOpen.dispose();
isLegendPanelOpen.dispose();
super.dispose();
}

void _updateSize(double width, double height) {
setState(() {
windowWidth = width.clamp(400, 1920);
windowHeight = height.clamp(isMinimized ? 40 : 200, 1080);
});
}

void _updatePosition(DragUpdateDetails details) {
if (isMaximized) return;
setState(() {
position += details.delta;
widget.onPositionUpdate?.call(position);
});
}

void _resizeWindow(DragUpdateDetails details, String edge) {
if (isMaximized) return;
setState(() {
double newWidth = windowWidth;
double newHeight = windowHeight;
Offset newPosition = position;

switch (edge) {
case 'top':
newHeight -= details.delta.dy;
newPosition = Offset(position.dx, position.dy + details.delta.dy);
break;
case 'bottom':
newHeight += details.delta.dy;
break;
case 'left':
newWidth -= details.delta.dx;
newPosition = Offset(position.dx + details.delta.dx, position.dy);
break;
case 'right':
newWidth += details.delta.dx;
break;
case 'topLeft':
newWidth -= details.delta.dx;
newHeight -= details.delta.dy;
newPosition = Offset(position.dx + details.delta.dx, position.dy + details.delta.dy);
break;
case 'topRight':
newWidth += details.delta.dx;
newHeight -= details.delta.dy;
newPosition = Offset(position.dx, position.dy + details.delta.dy);
break;
case 'bottomLeft':
newWidth -= details.delta.dx;
newHeight += details.delta.dy;
newPosition = Offset(position.dx + details.delta.dx, position.dy);
break;
case 'bottomRight':
newWidth += details.delta.dx;
newHeight += details.delta.dy;
break;
}

_updateSize(newWidth, newHeight);
position = newPosition;
widget.onPositionUpdate?.call(position);
});
}

void _minimizeWindow() {
setState(() {
if (!isMinimized) {
previousWidth = windowWidth;
previousHeight = windowHeight;
_updateSize(windowWidth, 40);
isMinimized = true;
} else {
_updateSize(previousWidth ?? 850, previousHeight ?? 450);
isMinimized = false;
}
});
}

void _maximizeWindow() {
setState(() {
if (!isMaximized) {
previousWidth = windowWidth;
previousHeight = windowHeight;
_updateSize(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height);
position = Offset.zero;
isMaximized = true;
} else {
_updateSize(previousWidth ?? 850, previousHeight ?? 450);
position = const Offset(100, 100);
isMaximized = false;
}
widget.onPositionUpdate?.call(position);
});
}

void _closeWindow() {
widget.entry.remove();
widget.onClose?.call(widget.entry);
}

Widget _buildChannelPanel() {
return ValueListenableBuilder<bool>(
valueListenable: isChannelPanelOpen,
builder: (context, open, _) {
return AnimatedContainer(
duration: const Duration(milliseconds: 200),
width: open ? 250 : 0,
decoration: BoxDecoration(
color: Colors.white.withOpacity(0.95),
borderRadius: const BorderRadius.only(
topLeft: Radius.circular(12),
bottomLeft: Radius.circular(12),
),
boxShadow: [
if (open)
BoxShadow(
color: Colors.black.withOpacity(0.1),
blurRadius: 4,
offset: const Offset(2, 0),
),
],
),
child: open
? ScrollConfiguration(
behavior: SmoothScrollBehavior(),
child: SingleChildScrollView(
physics: const AlwaysScrollableScrollPhysics(),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
const Padding(
padding: EdgeInsets.all(12),
child: Text(
'Channels',
style: TextStyle(
fontWeight: FontWeight.bold,
fontSize: 16,
color: Colors.black87,
),
),
),
..._dataNotifier.channelConfigs.keys.map((channel) {
return Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
ListTile(
contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
title: Text(
_dataNotifier.channelConfigs[channel]?.channelName ?? channel,
style: const TextStyle(fontSize: 14),
),
leading: Checkbox(
value: selectedChannels.contains(channel),
onChanged: (value) {
setState(() {
if (value == true) {
selectedChannels.add(channel);
} else {
if (selectedChannels.length <= 1) {
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(
content: Text('At least one channel must be selected.'),
),
);
return;
}
selectedChannels.remove(channel);
peakValues.remove(channel);
}
if (selectedChannels.length != 2) {
xAxisChannel = null;
showXAxisOptions = true;
}
initialSelectionDone = selectedChannels.isNotEmpty;
});
},
),
),
Padding(
padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
child: BlockPicker(
pickerColor: _dataNotifier.channelColors[channel] ?? Colors.blue,
onColorChanged: (color) {
final updatedColors = Map<String, Color>.from(_dataNotifier.channelColors)
..[channel] = color;
_dataNotifier.updateData(
newData: _dataNotifier.dataByChannelSegments,
newColors: updatedColors,
newConfigs: _dataNotifier.channelConfigs,
);
},
availableColors: const [
Colors.red,
Colors.blue,
Colors.green,
Colors.yellow,
Colors.purple,
Colors.orange,
Colors.cyan,
Colors.pink,
],
layoutBuilder: (context, colors, picker) => Column(
children: [
Wrap(
spacing: 8,
runSpacing: 8,
children: colors.map((color) => picker(color)).toList(),
),
],
),
),
),
],
);
}),
const SizedBox(height: 12),
if (!initialSelectionDone)
const Padding(
padding: EdgeInsets.all(12),
child: Text(
'Please select at least one channel.',
style: TextStyle(color: Colors.red, fontSize: 12),
),
),
],
),
),
)
    : null,
);
},
);
}

Widget _buildGraph() {
if (!initialSelectionDone || selectedChannels.isEmpty) {
return const Center(
child: Text(
'Please select at least one channel to display the graph.',
style: TextStyle(color: Colors.grey, fontSize: 16),
),
);
}

return AnimatedBuilder(
animation: _dataNotifier,
builder: (context, _) {
final dataByChannelSegments = _dataNotifier.dataByChannelSegments;
final channelColors = _dataNotifier.channelColors;
final channelConfigs = _dataNotifier.channelConfigs;

if (dataByChannelSegments.isEmpty ||
dataByChannelSegments.values.every((segments) => segments.every((data) => data.isEmpty))) {
return const Center(
child: Text(
'No data available...',
style: TextStyle(color: Colors.grey, fontSize: 16),
),
);
}

// Graph segment display with navigation
final segmentDisplay = Padding(
padding: const EdgeInsets.only(bottom: 8),
child: Row(
mainAxisAlignment: MainAxisAlignment.center,
children: [
IconButton(
icon: const Icon(Icons.arrow_left, color: AppColors.submitButton, size: 16),
tooltip: 'Previous Graph Segment',
onPressed: currentSegmentIndex > 0
? () {
setState(() {
currentSegmentIndex--;
});
}
    : null,
),
Text(
'Graph Segment ${currentSegmentIndex + 1}',
style: const TextStyle(
fontSize: 14,
fontWeight: FontWeight.bold,
color: Colors.black87,
),
),
IconButton(
icon: const Icon(Icons.arrow_right, color: AppColors.submitButton, size: 16),
tooltip: 'Next Graph Segment',
onPressed: currentSegmentIndex <
_dataNotifier.dataByChannelSegments.values
    .where((segments) => segments.isNotEmpty)
    .map((segments) => segments.length - 1)
    .reduce(max)
? () {
setState(() {
currentSegmentIndex++;
});
}
    : null,
),
],
),
);

List<LineChartBarData> lineBarsData = [];
double minX = double.infinity;
double maxX = -double.infinity;
double minY = double.infinity;
double maxY = -double.infinity;
peakValues.clear();

if (xAxisChannel != null && selectedChannels.length == 2) {
// Channel vs Channel mode: Plot one line
final otherChannel = selectedChannels.firstWhere((c) => c != xAxisChannel);
if (channelConfigs.containsKey(xAxisChannel) &&
channelConfigs.containsKey(otherChannel) &&
channelColors.containsKey(otherChannel)) {
final xData = (dataByChannelSegments[xAxisChannel] ?? [[]])[currentSegmentIndex];
final yData = (dataByChannelSegments[otherChannel] ?? [[]])[currentSegmentIndex];

List<FlSpot> spots = [];
for (int i = 0; i < min(xData.length, yData.length); i++) {
final xValue = xData[i]['Value'];
final yValue = yData[i]['Value'];
if (xValue is num && yValue is num && xValue.isFinite && yValue.isFinite) {
spots.add(FlSpot(xValue.toDouble(), yValue.toDouble()));
}
}

if (spots.isNotEmpty) {
// Sort spots by x-value for correct rendering
spots.sort((a, b) => a.x.compareTo(b.x));

// Peak detection for Y-axis channel
if (showPeaks.value) {
final peakSpot = spots.reduce((a, b) => a.y > b.y ? a : b);
peakValues[otherChannel] = {
'x': peakSpot.x,
'y': peakSpot.y,
};
}

final xValues = spots.map((s) => s.x).where((x) => x.isFinite);
final yValues = spots.map((s) => s.y).where((y) => y.isFinite);

if (xValues.isNotEmpty && yValues.isNotEmpty) {
minX = xValues.reduce(min);
maxX = xValues.reduce(max);
minY = yValues.reduce(min);
maxY = yValues.reduce(max);
}

lineBarsData.add(
LineChartBarData(
spots: spots,
isCurved: true,
curveSmoothness: 0.3,
color: channelColors[otherChannel]!,
barWidth: 2.0,
dotData: FlDotData(
show: showPeaks.value,
getDotPainter: (spot, percent, barData, index) {
final isPeak = showPeaks.value &&
peakValues[otherChannel]?['x'] == spot.x &&
peakValues[otherChannel]?['y'] == spot.y;
return FlDotCirclePainter(
radius: isPeak ? 6 : 3,
color: isPeak ? channelColors[otherChannel]!.withOpacity(1) : channelColors[otherChannel]!.withOpacity(0.7),
strokeWidth: isPeak ? 2 : 1,
strokeColor: Colors.white,
);
},
),
belowBarData: BarAreaData(show: false),
),
);
}
}
} else {
// Time-based mode: Plot one line per channel
for (var channel in selectedChannels) {
if (!channelConfigs.containsKey(channel) || !channelColors.containsKey(channel)) {
continue;
}

final color = channelColors[channel]!;
final segments = dataByChannelSegments[channel] ?? [[]];
final channelData = currentSegmentIndex < segments.length ? segments[currentSegmentIndex] : [];

if (channelData.isEmpty) {
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
continue;
}

// Sort spots by x-value to ensure correct rendering
spots.sort((a, b) => a.x.compareTo(b.x));

// Peak detection
if (spots.isNotEmpty && showPeaks.value) {
final peakSpot = spots.reduce((a, b) => a.y > b.y ? a : b);
peakValues[channel] = {
'x': peakSpot.x,
'y': peakSpot.y,
'timestamp': DateTime.fromMillisecondsSinceEpoch(peakSpot.x.toInt()).toString(),
};
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
curveSmoothness: 0.3,
color: color,
barWidth: 2.0,
dotData: FlDotData(
show: showPeaks.value,
getDotPainter: (spot, percent, barData, index) {
final isPeak = showPeaks.value &&
peakValues[channel]?['x'] == spot.x &&
peakValues[channel]?['y'] == spot.y;
return FlDotCirclePainter(
radius: isPeak ? 6 : 3,
color: isPeak ? color.withOpacity(1) : color.withOpacity(0.7),
strokeWidth: isPeak ? 2 : 1,
strokeColor: Colors.white,
);
},
),
belowBarData: BarAreaData(show: false),
),
);
}
}

if (lineBarsData.isEmpty) {
return const Center(
child: Text(
'No valid data to plot',
style: TextStyle(color: Colors.grey, fontSize: 16),
),
);
}

// Handle edge cases for axis ranges
final now = DateTime.now().millisecondsSinceEpoch.toDouble();
final timeRangeMs = (timeRangeHours + (timeRangeMinutes / 60)) * 3600000;
if (xAxisChannel == null) {
minX = minX.isFinite ? minX : now - timeRangeMs;
maxX = maxX.isFinite ? maxX : now;
} else {
minX = minX.isFinite ? minX : 0;
maxX = maxX.isFinite ? maxX : 100;
}
minY = minY.isFinite ? minY : 0;
maxY = maxY.isFinite ? maxY : 100;

// Ensure non-zero ranges to prevent interval == 0
double xRange = maxX - minX;
double yRange = maxY - minY;
if (xRange == 0) {
xRange = xAxisChannel == null ? timeRangeMs : 100;
minX -= xRange / 2;
maxX += xRange / 2;
}
if (yRange == 0) {
yRange = 1;
minY -= 0.5;
maxY += 0.5;
}

// Add padding to ranges
maxY += yRange * 0.15;
minY -= yRange * 0.1;
if (minY < 0 && xAxisChannel == null) minY = 0;
maxX += xRange * 0.05;
minX -= xRange * 0.05;


return Column(
children: [
segmentDisplay,
Expanded(
child: LineChart(
LineChartData(
gridData: FlGridData(
show: true,
drawVerticalLine: false,
drawHorizontalLine: true,
getDrawingHorizontalLine: (value) => FlLine(
color: Colors.grey.withOpacity(0.3),
strokeWidth: 1,
),
),
titlesData: FlTitlesData(
leftTitles: AxisTitles(
axisNameWidget: Text(
xAxisChannel == null
? 'Value (${channelConfigs.isNotEmpty ? channelConfigs.values.first.unit : "Unit"})'
    : 'Value (${channelConfigs[selectedChannels.firstWhere((c) => c != xAxisChannel)]?.unit ?? "Unit"})',
style: const TextStyle(
color: Colors.black,
fontWeight: FontWeight.bold,
fontSize: 14,
),
),
sideTitles: SideTitles(
showTitles: true,
reservedSize: 60,
interval: max(0.1, yRange / 5), // Ensure non-zero interval
getTitlesWidget: (value, meta) {
if (!value.isFinite) return const SizedBox();
return Padding(
padding: const EdgeInsets.only(right: 8),
child: Text(
value.toStringAsFixed(2),
style: const TextStyle(color: Colors.black, fontSize: 12),
textAlign: TextAlign.right,
),
);
},
),
),
bottomTitles: AxisTitles(
axisNameWidget: Text(
xAxisChannel == null
? 'Time'
    : 'Value (${channelConfigs[xAxisChannel]?.unit ?? "Unit"})',
style: const TextStyle(
color: Colors.black,
fontWeight: FontWeight.bold,
fontSize: 14,
),
),
sideTitles: SideTitles(
showTitles: true,
reservedSize: 40,
interval: xAxisChannel == null ? timeRangeMs / 5 : max(0.1, xRange / 5), // Ensure non-zero interval
getTitlesWidget: (value, meta) {
if (!value.isFinite) return const SizedBox();
if (xAxisChannel == null) {
final time = DateTime.fromMillisecondsSinceEpoch(value.toInt());
return Padding(
padding: const EdgeInsets.only(top: 8),
child: Text(
"${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}",
style: const TextStyle(color: Colors.black, fontSize: 12),
),
);
} else {
return Padding(
padding: const EdgeInsets.only(top: 8),
child: Text(
value.toStringAsFixed(2),
style: const TextStyle(color: Colors.black, fontSize: 12),
),
);
}
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
if (xAxisChannel != null && selectedChannels.length == 2) {
final yChannel = selectedChannels.firstWhere((c) => c != xAxisChannel);
final xChannelName = channelConfigs[xAxisChannel]?.channelName ?? xAxisChannel!;
final yChannelName = channelConfigs[yChannel]?.channelName ?? yChannel;
return LineTooltipItem(
'$yChannelName: ${spot.y.toStringAsFixed(2)} ${channelConfigs[yChannel]?.unit ?? ''}\n'
'$xChannelName: ${spot.x.toStringAsFixed(2)} ${channelConfigs[xAxisChannel]?.unit ?? ''}',
const TextStyle(color: Colors.white, fontSize: 12),
);
} else {
final channel = selectedChannels.toList()[spot.barIndex];
final channelName = channelConfigs[channel]?.channelName ?? 'Unknown';
final time = DateTime.fromMillisecondsSinceEpoch(spot.x.toInt());
return LineTooltipItem(
'Channel: $channelName\n'
'Value: ${spot.y.toStringAsFixed(2)} ${channelConfigs[channel]?.unit ?? ''}\n'
'Time: ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}',
const TextStyle(color: Colors.white, fontSize: 12),
);
}
}).toList();
},
),
handleBuiltInTouches: true,
),
),
),
),
],
);
},
);
}

Widget _buildTitleBarButton({
required IconData icon,
required String tooltip,
required VoidCallback onPressed,
bool isClose = false,
}) {
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
builder: (context, child) {
return Transform.scale(
scale: 1.0 + (_animationController!.value * 0.1),
child: SizedBox(
width: 28,
height: 28,
child: Icon(
icon,
color: Colors.white,
size: 18,
),
),
);
},
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
decoration: InputDecoration(
labelText: label,
labelStyle: const TextStyle(fontSize: 12, color: Colors.black87),
border: OutlineInputBorder(
borderRadius: BorderRadius.circular(8),
),
isDense: true,
),
style: const TextStyle(fontSize: 12),
onChanged: (value) {
setState(() {
final hours = double.tryParse(_timeRangeHrController.text) ?? 0.0;
final minutes = double.tryParse(_timeRangeMinController.text) ?? 0.0;
timeRangeHours = hours.clamp(0.0, 24.0);
timeRangeMinutes = minutes.clamp(0.0, 59.0);
if (timeRangeHours == 0 && timeRangeMinutes == 0) {
timeRangeMinutes = 1.0;
_timeRangeMinController.text = '1';
}
final timeRangeMs = (timeRangeHours + (timeRangeMinutes / 60)) * 3600000;
final newSegments = _dataNotifier.dataByChannelSegments.map((channel, segments) => MapEntry(
channel,
_createSegments(
segments.expand((s) => s).toList(),
timeRangeMs,
),
));
_dataNotifier.updateData(
newData: newSegments,
newColors: _dataNotifier.channelColors,
newConfigs: _dataNotifier.channelConfigs,
);
currentSegmentIndex = newSegments.values
    .where((segments) => segments.isNotEmpty)
    .map((segments) => segments.length - 1)
    .reduce(max);
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
constraints: BoxConstraints(
maxWidth: windowWidth - (isChannelPanelOpen.value ? 250 : 0) - 32, // Dynamic width
maxHeight: 100,
),
decoration: BoxDecoration(
color: Colors.white.withOpacity(0.95),
borderRadius: BorderRadius.circular(8),
boxShadow: [
if (open)
BoxShadow(
color: Colors.black.withOpacity(0.1),
blurRadius: 4,
offset: const Offset(0, 2),
),
],
),
child: open
? AnimatedBuilder(
animation: _dataNotifier,
builder: (context, _) {
return SingleChildScrollView(
child: Padding(
padding: const EdgeInsets.all(8),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Wrap(
spacing: 8,
runSpacing: 4,
children: selectedChannels.map((channel) {
final color = _dataNotifier.channelColors[channel] ?? Colors.blue;
final peak = peakValues[channel];
final channelName = _dataNotifier.channelConfigs[channel]?.channelName ?? channel;
final peakText = peak != null && showPeaks.value
? ' (${peak['y'].toStringAsFixed(1)})'
    : '';
return GestureDetector(
onTap: () {
setState(() {
if (selectedChannels.contains(channel)) {
if (selectedChannels.length <= 1) {
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(
content: Text('At least one channel must be selected.'),
),
);
return;
}
selectedChannels.remove(channel);
peakValues.remove(channel);
} else {
selectedChannels.add(channel);
}
if (selectedChannels.length != 2) {
xAxisChannel = null;
showXAxisOptions = true;
}
initialSelectionDone = selectedChannels.isNotEmpty;
});
},
child: Row(
mainAxisSize: MainAxisSize.min,
children: [
Container(
width: 12,
height: 12,
decoration: BoxDecoration(
color: color,
shape: BoxShape.circle,
border: Border.all(
color: selectedChannels.contains(channel) ? Colors.black : Colors.grey,
width: selectedChannels.contains(channel) ? 1.5 : 1,
),
),
),
const SizedBox(width: 4),
ConstrainedBox(
constraints: const BoxConstraints(maxWidth: 150),
child: Text(
'$channelName$peakText',
style: TextStyle(
fontSize: 11,
color: selectedChannels.contains(channel) ? Colors.black : Colors.grey,
),
overflow: TextOverflow.ellipsis,
),
),
],
),
);
}).toList(),
),
const SizedBox(height: 4),
Row(
mainAxisSize: MainAxisSize.min,
children: [
const Text(
'Segment Duration:',
style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
),
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
const Text(
'X-Axis:',
style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
),
const SizedBox(width: 8),
Wrap(
spacing: 8,
runSpacing: 4,
children: [
if (showXAxisOptions) ...[
TextButton(
onPressed: () {
setState(() {
xAxisChannel = null;
showXAxisOptions = false;
});
},
child: Text(
'Time',
style: TextStyle(
fontSize: 12,
color: xAxisChannel == null ? AppColors.submitButton : Colors.black87,
fontWeight: xAxisChannel == null ? FontWeight.bold : FontWeight.normal,
),
),
),
...selectedChannels.map((channel) => TextButton(
onPressed: () {
setState(() {
xAxisChannel = channel;
showXAxisOptions = false;
});
},
child: Text(
_dataNotifier.channelConfigs[channel]?.channelName ?? channel,
style: TextStyle(
fontSize: 12,
color: xAxisChannel == channel ? AppColors.submitButton : Colors.black87,
fontWeight: xAxisChannel == channel ? FontWeight.bold : FontWeight.normal,
),
),
)),
] else ...[
TextButton(
onPressed: () {
setState(() {
showXAxisOptions = true;
});
},
child: const Text(
'Select X-Axis',
style: TextStyle(
fontSize: 12,
color: AppColors.submitButton,
fontWeight: FontWeight.bold,
),
),
),
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
)
    : null,
);
},
);
}

Widget _buildResizeHandle(String edge, {double size = 10}) {
return GestureDetector(
onPanUpdate: (details) => _resizeWindow(details, edge),
child: MouseRegion(
cursor: edge.contains('top') && edge.contains('left')
? SystemMouseCursors.resizeUpLeft
    : edge.contains('top') && edge.contains('right')
? SystemMouseCursors.resizeUpRight
    : edge.contains('bottom') && edge.contains('left')
? SystemMouseCursors.resizeDownLeft
    : edge.contains('bottom') && edge.contains('right')
? SystemMouseCursors.resizeDownRight
    : edge.contains('top')
? SystemMouseCursors.resizeUp
    : edge.contains('bottom')
? SystemMouseCursors.resizeDown
    : edge.contains('left')
? SystemMouseCursors.resizeLeft
    : SystemMouseCursors.resizeRight,
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
return Material(
elevation: 8,
borderRadius: BorderRadius.circular(12),
child: Stack(
children: [
Container(
width: windowWidth,
height: windowHeight,
decoration: BoxDecoration(
gradient: const LinearGradient(
colors: [Colors.white, Color(0xFFF5F5F5)],
begin: Alignment.topCenter,
end: Alignment.bottomCenter,
),
borderRadius: BorderRadius.circular(12),
border: Border.all(color: Colors.grey.withOpacity(0.3)),
boxShadow: [
BoxShadow(
color: Colors.black.withOpacity(0.2),
blurRadius: 12,
offset: const Offset(0, 4),
),
],
),
child: Column(
children: [
GestureDetector(
onPanUpdate: _updatePosition,
child: Container(
padding: EdgeInsets.symmetric(horizontal: 12, vertical: isMinimized ? 4 : 8),
decoration: BoxDecoration(
gradient: LinearGradient(
colors: [AppColors.submitButton, AppColors.submitButton.withOpacity(0.8)],
begin: Alignment.topLeft,
end: Alignment.bottomRight,
),
borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
boxShadow: [
BoxShadow(
color: Colors.black.withOpacity(0.1),
blurRadius: 4,
offset: const Offset(0, 2),
),
],
),
child: Row(
mainAxisAlignment: MainAxisAlignment.spaceBetween,
children: [
Row(
children: [
const Icon(
Icons.show_chart,
color: Colors.white,
size: 18,
),
const SizedBox(width: 8),
Text(
"Live Graph - ${widget.windowId}",
style: TextStyle(
color: Colors.white,
fontWeight: FontWeight.bold,
fontSize: isMinimized ? 12 : 14,
letterSpacing: 1.1,
),
),
],
),
Row(
children: [
_buildTitleBarButton(
icon: Icons.remove,
tooltip: isMinimized ? 'Restore' : 'Minimize',
onPressed: _minimizeWindow,
),
_buildTitleBarButton(
icon: isMaximized ? Icons.fullscreen_exit : Icons.fullscreen,
tooltip: isMaximized ? 'Restore' : 'Maximize',
onPressed: _maximizeWindow,
),
_buildTitleBarButton(
icon: Icons.close,
tooltip: 'Close',
onPressed: _closeWindow,
isClose: true,
),
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
ValueListenableBuilder<bool>(
valueListenable: isChannelPanelOpen,
builder: (context, open, _) {
return Tooltip(
message: open ? 'Hide Channel Panel' : 'Show Channel Panel',
child: IconButton(
icon: Icon(
open ? Icons.arrow_left : Icons.arrow_right,
color: AppColors.submitButton,
),
onPressed: () {
if (!initialSelectionDone && !open) {
isChannelPanelOpen.value = true;
} else if (initialSelectionDone) {
isChannelPanelOpen.value = !open;
}
},
),
);
},
),
ValueListenableBuilder<bool>(
valueListenable: showPeaks,
builder: (context, show, _) {
return Tooltip(
message: show ? 'Hide Peaks' : 'Show Peaks',
child: IconButton(
icon: Icon(
Icons.insights,
color: show ? AppColors.submitButton : Colors.grey,
),
onPressed: () {
showPeaks.value = !show;
if (!show) {
setState(() {
peakValues.clear();
});
}
},
),
);
},
),
ValueListenableBuilder<bool>(
valueListenable: isLegendPanelOpen,
builder: (context, open, _) {
return Tooltip(
message: open ? 'Hide Legend Panel' : 'Show Legend Panel',
child: IconButton(
icon: Icon(
open ? Icons.arrow_drop_down : Icons.arrow_drop_up,
color: AppColors.submitButton,
),
onPressed: () {
isLegendPanelOpen.value = !open;
},
),
);
},
),
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
);
}
}


