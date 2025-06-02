import 'dart:io';
import 'package:intl/intl.dart';
import 'dart:typed_data';
import 'dart:async';
import 'dart:math'; // Ensure math library is imported for Random
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../constants/global.dart';
import '../../constants/database_manager.dart';
import '../../constants/sessionmanager.dart';
import '../../constants/theme.dart';
import '../NavPages/channel.dart'; // Assuming this path is correct
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

// New enum for message types
enum _SerialPortMessageType {
info,
success,
warning,
error,
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
// Replaced `late Widget portStatusMessage` with new state variables
String _currentMessage = "Loading port settings...";
_SerialPortMessageType _currentMessageType = _SerialPortMessageType.info;

List<String> errors = []; // This list still holds historical errors
Map<String, Color> channelColors = {};
bool isScanning = false;
bool isCancelled = false; // Indicates user cancelled, should not auto-reconnect
bool isManuallyStopped = false; // Indicates user stopped, should not auto-reconnect
SerialPortReader? reader;
StreamSubscription<Uint8List>? _readerSubscription;
DateTime? lastDataTime;
int scanIntervalSeconds = 1;
int currentGraphIndex = 0;
Map<String, List<List<Map<String, dynamic>>>> segmentedDataByChannel = {};
// Removed unused ScrollController: // final ScrollController _scrollController = ScrollController();
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
final _operatorController = TextEditingController(); // No default here, set on save if empty
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

// GlobalKey for ScaffoldMessengerState to show SnackBars from async methods
final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

// Helper for consistent log timestamp
String get _currentTime => DateFormat('HH:mm:ss').format(DateTime.now());

// Random instance for generating colors
final Random _random = Random();

@override
void initState() {
super.initState();
// Initialize _currentMessage and _currentMessageType here
_updateMessage("Loading port settings...", _SerialPortMessageType.info);

_initializeChannelConfigs();

// Load settings and start scan sequentially
WidgetsBinding.instance.addPostFrameCallback((_) async {
await _loadComPortSettings(); // Wait for COM port settings
if (!mounted) return; // Crucial check after async operation

if (_portName != null && _portName!.isNotEmpty) {
_startScan(); // Start scan only if port is configured
} else {
// If port isn't configured, ensure scanning flags are off
if (mounted) {
setState(() {
isScanning = false;
Global.isScanningNotifier.value = false;
});
}
}
_startReconnectTimer();
_startEndTimeCheck();
});
}

// New helper method to update the message state
void _updateMessage(String message, _SerialPortMessageType type) {
if (mounted) {
setState(() {
_currentMessage = message;
_currentMessageType = type;
});
}
}

Future<void> _loadComPortSettings() async {
if (!mounted) return; // Crucial check at the start of async method

try {
final settings = await DatabaseManager().getComPortSettings();
if (settings != null) {
if (!mounted) return; // Crucial check before setState
setState(() {
_portName = settings['selectedPort'] as String?;
_baudRate = settings['baudRate'] as int?;
_dataBits = settings['dataBits'] as int?;
_parity = settings['parity'] as String?;
_stopBits = settings['stopBits'] as int?;
_updateMessage(
_portName != null ? "Ready to start scanning on $_portName" : "Port not configured",
_portName != null ? _SerialPortMessageType.info : _SerialPortMessageType.warning,
);
LogPage.addLog('[$_currentTime] COM Port settings loaded: $_portName, $_baudRate. Ready to scan.');
});
} else {
if (!mounted) return; // Crucial check before setState
setState(() {
_updateMessage(
"No COM port settings found in database. Using default fallback settings.",
_SerialPortMessageType.warning,
);
_portName = 'COM6'; // Default fallback
_baudRate = 2400; // Default fallback
_dataBits = 8;    // Default fallback
_parity = 'None'; // Default fallback
_stopBits = 1;    // Default fallback
LogPage.addLog('[$_currentTime] No COM Port settings found, using defaults: COM6.');
});
}
} catch (e) {
if (mounted) {
setState(() {
_updateMessage(
"Error loading port settings: $e",
_SerialPortMessageType.error,
);
errors.add('Error loading port settings: $e');
_portName = 'COM6'; // Default fallback on error
_baudRate = 2400; // Default fallback
_dataBits = 8;    // Default fallback
_parity = 'None'; // Default fallback
_stopBits = 1;    // Default fallback
LogPage.addLog('[$_currentTime] Error loading COM Port settings: $e');
});
}
}
_initPort(); // Initialize port after settings are loaded
}

void _startEndTimeCheck() {
_endTimeTimer?.cancel();
_endTimeTimer = Timer.periodic(const Duration(seconds: 30), (timer) async { // Added async
if (!mounted) { // Crucial check at the start of timer callback
timer.cancel();
return;
}
final now = DateTime.now();
final endHour = widget.endTimeHr.toInt();
final endMinute = widget.endTimeMin.toInt();

// Create a DateTime object for the end time on the current day
DateTime endDateTime = DateTime(now.year, now.month, now.day, endHour, endMinute);

// If the current time is past the end time for today, consider the end time for tomorrow
if (now.isAfter(endDateTime)) {
endDateTime = endDateTime.add(const Duration(days: 1));
}

// Check if current time is at or past the calculated end time
if (now.isAtSameMomentAs(endDateTime) || now.isAfter(endDateTime)) {
if (isScanning) { // Only stop if scanning is active
debugPrint('End time reached: $endHour:$endMinute, stopping scan and saving data');
timer.cancel(); // Cancel the timer as end time is reached
_stopScan(); // Call _stopScan, which also sets isManuallyStopped and updates global notifier
await _saveData(Global.isDarkMode.value); // Await saving data
if (!mounted) return; // Crucial check after async operation
setState(() {
_updateMessage('End time reached, scan stopped and data saved', _SerialPortMessageType.success);
errors.add('End time reached, scan stopped and data saved');
});
// Navigate back to HomePage after a short delay to allow UI to update
Future.delayed(const Duration(seconds: 2), () {
if (!mounted) return; // Crucial check before navigation
Navigator.pushReplacement(
context,
MaterialPageRoute(builder: (context) => const HomePage()),
);
});
} else {
// If not scanning but end time is reached, cancel timer and log
debugPrint('End time reached, but scan was not active. Cancelling EndTime timer.');
timer.cancel();
}
}
});
}

void _initPort() {
if (!mounted) return; // Crucial check at the start of method

if (_portName == null || _portName!.isEmpty) {
if (!mounted) return; // Crucial check before setState
setState(() {
_updateMessage("COM Port name is not configured.", _SerialPortMessageType.error);
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
debugPrint('Previous port disposed successfully.');
} catch (e) {
debugPrint('Error cleaning up previous port: $e');
LogPage.addLog('[$_currentTime] Error cleaning up previous port: $e');
} finally {
port = null; // Ensure port is null after disposal attempt
}
}

try {
port = SerialPort(_portName!);
} on SerialPortError catch (e) {
debugPrint('SerialPortError initializing SerialPort object: ${e.message}');
if (!mounted) return; // Crucial check before setState
setState(() => _updateMessage('Error initializing port $_portName: ${e.message}', _SerialPortMessageType.error));
errors.add('Error initializing port $_portName: ${e.message}');
port = null; // Set to null on error
LogPage.addLog('[$_currentTime] Failed to initialize serial port $_portName: ${e.message}');
} catch (e) {
debugPrint('Generic error initializing SerialPort object: $e');
if (mounted) {
setState(() {
_updateMessage('Error initializing port $_portName: $e', _SerialPortMessageType.error);
errors.add('Error initializing port $_portName: $e');
});
}
port = null; // Set to null on error
LogPage.addLog('[$_currentTime] Failed to initialize serial port $_portName: $e');
}
}

// MODIFIED: _initializeChannelConfigs to use random colors
void _initializeChannelConfigs() {
channelConfigs.clear();
channelColors.clear();

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

// Generate a random color for the graph line
// Ensure color is distinguishable and not too dark/light depending on theme
Color randomColor;
if (Global.isDarkMode.value) { // For dark mode, generate brighter colors
randomColor = Color.fromARGB(
255, // Full opacity
_random.nextInt(156) + 100, // R (100-255)
_random.nextInt(156) + 100, // G (100-255)
_random.nextInt(156) + 100, // B (100-255)
);
} else { // For light mode, generate darker colors
randomColor = Color.fromARGB(
255, // Full opacity
_random.nextInt(156), // R (0-155)
_random.nextInt(156), // G (0-155)
_random.nextInt(156), // B (0-155)
);
}

channelColors[channelId] = randomColor;

debugPrint('Channel Color Tracking: Configured channel ${channel.channelName} (${channelId}) with RANDOM color ${randomColor.toHexString()}');
} catch (e) {
debugPrint('Error configuring channel at index $i: $e');
if (!mounted) return; // Crucial check before setState
setState(() {
errors.add('Invalid channel configuration at index $i: $e');
});
LogPage.addLog('[$_currentTime] Invalid channel configuration: $e');
}
}

if (channelConfigs.isEmpty) {
if (mounted) {
setState(() {
_updateMessage('No valid channels configured', _SerialPortMessageType.warning);
errors.add('No valid channels configured');
});
}
LogPage.addLog('[$_currentTime] No valid channels configured.');
}
}

