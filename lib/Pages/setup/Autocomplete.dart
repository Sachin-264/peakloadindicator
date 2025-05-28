import 'dart:io';
import 'package:intl/intl.dart';
import 'dart:typed_data';
import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'; // Keep for ConflictAlgorithm

// Replaced AppColors with ThemeColors
// import '../../constants/colors.dart';
import '../../constants/global.dart';
import '../../constants/database_manager.dart'; // ADDED: Import DatabaseManager
import 'package:flutter/foundation.dart'; // For debugPrint

import '../../constants/sessionmanager.dart';
import '../../constants/theme.dart'; // ADDED: Import ThemeColors
import '../NavPages/channel.dart'; // Assuming this path is correct, might need adjustment
import '../Secondary_window/secondary_window.dart';
import '../homepage.dart';
import '../logScreen/log.dart'; // Assuming log screen is available for logging

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class AutoStartScreen extends StatefulWidget {
final List<dynamic> selectedChannels;
final double endTimeHr;
final double endTimeMin;
final double scanTimeSec;
const AutoStartScreen({
super.key,
required this.selectedChannels,
required this.endTimeHr,
required this.endTimeMin,
required this.scanTimeSec,
});

@override
State<AutoStartScreen> createState() => _AutoStartScreenState();
}

class _AutoStartScreenState extends State<AutoStartScreen> {
// --- Serial Port Variables (now loaded from DB) ---
String? _portName; // Will be loaded from DB
int? _baudRate;    // Will be loaded from DB
int? _dataBits;    // Will be loaded from DB
String? _parity;   // Will be loaded from DB
int? _stopBits;    // Will be loaded from DB

SerialPort? port;
Map<String, List<Map<String, dynamic>>> dataByChannel = {};
Map<double, Map<String, dynamic>> _bufferedData = {};
String buffer = "";
late Widget portMessage;
List<String> errors = [];
Map<String, Color> channelColors = {};
bool isScanning = false;
bool isCancelled = false;
bool isManuallyStopped = false;
SerialPortReader? reader;
StreamSubscription<Uint8List>? _readerSubscription;
DateTime? lastDataTime;
int scanIntervalSeconds = 1;
int currentGraphIndex = 0;
Map<String, List<List<Map<String, dynamic>>>> segmentedDataByChannel = {};
final ScrollController _scrollController = ScrollController();
final ScrollController _tableScrollController = ScrollController();
String yAxisType = 'Load'; // Not actively used
Timer? _reconnectTimer;
Timer? _testDurationTimer;
Timer? _tableUpdateTimer;
Timer? _endTimeTimer;
int _reconnectAttempts = 0;
int _lastScanIntervalSeconds = 1;
Timer? _debounceTimer;
static const int _maxReconnectAttempts = 5;
static const int _minInactivityTimeoutSeconds = 5;
static const int _maxInactivityTimeoutSeconds = 30;
static const int _reconnectPeriodSeconds = 5;
String? _selectedGraphChannel;
bool _showGraphDots = false; // New state variable for showing graph dots

final _fileNameController = TextEditingController();
final _operatorController = TextEditingController();
final _scanRateHrController = TextEditingController(text: '0');
final _scanRateMinController = TextEditingController(text: '0');
final _scanRateSecController = TextEditingController(text: '1');
final _testDurationDayController = TextEditingController(text: '0');
final _testDurationHrController = TextEditingController(text: '0');
final _testDurationMinController = TextEditingController(text: '0');
final _testDurationSecController = TextEditingController(text: '0');
final _graphVisibleHrController = TextEditingController(text: '0');
final _graphVisibleMinController = TextEditingController(text: '60');

Map<String, Channel> channelConfigs = {};
final List<OverlayEntry> _windowEntries = [];

// Helper for consistent log timestamp
String get _currentTime => DateFormat('HH:mm:ss').format(DateTime.now());

@override
void initState() {
super.initState();
portMessage = Text(
"Loading port settings...", style: GoogleFonts.roboto(fontSize: 16));
_loadComPortSettings(); // Load settings first
_initializeChannelConfigs(); // Initialize channel configs based on selected channels
_startReconnectTimer(); // Start periodic check for port status

// Set initial scan rate from widget
_scanRateSecController.text = widget.scanTimeSec.toInt().toString();
scanIntervalSeconds = widget.scanTimeSec.toInt();
_lastScanIntervalSeconds = scanIntervalSeconds;

// Calculate and set initial test duration based on end time
final now = DateTime.now();
final endTimeToday = DateTime(
now.year, now.month, now.day, widget.endTimeHr.toInt(), widget.endTimeMin.toInt());
final endTime = now.isAfter(endTimeToday)
? endTimeToday.add(const Duration(days: 1)) // Next day if end time passed
    : endTimeToday;
final duration = endTime.difference(now);
final durationHours = duration.inHours;
final durationMinutes = duration.inMinutes % 60;
_testDurationHrController.text = durationHours.toString();
_testDurationMinController.text = durationMinutes.toString();

_startEndTimeCheck(); // Start end time check
}

Future<void> _loadComPortSettings() async {
try {
final settings = await DatabaseManager().getComPortSettings();
if (settings != null) {
setState(() {
_portName = settings['selectedPort'] as String?;
_baudRate = settings['baudRate'] as int?;
_dataBits = settings['dataBits'] as int?;
_parity = settings['parity'] as String?;
_stopBits = settings['stopBits'] as int?;
portMessage = Text(
_portName != null ? "Ready to start scanning on $_portName" : "Port not configured",
style: GoogleFonts.roboto(fontSize: 16, color: ThemeColors.getColor('serialPortMessageText', Global.isDarkMode.value)));
LogPage.addLog('[$_currentTime] COM Port settings loaded: $_portName, $_baudRate. Ready to scan.');
});
} else {
setState(() {
portMessage = Text(
"No COM port settings found in database. Using default fallback settings.",
style: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortErrorTextSmall', Global.isDarkMode.value), fontSize: 16));
_portName = 'COM6'; // Default fallback
_baudRate = 2400; // Default fallback
_dataBits = 8;    // Default fallback
_parity = 'None'; // Default fallback
_stopBits = 1;    // Default fallback
LogPage.addLog('[$_currentTime] No COM Port settings found, using defaults: COM6.');
});
}
} catch (e) {
setState(() {
portMessage = Text("Error loading port settings: $e",
style: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortErrorTextSmall', Global.isDarkMode.value), fontSize: 16));
_portName = 'COM6'; // Default fallback on error
_baudRate = 2400; // Default fallback
_dataBits = 8;    // Default fallback
_parity = 'None'; // Default fallback
_stopBits = 1;    // Default fallback
errors.add('Error loading port settings: $e');
LogPage.addLog('[$_currentTime] Error loading COM Port settings: $e');
});
}
_initPort(); // Initialize port after settings are loaded
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
// Compare only hour and minute for the current day
if (now.hour == endHour && now.minute == endMinute && isScanning) {
debugPrint('End time reached: $endHour:$endMinute, stopping scan and saving data');
timer.cancel();
_stopScan();
_saveData();
setState(() {
portMessage = Text('End time reached, scan stopped and data saved',
style: GoogleFonts.roboto(color: ThemeColors.getColor('successText', Global.isDarkMode.value), fontSize: 16));
errors.add('End time reached, scan stopped and data saved');
});
// Navigate back to HomePage after a short delay to allow UI to update
Future.delayed(const Duration(seconds: 2), () {
Navigator.pushReplacement(
context,
MaterialPageRoute(builder: (context) => const HomePage()),
);
});
}
});
}

void _initPort() {
if (_portName == null || _portName!.isEmpty) {
setState(() {
portMessage = Text("COM Port name is not configured.",
style: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortErrorTextSmall', Global.isDarkMode.value), fontSize: 16));
errors.add("COM Port name is not configured.");
});
LogPage.addLog('[$_currentTime] COM Port name not configured. Cannot initialize.');
return;
}

if (port != null) {
try {
if (port!.isOpen) {
port!.close();
}
port!.dispose(); // Dispose previous port instance
} catch (e) {
debugPrint('Error cleaning up previous port: $e');
}
}

try {
port = SerialPort(_portName!);
} on SerialPortError catch (e) {
debugPrint('SerialPortError initializing SerialPort object: ${e.message}');
setState(() {
portMessage = Text('Error initializing port $_portName: ${e.message}',
style: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortErrorTextSmall', Global.isDarkMode.value), fontSize: 16));
errors.add('Error initializing port $_portName: ${e.message}');
});
port = null;
LogPage.addLog('[$_currentTime] Failed to initialize serial port $_portName: ${e.message}');
} catch (e) {
debugPrint('Generic error initializing SerialPort object: $e');
setState(() {
portMessage = Text('Error initializing port $_portName: $e',
style: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortErrorTextSmall', Global.isDarkMode.value), fontSize: 16));
errors.add('Error initializing port $_portName: $e');
});
port = null;
LogPage.addLog('[$_currentTime] Failed to initialize serial port $_portName: $e');
}
}

void _initializeChannelConfigs() {
channelConfigs.clear();
channelColors.clear();

// Define fallback colors in case graphLineColour is invalid or transparent
const List<Color> fallbackColors = [
Colors.blue,
Colors.red,
Colors.green,
Colors.purple,
Colors.orange,
Colors.teal,
Colors.pink,
Colors.cyan,
Colors.brown,
Colors.indigo,
];

for (int i = 0; i < widget.selectedChannels.length; i++) {
final channelData = widget.selectedChannels[i];
try {
Channel channel;
if (channelData is Channel) {
channel = channelData;
} else if (channelData is Map<String, dynamic>) {
channel = Channel.fromJson(channelData);
} else {
throw Exception('Invalid channel data type at index $i');
}

final channelId = channel.startingCharacter;
channelConfigs[channelId] = channel;

// Set initial color from graphLineColour (AARRGGBB format)
Color channelColor = Color(channel.graphLineColour);
// Validate if color is reasonable; if not, use fallback
if (channel.graphLineColour == 0 || channelColor.alpha == 0) {
debugPrint('Channel Color Tracking: Invalid/empty graphLineColour for channel ${channel.channelName}, using fallback color ${fallbackColors[i % fallbackColors.length]}');
channelColor = fallbackColors[i % fallbackColors.length];
}
channelColors[channelId] = channelColor;

debugPrint('Channel Color Tracking: Configured channel ${channel.channelName} (${channelId}) with color ${channelColor.toHexString()}');
} catch (e) {
debugPrint('Error configuring channel at index $i: $e');
setState(() {
errors.add('Invalid channel configuration at index $i: $e');
});
LogPage.addLog('[$_currentTime] Invalid channel configuration: $e');
}
}

if (channelConfigs.isEmpty) {
setState(() {
portMessage = Text('No valid channels configured',
style: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortErrorTextSmall', Global.isDarkMode.value), fontSize: 16));
errors.add('No valid channels configured');
});
LogPage.addLog('[$_currentTime] No valid channels configured.');
}
}

void _showColorPicker(String channelId, bool isDarkMode) {
Color tempSelectedColor = channelColors[channelId]!; // Temporary variable to hold the color chosen in picker

showDialog(
context: context,
builder: (context) {
// StatefulBuilder allows managing the internal state of the dialog (like checkbox and picker color)
return StatefulBuilder(
builder: (BuildContext context, StateSetter setStateInDialog) {
bool isDefault = false; // Checkbox state, managed by setStateInDialog

return AlertDialog(
backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
title: Text('Select Color for Channel ${channelConfigs[channelId]?.channelName ?? 'Unknown'}',
style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode))),
content: SingleChildScrollView(
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
ColorPicker(
pickerColor: tempSelectedColor,
onColorChanged: (Color color) {
setStateInDialog(() { // Update dialog's internal state
tempSelectedColor = color; // Update temp color in dialog
});
},
showLabel: true,
pickerAreaHeightPercent: 0.8,
labelTypes: const [], // Hide labels for compactness
colorPickerWidth: 300,
portraitOnly: true,
displayThumbColor: true,
pickerAreaBorderRadius: BorderRadius.circular(10),
),
Row(
children: [
Checkbox(
value: isDefault,
onChanged: (bool? value) {
setStateInDialog(() { // Update dialog's internal state
isDefault = value ?? false;
});
},
checkColor: ThemeColors.getColor('submitButton', isDarkMode),
activeColor: ThemeColors.getColor('submitButton', isDarkMode).withOpacity(0.3),
),
Text('Set as default color',
style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogSubText', isDarkMode))),
],
),
],
),
),
actions: [
TextButton(
onPressed: () {
setState(() { // This setState rebuilds the main SerialPortScreen widget
channelColors[channelId] = tempSelectedColor; // Update the runtime color from temp
});

if (isDefault) {
_updateChannelColorInDatabase(channelId, tempSelectedColor);
}

Navigator.of(context).pop();
},
child: Text('Done',
style: GoogleFonts.roboto(color: ThemeColors.getColor('submitButton', isDarkMode))),
),
],
);
},
);
},
);
}

Future<void> _updateChannelColorInDatabase(String channelId, Color color) async {
try {
final database = await DatabaseManager().database;

final channel = channelConfigs[channelId]!;
// Store AARRGGBB value
int colorValue = color.value; // Color.value directly gives AARRGGBB integer
debugPrint('Channel Color Tracking: Updating ChannelColour to ${colorValue.toRadixString(16)} for channel ${channel.channelName} (RecNo: ${channel.recNo})');

await database.update(
'ChannelSetup', // Assuming your channel configuration table is named 'ChannelSetup'
    {'ChannelColour': colorValue}, // Assuming 'ChannelColour' is the column for graphLineColour
where: 'StartingCharacter = ? AND RecNo = ?', // Using StartingCharacter and RecNo for unique identification
whereArgs: [channelId, channel.recNo],
);

LogPage.addLog('[$_currentTime] Channel ${channel.channelName} graph color updated as default in DB.');
} catch (e) {
debugPrint('Error updating channel color in database: $e');
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text('Error saving default color: $e'),
backgroundColor: Colors.red,
duration: const Duration(seconds: 3),
),
);
LogPage.addLog('[$_currentTime] Error saving default channel color: $e');
}
}