// The _updateChannelColorInDatabase function is still needed if you want
// to save the *randomly assigned* color as the new default in the database
// when the 'Set as default color' checkbox is checked in the color picker.
Future<void> _updateChannelColorInDatabase(String channelId, Color color) async {
try {
final database = await DatabaseManager().database;

final channel = channelConfigs[channelId]!;
// Store AARRGGBB value
int colorValue = color.value; // Color.value directly gives AARRGGBB integer
debugPrint('Channel Color Tracking: Updating graphLineColour to ${colorValue.toRadixString(16)} for channel ${channel.channelName} (RecNo: ${channel.recNo})');

await database.update(
'ChannelSetup', // Assuming your channel configuration table is named 'ChannelSetup'
    {'graphLineColour': colorValue}, // Correct column name
where: 'StartingCharacter = ? AND RecNo = ?', // Using StartingCharacter and RecNo for unique identification
whereArgs: [channelId, channel.recNo],
);

LogPage.addLog('[$_currentTime] Channel ${channel.channelName} graph color updated as default in DB.');
} catch (e) {
debugPrint('Error updating channel color in database: $e');
_scaffoldMessengerKey.currentState?.showSnackBar( // Use _scaffoldMessengerKey to show SnackBar from an async method
SnackBar(
content: Text('Error saving default color: $e'),
backgroundColor: Colors.red,
duration: const Duration(seconds: 3),
),
);
LogPage.addLog('[$_currentTime] Error saving default channel color: $e');
}
}

// Re-added color picker functionality
void _showColorPicker(String channelId, bool isDarkMode) {
Color tempSelectedColor = channelColors[channelId]!; // Temporary variable to hold the color chosen in picker

showDialog(
context: context,
builder: (context) {
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
// Use checkColor for the checkmark, activeColor for the active state of the track
checkColor: Colors.white, // Ensure checkmark is visible
activeColor: ThemeColors.getColor('submitButton', isDarkMode),
side: BorderSide(color: ThemeColors.getColor('dialogSubText', isDarkMode)), // Border color
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
if (!mounted) return; // Crucial check before setState
setState(() { // This setState rebuilds the main AutoStartScreen widget
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


void _configurePort() {
if (port == null || !port!.isOpen) {
_updateMessage("Port is not open, cannot configure.", _SerialPortMessageType.error);
return;
}
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
if (!mounted) return; // Crucial check before setState
setState(() {
_updateMessage('Port config error: $e', _SerialPortMessageType.error);
errors.add('Port config error: $e');
});
LogPage.addLog('[$_currentTime] Serial port configuration error: $e');
} finally {
config.dispose(); // Ensure config is disposed
}
}

int _getInactivityTimeout() {
int timeout = scanIntervalSeconds + 10;
return timeout.clamp(
_minInactivityTimeoutSeconds, _maxInactivityTimeoutSeconds).toInt(); // Ensure int return
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
// ignore: invalid_use_of_protected_member
entry.markNeedsBuild(); // Mark needs build after position update
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
if (!mounted) { // Crucial check at start of timer callback
timer.cancel();
debugPrint('Autoreconnect timer cancelled: widget unmounted.');
return;
}
if (isCancelled || isManuallyStopped) {
debugPrint('Autoreconnect: Stopped by user action (cancelled/manually stopped).');
timer.cancel();
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
} else if (!isScanning) { // Only try to start if not scanning currently
debugPrint('Autoreconnect: Attempting to restart scan...');
_autoStartScan();
}
});
}

void _autoStopAndReconnect() {
debugPrint(
'Autoreconnect triggered: No data for ${_getInactivityTimeout()} seconds');
if (isScanning) {
_stopScanInternal(); // Internal stop, does not set isManuallyStopped
if (!mounted) return; // Crucial check before setState
setState(() {
_updateMessage('Port disconnected - Reconnecting...', _SerialPortMessageType.warning);
errors.add('Port disconnected - Reconnecting...');
});
_reconnectAttempts = 0; // Reset attempts for new auto-reconnect cycle
}
}

void _autoStartScan() {
if (!mounted) return; // Crucial check at start of method

if (!isScanning && !isCancelled && !isManuallyStopped &&
_reconnectAttempts < _maxReconnectAttempts) {
try {
debugPrint('Autoreconnect: Attempt ${_reconnectAttempts + 1}/$_maxReconnectAttempts');
LogPage.addLog('[$_currentTime] Attempting to auto-restart scan (Attempt ${_reconnectAttempts + 1}).');
if (_portName == null || _portName!.isEmpty) {
throw Exception('Port name not set. Cannot auto-reconnect.');
}

if (port == null || !port!.isOpen) {
_initPort(); // Re-initialize port object if null or not open
if (port == null) { // Check if _initPort failed to create port
throw Exception('Failed to initialize port $_portName.');
}
if (!port!.openReadWrite()) {
final lastError = SerialPort.lastError;
// Clean up port object if opening fails
try { port!.close(); port!.dispose(); } catch (_) {}
port = null; // Ensure port is null after failed open
throw Exception('Failed to open port for read/write: ${lastError?.message ?? "Unknown error"}');
}
}
_configurePort();
port!.flush(); // Clear any existing data in the port's buffer
_setupReader();
if (!mounted) return; // Crucial check before setState
setState(() {
isScanning = true;
Global.isScanningNotifier.value = true; // Set global notifier
isCancelled = false; // Reset these flags on successful auto-restart
isManuallyStopped = false;
_updateMessage('Reconnected to $_portName - Scanning resumed', _SerialPortMessageType.success);
errors.add('Reconnected to $_portName - Scanning resumed');
});
_reconnectAttempts = 0;
_startTableUpdateTimer();
// No need to call _addTableRow directly here, timer will handle it
LogPage.addLog('[$_currentTime] Auto-reconnected to $_portName. Scanning resumed.');
} catch (e) {
debugPrint('Autoreconnect: Error: $e');
if (!mounted) return; // Crucial check before setState
setState(() {
_updateMessage('Reconnect error: $e', _SerialPortMessageType.error);
errors.add('Reconnect error: $e');
});
_reconnectAttempts++;
LogPage.addLog('[$_currentTime] Failed to auto-restart scan: $e');
}
} else if (_reconnectAttempts >= _maxReconnectAttempts) {
if (mounted) {
setState(() {
_updateMessage('Reconnect failed after $_maxReconnectAttempts attempts', _SerialPortMessageType.error);
errors.add('Reconnect failed after $_maxReconnectAttempts attempts');
});
}
LogPage.addLog('[$_currentTime] Auto-reconnect failed after $_maxReconnectAttempts attempts. Stopping auto-reconnect.');
_reconnectTimer?.cancel(); // Stop the reconnect timer
}
}

void _setupReader() {
if (port == null || !port!.isOpen) return;
_readerSubscription?.cancel(); // Cancel any existing subscription
reader?.close(); // Close any existing reader
reader = SerialPortReader(port!, timeout: 500);
_readerSubscription = reader!.stream.listen(
(Uint8List data) {
if (!mounted) { // Crucial check at start of stream listener
_readerSubscription?.cancel(); // Cancel the subscription if widget is unmounted
return;
}
final decoded = String.fromCharCodes(data);
buffer += decoded;

String regexPattern = channelConfigs.entries.map((e) => '\\${e.value
    .startingCharacter}[0-9]+\\.[0-9]+').join('|');
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

// If buffer grows too large without matches, it implies unrecognized data or a bad pattern
if (buffer.length > 1000 && matches.isEmpty) {
debugPrint('Buffer length > 1000 and no matches. Clearing buffer to prevent overflow.');
buffer = '';
LogPage.addLog('[$_currentTime] Data stream not recognized. Clearing buffer.');
}
lastDataTime = DateTime.now();
},
onError: (error) {
debugPrint('Stream error: $error');
if (!mounted) { // Crucial check at start of stream listener
_readerSubscription?.cancel();
return;
}
setState(() {
_updateMessage('Error reading data: $error', _SerialPortMessageType.error);
errors.add('Error reading data: $error');
});
LogPage.addLog('[$_currentTime] Error reading data from serial port: $error');
// If stream errors, consider triggering an auto-reconnect attempt
_autoStopAndReconnect();
},
onDone: () {
debugPrint('Stream done');
if (!mounted) { // Crucial check at start of stream listener
_readerSubscription?.cancel();
return;
}
if (isScanning && !isCancelled && !isManuallyStopped) { // Only if scanning was active and not manually stopped/cancelled
setState(() {
_updateMessage('Port disconnected - Reconnecting...', _SerialPortMessageType.warning);
errors.add('Port disconnected - Reconnecting...');
});
LogPage.addLog('[$_currentTime] Serial port disconnected. Attempting to reconnect.');
_autoStopAndReconnect();
} else {
LogPage.addLog('[$_currentTime] Serial port stream done, but not auto-reconnecting (stopped/cancelled).');
}
},
);
}

void _startScan() {
if (!mounted) return; // Crucial check at start of method

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
_initPort(); // Re-initialize port object if null or not open
if (port == null) { // Check if _initPort failed to create port
throw Exception('Failed to initialize port $_portName.');
}
if (!port!.openReadWrite()) {
final lastError = SerialPort.lastError;
// Clean up port object if opening fails
try { port!.close(); port!.dispose(); } catch (_) {}
port = null; // Ensure port is null after failed open
throw Exception('Failed to open port for read/write: ${lastError?.message ?? "Unknown error"}');
}
}
_configurePort();
port!.flush(); // Clear any existing data in the port's buffer
_setupReader();
if (!mounted) return; // Crucial check before setState
setState(() {
isScanning = true;
Global.isScanningNotifier.value = true; // Set global notifier
isCancelled = false; // Reset these flags on user start
isManuallyStopped = false;
_updateMessage('Scanning active on $_portName', _SerialPortMessageType.success);
errors.add('Scanning active on $_portName');
// Reset data and segments for a new scan
dataByChannel.clear();
_bufferedData.clear();
segmentedDataByChannel.clear();
currentGraphIndex = 0;
});
_reconnectAttempts = 0; // Reset reconnect attempts on successful start

_startTableUpdateTimer();

_testDurationTimer?.cancel();
int testDurationSeconds = _calculateDurationInSeconds(
_testDurationDayController.text,
_testDurationHrController.text,
_testDurationMinController.text,
_testDurationSecController.text,
);
// If a test duration is explicitly set in the UI, use it
// Otherwise, the _endTimeTimer handles stopping by time of day
if (testDurationSeconds > 0) {
_testDurationTimer =
Timer(Duration(seconds: testDurationSeconds), () async { // Added async
if (!mounted) return; // Crucial check at start of timer callback
_stopScan(); // Call _stopScan, which sets isManuallyStopped and updates global notifier
await _saveData(Global.isDarkMode.value); // Pass isDarkMode here
if (!mounted) return; // Crucial check after async operation
setState(() {
_updateMessage('Test duration reached, scanning stopped', _SerialPortMessageType.info);
errors.add('Test duration reached, scanning stopped');
});
debugPrint('[SERIAL_PORT] Test duration of $testDurationSeconds seconds reached, stopped scanning');
LogPage.addLog('[$_currentTime] Test duration of ${Duration(seconds: testDurationSeconds).inMinutes} minutes reached. Scanning stopped automatically.');
});
}
} catch (e) {
debugPrint('Error starting scan: $e');
if (!mounted) return; // Crucial check before setState
setState(() {
_updateMessage('Error starting scan: $e', _SerialPortMessageType.error);
errors.add('Error starting scan: $e');
});
LogPage.addLog('[$_currentTime] Error starting scan: $e');
if (e.toString().contains('busy') ||
e.toString().contains('Access denied')) {
_cancelScan(); // Attempt a full cleanup if port is busy/denied
}
}
}
}

// User-initiated stop, sets isManuallyStopped
void _stopScan() {
_stopScanInternal();
if (!mounted) return; // Crucial check before setState
setState(() {
isManuallyStopped = true;
_updateMessage('Scanning stopped manually', _SerialPortMessageType.info);
errors.add('Scanning stopped manually');
});
_testDurationTimer?.cancel();
_tableUpdateTimer?.cancel();
LogPage.addLog('[$_currentTime] Scanning stopped manually.');
}