void _configurePort() {
if (port == null || !port!.isOpen) return;
final config = SerialPortConfig()
..baudRate = _baudRate ?? 2400
..bits = _dataBits ?? 8
..parity = (_parity == 'Even' ? SerialPortParity.even : _parity == 'Odd' ? SerialPortParity.odd : SerialPortParity.none)
..stopBits = _stopBits ?? 1
..setFlowControl(SerialPortFlowControl.none);
try {
port!.config = config;
debugPrint('Port configured: baudRate=${config.baudRate}, bits=${config.bits}');
} catch (e) {
debugPrint('Error configuring port: $e');
setState(() {
portMessage = Text('Port config error: $e',
style: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortErrorTextSmall', Global.isDarkMode.value), fontSize: 16));
errors.add('Port config error: $e');
});
LogPage.addLog('[$_currentTime] Serial port configuration error: $e');
} finally {
config.dispose();
}
}

int _getInactivityTimeout() {
int timeout = scanIntervalSeconds + 10;
return timeout.clamp(
_minInactivityTimeoutSeconds, _maxInactivityTimeoutSeconds);
}

void _updateGraphData(Map<String, dynamic> newData) {
dataByChannel[newData['Channel']] = [
...(dataByChannel[newData['Channel']] ?? []),
newData,
];
Global.graphDataSink.add({
'dataByChannel': Map.from(dataByChannel),
'channelColors': Map.from(channelColors),
'channelConfigs': Map.from(channelConfigs),
'isDarkMode': Global.isDarkMode.value, // Pass dark mode status
});
}

void _openFloatingGraphWindow() {
late OverlayEntry entry;
Offset position = const Offset(100, 100);

entry = OverlayEntry(builder: (context) {
return Positioned(
left: position.dx,
top: position.dy,
child: MultiWindowGraph(
windowId: 'window_${_windowEntries.length}',
initialData: dataByChannel,
channelColors: channelColors,
channelConfigs: channelConfigs,
entry: entry,
onPositionUpdate: (newPosition) {
position = newPosition;
entry.markNeedsBuild();
},
onClose: (closedEntry) {
_windowEntries.remove(closedEntry);
},
),
);
});

Overlay.of(context)?.insert(entry);
_windowEntries.add(entry);
LogPage.addLog('[$_currentTime] New floating graph window opened.');
}

void _startReconnectTimer() {
_reconnectTimer?.cancel();
_reconnectTimer =
Timer.periodic(Duration(seconds: _reconnectPeriodSeconds), (timer) {
if (isCancelled || isManuallyStopped) {
debugPrint('Autoreconnect: Stopped by user');
return;
}
if (isScanning && lastDataTime != null && DateTime
    .now()
    .difference(lastDataTime!)
    .inSeconds > _getInactivityTimeout()) {
debugPrint(
'No data received for ${_getInactivityTimeout()} seconds, reconnecting...');
LogPage.addLog('[$_currentTime] No data received. Attempting to reconnect serial port.');
_autoStopAndReconnect();
} else if (!isScanning) {
debugPrint('Autoreconnect: Attempting to restart scan...');
_autoStartScan();
}
});
}

void _autoStopAndReconnect() {
debugPrint(
'Autoreconnect triggered: No data for ${_getInactivityTimeout()} seconds');
if (isScanning) {
_stopScanInternal();
setState(() {
portMessage = Text('Port disconnected - Reconnecting...',
style: GoogleFonts.roboto(color: Colors.orange, fontSize: 16));
errors.add('Port disconnected - Reconnecting...');
});
_reconnectAttempts = 0;
}
}

void _autoStartScan() {
if (!isScanning && !isCancelled && !isManuallyStopped &&
_reconnectAttempts < _maxReconnectAttempts) {
try {
debugPrint('Autoreconnect: Attempt ${_reconnectAttempts + 1}/$_maxReconnectAttempts');
LogPage.addLog('[$_currentTime] Attempting to auto-restart scan (Attempt ${_reconnectAttempts + 1}).');
if (_portName == null || _portName!.isEmpty) {
throw Exception('Port name not set. Cannot auto-reconnect.');
}

if (port == null || !port!.isOpen) {
_initPort();
if (port == null) {
throw Exception('Failed to initialize port $_portName.');
}
if (!port!.openReadWrite()) {
final lastError = SerialPort.lastError;
throw Exception('Failed to open port for read/write: ${lastError?.message ?? "Unknown error"}');
}
}
_configurePort();
port!.flush();
_setupReader();
setState(() {
isScanning = true;
portMessage = Text('Reconnected to $_portName - Scanning resumed',
style: GoogleFonts.roboto(color: Colors.green,
fontSize: 16,
fontWeight: FontWeight.w600));
errors.add('Reconnected to $_portName - Scanning resumed');
});
_reconnectAttempts = 0;
_startTableUpdateTimer();
_addTableRow();
LogPage.addLog('[$_currentTime] Auto-reconnected to $_portName. Scanning resumed.');
} catch (e) {
debugPrint('Autoreconnect: Error: $e');
setState(() {
portMessage = Text('Reconnect error: $e',
style: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortErrorTextSmall', Global.isDarkMode.value), fontSize: 16));
errors.add('Reconnect error: $e');
});
_reconnectAttempts++;
LogPage.addLog('[$_currentTime] Failed to auto-restart scan: $e');
}
} else if (_reconnectAttempts >= _maxReconnectAttempts) {
setState(() {
portMessage =
Text('Reconnect failed after $_maxReconnectAttempts attempts',
style: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortErrorTextSmall', Global.isDarkMode.value), fontSize: 16));
errors.add('Reconnect failed after $_maxReconnectAttempts attempts');
});
LogPage.addLog('[$_currentTime] Auto-reconnect failed after $_maxReconnectAttempts attempts. Stopping auto-reconnect.');
}
}

void _setupReader() {
if (port == null || !port!.isOpen) return;
_readerSubscription?.cancel();
reader?.close();
reader = SerialPortReader(port!, timeout: 500);
_readerSubscription = reader!.stream.listen(
(Uint8List data) {
final decoded = String.fromCharCodes(data);
buffer += decoded;

String regexPattern = channelConfigs.entries.map((e) => '\\${e.value
    .startingCharacter}[0-9]+\\.[0-9]+').join('|'); // Adjusted regex for flexibility
final regex = RegExp(regexPattern);
final matches = regex.allMatches(buffer).toList();

for (final match in matches) {
final extracted = match.group(0);
if (extracted != null && channelConfigs.containsKey(extracted[0])) {
_addToDataList(extracted);
}
}

if (matches.isNotEmpty) {
buffer = buffer.replaceAll(regex, '');
}

if (buffer.length > 1000 && matches.isEmpty) {
debugPrint('Buffer length > 1000 and no matches. Clearing buffer to prevent overflow.');
buffer = '';
LogPage.addLog('[$_currentTime] Data stream not recognized. Clearing buffer.');
}
lastDataTime = DateTime.now();
},
onError: (error) {
debugPrint('Stream error: $error');
setState(() {
portMessage = Text('Error reading data: $error',
style: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortErrorTextSmall', Global.isDarkMode.value), fontSize: 16));
errors.add('Error reading data: $error');
});
LogPage.addLog('[$_currentTime] Error reading data from serial port: $error');
},
onDone: () {
debugPrint('Stream done');
if (isScanning) {
setState(() {
portMessage = Text('Port disconnected - Reconnecting...',
style: GoogleFonts.roboto(color: Colors.orange, fontSize: 16));
errors.add('Port disconnected - Reconnecting...');
});
LogPage.addLog('[$_currentTime] Serial port disconnected. Attempting to reconnect.');
}
},
);
}

void _startScan() {
if (!isScanning) {
try {
debugPrint('Starting scan...');
LogPage.addLog('[$_currentTime] Starting data scan on $_portName.');
if (channelConfigs.isEmpty) {
throw Exception('No channels configured');
}
if (_portName == null || _portName!.isEmpty) {
throw Exception('COM Port not configured.');
}

if (port == null || !port!.isOpen) {
_initPort();
if (port == null) {
throw Exception('Failed to initialize port $_portName.');
}
if (!port!.openReadWrite()) {
final lastError = SerialPort.lastError;
throw Exception('Failed to open port for read/write: ${lastError?.message ?? "Unknown error"}');
}
}
_configurePort();
port!.flush();
_setupReader();
setState(() {
isScanning = true;
isCancelled = false;
isManuallyStopped = false;
portMessage = Text('Scanning active on $_portName',
style: GoogleFonts.roboto(color: Colors.green,
fontWeight: FontWeight.w600,
fontSize: 16));
errors.add('Scanning active on $_portName');
if (segmentedDataByChannel.isNotEmpty) {
currentGraphIndex = segmentedDataByChannel.values.first.length - 1;
}
});
_reconnectAttempts = 0;

_startTableUpdateTimer();

_testDurationTimer?.cancel();
int testDurationSeconds = _calculateDurationInSeconds(
_testDurationDayController.text,
_testDurationHrController.text,
_testDurationMinController.text,
_testDurationSecController.text,
);
if (testDurationSeconds > 0) {
_testDurationTimer =
Timer(Duration(seconds: testDurationSeconds), () {
_stopScan();
setState(() {
portMessage = Text('Test duration reached, scanning stopped',
style: GoogleFonts.roboto(
color: ThemeColors.getColor('successText', Global.isDarkMode.value), fontSize: 16));
errors.add('Test duration reached, scanning stopped');
});
debugPrint('[SERIAL_PORT] Test duration of $testDurationSeconds seconds reached, stopped scanning');
LogPage.addLog('[$_currentTime] Test duration of ${Duration(seconds: testDurationSeconds).inMinutes} minutes reached. Scanning stopped automatically.');
});
}
} catch (e) {
debugPrint('Error starting scan: $e');
setState(() {
portMessage = Text('Error starting scan: $e',
style: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortErrorTextSmall', Global.isDarkMode.value), fontSize: 16));
errors.add('Error starting scan: $e');
});
LogPage.addLog('[$_currentTime] Error starting scan: $e');
if (e.toString().contains('busy') ||
e.toString().contains('Access denied')) {
_cancelScan();
// _startScan(); // Removed this, as _cancelScan already calls _initPort for next scan
}
}
}
}

void _stopScan() {
_stopScanInternal();
setState(() {
isManuallyStopped = true;
portMessage = Text(
'Scanning stopped manually', style: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortMessageText', Global.isDarkMode.value), fontSize: 16));
errors.add('Scanning stopped manually');
});
_testDurationTimer?.cancel();
_tableUpdateTimer?.cancel();
LogPage.addLog('[$_currentTime] Scanning stopped manually.');
}

void _stopScanInternal() {
if (isScanning) {
try {
debugPrint('Stopping scan...');
_readerSubscription?.cancel();
reader?.close();
if (port != null && port!.isOpen) {
port!.close();
}
setState(() {
isScanning = false;
reader = null;
_readerSubscription = null;
portMessage =
Text('Scanning stopped', style: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortMessageText', Global.isDarkMode.value), fontSize: 16));
errors.add('Scanning stopped');
});
} catch (e) {
debugPrint('Error stopping scan: $e');
setState(() {
portMessage = Text('Error stopping scan: $e',
style: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortErrorTextSmall', Global.isDarkMode.value), fontSize: 16));
errors.add('Error stopping scan: $e');
});
LogPage.addLog('[$_currentTime] Error stopping scan: $e');
}
}
}

void _cancelScan() {
try {
debugPrint('Cancelling scan...');
_readerSubscription?.cancel();
reader?.close();
if (port != null && port!.isOpen) {
port!.close();
}
setState(() {
isScanning = false;
isCancelled = true;
isManuallyStopped = true; // Ensure manual stop flag is also set to prevent auto-reconnect
dataByChannel.clear();
_bufferedData.clear();
buffer = "";
segmentedDataByChannel.clear();
errors.clear();
currentGraphIndex = 0;
reader = null;
_readerSubscription = null;
port = null; // Ensure port object is nulled to be re-initialized if needed
portMessage =
Text('Scan cancelled', style: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortMessageText', Global.isDarkMode.value), fontSize: 16));
errors.add('Scan cancelled');
});
_initPort(); // Re-initialize port for potential next scan
_testDurationTimer?.cancel();
_tableUpdateTimer?.cancel();
_debounceTimer?.cancel(); // Cancel any active debounce timers
LogPage.addLog('[$_currentTime] Data scan cancelled. All data cleared.');
} catch (e) {
debugPrint('Error cancelling scan: $e');
setState(() {
portMessage = Text('Error cancelling scan: $e',
style: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortErrorTextSmall', Global.isDarkMode.value), fontSize: 16));
errors.add('Error cancelling scan: $e');
});
LogPage.addLog('[$_currentTime] Error cancelling scan: $e');
}
}

void _startTableUpdateTimer() {
_tableUpdateTimer?.cancel();
if (scanIntervalSeconds < 1) {
scanIntervalSeconds = 1;
}
if (scanIntervalSeconds != _lastScanIntervalSeconds) {
_lastScanIntervalSeconds = scanIntervalSeconds;
debugPrint('Table update timer interval changed to $scanIntervalSeconds seconds');
}
_tableUpdateTimer =
Timer.periodic(Duration(seconds: scanIntervalSeconds), (_) {
if (!isScanning || isCancelled || isManuallyStopped) {
_tableUpdateTimer?.cancel();
debugPrint('Table update timer cancelled due to scan state');
return;
}
_addTableRow();
});
debugPrint('Started table update timer with interval $scanIntervalSeconds seconds');
}

void _addTableRow() {
DateTime now = DateTime.now();
double timestamp = now.millisecondsSinceEpoch.toDouble();
String time = "${now.hour}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
String date = "${now.day}/${now.month}/${now.year}";

// Find the most recent data for each channel within the scan interval
Map<String, Map<String, dynamic>> latestChannelData = {};
double intervalStart = timestamp - (scanIntervalSeconds * 1000);
var recentTimestamps = _bufferedData.keys
    .where((t) => t >= intervalStart && t <= timestamp)
    .toList()
..sort();

for (var channel in channelConfigs.keys) {
Map<String, dynamic>? latestData;
for (var t in recentTimestamps.reversed) {
if (_bufferedData[t]?.containsKey(channel) == true) {
latestData = _bufferedData[t]![channel];
break;
}
}
latestChannelData[channel] = latestData ?? {'Value': 0.0, 'Data': ''};
}

// Clear buffered data older than the scan interval
_bufferedData.removeWhere((t, _) => t < intervalStart);

setState(() {
Map<String, dynamic> newData = {
'Serial No': '${(dataByChannel.isNotEmpty ? dataByChannel.values.first.length : 0) + 1}',
'Time': time,
'Date': date,
'Timestamp': timestamp,
};

channelConfigs.keys.forEach((channel) {
double value = (latestChannelData[channel]!['Value'] as num?)?.toDouble() ?? 0.0;
newData['Value_$channel'] = value.isFinite ? value : 0.0;
newData['Channel_$channel'] = channel;

var channelData = {
...newData,
'Value': newData['Value_$channel'],
'Channel': channel,
'Data': latestChannelData[channel]!['Data'] ?? '',
};

dataByChannel.putIfAbsent(channel, () => []).add(channelData);

// Call _updateGraphData for each channel's new data
_updateGraphData(channelData);
});

_segmentData(newData);
lastDataTime = now;

WidgetsBinding.instance.addPostFrameCallback((_) {
if (_scrollController.hasClients) {
_scrollController.animateTo(
_scrollController.position.maxScrollExtent,
duration: const Duration(milliseconds: 300),
curve: Curves.easeOut,
);
}
if (_tableScrollController.hasClients) {
_tableScrollController.animateTo(
_tableScrollController.position.maxScrollExtent,
duration: const Duration(milliseconds: 300),
curve: Curves.easeOut,
);
}
});

if (segmentedDataByChannel.isNotEmpty && segmentedDataByChannel.values.first.isNotEmpty) {
currentGraphIndex = segmentedDataByChannel.values.first.length - 1;
}
});
}

void _addToDataList(String data) {
DateTime now = DateTime.now();
final channelId = data[0];
if (!channelConfigs.containsKey(channelId)) {
debugPrint('Unknown channel: $channelId');
return;
}

final config = channelConfigs[channelId]!;
// Note: The previous logic had a fixed dataLength check `if (data.length != config.dataLength)`.
// Given the regex is now `[0-9]+\.[0-9]+` (flexible length after character),
// this check might be problematic if dataLength isn't exact.
// I've left it commented out in SerialPortScreen's version, keeping it commented here too for consistency.
// if (data.length != config.dataLength) {
//   debugPrint('Invalid data length for channel $channelId: $data (expected ${config.dataLength})');
//   return;
// }

final valueStr = data.substring(1);
double value = double.tryParse(valueStr) ?? 0.0;
double timestamp = now.millisecondsSinceEpoch.toDouble();

_bufferedData.putIfAbsent(timestamp, () => {});
_bufferedData[timestamp]![channelId] = {
'Value': value,
'Time': "${now.hour}:${now.minute.toString().padLeft(2, '0')}:${now.second
    .toString().padLeft(2, '0')}",
'Date': "${now.day}/${now.month}/${now.year}",
'Data': data,
'Timestamp': timestamp,
'Channel': channelId,
};
}

void _segmentData(Map<String, dynamic> newData) {
int graphVisibleSeconds = _calculateDurationInSeconds(
'0', _graphVisibleHrController.text, _graphVisibleMinController.text,
'0');
if (graphVisibleSeconds <= 0) {
debugPrint('[SEGMENT_DATA] Invalid graph visible duration: $graphVisibleSeconds seconds');
return;
}

double newTimestamp = newData['Timestamp'] as double;
channelConfigs.keys.forEach((channelId) {
segmentedDataByChannel.putIfAbsent(channelId, () => []);

if (segmentedDataByChannel[channelId]!.isEmpty) {
segmentedDataByChannel[channelId]!.add([
{
...newData,
'Value': newData['Value_$channelId'] ?? 0.0,
'Channel': channelId,
}
]);
return;
}

List<Map<String, dynamic>> lastSegment = segmentedDataByChannel[channelId]!
    .last;
double lastSegmentStartTime = lastSegment.first['Timestamp'] as double;

if ((newTimestamp - lastSegmentStartTime) / 1000 >= graphVisibleSeconds) {
segmentedDataByChannel[channelId]!.add([
{
...newData,
'Value': newData['Value_$channelId'] ?? 0.0,
'Channel': channelId,
}
]);
debugPrint('[SERIAL_PORT] Added new segment for channel $channelId at timestamp $newTimestamp');
} else {
segmentedDataByChannel[channelId]!.last.add({
...newData,
'Value': newData['Value_$channelId'] ?? 0.0,
'Channel': channelId,
});
}
});

if (segmentedDataByChannel.isNotEmpty && segmentedDataByChannel.values.first.isNotEmpty) {
setState(() {
currentGraphIndex = segmentedDataByChannel.values.first.length - 1;
});
}
}

int _calculateDurationInSeconds(String day, String hr, String min,
String sec) {
return ((int.tryParse(day) ?? 0) * 86400) +
((int.tryParse(hr) ?? 0) * 3600) +
((int.tryParse(min) ?? 0) * 60) +
(int.tryParse(sec) ?? 0);
}

void _updateScanInterval() {
final newInterval = _calculateDurationInSeconds(
'0',
_scanRateHrController.text,
_scanRateMinController.text,
_scanRateSecController.text,
);
if (newInterval != scanIntervalSeconds) {
setState(() {
scanIntervalSeconds = newInterval < 1 ? 1 : newInterval;
debugPrint('Scan interval updated: $scanIntervalSeconds seconds');
});
if (isScanning) {
_startTableUpdateTimer();
}
LogPage.addLog('[$_currentTime] Scan interval updated to $scanIntervalSeconds seconds.');
}
}

Future<void> _saveData() async {
bool isDarkMode = Global.isDarkMode.value; // Get current dark mode status
try {
debugPrint('Saving data to databases started...');
LogPage.addLog('[$_currentTime] Saving data to databases...');

showDialog(
context: context,
barrierDismissible: false,
builder: (BuildContext dialogContext) => Center(
child: CircularProgressIndicator(
valueColor: AlwaysStoppedAnimation<Color>(ThemeColors.getColor('submitButton', isDarkMode)),
),
),
);

final appDocumentsDir = await getApplicationSupportDirectory();
final dataFolder = Directory(path.join(appDocumentsDir.path, 'CountronicsData'));
if (!await dataFolder.exists()) {
await dataFolder.create(recursive: true);
}
debugPrint('Data folder: ${dataFolder.path}');

final now = DateTime.now();
final dateTimeString = DateFormat('yyyyMMddHHmmss').format(now);
final newDbFileName = 'serial_port_data_$dateTimeString.db';
final newDbPathFull = path.join(dataFolder.path, newDbFileName);
debugPrint('New database full path: $newDbPathFull');

final mainDatabase = await DatabaseManager().database;
debugPrint('Main database accessed via DatabaseManager.');

debugPrint('Opening new session database ($newDbFileName) via SessionDatabaseManager.');
final newSessionDatabase = await SessionDatabaseManager().openSessionDatabase(newDbFileName);
debugPrint('New session database opened and managed.');

SharedPreferences prefs = await SharedPreferences.getInstance();
int recNo = prefs.getInt('recNo') ?? 5;
debugPrint('Current record number: $recNo');

final testPayload = _prepareTestPayload(recNo, newDbFileName);
final test1Payload = _prepareTest1Payload(recNo);
final test2Payload = _prepareTest2Payload(recNo);

await mainDatabase.insert(
'Test',
testPayload,
conflictAlgorithm: ConflictAlgorithm.replace,
);
debugPrint('Inserted into main database Test table: $testPayload');

await newSessionDatabase.insert(
'Test',
testPayload,
conflictAlgorithm: ConflictAlgorithm.replace,
);
debugPrint('Inserted into new database Test table: $testPayload');

await newSessionDatabase.transaction((txn) async {
for (var entry in test1Payload) {
await txn.insert(
'Test1',
entry,
conflictAlgorithm: ConflictAlgorithm.replace,
);
}
});
debugPrint('Inserted ${test1Payload.length} entries into new database Test1 table');

await newSessionDatabase.insert(
'Test2',
test2Payload,
conflictAlgorithm: ConflictAlgorithm.replace,
);
debugPrint('Inserted into new database Test2 table: $test2Payload');

await prefs.setInt('recNo', recNo + 1);
debugPrint('Record number updated to: ${recNo + 1}');

Navigator.of(context).pop();

ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text('Data saved successfully to databases'),
backgroundColor: Colors.green,
duration: const Duration(seconds: 3),
),
);
LogPage.addLog('[$_currentTime] Data saved successfully to $newDbFileName.');
} catch (e, s) {
if (Navigator.of(context).canPop()) {
Navigator.of(context).pop();
}
debugPrint('Error saving data to databases: $e\nStackTrace: $s');
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text('Error saving data: $e'),
backgroundColor: ThemeColors.getColor('errorText', isDarkMode),
duration: const Duration(seconds: 3),
),
);
LogPage.addLog('[$_currentTime] Error saving data: $e');
}
}

Map<String, dynamic> _prepareTestPayload(int recNo, String newDbFileName) {
return {
"RecNo": recNo.toDouble(),
"FName": _fileNameController.text,
"OperatorName": _operatorController.text,
"TDate": DateFormat('yyyy-MM-dd').format(DateTime.now()),
"TTime": DateFormat('HH:mm:ss').format(DateTime.now()),
"ScanningRate": scanIntervalSeconds.toDouble(),
"ScanningRateHH": double.tryParse(_scanRateHrController.text) ?? 0.0,
"ScanningRateMM": double.tryParse(_scanRateMinController.text) ?? 0.0,
"ScanningRateSS": double.tryParse(_scanRateSecController.text) ?? 0.0,
"TestDurationDD": double.tryParse(_testDurationDayController.text) ?? 0.0,
"TestDurationHH": double.tryParse(_testDurationHrController.text) ?? 0.0,
"TestDurationMM": double.tryParse(_testDurationMinController.text) ?? 0.0,
"TestDurationSS": double.tryParse(_testDurationSecController.text) ?? 0.0, // Added TestDurationSS
"GraphVisibleArea": _calculateDurationInSeconds('0', _graphVisibleHrController.text, _graphVisibleMinController.text, '0').toDouble(),
"BaseLine": 0.0,
"FullScale": 0.0,
"Descrip": "",
"AbsorptionPer": 0.0,
"NOR": 0.0,
"FLName": "${_fileNameController.text}.csv",
"XAxis": "Time",
"XAxisRecNo": 1.0,
"XAxisUnit": "s",
"XAxisCode": 1.0,
"TotalChannel": channelConfigs.keys.length,
"MaxYAxis": channelConfigs.isNotEmpty ? channelConfigs.values.map((c) => c.chartMaximumValue).fold(double.negativeInfinity, max) : 100.0,
"MinYAxis": channelConfigs.isNotEmpty ? channelConfigs.values.map((c) => c.chartMinimumValue).fold(double.infinity, min) : 0.0,
"DBName": newDbFileName,
};
}

List<Map<String, dynamic>> _prepareTest1Payload(int recNo) {
List<Map<String, dynamic>> payload = [];
final sortedChannels = channelConfigs.keys.toList()..sort();

final Set<double> allTimestampsSet = {};
dataByChannel.values.forEach((channelDataList) {
if (channelDataList != null) {
for (var entry in channelDataList) {
if (entry['Timestamp'] is double) {
allTimestampsSet.add(entry['Timestamp'] as double);
}
}
}
});
final timestamps = allTimestampsSet.toList()..sort();

for (int i = 0; i < timestamps.length; i++) {
final timestamp = timestamps[i];
final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp.toInt());

Map<String, dynamic> payloadEntry = {
"RecNo": recNo.toDouble(),
"SNo": (i + 1).toDouble(),
"SlNo": (i + 1).toDouble(),
"ChangeTime": _formatTime(scanIntervalSeconds * (i + 1)),
"AbsDate": DateFormat('yyyy-MM-dd').format(dateTime),
"AbsTime": DateFormat('HH:mm:ss').format(dateTime),
"AbsDateTime": DateFormat('yyyy-MM-dd HH:mm:ss').format(dateTime),
"Shown": "Y",
"AbsAvg": 0.0,
};

for (int j = 1; j <= 50; j++) {
payloadEntry["AbsPer$j"] = null;
}

for (int j = 0; j < sortedChannels.length && j < 50; j++) {
final channelId = sortedChannels[j];
final channelDataList = dataByChannel[channelId];
final Map<String, dynamic> dataEntryForTimestamp = channelDataList?.firstWhere(
(d) => (d['Timestamp'] as double?) == timestamp,
orElse: () => <String, dynamic>{},
) ?? {};

if (dataEntryForTimestamp.isNotEmpty && dataEntryForTimestamp['Value'] != null && (dataEntryForTimestamp['Value'] as num).isFinite) {
payloadEntry["AbsPer${j + 1}"] = (dataEntryForTimestamp['Value'] as num).toDouble();
}
}
payload.add(payloadEntry);
}

debugPrint('[SERIAL_PORT] Prepared Test1 payload with ${payload.length} entries');
return payload;
}

Map<String, dynamic> _prepareTest2Payload(int recNo) {
final sortedChannels = channelConfigs.keys.toList()..sort();
Map<String, dynamic> payload = {
"RecNo": recNo.toDouble(),
};

for (int i = 1; i <= 50; i++) {
String channelName = '';
if (i <= sortedChannels.length) {
final channelId = sortedChannels[i - 1];
channelName = channelConfigs[channelId]?.channelName ?? '';
}
payload["ChannelName$i"] = channelName;
}

debugPrint('[SERIAL_PORT] Prepared Test2 payload with ${sortedChannels.length} channel names');
return payload;
}

String _formatTime(int seconds) {
final hours = seconds ~/ 3600;
final minutes = (seconds % 3600) ~/ 60;
final secs = seconds % 60;
return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(
2, '0')}:${secs.toString().padLeft(2, '0')}';
}

void _showPreviousGraph() {
if (segmentedDataByChannel.isNotEmpty && segmentedDataByChannel.values.first.isNotEmpty && currentGraphIndex > 0) {
setState(() => currentGraphIndex--);
debugPrint('[SERIAL_PORT] Navigated to previous graph segment: $currentGraphIndex');
LogPage.addLog('[$_currentTime] Navigated to previous graph segment.');
}
}

void _showNextGraph() {
int maxIndex = (segmentedDataByChannel.values.firstOrNull?.length ?? 1) - 1;
if (segmentedDataByChannel.isNotEmpty && segmentedDataByChannel.values.first.isNotEmpty && currentGraphIndex < maxIndex) {
setState(() => currentGraphIndex++);
debugPrint('[SERIAL_PORT] Navigated to next graph segment: $currentGraphIndex');
LogPage.addLog('[$_currentTime] Navigated to next graph segment.');
}
}

Map<String, List<Map<String, dynamic>>> get _currentGraphDataByChannel {
Map<String, List<Map<String, dynamic>>> currentData = {};
if (segmentedDataByChannel.isEmpty || segmentedDataByChannel.values.every((list) => list.isEmpty)) {
return {};
}
channelConfigs.keys.forEach((channel) {
if (segmentedDataByChannel.containsKey(channel) &&
currentGraphIndex < segmentedDataByChannel[channel]!.length) {
currentData[channel] =
segmentedDataByChannel[channel]![currentGraphIndex];
} else {
currentData[channel] = [];
}
});
return currentData;
}

Widget _buildGraphNavigation(bool isDarkMode) {
if (segmentedDataByChannel.isEmpty ||
segmentedDataByChannel.values.every((list) => list.isEmpty) ||
segmentedDataByChannel.values.first.length <= 1) {
return const SizedBox(height: 24);
}
return Padding(
padding: const EdgeInsets.symmetric(vertical: 8.0),
child: Row(
mainAxisAlignment: MainAxisAlignment.center,
children: [
IconButton(
icon: Icon(Icons.chevron_left, color: ThemeColors.getColor('sidebarIcon', isDarkMode)),
onPressed: _showPreviousGraph),
Text('Segment ${currentGraphIndex + 1}/${segmentedDataByChannel.values
    .first.length}',
style: GoogleFonts.roboto(
color: ThemeColors.getColor('serialPortGraphAxisLabel', isDarkMode), fontWeight: FontWeight.w500)),
IconButton(
icon: Icon(Icons.chevron_right, color: ThemeColors.getColor('sidebarIcon', isDarkMode)),
onPressed: _showNextGraph),
],
),
);
}

Widget _buildGraph(bool isDarkMode) {
final currentGraphData = _currentGraphDataByChannel;

List<LineChartBarData> lineBarsData = [];
Map<int, String> barIndexToChannelId = {}; // Map to link line chart bar index to channel ID for tooltips

double minX;
double maxX;
double minY = double.infinity;
double maxY = -double.infinity;
Set<double> uniqueTimestamps = {};

int segmentHours = int.tryParse(_graphVisibleHrController.text) ?? 0;
int segmentMinutes = int.tryParse(_graphVisibleMinController.text) ?? 60;
double segmentSeconds = (segmentHours * 3600) + (segmentMinutes * 60);
double segmentDurationMs = segmentSeconds * 1000;
if (segmentDurationMs <= 0) segmentDurationMs = 3600 * 1000; // Default to 1 hour (3600s) if not set or 0

final channelsToPlot = _selectedGraphChannel != null ? [_selectedGraphChannel!] : channelConfigs.keys.toList();
channelsToPlot.sort(); // Sort to ensure consistent barIndex assignments

// Determine overall X-axis range based on the current graph segment
double segmentStartTimeMs;
if (segmentedDataByChannel.isNotEmpty && segmentedDataByChannel.values.any((list) => list.isNotEmpty)) {
double tempMinTimestamp = double.infinity;
for (var channelId in channelConfigs.keys) {
if (segmentedDataByChannel.containsKey(channelId) &&
currentGraphIndex < segmentedDataByChannel[channelId]!.length &&
segmentedDataByChannel[channelId]![currentGraphIndex].isNotEmpty) {
final segment = segmentedDataByChannel[channelId]![currentGraphIndex];
if (segment.first['Timestamp'] is num) {
tempMinTimestamp = min(tempMinTimestamp, (segment.first['Timestamp'] as num).toDouble());
}
}
}
segmentStartTimeMs = (tempMinTimestamp != double.infinity) ? tempMinTimestamp : (DateTime.now().millisecondsSinceEpoch.toDouble() - segmentDurationMs);
} else {
segmentStartTimeMs = DateTime.now().millisecondsSinceEpoch.toDouble() - segmentDurationMs;
}
double segmentEndTimeMs = segmentStartTimeMs + segmentDurationMs;

minX = segmentStartTimeMs;
maxX = segmentEndTimeMs;

if (currentGraphData.isEmpty || currentGraphData.values.every((data) => data.isEmpty)) {
return Center(
child: Text(
'Waiting for channel data...',
style: GoogleFonts.roboto(color: ThemeColors.getColor('cardText', isDarkMode), fontSize: 18),
),
);
}

for (var channelId in channelsToPlot) {
if (!channelConfigs.containsKey(channelId) || !channelColors.containsKey(channelId)) {
debugPrint('Skipping channel $channelId: Missing configuration or color');
continue;
}

final config = channelConfigs[channelId]!;
final defaultColor = channelColors[channelId]!;
final alarmColor = Color(config.targetAlarmColour);
final channelData = currentGraphData[channelId] ?? [];

List<FlSpot> normalSpots = [];
List<FlSpot> alarmSpots = [];

for (var d in channelData) {
double timestamp = (d['Timestamp'] as num?)?.toDouble() ?? 0.0;
double value = (d['Value'] as num?)?.toDouble() ?? 0.0;
if (!timestamp.isFinite || !value.isFinite) {
continue;
}

uniqueTimestamps.add(timestamp);
FlSpot spot = FlSpot(timestamp, value);

// Check for alarm conditions only if targetAlarmMax/Min are not null
bool isAboveMaxAlarm = config.targetAlarmMax != null && value > config.targetAlarmMax!;
bool isBelowMinAlarm = config.targetAlarmMin != null && value < config.targetAlarmMin!;

if (isAboveMaxAlarm || isBelowMinAlarm) {
alarmSpots.add(spot);
debugPrint('Target Alarm Tracking: Alarm triggered for channel ${config.channelName} (Value: $value, Max: ${config.targetAlarmMax}, Min: ${config.targetAlarmMin})');
} else {
normalSpots.add(spot);
}

minY = min(minY, value);
maxY = max(maxY, value);
}

if (normalSpots.isNotEmpty) {
lineBarsData.add(
LineChartBarData(
spots: normalSpots,
isCurved: true,
color: defaultColor,
barWidth: 3,
dotData: FlDotData(
show: _showGraphDots, // Controlled by _showGraphDots
getDotPainter: (spot, percent, bar, index) {
return FlDotCirclePainter(
radius: _showGraphDots ? 4 : 0, // Smaller dots when enabled
color: defaultColor,
strokeWidth: 1,
strokeColor: Colors.white,
);
}),
belowBarData: BarAreaData(show: false),
),
);
barIndexToChannelId[lineBarsData.length - 1] = channelId;
}

if (alarmSpots.isNotEmpty) {
lineBarsData.add(
LineChartBarData(
spots: alarmSpots,
isCurved: true,
color: alarmColor,
barWidth: 3,
dotData: FlDotData(show: true, getDotPainter: (spot, percent, bar, index) {
return FlDotCirclePainter(
radius: 5, // Slightly larger, always shown for alarm
color: alarmColor,
strokeWidth: 1,
strokeColor: Colors.white,
);
}),
belowBarData: BarAreaData(show: false),
),
);
barIndexToChannelId[lineBarsData.length - 1] = channelId;
}
}

// Adjust Y-axis bounds based on actual data
if (minY == double.infinity || maxY == -double.infinity) {
minY = 0.0;
maxY = 100.0;
} else {
double yRange = maxY - minY;
if (yRange == 0) {
maxY += 10;
minY -= (minY > 0 ? 1 : 0);
} else {
maxY += yRange * 0.1;
minY -= yRange * 0.05;
}
bool allChannelsMinNonNegative = channelConfigs.values.every((c) => c.chartMinimumValue >= 0);
if (minY < 0 && allChannelsMinNonNegative) {
minY = 0;
}
}

List<double> sortedTimestamps = uniqueTimestamps.toList()..sort();

double intervalY = (maxY - minY) / 5;
if (intervalY <= 0 || !intervalY.isFinite) {
intervalY = (maxY > 0) ? maxY / 5 : 1;
if (intervalY <= 0) intervalY = 1.0;
}

Widget legend = SingleChildScrollView(
scrollDirection: Axis.horizontal,
child: Row(
mainAxisAlignment: MainAxisAlignment.center,
children: channelsToPlot
    .where((channelId) => channelConfigs.containsKey(channelId) && channelColors.containsKey(channelId))
    .map((channelId) {
final color = channelColors[channelId];
final channelName = channelConfigs[channelId]?.channelName ?? 'Unknown';
return Material(
color: Colors.transparent,
child: InkWell(
onTap: () {
_showColorPicker(channelId, isDarkMode);
},
borderRadius: BorderRadius.circular(8),
child: Padding(
padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
child: Row(
mainAxisSize: MainAxisSize.min,
children: [
Container(
width: 16,
height: 16,
decoration: BoxDecoration(
color: color,
borderRadius: BorderRadius.circular(4),
border: Border.all(color: Colors.grey.withOpacity(0.5)),
),
),
const SizedBox(width: 6),
Text('$channelName', style: GoogleFonts.roboto(
color: ThemeColors.getColor('serialPortGraphAxisLabel', isDarkMode), fontSize: 13, fontWeight: FontWeight.w500)),
const SizedBox(width: 4),
Icon(Icons.palette, size: 16, color: ThemeColors.getColor('serialPortDropdownIcon', isDarkMode)),
],
),
),
),
);
}).toList(),
),
);

return Column(
children: [
_buildGraphNavigation(isDarkMode),
Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), child: legend),
Expanded(
child: Padding(
padding: const EdgeInsets.fromLTRB(16.0, 24.0, 16.0, 16.0),
child: LineChart(
LineChartData(
lineTouchData: LineTouchData(
touchTooltipData: LineTouchTooltipData(
getTooltipItems: (touchedSpots) {
return touchedSpots.map((spot) {
if (!spot.x.isFinite || !spot.y.isFinite) {
return null;
}
final channelId = barIndexToChannelId[spot.barIndex];
if (channelId == null || !channelConfigs.containsKey(channelId)) {
return null;
}

final channelName = channelConfigs[channelId]?.channelName ?? 'Unknown';
final unit = channelConfigs[channelId]?.unit ?? '';
return LineTooltipItem(
'$channelName\n${spot.y.toStringAsFixed(2)} $unit\n${DateFormat('HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(spot.x.toInt()))}',
GoogleFonts.roboto(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 12),
);
}).where((item) => item != null).toList().cast<LineTooltipItem>();
},
tooltipBorder: BorderSide(color: ThemeColors.getColor('tooltipBorder', isDarkMode)),
),
),
gridData: FlGridData(
show: true,
drawVerticalLine: true,
horizontalInterval: intervalY,
getDrawingVerticalLine: (value) {
return FlLine(color: ThemeColors.getColor('serialPortGraphGridLine', isDarkMode), strokeWidth: 1);
},
getDrawingHorizontalLine: (value) {
return FlLine(color: ThemeColors.getColor('serialPortGraphGridLine', isDarkMode), strokeWidth: 1);
},
),
titlesData: FlTitlesData(
rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
leftTitles: AxisTitles(
axisNameWidget: Text(
'Load (${channelConfigs.isNotEmpty ? channelConfigs.values.first.unit : "Unit"})',
style: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortGraphAxisLabel', isDarkMode), fontWeight: FontWeight.bold, fontSize: 14),
),
sideTitles: SideTitles(
showTitles: true,
reservedSize: 50,
interval: intervalY,
getTitlesWidget: (value, meta) {
return Text(
value.isFinite ? value.toStringAsFixed(2) : '',
style: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortGraphAxisLabel', isDarkMode), fontSize: 12),
);
},
),
),
bottomTitles: AxisTitles(
axisNameWidget: Text(
'Time',
style: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortGraphAxisLabel', isDarkMode), fontWeight: FontWeight.bold, fontSize: 14),
),
sideTitles: SideTitles(
showTitles: true,
reservedSize: 40,
getTitlesWidget: (value, meta) {
if (meta.appliedInterval > 0 && uniqueTimestamps.isNotEmpty) {
final dateTime = DateTime.fromMillisecondsSinceEpoch(value.toInt());
return Padding(
padding: const EdgeInsets.only(top: 8.0),
child: Text(
'${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}',
style: GoogleFonts.roboto(
color: ThemeColors.getColor('serialPortGraphAxisLabel', isDarkMode), fontSize: 12, fontWeight: FontWeight.w600),
textAlign: TextAlign.center,
),
);
}
return const SizedBox.shrink();
},
interval: segmentDurationMs / 5,
),
),
),
borderData: FlBorderData(show: true, border: Border.all(color: ThemeColors.getColor('serialPortCardBorder', isDarkMode))),
minX: minX,
maxX: maxX,
minY: minY,
maxY: maxY,
lineBarsData: lineBarsData,
clipData: FlClipData.all(),
extraLinesData: const ExtraLinesData(extraLinesOnTop: true),
),
key: ValueKey(channelColors.hashCode ^ currentGraphIndex ^ segmentedDataByChannel.hashCode ^ _selectedGraphChannel.hashCode ^ _showGraphDots.hashCode),
),
),
),
],
);
}