// Internal stop logic, doesn't set isManuallyStopped
void _stopScanInternal() {
if (!mounted) return; // Crucial check at start of method

if (isScanning) {
try {
debugPrint('Stopping scan internally...');
_readerSubscription?.cancel();
reader?.close();
if (port != null && port!.isOpen) {
port!.close();
}
if (!mounted) return; // Crucial check before setState
setState(() {
isScanning = false;
Global.isScanningNotifier.value = false; // Set global notifier
reader = null;
_readerSubscription = null;
// _currentMessage and _currentMessageType updated by _stopScan or _autoStopAndReconnect
});
} catch (e) {
debugPrint('Error stopping scan internally: $e');
if (!mounted) return; // Crucial check before setState
setState(() {
_updateMessage('Error stopping scan internally: $e', _SerialPortMessageType.error);
errors.add('Error stopping scan internally: $e');
});
LogPage.addLog('[$_currentTime] Error stopping scan internally: $e');
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
if (!mounted) return; // Crucial check before setState
setState(() {
isScanning = false;
isCancelled = true; // Scan has been explicitly cancelled -> this triggers Exit button
isManuallyStopped = true; // Ensure manual stop flag is also set to prevent auto-reconnect
dataByChannel.clear();
_bufferedData.clear();
buffer = "";
segmentedDataByChannel.clear();
errors.clear(); // Clear all errors on cancel for a clean slate
currentGraphIndex = 0;
reader = null;
_readerSubscription = null;
port = null; // Ensure port object is nulled to be re-initialized if needed
_updateMessage('Scan cancelled', _SerialPortMessageType.info);
});
_initPort(); // Re-initialize port for potential next scan
_testDurationTimer?.cancel();
_tableUpdateTimer?.cancel();
_debounceTimer?.cancel(); // Cancel any active debounce timers
LogPage.addLog('[$_currentTime] Data scan cancelled. All data cleared.');
} catch (e) {
debugPrint('Error cancelling scan: $e');
if (!mounted) return; // Crucial check before setState
setState(() {
_updateMessage('Error cancelling scan: $e', _SerialPortMessageType.error);
errors.add('Error cancelling scan: $e'); // Keep in errors list for debugging
});
LogPage.addLog('[$_currentTime] Error cancelling scan: $e');
}
}

void _startTableUpdateTimer() {
_tableUpdateTimer?.cancel();
if (scanIntervalSeconds < 1) {
scanIntervalSeconds = 1;
}
// Only log if interval actually changes, to reduce debug noise
if (scanIntervalSeconds != _lastScanIntervalSeconds) {
_lastScanIntervalSeconds = scanIntervalSeconds;
debugPrint('Table update timer interval changed to $scanIntervalSeconds seconds');
}
_tableUpdateTimer =
Timer.periodic(Duration(seconds: scanIntervalSeconds), (_) {
if (!mounted) { // Crucial check at start of timer callback
_tableUpdateTimer?.cancel();
debugPrint('Table update timer cancelled: widget unmounted.');
return;
}
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
if (!mounted) return; // Crucial check at start of method

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

if (!mounted) return; // Crucial check before setState after async operations
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
newData['Channel_$channel'] = channel; // This might be redundant if 'Channel' is added per entry

var channelData = {
...newData, // Include common fields like 'Serial No', 'Time', 'Date'
'Value': newData['Value_$channel'],
'Channel': channel,
'Data': latestChannelData[channel]!['Data'] ?? '',
};

// Add to dataByChannel for the main table and saving
dataByChannel.putIfAbsent(channel, () => []).add(channelData);

// Call _updateGraphData for each channel's new data
_updateGraphData(channelData);
});

_segmentData(newData); // Segment data for graph
lastDataTime = now; // Update last data time for inactivity check

// Schedule post-frame callback for scrolling
WidgetsBinding.instance.addPostFrameCallback((_) {
if (!mounted) return; // Crucial check inside post-frame callback
// Scroll to the end of the table
if (_tableScrollController.hasClients) {
_tableScrollController.animateTo(
_tableScrollController.position.maxScrollExtent,
duration: const Duration(milliseconds: 300),
curve: Curves.easeOut,
);
}
});

if (segmentedDataByChannel.isNotEmpty && segmentedDataByChannel.values.any((list) => list.isNotEmpty)) {
currentGraphIndex = segmentedDataByChannel.values.first.length - 1; // Always show the latest segment
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

// No need to access config if not using its properties here
// final config = channelConfigs[channelId]!;

final valueStr = data.substring(1);
double value = double.tryParse(valueStr) ?? 0.0;
double timestamp = now.millisecondsSinceEpoch.toDouble();

// Ensure _bufferedData for this timestamp is initialized before adding channel data
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
if (!mounted) return; // Crucial check at start of method

int graphVisibleSeconds = _calculateDurationInSeconds(
'0', _graphVisibleHrController.text, _graphVisibleMinController.text,
'0');
if (graphVisibleSeconds <= 0) {
debugPrint('[SEGMENT_DATA] Invalid graph visible duration: $graphVisibleSeconds seconds. Defaulting to 60 minutes.');
graphVisibleSeconds = 3600; // Default to 60 minutes if invalid
}

double newTimestamp = newData['Timestamp'] as double;
channelConfigs.keys.forEach((channelId) {
segmentedDataByChannel.putIfAbsent(channelId, () => []);

// If no segments exist or the last segment is too old, start a new one
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
// Otherwise, add to the current last segment
segmentedDataByChannel[channelId]!.last.add({
...newData,
'Value': newData['Value_$channelId'] ?? 0.0,
'Channel': channelId,
});
}
});

if (segmentedDataByChannel.isNotEmpty && segmentedDataByChannel.values.any((list) => list.isNotEmpty)) {
if (mounted) { // Crucial check before setState
setState(() {
currentGraphIndex = segmentedDataByChannel.values.first.length - 1; // Always show the latest segment
});
}
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
if (mounted) { // Crucial check before setState
setState(() {
scanIntervalSeconds = newInterval < 1 ? 1 : newInterval;
debugPrint('Scan interval updated: $scanIntervalSeconds seconds');
});
}
if (isScanning) {
_startTableUpdateTimer(); // Restart timer with new interval
}
LogPage.addLog('[$_currentTime] Scan interval updated to $scanIntervalSeconds seconds.');
}
}

Future<void> _saveData(bool isDarkMode) async { // Passed `isDarkMode` to the function
Database? newSessionDatabase; // Declare here to ensure it's in scope for finally
try {
// Auto-populate File Name and Operator if empty
String fileName = _fileNameController.text.trim();
String operatorName = _operatorController.text.trim();

if (fileName.isEmpty) {
fileName = 'Data_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}';
if (mounted) _fileNameController.text = fileName; // Update controller to reflect change
LogPage.addLog('[$_currentTime] File Name was empty, auto-generated: $fileName');
}
if (operatorName.isEmpty) {
operatorName = 'Operator';
if (mounted) _operatorController.text = operatorName; // Update controller to reflect change
LogPage.addLog('[$_currentTime] Operator Name was empty, auto-filled with: $operatorName');
}

debugPrint('Saving data to databases started...');
LogPage.addLog('[$_currentTime] Saving data to databases.');

if (!mounted) { // Check before showing dialog
LogPage.addLog('[$_currentTime] Widget unmounted, cannot show save dialog.');
return;
}

// Show loading dialog
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
newSessionDatabase = await SessionDatabaseManager().openSessionDatabase(newDbFileName);
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

if (!mounted) return; // Crucial check before popping dialog or showing SnackBar
Navigator.of(context).pop(); // Dismiss progress dialog

_scaffoldMessengerKey.currentState?.showSnackBar( // Use GlobalKey for ScaffoldMessenger
SnackBar(
content: Text('Data saved successfully to "$fileName.db"'), // Informative message
backgroundColor: Colors.green,
duration: const Duration(seconds: 3),
),
);
LogPage.addLog('[$_currentTime] Data saved successfully to "$fileName.db".');
} catch (e, s) {
if (mounted && Navigator.of(context).canPop()) { // Check mounted before popping dialog
Navigator.of(context).pop(); // Dismiss progress dialog if still showing
}
debugPrint('Error saving data to databases: $e\nStackTrace: $s');
if (mounted) { // Check mounted before showing SnackBar
_scaffoldMessengerKey.currentState?.showSnackBar( // Use GlobalKey for ScaffoldMessenger
SnackBar(
content: Text('Error saving data: $e'),
backgroundColor: ThemeColors.getColor('errorText', isDarkMode),
duration: const Duration(seconds: 3),
),
);
}
LogPage.addLog('[$_currentTime] Error saving data: $e');
} finally {
// Ensure the session database is closed in all cases
if (newSessionDatabase != null && newSessionDatabase.isOpen) {
await newSessionDatabase.close();
debugPrint('Session database connection closed in finally block.');
}
}
}

Map<String, dynamic> _prepareTestPayload(int recNo, String newDbFileName) {
return {
"RecNo": recNo.toDouble(),
"FName": _fileNameController.text, // Use the (possibly updated) controller text
"OperatorName": _operatorController.text, // Use the (possibly updated) controller text
"TDate": DateFormat('yyyy-MM-dd').format(DateTime.now()),
"TTime": DateFormat('HH:mm:ss').format(DateTime.now()),
"ScanningRate": scanIntervalSeconds.toDouble(),
"ScanningRateHH": double.tryParse(_scanRateHrController.text) ?? 0.0,
"ScanningRateMM": double.tryParse(_scanRateMinController.text) ?? 0.0,
"ScanningRateSS": double.tryParse(_scanRateSecController.text) ?? 0.0,
"TestDurationDD": double.tryParse(_testDurationDayController.text) ?? 0.0,
"TestDurationHH": double.tryParse(_testDurationHrController.text) ?? 0.0,
"TestDurationMM": double.tryParse(_testDurationMinController.text) ?? 0.0,
"TestDurationSS": double.tryParse(_testDurationSecController.text) ?? 0.0,
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
"ChangeTime": _formatTime(scanIntervalSeconds * (i + 1)), // This might need adjustment if timestamps are not strictly multiples of scanInterval
"AbsDate": DateFormat('yyyy-MM-dd').format(dateTime),
"AbsTime": DateFormat('HH:mm:ss').format(dateTime),
"AbsDateTime": DateFormat('yyyy-MM-dd HH:mm:ss').format(dateTime),
"Shown": "Y",
"AbsAvg": 0.0,
};

// Initialize all AbsPer fields to null or 0.0 as per DB schema
for (int j = 1; j <= 100; j++) {
payloadEntry["AbsPer$j"] = null; // Use null for unset values, or 0.0 if numerical default is preferred
}

for (int j = 0; j < sortedChannels.length && j < 100; j++) {
final channelId = sortedChannels[j];
// Find the data entry for this specific timestamp and channel
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

for (int i = 1; i <= 100; i++) {
String channelName = '';
if (i <= sortedChannels.length) {
final channelKey = sortedChannels[i - 1];
channelName = channelConfigs[channelKey]?.channelName ?? '';
}
payload["ChannelName$i"] = channelName;
}

debugPrint('[SERIAL_PORT] Prepared Test2 payload with ${sortedChannels.length} channel names');
return payload;
}

// Corrected _formatTime function - removed stray Japanese characters
String _formatTime(int seconds) {
final hours = seconds ~/ 3600;
final minutes = (seconds % 3600) ~/ 60;
final secs = seconds % 60;
return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
}

void _showPreviousGraph() {
if (!mounted) return; // Crucial check
if (segmentedDataByChannel.isNotEmpty && segmentedDataByChannel.values.any((list) => list.isNotEmpty) && currentGraphIndex > 0) {
setState(() => currentGraphIndex--);
debugPrint('[SERIAL_PORT] Navigated to previous graph segment: $currentGraphIndex');
LogPage.addLog('[$_currentTime] Navigated to previous graph segment.');
}
}

void _showNextGraph() {
if (!mounted) return; // Crucial check
int maxIndex = (segmentedDataByChannel.values.firstOrNull?.length ?? 1) - 1;
if (segmentedDataByChannel.isNotEmpty && segmentedDataByChannel.values.any((list) => list.isNotEmpty) && currentGraphIndex < maxIndex) {
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
return const SizedBox(height: 24); // Keep some space for consistent layout
}
return Padding(
padding: const EdgeInsets.symmetric(vertical: 8.0),
child: Row(
mainAxisAlignment: MainAxisAlignment.center,
children: [
IconButton(
icon: Icon(Icons.chevron_left, color: ThemeColors.getColor('sidebarIcon', isDarkMode)),
onPressed: currentGraphIndex > 0 ? _showPreviousGraph : null), // Disable if no previous
Text('Segment ${currentGraphIndex + 1}/${segmentedDataByChannel.values
    .first.length}',
style: GoogleFonts.roboto(
color: ThemeColors.getColor('serialPortGraphAxisLabel', isDarkMode), fontWeight: FontWeight.w500)),
IconButton(
icon: Icon(Icons.chevron_right, color: ThemeColors.getColor('sidebarIcon', isDarkMode)),
onPressed: currentGraphIndex < (segmentedDataByChannel.values.first.length - 1) ? _showNextGraph : null), // Disable if no next
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
for (var channelId in channelConfigs.keys) { // Iterate over actually selected/all channels
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

double intervalY = (maxY - minY) / 5;
if (intervalY <= 0 || !intervalY.isFinite) {
intervalY = (maxY > 0) ? maxY / 5 : 1;
if (intervalY <= 0) intervalY = 1.0;
}

// MODIFIED: Legend to be on one row with horizontal scrolling + with color picker
Widget legend = SingleChildScrollView(
scrollDirection: Axis.horizontal,
child: Row(
mainAxisAlignment: MainAxisAlignment.center,
children: channelsToPlot
    .where((channelId) => channelConfigs.containsKey(channelId) && channelColors.containsKey(channelId))
    .map((channelId) {
final color = channelColors[channelId];
final channelName = channelConfigs[channelId]?.channelName ?? 'Unknown';
return Material( // Wrap in Material for InkWell splash effect
color: Colors.transparent, // Make Material transparent
child: InkWell(
onTap: () {
_showColorPicker(channelId, isDarkMode); // Re-added color picker
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
Text('Channel $channelName', style: GoogleFonts.roboto(
color: ThemeColors.getColor('serialPortGraphAxisLabel', isDarkMode), fontSize: 13, fontWeight: FontWeight.w500)),
const SizedBox(width: 4),
Icon(Icons.palette, size: 16, color: ThemeColors.getColor('serialPortDropdownIcon', isDarkMode)), // Palette icon
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
final decimalPlaces = channelConfigs[channelId]!.decimalPlaces; // Correctly get decimal places

return LineTooltipItem(
'Channel $channelName\n${spot.y.toStringAsFixed(decimalPlaces)} $unit\n${DateFormat('HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(spot.x.toInt()))}',
GoogleFonts.roboto(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 12),
);
}).where((item) => item != null).toList().cast<LineTooltipItem>();
},
tooltipBorder: BorderSide(color: ThemeColors.getColor('tooltipBorder', isDarkMode)),
tooltipPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), // Added
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
reservedSize: 70, // Increased reservedSize for rotated text
getTitlesWidget: (value, meta) {
if (meta.appliedInterval > 0 && uniqueTimestamps.isNotEmpty) {
final dateTime = DateTime.fromMillisecondsSinceEpoch(value.toInt());
return Padding(
padding: const EdgeInsets.only(top: 8.0),
child: Transform.rotate( // Rotate the text
angle: pi / 2, // Rotate 90 degrees clockwise
alignment: Alignment.center,
child: Align( // Align the rotated text within its space
alignment: Alignment.centerRight, // Adjust alignment after rotation
child: Text(
'${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}',
style: GoogleFonts.roboto(
color: ThemeColors.getColor('serialPortGraphAxisLabel', isDarkMode), fontSize: 12, fontWeight: FontWeight.w600),
),
),
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
}
});
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
onPressed: () {
if (!mounted) return;
_tableScrollController.animateTo(
0, duration: const Duration(milliseconds: 300),
curve: Curves.easeInOut);
}
),
IconButton(
icon: Icon(
Icons.arrow_downward, color: ThemeColors.getColor('sidebarIcon', isDarkMode)),
onPressed: () {
if (!mounted) return;
_tableScrollController.animateTo(
_tableScrollController.position.maxScrollExtent,
duration: const Duration(milliseconds: 300),
curve: Curves.easeOut,
);
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

// Changed to a more compact width and content padding
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
fontSize: compact ? 11 : 13, // Smaller font for compact fields
fontWeight: FontWeight.w300,
),
filled: true,
fillColor: ThemeColors.getColor('serialPortInputFill', isDarkMode),
border: OutlineInputBorder(
borderRadius: BorderRadius.circular(8),
borderSide: BorderSide.none,
),
contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), // More compact padding
isDense: true, // Reduce overall height
),
style: GoogleFonts.roboto(
color: ThemeColors.getColor('serialPortInputText', isDarkMode),
fontSize: compact ? 12 : 14, // Smaller font for compact fields
fontWeight: FontWeight.w400,
),
onChanged: (value) {
_debounceTimer?.cancel();
_debounceTimer = Timer(const Duration(milliseconds: 500), () {
if (!mounted) return; // Crucial check inside debounce callback
if (controller == _scanRateHrController || controller == _scanRateMinController || controller == _scanRateSecController) {
_updateScanInterval();
} else if (controller == _graphVisibleHrController || controller == _graphVisibleMinController) {
// This setState only rebuilds the widget to update graph parameters
setState(() {});
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
padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // More compact
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(10)),
),
child: Row(
mainAxisSize: MainAxisSize.min,
children: [
const Icon(Icons.add, color: Colors.white, size: 16), // Slightly smaller icon
const SizedBox(width: 6), // Reduced spacing
Text(
'Add Window',
style: GoogleFonts.roboto(
color: Colors.white,
fontWeight: FontWeight.w600,
fontSize: 12, // Smaller font
),
),
],
),
),
);
}

void _showModeSelectionDialog(bool isDarkMode) {
showDialog(
context: context,
builder: (BuildContext dialogContext) { // Use dialogContext here
return AlertDialog(
backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
title: Text('Select Display Mode',
style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode))),
content: Column(
mainAxisSize: MainAxisSize.min,
children: [
RadioListTile<String>(
title: Text('Combined (Table & Graph)', style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogSubText', isDarkMode))),
value: 'Combined',
groupValue: Global.selectedMode.value,
onChanged: (String? value) {
if (value != null) {
Global.selectedMode.value = value;
Navigator.of(dialogContext).pop(); // Use dialogContext to pop
LogPage.addLog('[$_currentTime] Display mode changed to Combined.');
}
},
activeColor: ThemeColors.getColor('submitButton', isDarkMode),
),
RadioListTile<String>(
title: Text('Table Only', style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogSubText', isDarkMode))),
value: 'Table',
groupValue: Global.selectedMode.value,
onChanged: (String? value) {
if (value != null) {
Global.selectedMode.value = value;
Navigator.of(dialogContext).pop(); // Use dialogContext to pop
LogPage.addLog('[$_currentTime] Display mode changed to Table Only.');
}
},
activeColor: ThemeColors.getColor('submitButton', isDarkMode),
),
RadioListTile<String>(
title: Text('Graph Only', style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogSubText', isDarkMode))),
value: 'Graph',
groupValue: Global.selectedMode.value,
onChanged: (String? value) {
if (value != null) {
Global.selectedMode.value = value;
Navigator.of(dialogContext).pop(); // Use dialogContext to pop
LogPage.addLog('[$_currentTime] Display mode changed to Graph Only.');
}
},
activeColor: ThemeColors.getColor('submitButton', isDarkMode),
),
],
),
actions: [
TextButton(
onPressed: () {
Navigator.of(dialogContext).pop(); // Use dialogContext to pop
},
child: Text('Close', style: GoogleFonts.roboto(color: ThemeColors.getColor('submitButton', isDarkMode))),
),
],
);
},
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
// Scan Rate
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
const SizedBox(width: 12), // small gap between sections
// Test Duration
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
// --- End of _buildFullInputSectionContent method ---

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
mainAxisSize: MainAxisSize.min, // Make column take minimum height
children: [
Wrap( // For buttons
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
'Save Data', () => _saveData(isDarkMode), isDarkMode, color: Colors.green[700]), // Pass isDarkMode
_buildControlButton(
'Multi File', () {LogPage.addLog('[$_currentTime] Multi File button pressed.');}, isDarkMode, color: Colors.purple[700]),
// MODIFIED: Exit button visibility and disclaimer
if (isCancelled) // Only show Exit button if scan has been explicitly cancelled
_buildControlButton('Exit', () async {
// IMPORTANT: Call _cancelScan before navigating away
if (isScanning) {
// Show a confirmation dialog if scan is still active
await showDialog(
context: context,
barrierDismissible: false,
builder: (dialogContext) => AlertDialog( // Use a new context for dialog
title: Text('Confirm Exit', style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode))),
content: Text('Scanning is active. Do you want to stop and exit?', style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogSubText', isDarkMode))),
actions: [
TextButton(
onPressed: () {
Navigator.of(dialogContext).pop(); // Stay on screen
},
child: Text('Cancel', style: GoogleFonts.roboto(color: ThemeColors.getColor('submitButton', isDarkMode))),
),
TextButton(
onPressed: () {
_cancelScan(); // Perform full cleanup
Navigator.of(dialogContext).pop(); // Close dialog
if (mounted) { // Crucial check before navigation
LogPage.addLog('[$_currentTime] Exiting AutoStart Screen. Scanning stopped.');
Global.isScanningNotifier.value = false; // Ensure global notifier is reset
Navigator.pushReplacement(context,
MaterialPageRoute(builder: (context) => const HomePage()));
}
},
child: Text('Exit', style: GoogleFonts.roboto(color: ThemeColors.getColor('resetButton', isDarkMode))),
),
],
backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
),
);
} else {
// If not scanning, just exit
LogPage.addLog('[$_currentTime] Exiting AutoStart Screen.');
Global.isScanningNotifier.value = false; // Ensure global notifier is reset
Navigator.pushReplacement(context,
MaterialPageRoute(builder: (context) => const HomePage()));
}
}, isDarkMode, color: ThemeColors.getColor('cardText', isDarkMode)),
],
),
const SizedBox(height: 16), // Spacer between buttons and message
// Directly placing the _buildMessageWidget here
_buildMessageWidget(isDarkMode),
// Disclaimer message - conditional based on isCancelled
if (!isCancelled)
Padding(
padding: const EdgeInsets.only(top: 8.0),
child: Text(
"The 'Exit' button will appear after cancelling the scan.",
style: GoogleFonts.roboto(
color: ThemeColors.getColor('dialogSubText', isDarkMode),
fontSize: 12,
fontStyle: FontStyle.italic),
textAlign: TextAlign.center,
),
),
],
),
);
}

// New widget to display messages with icons and styled backgrounds
Widget _buildMessageWidget(bool isDarkMode) {
Color textColor;
Color iconColor;
IconData iconData;
Color backgroundColor;
Color borderColor;

switch (_currentMessageType) {
case _SerialPortMessageType.success:
textColor = ThemeColors.getColor('submitButton', isDarkMode);
iconColor = ThemeColors.getColor('submitButton', isDarkMode);
iconData = Icons.check_circle_outline;
backgroundColor = ThemeColors.getColor('submitButton', isDarkMode).withOpacity(0.08);
borderColor = ThemeColors.getColor('submitButton', isDarkMode).withOpacity(0.6);
break;
case _SerialPortMessageType.info:
textColor = ThemeColors.getColor('serialPortMessageText', isDarkMode);
iconColor = ThemeColors.getColor('serialPortMessageText', isDarkMode);
iconData = isScanning ? Icons.cached : Icons.info_outline; // Show refresh icon if scanning
backgroundColor = ThemeColors.getColor('serialPortMessagePanelBackground', isDarkMode);
borderColor = ThemeColors.getColor('serialPortCardBorder', isDarkMode);
break;
case _SerialPortMessageType.warning:
textColor = Colors.orange[700]!;
iconColor = Colors.orange[700]!;
iconData = Icons.warning_amber_outlined;
backgroundColor = Colors.orange.withOpacity(0.08);
borderColor = Colors.orange.withOpacity(0.6);
break;
case _SerialPortMessageType.error:
textColor = ThemeColors.getColor('errorText', isDarkMode);
iconColor = ThemeColors.getColor('errorText', isDarkMode);
iconData = Icons.error_outline;
backgroundColor = ThemeColors.getColor('errorText', isDarkMode).withOpacity(0.08);
borderColor = ThemeColors.getColor('errorText', isDarkMode).withOpacity(0.6);
break;
}

return Container(
width: double.infinity, // Still stretches to full width
padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
margin: const EdgeInsets.only(top: 8),
decoration: BoxDecoration(
color: backgroundColor,
borderRadius: BorderRadius.circular(8),
border: Border.all(color: borderColor),
),
child: Row(
mainAxisSize: MainAxisSize.max, // Let Row fill the width
mainAxisAlignment: MainAxisAlignment.center, // Center contents of the row
children: [
// Only show progress indicator if it's 'info' type and actively scanning
if (_currentMessageType == _SerialPortMessageType.info && isScanning)
Padding(
padding: const EdgeInsets.only(right: 8.0),
child: SizedBox(
width: 16,
height: 16,
child: CircularProgressIndicator(
strokeWidth: 2,
valueColor: AlwaysStoppedAnimation<Color>(iconColor),
),
),
)
else
Icon(iconData, color: iconColor, size: 20),
const SizedBox(width: 8),
Flexible( // Use Flexible to allow text to wrap but constrain its width
child: Text(
_currentMessage,
style: GoogleFonts.roboto(color: textColor, fontSize: 14),
textAlign: TextAlign.center, // Center the text itself
overflow: TextOverflow.ellipsis, // Keep ellipsis for long lines
maxLines: 2, // Allow up to 2 lines
),
),
],
),
);
}

// MODIFIED _buildLeftSection to implement 20/60/20 split
Widget _buildLeftSection(bool isDarkMode) {
// This section now contains ALL inputs and ALL general controls for Combined mode
return Column(
crossAxisAlignment: CrossAxisAlignment.stretch, // Stretch children horizontally
children: [
// TOP SECTION: Input fields (approx 20% height)
Flexible( // Use Flexible so it takes its allocated space, but internal widgets size themselves
flex: 2, // 2 out of 10 total flex points for vertical distribution
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
const SizedBox(height: 16), // Spacer between sections

// MIDDLE SECTION: Data table (approx 60% height)
Expanded( // Use Expanded so the table truly takes all remaining space after flexible widgets
flex: 6, // 6 out of 10 total flex points
child: Card( // Wrap the table builder in a Card
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
const SizedBox(height: 16), // Spacer between sections

// BOTTOM SECTION: Control buttons (approx 20% height) - Show only if not 'Graph' mode
ValueListenableBuilder<String>(
valueListenable: Global.selectedMode,
builder: (context, mode, _) {
// Show bottom section on left for 'Table' and 'Combined' modes
if (mode == 'Table' || mode == 'Combined') {
return Flexible(
flex: 2,
child: _buildBottomSectionContent(isDarkMode), // Direct use, removed redundant Column
);
}
return const SizedBox.shrink(); // Hide for 'Graph' mode
},
),
],
);
}

Widget _buildRightSection(bool isDarkMode) {
final isCompact = MediaQuery
    .of(context)
    .size
    .width < 600;

// Widget for graph-specific controls, shared by 'Graph' and 'Combined' modes
Widget graphControlBar = SingleChildScrollView( // Allows horizontal scrolling for the top control bar
scrollDirection: Axis.horizontal,
child: Row( // Use Row instead of Wrap to force one row
mainAxisAlignment: MainAxisAlignment.start,
crossAxisAlignment: CrossAxisAlignment.center,
children: [
Row( // Segment controls
mainAxisSize: MainAxisSize.min,
children: [
Text('Segment:',
style: GoogleFonts.roboto(
color: ThemeColors.getColor('dialogText', isDarkMode),
fontWeight: FontWeight.w500,
fontSize: 13)),
const SizedBox(width: 4),
// Increased width for better readability for graph segment time fields
_buildTimeInputField(
_graphVisibleHrController, 'Hr', isDarkMode, compact: true, width: 50),
const SizedBox(width: 4),
_buildTimeInputField(
_graphVisibleMinController, 'Min', isDarkMode,
compact: true, width: 50),
],
),
const SizedBox(width: 8),

// Channel Selector Dropdown
Container(
// Increased padding and added border for visibility
padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
decoration: BoxDecoration(
color: ThemeColors.getColor('serialPortDropdownBackground', isDarkMode),
borderRadius: BorderRadius.circular(8),
border: Border.all(color: ThemeColors.getColor('serialPortCardBorder', isDarkMode).withOpacity(0.7)), // Added border
boxShadow: [
BoxShadow(
color: ThemeColors.getColor('serialPortCardBorder', isDarkMode).withOpacity(0.3),
blurRadius: 3)
],
),
child: DropdownButton<String?>(
value: _selectedGraphChannel,
hint: Text('All Channels',
style: GoogleFonts.roboto(
color: ThemeColors.getColor('serialPortDropdownText', isDarkMode), fontSize: 13)),
onChanged: (String? newValue) {
if (!mounted) return; // Crucial check for onChanged
setState(() {
_selectedGraphChannel = newValue;
});
},
items: [
DropdownMenuItem<String?>(
value: null,
child: Text('All Channels',
style: GoogleFonts.roboto(
color: ThemeColors.getColor('serialPortDropdownText', isDarkMode), fontSize: 13)),
),
...channelConfigs.keys.map(
(channelId) =>
DropdownMenuItem<String>(
value: channelId,
child: Text(
'Channel ${channelConfigs[channelId]!.channelName}',
style: GoogleFonts.roboto(
color: ThemeColors.getColor('serialPortDropdownText', isDarkMode), fontSize: 13),
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

// Show Dots Switch
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
if (!mounted) return; // Crucial check for onChanged
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

// Add Window button
_buildStyledAddButton(isDarkMode),
],
),
);

// Common graph view structure
Widget graphView = Expanded(
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
);

return ValueListenableBuilder<String>(
valueListenable: Global.selectedMode,
builder: (context, mode, _) {
final selectedMode = mode ?? 'Graph';

if (selectedMode == 'Graph') {
return Column(
crossAxisAlignment: CrossAxisAlignment.stretch,
children: [
// Full input section for Graph mode
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
SizedBox(width: isCompact ? 100 : 120, child: TextField(controller: _fileNameController, decoration: InputDecoration(labelText: 'File Name', labelStyle: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortInputLabel', isDarkMode), fontSize: 13), filled: true, fillColor: ThemeColors.getColor('serialPortInputFill', isDarkMode), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: isCompact ? 8 : 10), isDense: true,), style: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortInputText', isDarkMode), fontSize: 14), onChanged: (val) {},)),
const SizedBox(width: 8),
SizedBox(width: isCompact ? 100 : 120, child: TextField(controller: _operatorController, decoration: InputDecoration(labelText: 'Operator', labelStyle: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortInputLabel', isDarkMode), fontSize: 13), filled: true, fillColor: ThemeColors.getColor('serialPortInputFill', isDarkMode), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: isCompact ? 8 : 10), isDense: true,), style: GoogleFonts.roboto(color: ThemeColors.getColor('serialPortInputText', isDarkMode), fontSize: 14), onChanged: (val) {},)),
const SizedBox(width: 8),
Row(mainAxisSize: MainAxisSize.min, children: [ Text('Scan Rate:', style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode), fontWeight: FontWeight.w500, fontSize: 13)), const SizedBox(width: 4), _buildTimeInputField(_scanRateHrController, 'Hr', isDarkMode, compact: true, width: 45), const SizedBox(width: 4), _buildTimeInputField(_scanRateMinController, 'Min', isDarkMode, compact: true, width: 45), const SizedBox(width: 4), _buildTimeInputField(_scanRateSecController, 'Sec', isDarkMode, compact: true, width: 45), ],),
const SizedBox(width: 8),
Row(mainAxisSize: MainAxisSize.min, children: [ Text('Test Duration:', style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode), fontWeight: FontWeight.w500, fontSize: 13)), const SizedBox(width: 4), _buildTimeInputField(_testDurationDayController, 'Day', isDarkMode, compact: true, width: 45), const SizedBox(width: 4), _buildTimeInputField(_testDurationHrController, 'Hr', isDarkMode, compact: true, width: 45), const SizedBox(width: 4), _buildTimeInputField(_testDurationMinController, 'Min', isDarkMode, compact: true, width: 45), const SizedBox(width: 4), _buildTimeInputField(_testDurationSecController, 'Sec', isDarkMode, compact: true, width: 45), ],),
const SizedBox(width: 8),
graphControlBar, // Include graph controls here
],
),
),
),
),
const SizedBox(height: 16),
graphView, // The graph itself
const SizedBox(height: 16),
_buildBottomSectionContent(isDarkMode), // Buttons for Graph mode
],
);
} else if (selectedMode == 'Combined') {
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
child: graphControlBar, // ONLY graph controls here for Combined mode
),
),
const SizedBox(height: 16),
graphView, // The graph itself
],
);
} else {
return const SizedBox.shrink(); // No content for 'Table' mode in this section
}
},
);
}