List<TableRow> _buildTableRows(bool isDarkMode) {
List<TableRow> tableRows = [];
final sortedChannelKeys = channelConfigs.keys.toList()..sort();
final headers = ['Time', ...sortedChannelKeys];
final columnCount = headers.length;
const int maxRows = 100;

if (dataByChannel.isEmpty || dataByChannel.values.every((list) => list == null || list.isEmpty)) {
tableRows.add(
TableRow(
children: List.generate(
columnCount > 0 ? columnCount : 1,
(index) =>
Padding(
padding: const EdgeInsets.all(12.0),
child: Text(
index == 0 ? 'No data available' : '',
style: GoogleFonts.roboto(
color: ThemeColors.getColor('cardText', isDarkMode), fontSize: 14),
),
),
),
),
);
return tableRows;
}

final Set<double> allTimestampsSet = {};
dataByChannel.values.forEach((channelDataList) {
if (channelDataList != null) {
for (var dataEntry in channelDataList) {
if (dataEntry['Timestamp'] is double) {
allTimestampsSet.add(dataEntry['Timestamp'] as double);
}
}
}});
final timestamps = allTimestampsSet.toList()..sort();
final startIndex = timestamps.length > maxRows
? timestamps.length - maxRows
    : 0;

tableRows.add(
TableRow(
decoration: BoxDecoration(color: ThemeColors.getColor('serialPortTableHeaderBackground', isDarkMode)),
children: headers.map((header) {
return Padding(
padding: const EdgeInsets.all(12.0),
child: Text(
header == 'Time' ? 'Time' : channelConfigs[header]?.channelName ??
'Unknown',
style: GoogleFonts.roboto(fontWeight: FontWeight.bold,
color: ThemeColors.getColor('dialogText', isDarkMode),
fontSize: 14),
),
);
}).toList(),
),
);

for (int i = startIndex; i < timestamps.length; i++) {
final timestamp = timestamps[i];
String timeForRow = '';
for (var channelKey in sortedChannelKeys) {
final channelDataList = dataByChannel[channelKey];
Map<String, dynamic> dataEntry = {};
if (channelDataList != null) {
dataEntry = channelDataList.firstWhere(
(d) => (d['Timestamp'] as double?) == timestamp,
orElse: () => <String, dynamic>{},
);
}
if (dataEntry.isNotEmpty && dataEntry.containsKey('Time')) {
timeForRow = dataEntry['Time'] as String? ?? '';
if (timeForRow.isNotEmpty) break;
}
}

final rowCells = headers.map((header) {
if (header == 'Time') {
return Padding(
padding: const EdgeInsets.all(12.0),
child: Text(
timeForRow,
style: GoogleFonts.roboto(
color: i == timestamps.length - 1 ? Colors.green : ThemeColors.getColor('serialPortInputText', isDarkMode),
fontWeight: i == timestamps.length - 1
? FontWeight.bold
    : FontWeight.normal,
fontSize: 14,
),
),
);
}
final channelKey = header;
final channelDataList = dataByChannel[channelKey];
Map<String, dynamic> channelDataEntry = {};
if (channelDataList != null) {
channelDataEntry = channelDataList.firstWhere(
(d) => (d['Timestamp'] as double?) == timestamp,
orElse: () => <String, dynamic>{},
);
}

String valueText = '';
if (channelDataEntry.isNotEmpty && channelDataEntry['Value'] != null && channelConfigs[channelKey] != null) {
final config = channelConfigs[channelKey]!;
final value = channelDataEntry['Value'];
if (value is num && value.isFinite) {
valueText = '${(value as num).toStringAsFixed(config.decimalPlaces)}${config.unit}';
}
}
return Padding(
padding: const EdgeInsets.all(12.0),
child: Text(
valueText,
style: GoogleFonts.roboto(
color: i == timestamps.length - 1 && valueText.isNotEmpty ? Colors.green : ThemeColors.getColor('serialPortInputText', isDarkMode),
fontWeight: i == timestamps.length - 1 && valueText.isNotEmpty
? FontWeight.bold
    : FontWeight.normal,
fontSize: 14,
),
),
);
}).toList();

tableRows.add(
TableRow(
decoration: BoxDecoration(
color: i % 2 == 0 ? ThemeColors.getColor('serialPortTableRowEven', isDarkMode) : ThemeColors.getColor('serialPortTableRowOdd', isDarkMode)),
children: rowCells,
),
);
}
return tableRows;
}

Widget _buildDataTable(bool isDarkMode) {
return Container(
decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
border: Border.all(color: ThemeColors.getColor('serialPortCardBorder', isDarkMode))),
child: Column(
children: [
Expanded(
child: SingleChildScrollView(
controller: _tableScrollController,
scrollDirection: Axis.vertical,
physics: const AlwaysScrollableScrollPhysics(),
child: SingleChildScrollView(
scrollDirection: Axis.horizontal,
child: Table(
border: TableBorder.all(color: ThemeColors.getColor('serialPortCardBorder', isDarkMode)),
defaultColumnWidth: const IntrinsicColumnWidth(),
children: _buildTableRows(isDarkMode),
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
icon: Icon(Icons.arrow_upward, color: ThemeColors.getColor('sidebarIcon', isDarkMode)),
onPressed: () => _tableScrollController.animateTo(
0, duration: const Duration(milliseconds: 300),
curve: Curves.easeInOut),
),
IconButton(
icon: Icon(
Icons.arrow_downward, color: ThemeColors.getColor('sidebarIcon', isDarkMode)),
onPressed: () {
_tableScrollController.animateTo(
_tableScrollController.position.maxScrollExtent,
duration: const Duration(milliseconds: 300),
curve: Curves.easeInOut);
debugPrint('[SERIAL_PORT] Scrolled table to latest data');
},
),
],
),
),
],
),
);
}