@override
Widget build(BuildContext context) {
return ScaffoldMessenger( // Wrap with ScaffoldMessenger to provide context for Snackbars
key: _scaffoldMessengerKey,
child: ValueListenableBuilder<bool>(
valueListenable: Global.isDarkMode,
builder: (context, isDarkMode, child) {
return Scaffold(
backgroundColor: ThemeColors.getColor('serialPortBackground', isDarkMode),
body: SafeArea(
child: ValueListenableBuilder<String>(
valueListenable: Global.selectedMode,
builder: (context, mode, _) {
final selectedMode = mode ?? 'Graph'; // Default to Graph if somehow null
if (selectedMode == 'Table') {
return Padding(
padding: const EdgeInsets.all(16.0),
child: _buildLeftSection(isDarkMode), // Only left section for 'Table' mode
);
} else if (selectedMode == 'Graph') {
return Padding(
padding: const EdgeInsets.all(16.0),
child: _buildRightSection(isDarkMode), // Only right section for 'Graph' mode
);
} else { // 'Combined' mode
return Padding(
padding: const EdgeInsets.all(16.0),
child: Row( // Combined mode (original 2:3 ratio)
crossAxisAlignment: CrossAxisAlignment.stretch, // Stretch children vertically
children: [
Expanded(flex: 1, child: _buildLeftSection(isDarkMode)), // Left section with all controls/inputs
const SizedBox(width: 16),
Expanded(flex: 1, child: _buildRightSection(isDarkMode)), // Right section with only graph and its specific controls
],
),
);
}
},
),
),
);
},
),
);
}

@override
void dispose() {
LogPage.addLog('[$_currentTime] AutoStart Screen disposed.');

for (var entry in _windowEntries) {
entry.remove();
}
_windowEntries.clear();

// Removed unused _scrollController.dispose();
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

// Cancel all timers
_reconnectTimer?.cancel();
_testDurationTimer?.cancel();
_tableUpdateTimer?.cancel();
_debounceTimer?.cancel();
_endTimeTimer?.cancel(); // Cancel the end time timer

// Cancel reader subscription and close reader
_readerSubscription?.cancel();
reader?.close();

// Close and dispose serial port
if (port != null) {
if (port!.isOpen) {
try {
port!.close();
} catch (e) {
LogPage.addLog('[$_currentTime] Error closing serial port on dispose: $e');
}
}
try {
port!.dispose();
} catch (e) {
LogPage.addLog('[$_currentTime] Error disposing serial port on dispose: $e');
}
}
port = null; // Ensure port is null after disposal

Global.isScanningNotifier.value = false; // Set global notifier to false

super.dispose();
}
}