Widget _buildTimeInputField(TextEditingController controller, String label, bool isDarkMode,
{bool compact = false, double width = 60}) {
return SizedBox(
width: width,
child: TextField(
controller: controller,
keyboardType: TextInputType.number,
inputFormatters: [FilteringTextInputFormatter.digitsOnly],
decoration: InputDecoration(
labelText: label,
labelStyle: GoogleFonts.roboto(
color: ThemeColors.getColor('serialPortInputLabel', isDarkMode),
fontSize: 12,
fontWeight: FontWeight.w300,
),
filled: true,
fillColor: ThemeColors.getColor('serialPortInputFill', isDarkMode),
border: OutlineInputBorder(
borderRadius: BorderRadius.circular(8),
borderSide: BorderSide.none,
),
contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
isDense: true,
),
style: GoogleFonts.roboto(
color: ThemeColors.getColor('serialPortInputText', isDarkMode),
fontSize: 14,
fontWeight: FontWeight.w400,
),
onChanged: (value) {
_debounceTimer?.cancel();
_debounceTimer = Timer(const Duration(milliseconds: 500), () {
if (controller == _scanRateHrController || controller == _scanRateMinController || controller == _scanRateSecController) {
_updateScanInterval();
} else if (controller == _graphVisibleHrController || controller == _graphVisibleMinController) {
if (mounted) setState(() {});
}
});
},
),
);
}

Widget _buildControlButton(String text, VoidCallback? onPressed, bool isDarkMode,
{Color? color, bool? disabled}) {
return ElevatedButton(
onPressed: disabled == true ? null : onPressed,
style: ElevatedButton.styleFrom(
backgroundColor: color ?? ThemeColors.getColor('submitButton', isDarkMode),
padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
foregroundColor: Colors.white,
),
child: Text(text, style: GoogleFonts.roboto(
color: Colors.white, fontWeight: FontWeight.w500)),
);
}

Widget _buildStyledAddButton(bool isDarkMode) {
return Container(
decoration: BoxDecoration(
gradient: ThemeColors.getButtonGradient(isDarkMode),
borderRadius: BorderRadius.circular(10),
boxShadow: [
BoxShadow(
color: ThemeColors.getColor('buttonGradientStart', isDarkMode).withOpacity(0.3),
blurRadius: 8,
offset: const Offset(0, 4),
),
],
),
child: ElevatedButton(
onPressed: _openFloatingGraphWindow,
style: ElevatedButton.styleFrom(
backgroundColor: Colors.transparent,
shadowColor: Colors.transparent,
padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(10)),
),
child: Row(
mainAxisSize: MainAxisSize.min,
children: [
const Icon(Icons.add, color: Colors.white, size: 20),
const SizedBox(width: 8),
Text(
'Add Window',
style: GoogleFonts.roboto(
color: Colors.white,
fontWeight: FontWeight.w600,
fontSize: 16,
),
),
],
),
),
);
}

Widget _buildLatestDataDisplay(bool isDarkMode) {
if (dataByChannel.isEmpty || dataByChannel.values.every((list) => list == null || list.isEmpty)) {
return const SizedBox.shrink();
}

Map<String, dynamic>? latestDataEntry;
double latestTimestamp = -double.infinity;

for (String channelId in channelConfigs.keys) {
if (dataByChannel.containsKey(channelId) && dataByChannel[channelId] != null && dataByChannel[channelId]!.isNotEmpty) {
final currentChannelLastEntry = dataByChannel[channelId]!.last;
final currentTimestamp = (currentChannelLastEntry['Timestamp'] as num?)?.toDouble() ?? -double.infinity;

if (currentTimestamp > latestTimestamp) {
latestTimestamp = currentTimestamp;
latestDataEntry = currentChannelLastEntry;
} else if (currentTimestamp == latestTimestamp && latestDataEntry != null && channelConfigs.containsKey(channelId)) {
latestDataEntry = currentChannelLastEntry;
}
}
}

if (latestDataEntry == null || latestDataEntry!['Channel'] == null || !channelConfigs.containsKey(latestDataEntry!['Channel'])) {
return const SizedBox.shrink();
}
final config = channelConfigs[latestDataEntry!['Channel']]!;
return Container(
width: double.infinity,
padding: const EdgeInsets.all(8),
margin: const EdgeInsets.symmetric(vertical: 4),
decoration: BoxDecoration(color: ThemeColors.getColor('serialPortLiveValueBackground', isDarkMode),
borderRadius: BorderRadius.circular(8)),
child: Text(
'Latest: Channel ${config
    .channelName} - ${latestDataEntry!['Time']} ${latestDataEntry!['Date']} - ${ (latestDataEntry!['Value'] as num).isFinite ? (latestDataEntry!['Value'] as num)
    .toStringAsFixed(config.decimalPlaces) : "N/A"}${config.unit}',
style: GoogleFonts.roboto(
color: ThemeColors.getColor('serialPortLiveValueText', isDarkMode), fontWeight: FontWeight.bold),
textAlign: TextAlign.center,
),
);
}

Widget _buildFullInputSectionContent(bool isDarkMode) {
return Column(
mainAxisSize: MainAxisSize.min,
children: [
Row(
children: [
Expanded(
child: TextField(
controller: _fileNameController,
decoration: InputDecoration(
labelText: 'File Name',
labelStyle: GoogleFonts.roboto(
color: ThemeColors.getColor('serialPortInputLabel', isDarkMode),
fontSize: 13,
),
filled: true,
fillColor: ThemeColors.getColor('serialPortInputFill', isDarkMode),
border: OutlineInputBorder(
borderRadius: BorderRadius.circular(8),
borderSide: BorderSide.none,
),
contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
isDense: true,
),
style: GoogleFonts.roboto(
color: ThemeColors.getColor('serialPortInputText', isDarkMode),
fontSize: 14,
),
onChanged: (val) {},
),
),
const SizedBox(width: 16),
Expanded(
child: TextField(
controller: _operatorController,
decoration: InputDecoration(
labelText: 'Operator',
labelStyle: GoogleFonts.roboto(
color: ThemeColors.getColor('serialPortInputLabel', isDarkMode),
fontSize: 13,
),
filled: true,
fillColor: ThemeColors.getColor('serialPortInputFill', isDarkMode),
border: OutlineInputBorder(
borderRadius: BorderRadius.circular(8),
borderSide: BorderSide.none,
),
contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
isDense: true,
),
style: GoogleFonts.roboto(
color: ThemeColors.getColor('serialPortInputText', isDarkMode),
fontSize: 14,
),
onChanged: (val) {},
),
),
],
),
const SizedBox(height: 16),
Row(
children: [
Expanded(
child: Row(
crossAxisAlignment: CrossAxisAlignment.center,
children: [
SizedBox(
width: 80,
child: Text(
'Scan Rate:',
style: GoogleFonts.roboto(
color: ThemeColors.getColor('dialogText', isDarkMode),
fontWeight: FontWeight.w500,
fontSize: 13,
),
),
),
_buildTimeInputField(_scanRateHrController, 'Hr', isDarkMode, compact: true, width: 45),
const SizedBox(width: 2),
_buildTimeInputField(_scanRateMinController, 'Min', isDarkMode, compact: true, width: 45),
const SizedBox(width: 2),
_buildTimeInputField(_scanRateSecController, 'Sec', isDarkMode, compact: true, width: 45),
],
),
),
const SizedBox(width: 12),
Expanded(
child: Row(
crossAxisAlignment: CrossAxisAlignment.center,
children: [
SizedBox(
width: 90,
child: Text(
'Test Duration:',
style: GoogleFonts.roboto(
color: ThemeColors.getColor('dialogText', isDarkMode),
fontWeight: FontWeight.w500,
fontSize: 13,
),
),
),
_buildTimeInputField(_testDurationDayController, 'Day', isDarkMode, compact: true, width: 45),
const SizedBox(width: 2),
_buildTimeInputField(_testDurationHrController, 'Hr', isDarkMode, compact: true, width: 45),
const SizedBox(width: 2),
_buildTimeInputField(_testDurationMinController, 'Min', isDarkMode, compact: true, width: 45),
const SizedBox(width: 2),
_buildTimeInputField(_testDurationSecController, 'Sec', isDarkMode, compact: true, width: 45),
],
),
),
],
),
],
);
}

Widget _buildBottomSectionContent(bool isDarkMode) {
return Container(
width: double.infinity,
padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
decoration: BoxDecoration(
color: isScanning ? ThemeColors.getColor('submitButton', isDarkMode).withOpacity(0.1) : ThemeColors.getColor('serialPortMessagePanelBackground', isDarkMode),
borderRadius: BorderRadius.circular(12),
border: Border.all(
color: isScanning ? ThemeColors.getColor('submitButton', isDarkMode).withOpacity(0.5) : ThemeColors.getColor('serialPortCardBorder', isDarkMode)),
),
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
Wrap(
spacing: 12,
runSpacing: 12,
alignment: WrapAlignment.center,
children: [
_buildControlButton(
'Start Scan', _startScan, isDarkMode, disabled: isScanning),
_buildControlButton(
'Stop Scan', _stopScan, isDarkMode, color: Colors.orange[700],
disabled: !isScanning),
_buildControlButton(
'Cancel Scan', _cancelScan, isDarkMode, color: ThemeColors.getColor('resetButton', isDarkMode)),
_buildControlButton(
'Save Data', () => _saveData(), isDarkMode, color: Colors.green[700]),
_buildControlButton(
'Multi File', () {LogPage.addLog('[$_currentTime] Multi File button pressed.');}, isDarkMode, color: Colors.purple[700]),
_buildControlButton('Exit', () {
LogPage.addLog('[$_currentTime] Exiting Auto Start Screen.');
Navigator.pushReplacement(context,
MaterialPageRoute(builder: (context) => const HomePage()));
}, isDarkMode, color: ThemeColors.getColor('cardText', isDarkMode)),
],
),
const SizedBox(height: 16),
Align(
alignment: Alignment.bottomCenter,
child: Row(
mainAxisAlignment: MainAxisAlignment.center,
crossAxisAlignment: CrossAxisAlignment.center,
children: [
if (isScanning)
Padding(
padding: const EdgeInsets.only(right: 8.0),
child: SizedBox(
width: 16,
height: 16,
child: CircularProgressIndicator(
strokeWidth: 2,
valueColor: AlwaysStoppedAnimation<Color>(
ThemeColors.getColor('submitButton', isDarkMode)))),
),
Expanded(
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
portMessage,
if (errors.isNotEmpty)
Builder(
builder: (context) {
String messageToDisplay = '';
List<String> actualErrors = errors.where((e) =>
!e.contains('Scanning active') && !e.contains('Reconnected')).toList();

if (actualErrors.isNotEmpty) {
messageToDisplay = actualErrors.last;
}
return Text(
messageToDisplay,
style: GoogleFonts.roboto(
color: messageToDisplay.contains('Error') || messageToDisplay.contains('failed') || messageToDisplay.contains('disconnected')
? ThemeColors.getColor('serialPortErrorTextSmall', isDarkMode)
    : ThemeColors.getColor('serialPortMessageText', isDarkMode),
fontSize: 12),
overflow: TextOverflow.ellipsis,
maxLines: 1,
textAlign: TextAlign.center,
);
},
),
],
),
),
],
),
),
],
),
);
}

Widget _buildLeftSection(bool isDarkMode) {
return Column(
crossAxisAlignment: CrossAxisAlignment.stretch,
children: [
Flexible(
flex: 2,
child: Card(
elevation: 0,
color: ThemeColors.getColor('serialPortCardBackground', isDarkMode),
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
side: BorderSide(color: ThemeColors.getColor('serialPortCardBorder', isDarkMode))),
child: Padding(
padding: const EdgeInsets.all(16.0),
child: _buildFullInputSectionContent(isDarkMode),
),
),
),
const SizedBox(height: 16),
Expanded(
flex: 6,
child: Card(
elevation: 0,
color: ThemeColors.getColor('serialPortCardBackground', isDarkMode),
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(12),
side: BorderSide(color: ThemeColors.getColor('serialPortCardBorder', isDarkMode))),
child: Padding(
padding: const EdgeInsets.all(16.0),
child: _buildDataTable(isDarkMode),
),
),
),
const SizedBox(height: 16),
Flexible(
flex: 2,
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
_buildLatestDataDisplay(isDarkMode),
_buildBottomSectionContent(isDarkMode),
],
),
),
],
);
}

Widget _buildRightSection(bool isDarkMode) {
final isCompact = MediaQuery
    .of(context)
    .size
    .width < 600;
return ValueListenableBuilder<String>(
valueListenable: Global.selectedMode,
builder: (context, mode, _) {
final selectedMode = mode ?? 'Graph';
if (selectedMode == 'Graph') {
return Column(
crossAxisAlignment: CrossAxisAlignment.stretch,
children: [
Card(
elevation: 0,
color: ThemeColors.getColor('serialPortCardBackground', isDarkMode),
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(12),
side: BorderSide(color: ThemeColors.getColor('serialPortCardBorder', isDarkMode))),
child: Padding(
padding: const EdgeInsets.all(8.0),
child: SingleChildScrollView(
scrollDirection: Axis.horizontal,
child: Row(
mainAxisAlignment: MainAxisAlignment.start,
crossAxisAlignment: CrossAxisAlignment.center,
children: [
SizedBox(
width: isCompact ? 100 : 120,
child: TextField(
controller: _fileNameController,
decoration: InputDecoration(
labelText: 'File Name',
labelStyle: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortInputLabel', isDarkMode), fontSize: 13),
filled: true,
fillColor: ThemeColors.getColor('serialPortInputFill', isDarkMode),
border: OutlineInputBorder(
borderRadius: BorderRadius.circular(8),
borderSide: BorderSide.none),
contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: isCompact ? 8 : 10),
isDense: true,
),
style: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortInputText', isDarkMode), fontSize: 14),
onChanged: (val) {},
),
),
const SizedBox(width: 8),
SizedBox(
width: isCompact ? 100 : 120,
child: TextField(
controller: _operatorController,
decoration: InputDecoration(
labelText: 'Operator',
labelStyle: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortInputLabel', isDarkMode), fontSize: 13),
filled: true,
fillColor: ThemeColors.getColor('serialPortInputFill', isDarkMode),
border: OutlineInputBorder(
borderRadius: BorderRadius.circular(8),
borderSide: BorderSide.none),
contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: isCompact ? 8 : 10),
isDense: true,
),
style: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortInputText', isDarkMode), fontSize: 14),
onChanged: (val) {},
),
),
const SizedBox(width: 8),
Row(
mainAxisSize: MainAxisSize.min,
children: [
Text('Scan Rate:',
style: GoogleFonts.roboto(
color: ThemeColors.getColor('dialogText', isDarkMode),
fontWeight: FontWeight.w500,
fontSize: 13)),
const SizedBox(width: 4),
_buildTimeInputField(
_scanRateHrController, 'Hr', isDarkMode, compact: true, width: 45),
const SizedBox(width: 4),
_buildTimeInputField(
_scanRateMinController, 'Min', isDarkMode, compact: true, width: 45),
const SizedBox(width: 4),
_buildTimeInputField(
_scanRateSecController, 'Sec', isDarkMode, compact: true, width: 45),
],
),
const SizedBox(width: 8),
Row(
mainAxisSize: MainAxisSize.min,
children: [
Text('Test Duration:',
style: GoogleFonts.roboto(
color: ThemeColors.getColor('dialogText', isDarkMode),
fontWeight: FontWeight.w500,
fontSize: 13)),
const SizedBox(width: 4),
_buildTimeInputField(
_testDurationDayController, 'Day', isDarkMode,
compact: true, width: 45),
const SizedBox(width: 4),
_buildTimeInputField(
_testDurationHrController, 'Hr', isDarkMode, compact: true, width: 45),
const SizedBox(width: 4),
_buildTimeInputField(
_testDurationMinController, 'Min', isDarkMode,
compact: true, width: 45),
const SizedBox(width: 4),
_buildTimeInputField(
_testDurationSecController, 'Sec', isDarkMode,
compact: true, width: 45),
],
),
const SizedBox(width: 8),
Row(
mainAxisSize: MainAxisSize.min,
children: [
Text('Segment:',
style: GoogleFonts.roboto(
color: ThemeColors.getColor('dialogText', isDarkMode),
fontWeight: FontWeight.w500,
fontSize: 13)),
const SizedBox(width: 4),
_buildTimeInputField(
_graphVisibleHrController, 'Hr', isDarkMode, compact: true, width: 45),
const SizedBox(width: 4),
_buildTimeInputField(
_graphVisibleMinController, 'Min', isDarkMode,
compact: true, width: 45),
],
),
const SizedBox(width: 8),
Container(
padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
decoration: BoxDecoration(
color: ThemeColors.getColor('serialPortDropdownBackground', isDarkMode),
borderRadius: BorderRadius.circular(8),
boxShadow: [
BoxShadow(
color: ThemeColors.getColor('serialPortCardBorder', isDarkMode).withOpacity(0.5),
blurRadius: 5)
],
),
child: DropdownButton<String?>(
value: _selectedGraphChannel,
hint: Text('All Channels',
style: GoogleFonts.roboto(
color: ThemeColors.getColor('serialPortDropdownText', isDarkMode))),
onChanged: (String? newValue) {
setState(() {
_selectedGraphChannel = newValue;
});
},
items: [
DropdownMenuItem<String?>(
value: null,
child: Text('All Channels',
style: GoogleFonts.roboto(
color: ThemeColors.getColor('serialPortDropdownText', isDarkMode))),
),
...channelConfigs.keys.map(
(channelId) =>
DropdownMenuItem<String>(
value: channelId,
child: Text(
'Channel ${channelConfigs[channelId]!
    .channelName}',
style: GoogleFonts.roboto(
color: ThemeColors.getColor('serialPortDropdownText', isDarkMode)),
),
)),
],
underline: Container(),
icon: Icon(Icons.arrow_drop_down,
color: ThemeColors.getColor('serialPortDropdownIcon', isDarkMode)),
dropdownColor: ThemeColors.getColor('serialPortDropdownBackground', isDarkMode),
),
),
const SizedBox(width: 8),
Row(
mainAxisSize: MainAxisSize.min,
children: [
Text('Show Dots:',
style: GoogleFonts.roboto(
color: ThemeColors.getColor('dialogText', isDarkMode),
fontWeight: FontWeight.w500,
fontSize: 13,
),
),
Switch(
value: _showGraphDots,
onChanged: (bool value) {
setState(() {
_showGraphDots = value;
});
},
activeColor: ThemeColors.getColor('submitButton', isDarkMode),
inactiveThumbColor: ThemeColors.getColor('resetButton', isDarkMode),
inactiveTrackColor: ThemeColors.getColor('secondaryButton', isDarkMode).withOpacity(0.3),
),
],
),
const SizedBox(width: 8),
_buildStyledAddButton(isDarkMode),
],
),
),
),
),
const SizedBox(height: 16),
Expanded(
child: Card(
elevation: 0,
color: ThemeColors.getColor('serialPortCardBackground', isDarkMode),
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(12),
side: BorderSide(color: ThemeColors.getColor('serialPortCardBorder', isDarkMode))),
child: Padding(
padding: EdgeInsets.all(isCompact ? 8.0 : 16.0),
child: _buildGraph(isDarkMode)),
),
),
const SizedBox(height: 16),
_buildBottomSectionContent(isDarkMode),
],
);
} else {
return Column(
crossAxisAlignment: CrossAxisAlignment.stretch,
children: [
Card(
elevation: 0,
color: ThemeColors.getColor('serialPortCardBackground', isDarkMode),
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(12),
side: BorderSide(color: ThemeColors.getColor('serialPortCardBorder', isDarkMode))),
child: Padding(
padding: const EdgeInsets.all(8.0),
child: SingleChildScrollView(
scrollDirection: Axis.horizontal,
child: Row(
mainAxisAlignment: MainAxisAlignment.end,
crossAxisAlignment: CrossAxisAlignment.center,
children: [
Row(
mainAxisSize: MainAxisSize.min,
children: [
Text('Graph Segment:',
style: GoogleFonts.roboto(
color: ThemeColors.getColor('dialogText', isDarkMode),
fontWeight: FontWeight.w500)),
const SizedBox(width: 8),
_buildTimeInputField(_graphVisibleHrController, 'Hr', isDarkMode),
const SizedBox(width: 8),
_buildTimeInputField(
_graphVisibleMinController, 'Min', isDarkMode),
],
),
const SizedBox(width: 8),
Container(
padding: const EdgeInsets.symmetric(
horizontal: 12, vertical: 8),
decoration: BoxDecoration(
color: ThemeColors.getColor('serialPortDropdownBackground', isDarkMode),
borderRadius: BorderRadius.circular(8),
boxShadow: [
BoxShadow(
color: ThemeColors.getColor('serialPortCardBorder', isDarkMode).withOpacity(0.5),
blurRadius: 5)
]),
child: DropdownButton<String?>(
value: _selectedGraphChannel,
hint: Text('All Channels',
style: GoogleFonts.roboto(
color: ThemeColors.getColor('serialPortDropdownText', isDarkMode))),
onChanged: (String? newValue) {
setState(() {
_selectedGraphChannel = newValue;
});
},
items: [
DropdownMenuItem<String?>(
value: null,
child: Text('All Channels',
style: GoogleFonts.roboto(
color: ThemeColors.getColor('serialPortDropdownText', isDarkMode)))),
...channelConfigs.keys.map((channelId) =>
DropdownMenuItem<String>(
value: channelId,
child: Text(
'Channel ${channelConfigs[channelId]!
    .channelName}',
style: GoogleFonts.roboto(
color: ThemeColors.getColor('serialPortDropdownText', isDarkMode))),
)),
],
underline: Container(),
icon: Icon(Icons.arrow_drop_down,
color: ThemeColors.getColor('serialPortDropdownIcon', isDarkMode)),
dropdownColor: ThemeColors.getColor('serialPortDropdownBackground', isDarkMode),
),
),
const SizedBox(width: 8),
Row(
mainAxisSize: MainAxisSize.min,
children: [
Text('Show Dots:',
style: GoogleFonts.roboto(
color: ThemeColors.getColor('dialogText', isDarkMode),
fontWeight: FontWeight.w500,
fontSize: 13,
),
),
Switch(
value: _showGraphDots,
onChanged: (bool value) {
setState(() {
_showGraphDots = value;
});
},
activeColor: ThemeColors.getColor('submitButton', isDarkMode),
inactiveThumbColor: ThemeColors.getColor('resetButton', isDarkMode),
inactiveTrackColor: ThemeColors.getColor('secondaryButton', isDarkMode).withOpacity(0.3),
),
],
),
const SizedBox(width: 8),
_buildStyledAddButton(isDarkMode),
],
),
),
),
),
const SizedBox(height: 16),
Expanded(
child: Card(
elevation: 0,
color: ThemeColors.getColor('serialPortCardBackground', isDarkMode),
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(12),
side: BorderSide(color: ThemeColors.getColor('serialPortCardBorder', isDarkMode))),
child: Padding(
padding: EdgeInsets.all(isCompact ? 8.0 : 16.0),
child: _buildGraph(isDarkMode)),
),
),
],
);
}
},
);
}

@override
Widget build(BuildContext context) {
return ValueListenableBuilder<bool>(
valueListenable: Global.isDarkMode,
builder: (context, isDarkMode, child) {
return Scaffold(
backgroundColor: ThemeColors.getColor('serialPortBackground', isDarkMode),
body: SafeArea(
child: ValueListenableBuilder<String>(
valueListenable: Global.selectedMode,
builder: (context, mode, _) {
final selectedMode = mode ?? 'Graph';
return Padding(
padding: const EdgeInsets.all(16.0),
child: selectedMode == 'Table'
? _buildLeftSection(isDarkMode)
    : selectedMode == 'Graph'
? _buildRightSection(isDarkMode)
    : Row(
crossAxisAlignment: CrossAxisAlignment.stretch,
children: [
Expanded(flex: 1, child: _buildLeftSection(isDarkMode)),
const SizedBox(width: 16),
Expanded(flex: 1, child: _buildRightSection(isDarkMode)),
],
),
);
},
),
),
);
},
);
}

@override
void dispose() {
LogPage.addLog('[$_currentTime] Auto Start Screen disposed.');

for (var entry in _windowEntries) {
entry.remove();
}
_windowEntries.clear();

_scrollController.dispose();
_tableScrollController.dispose();
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
_graphVisibleMinController.dispose();

_readerSubscription?.cancel();
reader?.close();
if (port != null && port!.isOpen) {
try {
port!.close();
} catch (e) {
LogPage.addLog('[$_currentTime] Error closing serial port on exit: $e');
}
port!.dispose();
} else {
port?.dispose();
}
port = null;

_reconnectTimer?.cancel();
_testDurationTimer?.cancel();
_tableUpdateTimer?.cancel();
_debounceTimer?.cancel();
_endTimeTimer?.cancel();
super.dispose();
}
}
