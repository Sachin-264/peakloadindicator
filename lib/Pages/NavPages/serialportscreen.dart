import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../constants/colors.dart';
import '../../constants/global.dart';
import 'package:flutter/foundation.dart';
import 'package:peakloadindicator/Pages/homepage.dart';
import 'channel.dart';

class SerialPortScreen extends StatefulWidget {
  final List<dynamic> selectedChannels;
  const SerialPortScreen({super.key, required this.selectedChannels});

  @override
  State<SerialPortScreen> createState() => _SerialPortScreenState();
}

class _SerialPortScreenState extends State<SerialPortScreen> {
  final String portName = 'COM6';
  SerialPort? port;
  Map<String, List<Map<String, dynamic>>> dataByChannel = {};
  final Set<String> _openDialogChannels = {};
  Map<String, int> _windowIds = {};
  Map<double, Map<String, dynamic>> _bufferedData = {};
  String buffer = "";
  Widget portMessage = Text("Ready to start scanning", style: GoogleFonts.roboto(fontSize: 16));
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
  String yAxisType = 'Load';
  Timer? _reconnectTimer;
  Timer? _testDurationTimer;
  Timer? _tableUpdateTimer; // New timer for table updates
  int _reconnectAttempts = 0;
  int _lastScanIntervalSeconds = 1;
  Timer? _debounceTimer;
  static const int _maxReconnectAttempts = 5;
  static const int _minInactivityTimeoutSeconds = 5;
  static const int _maxInactivityTimeoutSeconds = 30;
  static const int _reconnectPeriodSeconds = 5;

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

  @override
  void initState() {
    super.initState();
    _initPort();
    _initializeChannelConfigs();
    _startReconnectTimer();
  }

  void _initPort() {
    port = SerialPort(portName);
    debugPrint('Initialized port: $portName');
  }

  void _initializeChannelConfigs() {
    channelConfigs.clear();
    channelColors.clear();
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
        final channelId = channel.channelName[0];
        channelConfigs[channelId] = channel;
        channelColors[channelId] = defaultColors[i % defaultColors.length];
        debugPrint('Configured channel $channelId: ${channel.toString()}');
      } catch (e) {
        debugPrint('Error configuring channel at index $i: $e');
        setState(() {
          errors.add('Invalid channel configuration at index $i: $e');
        });
      }
    }

    if (channelConfigs.isEmpty) {
      setState(() {
        portMessage = Text('No valid channels configured', style: GoogleFonts.roboto(color: Colors.red, fontSize: 16));
        errors.add('No valid channels configured');
      });
    }
  }

  void _openSecondaryWindow(String? channel) async {
    // Generate a unique key for each window
    final uniqueKey = '${channel ?? 'all'}_${DateTime.now().millisecondsSinceEpoch}';
    debugPrint('Opening secondary window with key $uniqueKey');

    try {
      final channelData = _prepareChannelData(channel);
      final args = {
        'channel': channel ?? 'All',
        'channelData': channelData,
      };

      final window = await DesktopMultiWindow.createWindow(jsonEncode(args));
      _windowIds[uniqueKey] = window.windowId;
      _openDialogChannels.add(uniqueKey);
      window
        ..setFrame(const Offset(100, 100) & const Size(800, 600))
        ..center()
        ..setTitle('Channel ${channelData['channelName']} Data')
        ..show();

      print('[SECONDARY_WINDOW] Opened window with key $uniqueKey and ID ${window.windowId}');

      // Listen for window close event
      DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
        if (call.method == 'close' && _windowIds.containsValue(fromWindowId)) {
          final key = _windowIds.entries.firstWhere((e) => e.value == fromWindowId).key;
          _windowIds.remove(key);
          _openDialogChannels.remove(key);
          print('[SECONDARY_WINDOW] Closed window with key $key');
        }
        return null;
      });
    } catch (e) {
      debugPrint('Error opening secondary window: $e');
      setState(() {
        errors.add('Error opening secondary window: $e');
        portMessage = Text('Error opening window: $e', style: GoogleFonts.roboto(color: Colors.red, fontSize: 16));
      });
      _openDialogChannels.remove(uniqueKey);
    }
  }

  void _updateSecondaryWindow(String? channel) async {
    // Update all windows that match the channel (or 'all')
    final channelKeyPrefix = channel ?? 'all';
    try {
      final channelData = _prepareChannelData(channel);
      final args = {
        'channel': channel ?? 'All',
        'channelData': channelData,
      };

      // Iterate over all open windows
      for (var key in _windowIds.keys) {
        // Check if the window matches the channel or is an 'all' window
        if (key.startsWith(channelKeyPrefix) || key.startsWith('all')) {
          if (_windowIds.containsKey(key)) {
            try {
              await DesktopMultiWindow.invokeMethod(
                _windowIds[key]!,
                'updateData',
                jsonEncode(args),
              );
              print('[SECONDARY_WINDOW] Updated data for window with key $key');
            } catch (e) {
              debugPrint('Error updating window $key: $e');
              // Remove invalid window ID
              _windowIds.remove(key);
              _openDialogChannels.remove(key);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error updating secondary windows for $channelKeyPrefix: $e');
    }
  }


  Map<String, dynamic> _prepareChannelData(String? channel) {
    print('[CHANNEL_DATA] Preparing data for channel: $channel');
    Map<String, dynamic> data = {
      'channelName': channel == null ? 'All Channels' : channelConfigs[channel]!.channelName,
      'dataPoints': [],
    };

    int segmentHours = int.tryParse(_graphVisibleHrController.text) ?? 0;
    int segmentMinutes = int.tryParse(_graphVisibleMinController.text) ?? 60;
    double segmentSeconds = (segmentHours * 3600) + (segmentMinutes * 60);
    double segmentDurationMs = segmentSeconds * 1000;

    // Get the current segment data
    List<Map<String, dynamic>> segmentData = [];
    if (segmentedDataByChannel.containsKey(channelConfigs.keys.first) &&
        segmentedDataByChannel[channelConfigs.keys.first]!.isNotEmpty &&
        currentGraphIndex < segmentedDataByChannel[channelConfigs.keys.first]!.length) {
      segmentData = segmentedDataByChannel[channelConfigs.keys.first]![currentGraphIndex];
    } else if (dataByChannel.containsKey(channelConfigs.keys.first)) {
      segmentData = dataByChannel[channelConfigs.keys.first]!.toList();
    }

    print('[CHANNEL_DATA] Segment data length: ${segmentData.length}');
    if (segmentData.isNotEmpty) {
      // print('[CHANNEL_DATA] Segment data sample: data aagya ');
    }

    // Calculate segment boundaries
    double segmentStartTimeMs;
    double segmentEndTimeMs;
    if (segmentData.isNotEmpty) {
      double firstTimestampMs = (segmentData.first['Timestamp'] as num?)?.toDouble() ?? DateTime.now().millisecondsSinceEpoch.toDouble();
      segmentStartTimeMs = firstTimestampMs;
      segmentEndTimeMs = firstTimestampMs + segmentDurationMs;
    } else {
      segmentStartTimeMs = DateTime.now().millisecondsSinceEpoch.toDouble() - segmentDurationMs;
      segmentEndTimeMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    }

    print('[CHANNEL_DATA] Segment boundaries: start=$segmentStartTimeMs, end=$segmentEndTimeMs');

    if (channel == null) {
      // Prepare data for all channels
      channelConfigs.keys.forEach((ch) {
        List<Map<String, dynamic>> points = segmentData
            .where((row) {
          try {
            double timestampMs = (row['Timestamp'] as num?)?.toDouble() ?? 0.0;
            bool isWithinBounds = timestampMs >= segmentStartTimeMs && timestampMs < segmentEndTimeMs && timestampMs.isFinite;
            if (!isWithinBounds) {
              print('[CHANNEL_DATA] Filtered out point for channel $ch: timestamp=$timestampMs');
            }
            return isWithinBounds;
          } catch (e) {
            debugPrint('Error processing timestamp for channel $ch: $e');
            return false;
          }
        })
            .map((row) {
          final value = (row['Value_$ch'] as num?)?.toDouble() ?? 0.0;
          return {
            'time': row['Time'] as String? ?? '',
            'value': value.isFinite ? value : 0.0,
            'timestamp': row['Timestamp']?.toDouble() ?? 0.0,
          };
        })
            .toList();

        data['dataPoints'].add({
          'channelIndex': ch,
          'channelName': channelConfigs[ch]!.channelName,
          'points': points,
        });
        print('[CHANNEL_DATA] Added ${points.length} points for channel ${channelConfigs[ch]!.channelName} (index $ch)');
      });
    } else {
      // Prepare data for a specific channel
      List<Map<String, dynamic>> points = segmentData
          .where((row) {
        try {
          double timestampMs = (row['Timestamp'] as num?)?.toDouble() ?? 0.0;
          bool isWithinBounds = timestampMs >= segmentStartTimeMs && timestampMs < segmentEndTimeMs && timestampMs.isFinite;
          if (!isWithinBounds) {
            print('[CHANNEL_DATA] Filtered out point for channel $channel: timestamp=$timestampMs');
          }
          return isWithinBounds;
        } catch (e) {
          debugPrint('Error processing timestamp for channel $channel: $e');
          return false;
        }
      })
          .map((row) {
        final value = (row['Value_$channel'] as num?)?.toDouble() ?? 0.0;
        return {
          'time': row['Time'] as String? ?? '',
          'value': value.isFinite ? value : 0.0,
          'timestamp': row['Timestamp']?.toDouble() ?? 0.0,
        };
      })
          .toList();

      data['dataPoints'] = points;
      print('[CHANNEL_DATA] Added ${points.length} points for channel ${channelConfigs[channel]!.channelName} (index $channel)');
    }

    return data;
  }

  void _showColorPicker(String channel) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select Color for Channel ${channelConfigs[channel]!.channelName}'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: channelColors[channel]!,
            onColorChanged: (Color color) {
              setState(() {
                channelColors[channel] = color;
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
  }

  void _showChannelSelectionDialog() {
    Map<String, bool> selectedChannels = {};
    channelConfigs.keys.forEach((channel) {
      selectedChannels[channel] = false;
    });
    bool selectAll = false;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select Channels', style: GoogleFonts.roboto(fontWeight: FontWeight.bold)),
        content: StatefulBuilder(
          builder: (context, setDialogState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  title: Text('All Channels', style: GoogleFonts.roboto()),
                  value: selectAll,
                  onChanged: (value) {
                    setDialogState(() {
                      selectAll = value ?? false;
                      selectedChannels.updateAll((key, _) => selectAll);
                    });
                  },
                ),
                ...channelConfigs.keys.map((channel) => CheckboxListTile(
                  title: Text('Channel ${channelConfigs[channel]!.channelName}', style: GoogleFonts.roboto()),
                  value: selectedChannels[channel],
                  onChanged: (value) {
                    setDialogState(() {
                      selectedChannels[channel] = value ?? false;
                      selectAll = selectedChannels.values.every((selected) => selected);
                    });
                  },
                )),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: GoogleFonts.roboto(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (selectAll || selectedChannels.values.every((selected) => selected)) {
                _openSecondaryWindow(null); // Open window for all channels
              } else {
                selectedChannels.forEach((channel, selected) {
                  if (selected) {
                    _openSecondaryWindow(channel);
                  }
                });
              }
              print('[CHANNEL_SELECTION] Selected channels: ${selectedChannels.entries.where((e) => e.value).map((e) => e.key).toList()}');
            },
            child: Text('Add', style: GoogleFonts.roboto(color: AppColors.submitButton)),
          ),
        ],
      ),
    );
  }

  void _configurePort() {
    if (port == null || !port!.isOpen) return;
    final config = SerialPortConfig()
      ..baudRate = 2400
      ..bits = 8
      ..parity = SerialPortParity.none
      ..stopBits = 1
      ..setFlowControl(SerialPortFlowControl.none);
    port!.config = config;
    debugPrint('Port configured: baudRate=${config.baudRate}, bits=${config.bits}, '
        'parity=${config.parity}, stopBits=${config.stopBits}');
    config.dispose();
  }

  int _getInactivityTimeout() {
    int timeout = scanIntervalSeconds + 2;
    return timeout.clamp(_minInactivityTimeoutSeconds, _maxInactivityTimeoutSeconds);
  }

  void _startReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(Duration(seconds: _reconnectPeriodSeconds), (timer) {
      if (isCancelled || isManuallyStopped) {
        debugPrint('Autoreconnect: Stopped by user');
        return;
      }
      if (isScanning && lastDataTime != null && DateTime.now().difference(lastDataTime!).inSeconds > _getInactivityTimeout()) {
        debugPrint('No data received for ${_getInactivityTimeout()} seconds, reconnecting...');
        _autoStopAndReconnect();
      } else if (!isScanning) {
        debugPrint('Autoreconnect: Attempting to restart scan...');
        _autoStartScan();
      }
    });
  }

  void _autoStopAndReconnect() {
    if (isScanning) {
      _stopScanInternal();
      setState(() {
        portMessage = Text('Port disconnected - Reconnecting...', style: GoogleFonts.roboto(color: Colors.orange, fontSize: 16));
        errors.add('Port disconnected - Reconnecting...');
      });
      _reconnectAttempts = 0;
    }
  }

  void _autoStartScan() {
    if (!isScanning && !isCancelled && !isManuallyStopped && _reconnectAttempts < _maxReconnectAttempts) {
      try {
        debugPrint('Autoreconnect: Attempt ${_reconnectAttempts + 1}/$_maxReconnectAttempts');
        if (port == null || !port!.isOpen) {
          _initPort();
          if (!port!.openReadWrite()) {
            throw SerialPort.lastError!;
          }
        }
        _configurePort();
        port!.flush();
        _setupReader();
        setState(() {
          isScanning = true;
          portMessage = Text('Reconnected to $portName - Scanning resumed', style: GoogleFonts.roboto(color: Colors.green, fontSize: 16, fontWeight: FontWeight.w600));
          errors.add('Reconnected to $portName - Scanning resumed');
        });
        _reconnectAttempts = 0;
      } catch (e) {
        debugPrint('Autoreconnect: Error: $e');
        setState(() {
          portMessage = Text('Reconnect error: $e', style: GoogleFonts.roboto(color: Colors.red, fontSize: 16));
          errors.add('Reconnect error: $e');
        });
        _reconnectAttempts++;
      }
    } else if (_reconnectAttempts >= _maxReconnectAttempts) {
      setState(() {
        portMessage = Text('Reconnect failed after $_maxReconnectAttempts attempts', style: GoogleFonts.roboto(color: Colors.red, fontSize: 16));
        errors.add('Reconnect failed after $_maxReconnectAttempts attempts');
      });
    }
  }

  void _setupReader() {
    if (port == null || !port!.isOpen) return;
    reader?.close();
    _readerSubscription?.cancel();
    reader = SerialPortReader(port!);
    _readerSubscription = reader!.stream.listen(
          (Uint8List data) {
        final decoded = String.fromCharCodes(data);
        buffer += decoded;

        String regexPattern = channelConfigs.entries.map((e) => '\\${e.value.startingCharacter}[0-9]*\\.[0-9]').join('|');
        final regex = RegExp(regexPattern);
        final matches = regex.allMatches(buffer).toList();

        for (final match in matches) {
          final extracted = match.group(0);
          if (extracted != null && channelConfigs.containsKey(extracted[0])) {
            // debugPrint('Matched data: $extracted');
            _addToDataList(extracted);
          }
        }

        if (matches.isNotEmpty) {
          buffer = buffer.replaceAll(regex, '');
        }

        if (buffer.length > 1000 && matches.isEmpty) {
          buffer = '';
        }
      },
      onError: (error) {
        debugPrint('Stream error: $error');
        setState(() {
          portMessage = Text('Error reading data: $error', style: GoogleFonts.roboto(color: Colors.red, fontSize: 16));
          errors.add('Error reading data: $error');
        });
      },
      onDone: () {
        debugPrint('Stream done');
        if (isScanning) {
          setState(() {
            portMessage = Text('Port disconnected - Reconnecting...', style: GoogleFonts.roboto(color: Colors.orange, fontSize: 16));
            errors.add('Port disconnected - Reconnecting...');
          });
        }
      },
    );
  }

  void _startScan() {
    if (!isScanning) {
      try {
        debugPrint('Starting scan...');
        if (channelConfigs.isEmpty) {
          throw Exception('No channels configured');
        }
        if (port == null || !port!.isOpen) {
          _initPort();
          if (port != null && port!.isOpen) {
            port!.close();
          }
          if (!port!.openReadWrite()) {
            throw SerialPort.lastError!;
          }
        }
        _configurePort();
        port!.flush();
        _setupReader();
        setState(() {
          isScanning = true;
          isCancelled = false;
          isManuallyStopped = false;
          portMessage = Text('Scanning active on $portName', style: GoogleFonts.roboto(color: Colors.green, fontWeight: FontWeight.w600, fontSize: 16));
          errors.add('Scanning active on $portName');
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
          _testDurationTimer = Timer(Duration(seconds: testDurationSeconds), () {
            _stopScan();
            setState(() {
              portMessage = Text('Test duration reached, scanning stopped', style: GoogleFonts.roboto(color: Colors.blue, fontSize: 16));
              errors.add('Test duration reached, scanning stopped');
            });
            print('[SERIAL_PORT] Test duration of $testDurationSeconds seconds reached, stopped scanning');
          });
        }
      } catch (e) {
        debugPrint('Error starting scan: $e');
        setState(() {
          portMessage = Text('Error starting scan: $e', style: GoogleFonts.roboto(color: Colors.red, fontSize: 16));
          errors.add('Error starting scan: $e');
        });
        if (e.toString().contains('busy') || e.toString().contains('Access denied')) {
          _cancelScan();
          _startScan();
        }
      }
    }
  }

  void _stopScan() {
    _stopScanInternal();
    setState(() {
      isManuallyStopped = true;
      portMessage = Text('Scanning stopped manually', style: GoogleFonts.roboto(fontSize: 16));
      errors.add('Scanning stopped manually');
    });
    _testDurationTimer?.cancel();
    _tableUpdateTimer?.cancel();
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
          portMessage = Text('Scanning stopped', style: GoogleFonts.roboto(fontSize: 16));
          errors.add('Scanning stopped');
        });
      } catch (e) {
        debugPrint('Error stopping scan: $e');
        setState(() {
          portMessage = Text('Error stopping scan: $e', style: GoogleFonts.roboto(color: Colors.red, fontSize: 16));
          errors.add('Error stopping scan: $e');
        });
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
      _openDialogChannels.toList().forEach((key) async {
        if (_windowIds.containsKey(key)) {
          await DesktopMultiWindow.invokeMethod(_windowIds[key]!, 'close', '');
          _windowIds.remove(key);
        }
      });
      _openDialogChannels.clear();
      setState(() {
        isScanning = false;
        isCancelled = true;
        dataByChannel.clear();
        _bufferedData.clear();
        buffer = "";
        segmentedDataByChannel.clear();
        errors.clear();
        currentGraphIndex = 0;
        reader = null;
        _readerSubscription = null;
        port = null;
        portMessage = Text('Scan cancelled', style: GoogleFonts.roboto(fontSize: 16));
        errors.add('Scan cancelled');
      });
      _initPort();
      _testDurationTimer?.cancel();
      _tableUpdateTimer?.cancel();
    } catch (e) {
      debugPrint('Error cancelling scan: $e');
      setState(() {
        portMessage = Text('Error cancelling scan: $e', style: GoogleFonts.roboto(color: Colors.red, fontSize: 16));
        errors.add('Error cancelling scan: $e');
      });
    }
  }

  void _startTableUpdateTimer() {
    if (scanIntervalSeconds == _lastScanIntervalSeconds && _tableUpdateTimer != null && _tableUpdateTimer!.isActive) {
      // debugPrint('Table update timer already active with interval $scanIntervalSeconds seconds, skipping restart');
      return;
    }

    _tableUpdateTimer?.cancel();
    if (scanIntervalSeconds < 1) {
      scanIntervalSeconds = 1;
    }
    _lastScanIntervalSeconds = scanIntervalSeconds;
    _tableUpdateTimer = Timer.periodic(Duration(seconds: scanIntervalSeconds), (_) {
      if (!isScanning || isCancelled || isManuallyStopped) {
        _tableUpdateTimer?.cancel();
        debugPrint('Table update timer cancelled due to scan state');
        return;
      }
      _addTableRow();
    });
    // debugPrint('Started table update timer with interval $scanIntervalSeconds seconds');
  }

  void _addTableRow() {
    DateTime now = DateTime.now();
    double timestamp = now.millisecondsSinceEpoch.toDouble();
    String time = "${now.hour}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
    String date = "${now.day}/${now.month}/${now.year}";

    setState(() {
      Map<String, dynamic> newData = {
        'Serial No': '${(dataByChannel.isNotEmpty ? dataByChannel.values.first.length : 0) + 1}',
        'Time': time,
        'Date': date,
        'Timestamp': timestamp,
      };

      channelConfigs.keys.forEach((channel) {
        var latestData;
        if (_bufferedData.isNotEmpty) {
          final recentTimestamps = _bufferedData.keys
              .where((t) => (t - timestamp).abs() <= 1000)
              .toList()
            ..sort();
          if (recentTimestamps.isNotEmpty) {
            final closestTimestamp = recentTimestamps.last;
            latestData = _bufferedData[closestTimestamp]?[channel];
          }
        }

        latestData ??= dataByChannel[channel]?.lastWhere(
              (d) => d['Timestamp'] <= timestamp,
          orElse: () => <String, dynamic>{'Value': 0.0, 'Data': ''},
        ) ??
            <String, dynamic>{'Value': 0.0, 'Data': ''};

        double value = (latestData['Value'] as num?)?.toDouble() ?? 0.0;
        // debugPrint(
        //     '[TABLE_UPDATE] Channel $channel at timestamp $timestamp: Retrieved value $value from latestData $latestData');

        newData['Value_$channel'] = value.isFinite ? value : 0.0;
        newData['Channel_$channel'] = channel;

        dataByChannel.putIfAbsent(channel, () => []).add({
          ...newData,
          'Value': newData['Value_$channel'],
          'Channel': channel,
          'Data': latestData['Data'] ?? '',
        });
      });

      _segmentData(newData);
      lastDataTime = now;
      // debugPrint('[TABLE_UPDATE] Added table row at timestamp $timestamp with data: $newData');

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

      // Update all secondary windows
      _openDialogChannels.forEach((channelKey) {
        String? channel = channelKey.startsWith('all') ? null : channelKey.split('_')[0];
        _updateSecondaryWindow(channel);
      });
    });
  }

  void _addToDataList(String data) {
    DateTime now = DateTime.now();
    final channel = data[0];
    if (!channelConfigs.containsKey(channel)) {
      debugPrint('Unknown channel: $channel');
      return;
    }

    final config = channelConfigs[channel]!;
    if (data.length != config.dataLength) {
      debugPrint('Invalid data length for channel $channel: $data (expected ${config.dataLength})');
      return;
    }

    final valueStr = data.substring(1);
    double value = double.tryParse(valueStr) ?? 0.0;
    double timestamp = now.millisecondsSinceEpoch.toDouble();

    _bufferedData.putIfAbsent(timestamp, () => {});
    _bufferedData[timestamp]![channel] = {
      'Value': value,
      'Time': "${now.hour}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}",
      'Date': "${now.day}/${now.month}/${now.year}",
      'Data': data,
      'Timestamp': timestamp,
      'Channel': channel,
    };

    // print('[SERIAL_PORT] Buffered data for channel $channel at timestamp $timestamp: $value');
  }

  void _segmentData(Map<String, dynamic> newData) {
    int graphVisibleSeconds = _calculateDurationInSeconds('0', _graphVisibleHrController.text, _graphVisibleMinController.text, '0');
    if (graphVisibleSeconds <= 0) {
      debugPrint('[SEGMENT_DATA] Invalid graph visible duration: $graphVisibleSeconds seconds');
      return;
    }

    double newTimestamp = newData['Timestamp'] as double;
    channelConfigs.keys.forEach((channel) {
      segmentedDataByChannel.putIfAbsent(channel, () => []);

      if (segmentedDataByChannel[channel]!.isEmpty) {
        segmentedDataByChannel[channel]!.add([{
          ...newData,
          'Value': newData['Value_$channel'],
          'Channel': channel,
        }]);
        // print('[SERIAL_PORT] Created new segment for channel $channel at timestamp $newTimestamp');
        return;
      }

      // Get the timestamp of the first data point in the last segment
      List<Map<String, dynamic>> lastSegment = segmentedDataByChannel[channel]!.last;
      double lastSegmentStartTime = lastSegment.first['Timestamp'] as double;

      // Calculate if the new data point exceeds the segment duration
      if ((newTimestamp - lastSegmentStartTime) / 1000 >= graphVisibleSeconds) {
        segmentedDataByChannel[channel]!.add([{
          ...newData,
          'Value': newData['Value_$channel'],
          'Channel': channel,
        }]);
        // print('[SERIAL_PORT] Added new segment for channel $channel at timestamp $newTimestamp');
      } else {
        segmentedDataByChannel[channel]!.last.add({
          ...newData,
          'Value': newData['Value_$channel'],
          'Channel': channel,
        });
        // print('[SERIAL_PORT] Added data to existing segment for channel $channel at timestamp $newTimestamp');
      }
    });

    // Update currentGraphIndex to the latest segment
    if (segmentedDataByChannel.isNotEmpty) {
      setState(() {
        currentGraphIndex = segmentedDataByChannel.values.first.length - 1;
      });
    }
  }

  int _calculateDurationInSeconds(String day, String hr, String min, String sec) {
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
    }
  }

  Future<void> _saveData() async {
    try {
      print('Saving data to database started...');

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) => Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.submitButton),
          ),
        ),
      );

      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;

      final databasesPath = await getDatabasesPath();
      final path = '$databasesPath/Countronics.db';
      final database = await openDatabase(path);

      SharedPreferences prefs = await SharedPreferences.getInstance();
      int recNo = prefs.getInt('recNo') ?? 5;
      print('Current record number: $recNo');

      final testPayload = _prepareTestPayload(recNo);
      final test1Payload = _prepareTest1Payload(recNo);
      final test2Payload = _prepareTest2Payload(recNo);

      print('Test payload: $testPayload');
      print('Test1 payload: $test1Payload');
      print('Test2 payload: $test2Payload');

      await database.insert('Test', testPayload, conflictAlgorithm: ConflictAlgorithm.replace);
      print('Inserted into Test table: $testPayload');

      for (var entry in test1Payload) {
        await database.insert('Test1', entry, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      print('Inserted ${test1Payload.length} entries into Test1 table');

      await database.insert('Test2', test2Payload, conflictAlgorithm: ConflictAlgorithm.replace);
      print('Inserted into Test2 table: $test2Payload');

      await prefs.setInt('recNo', recNo + 1);
      print('Record number updated to: ${recNo + 1}');

      await database.close();

      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Data saved successfully to database'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      Navigator.of(context).pop();
      print('Error saving data to database: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving data: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Map<String, dynamic> _prepareTestPayload(int recNo) {
    return {
      "RecNo": recNo.toDouble(),
      "FName": _fileNameController.text,
      "OperatorName": _operatorController.text,
      "TDate": DateTime.now().toString().split(' ')[0],
      "TTime": DateTime.now().toString().split(' ')[1].split('.')[0],
      "ScanningRate": scanIntervalSeconds.toDouble(),
      "ScanningRateHH": double.tryParse(_scanRateHrController.text) ?? 0.0,
      "ScanningRateMM": double.tryParse(_scanRateMinController.text) ?? 0.0,
      "ScanningRateSS": double.tryParse(_scanRateSecController.text) ?? 0.0,
      "TestDurationDD": double.tryParse(_testDurationDayController.text) ?? 0.0,
      "TestDurationHH": double.tryParse(_testDurationHrController.text) ?? 0.0,
      "TestDurationMM": double.tryParse(_testDurationMinController.text) ?? 0.0,
      "GraphVisibleArea": 0.0,
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
      "MaxYAxis": channelConfigs.isNotEmpty ? channelConfigs.values.first.chartMaximumValue : 100.0,
      "MinYAxis": channelConfigs.isNotEmpty ? channelConfigs.values.first.chartMinimumValue : 0.0,
    };
  }

  List<Map<String, dynamic>> _prepareTest1Payload(int recNo) {
    List<Map<String, dynamic>> payload = [];
    final sortedChannels = channelConfigs.keys.toList()..sort();
    final timestamps = dataByChannel.values.firstOrNull?.map((d) => d['Timestamp'] as double).toSet().toList() ?? [];
    timestamps.sort();

    for (int i = 0; i < timestamps.length; i++) {
      final timestamp = timestamps[i];
      final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp.toInt());
      final data = dataByChannel[sortedChannels.first]?.firstWhere((d) => d['Timestamp'] == timestamp, orElse: () => {}) ?? {};

      Map<String, dynamic> payloadEntry = {
        "RecNo": recNo.toDouble(),
        "SNo": (i + 1).toDouble(),
        "SlNo": (i + 1).toDouble(),
        "ChangeTime": _formatTime(scanIntervalSeconds * (i + 1)),
        "AbsDate": "${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}",
        "AbsTime": "${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}",
        "AbsDateTime": "${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}",
        "Shown": i % 2 == 0 ? "Y" : "N",
        "AbsAvg": 0.0,
      };

      for (int j = 1; j <= 50; j++) {
        payloadEntry["AbsPer$j"] = null;
      }

      for (int j = 0; j < sortedChannels.length && j < 50; j++) {
        final channel = sortedChannels[j];
        final channelData = dataByChannel[channel]?.firstWhere((d) => d['Timestamp'] == timestamp, orElse: () => {}) ?? {};
        if (channelData['Value'] != null && (channelData['Value'] as double).isFinite) {
          payloadEntry["AbsPer${j + 1}"] = channelData['Value'] as double;
        }
      }

      payload.add(payloadEntry);
    }

    print('[SERIAL_PORT] Prepared Test1 payload with ${payload.length} entries');
    return payload;
  }

  Map<String, dynamic> _prepareTest2Payload(int recNo) {
    final sortedChannels = channelConfigs.keys.toList()..sort();
    Map<String, dynamic> payload = {
      "RecNo": recNo.toDouble(),
    };

    for (int i = 1; i <= 50; i++) {
      String channelName = i <= sortedChannels.length ? channelConfigs[sortedChannels[i - 1]]!.channelName : '';
      payload["ChannelName$i"] = channelName;
    }

    print('[SERIAL_PORT] Prepared Test2 payload with ${sortedChannels.length} channel names');
    return payload;
  }

  String _formatTime(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _showPreviousGraph() {
    if (currentGraphIndex > 0) {
      setState(() => currentGraphIndex--);
      print('[SERIAL_PORT] Navigated to previous graph segment: $currentGraphIndex');
    }
  }

  void _showNextGraph() {
    if (currentGraphIndex < (segmentedDataByChannel.values.firstOrNull?.length ?? 1) - 1) {
      setState(() => currentGraphIndex++);
      print('[SERIAL_PORT] Navigated to next graph segment: $currentGraphIndex');
    }
  }

  Map<String, List<Map<String, dynamic>>> get _currentGraphDataByChannel {
    Map<String, List<Map<String, dynamic>>> currentData = {};
    dataByChannel.forEach((channel, data) {
      if (segmentedDataByChannel[channel] != null && currentGraphIndex < segmentedDataByChannel[channel]!.length) {
        currentData[channel] = segmentedDataByChannel[channel]![currentGraphIndex];
      } else {
        currentData[channel] = data;
      }
    });
    return currentData;
  }

  Widget _buildGraphNavigation() {
    if (segmentedDataByChannel.isEmpty || segmentedDataByChannel.values.first.length <= 1) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(icon: Icon(Icons.chevron_left, color: AppColors.textPrimary), onPressed: _showPreviousGraph),
          Text('Segment ${currentGraphIndex + 1}/${segmentedDataByChannel.values.first.length}',
              style: GoogleFonts.roboto(color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
          IconButton(icon: Icon(Icons.chevron_right, color: AppColors.textPrimary), onPressed: _showNextGraph),
        ],
      ),
    );
  }

  Widget _buildGraph() {
    if (_currentGraphDataByChannel.isEmpty || _currentGraphDataByChannel.values.every((data) => data.isEmpty)) {
      return Center(
        child: Text(
          'Waiting for channel data...',
          style: GoogleFonts.roboto(color: Colors.grey[600], fontSize: 18),
        ),
      );
    }

    List<LineChartBarData> lineBarsData = [];
    double minX = double.infinity;
    double maxX = -double.infinity;
    double minY = double.infinity;
    double maxY = -double.infinity;
    Set<double> uniqueTimestamps = {};

    // Calculate segment time boundaries
    int segmentHours = int.tryParse(_graphVisibleHrController.text) ?? 0;
    int segmentMinutes = int.tryParse(_graphVisibleMinController.text) ?? 60;
    double segmentSeconds = (segmentHours * 3600) + (segmentMinutes * 60);
    double segmentDurationMs = segmentSeconds * 1000;

    final channelsToPlot = channelConfigs.keys.toList();

    for (var channel in channelsToPlot) {
      if (!channelConfigs.containsKey(channel) || !channelColors.containsKey(channel)) {
        debugPrint('Skipping channel $channel: Missing configuration or color');
        continue;
      }

      final config = channelConfigs[channel]!;
      final color = channelColors[channel]!;
      final channelData = _currentGraphDataByChannel[channel] ?? [];

      if (channelData.isEmpty) {
        debugPrint('No data available for channel $channel');
        continue;
      }

      // Determine segment time boundaries
      double segmentStartTimeMs = channelData.isNotEmpty
          ? (channelData.first['Timestamp'] as num?)?.toDouble() ?? DateTime.now().millisecondsSinceEpoch.toDouble()
          : DateTime.now().millisecondsSinceEpoch.toDouble();
      double segmentEndTimeMs = segmentStartTimeMs + segmentDurationMs;

      List<FlSpot> spots = channelData
          .where((d) {
        double timestamp = (d['Timestamp'] as num?)?.toDouble() ?? 0.0;
        return d['Value'] != null &&
            d['Timestamp'] != null &&
            (d['Value'] as double).isFinite &&
            (d['Timestamp'] as double).isFinite &&
            timestamp >= segmentStartTimeMs &&
            timestamp < segmentEndTimeMs;
      })
          .map((d) {
        double timestamp = (d['Timestamp'] as double);
        uniqueTimestamps.add(timestamp);
        double value = (d['Value'] as double);
        return FlSpot(timestamp, value);
      })
          .toList();

      if (spots.isNotEmpty) {
        final xValues = spots.map((s) => s.x).where((x) => x.isFinite);
        final yValues = spots.map((s) => s.y).where((y) => y.isFinite);

        if (xValues.isNotEmpty && yValues.isNotEmpty) {
          minX = min(minX, xValues.reduce((a, b) => a < b ? a : b));
          maxX = max(maxX, xValues.reduce((a, b) => a > b ? a : b));
          minY = min(minY, yValues.reduce((a, b) => a < b ? a : b));
          maxY = max(maxY, yValues.reduce((a, b) => a > b ? a : b));
        }

        lineBarsData.add(
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) {
                bool isNearMaxY = (spot.y >= maxY * 0.95);
                return FlDotCirclePainter(
                  radius: isNearMaxY ? 6 : 4,
                  color: isNearMaxY ? Colors.red : Colors.blue,
                  strokeWidth: 1,
                  strokeColor: Colors.white,
                );
              },
            ),
            belowBarData: BarAreaData(show: false),
          ),
        );
      }
    }

    if (lineBarsData.isEmpty || minX == double.infinity || maxX == -double.infinity) {
      minX = DateTime.now().millisecondsSinceEpoch.toDouble() - segmentDurationMs;
      maxX = DateTime.now().millisecondsSinceEpoch.toDouble();
      minY = 0.0;
      maxY = 100.0;
    } else {
      double yRange = maxY - minY;
      maxY += yRange * 0.1;
      minY -= yRange * 0.05;
      if (minY < 0 && minY != 0) minY = 0;
    }

    List<double> sortedTimestamps = uniqueTimestamps.toList()..sort();
    // print('[GRAPH] Unique timestamps for x-axis: $sortedTimestamps');

    double intervalY = (maxY - minY) / 5;
    if (intervalY == 0 || !intervalY.isFinite) intervalY = 1;

    Widget legend = Wrap(
      spacing: 16,
      runSpacing: 8,
      children: channelsToPlot
          .where((channel) => channelConfigs.containsKey(channel) && channelColors.containsKey(channel))
          .map((channel) {
        final color = channelColors[channel];
        final channelName = channelConfigs[channel]?.channelName ?? 'Unknown';
        return GestureDetector(
          onTap: () => _showColorPicker(channel),
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
        _buildGraphNavigation(),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), child: legend),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 24.0, 16.0, 16.0),
            child: LineChart(
              LineChartData(
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                      if (!spot.x.isFinite || !spot.y.isFinite) return null;
                      final channel = channelsToPlot[spot.barIndex];
                      final channelName = channelConfigs[channel]?.channelName ?? 'Unknown';
                      final unit = channelConfigs[channel]?.unit ?? '';
                      return LineTooltipItem(
                        'Channel $channelName\n${spot.y.toStringAsFixed(2)} $unit\n${DateTime.fromMillisecondsSinceEpoch(spot.x.toInt()).toString().split('.')[0]}',
                        GoogleFonts.roboto(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 12),
                      );
                    }).where((item) => item != null).toList().cast<LineTooltipItem>(),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: intervalY,
                  getDrawingVerticalLine: (value) => sortedTimestamps.contains(value)
                      ? FlLine(color: Colors.grey.withOpacity(0.3), strokeWidth: 1)
                      : FlLine(color: Colors.transparent),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    axisNameWidget: Text(
                      'Load (${channelConfigs.isNotEmpty ? channelConfigs.values.first.unit : "Unit"})',
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
                      getTitlesWidget: (value, meta) {
                        if (!sortedTimestamps.contains(value)) {
                          return const SizedBox();
                        }
                        final dateTime = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}',
                            style: GoogleFonts.roboto(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
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
                clipData: FlClipData(
                  top: false,
                  bottom: true,
                  left: true,
                  right: true,
                ),
                extraLinesData: ExtraLinesData(
                  extraLinesOnTop: true,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<TableRow> _buildTableRows() {
    List<TableRow> tableRows = [];
    final headers = ['Time', ...channelConfigs.keys.toList()..sort()];
    final columnCount = headers.length;
    const int maxRows = 100;

    if (dataByChannel.isEmpty) {
      tableRows.add(
        TableRow(
          children: List.generate(
            columnCount,
                (index) => Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text(
                index == 0 ? 'No data available' : '',
                style: GoogleFonts.roboto(color: AppColors.textPrimary, fontSize: 14),
              ),
            ),
          ),
        ),
      );
      return tableRows;
    }

    final timestamps = dataByChannel.values.firstOrNull?.map((d) => d['Timestamp'] as double).toSet().toList() ?? [];
    timestamps.sort();
    final startIndex = timestamps.length > maxRows ? timestamps.length - maxRows : 0;

    tableRows.add(
      TableRow(
        decoration: BoxDecoration(color: Colors.grey[200]),
        children: headers.map((header) {
          return Padding(
            padding: const EdgeInsets.all(12.0),
            child: Text(
              header == 'Time' ? 'Time' : channelConfigs[header]!.channelName,
              style: GoogleFonts.roboto(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 14),
            ),
          );
        }).toList(),
      ),
    );

    for (int i = startIndex; i < timestamps.length; i++) {
      final timestamp = timestamps[i];
      final data = dataByChannel[headers[1]]?.firstWhere((d) => d['Timestamp'] == timestamp, orElse: () => {}) ?? {};
      final time = data['Time'] as String? ?? '';

      final rowCells = headers.map((header) {
        if (header == 'Time') {
          return Padding(
            padding: const EdgeInsets.all(12.0),
            child: Text(
              time,
              style: GoogleFonts.roboto(
                color: i == timestamps.length - 1 ? Colors.green : AppColors.textPrimary,
                fontWeight: i == timestamps.length - 1 ? FontWeight.bold : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          );
        }
        final channel = header;
        final channelData = dataByChannel[channel]?.firstWhere((d) => d['Timestamp'] == timestamp, orElse: () => {}) ?? {};
        final config = channelConfigs[channel]!;
        final value = channelData['Value'] != null ? '${channelData['Value'].toStringAsFixed(config.decimalPlaces)}${config.unit}' : '';
        return Padding(
          padding: const EdgeInsets.all(12.0),
          child: Text(
            value,
            style: GoogleFonts.roboto(
              color: i == timestamps.length - 1 && value.isNotEmpty ? Colors.green : AppColors.textPrimary,
              fontWeight: i == timestamps.length - 1 && value.isNotEmpty ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
            ),
          ),
        );
      }).toList();

      tableRows.add(
        TableRow(
          decoration: BoxDecoration(color: i % 2 == 0 ? Colors.white : Colors.grey[50]),
          children: rowCells,
        ),
      );
    }

    // print('[SERIAL_PORT] Built ${tableRows.length} table rows (limited to last $maxRows)');
    return tableRows;
  }

  Widget _buildDataTable() {
    return Container(
      height: 400,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller : _tableScrollController,
              scrollDirection: Axis.vertical,
              physics: const AlwaysScrollableScrollPhysics(),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  border: TableBorder.all(color: Colors.grey[200]!),
                  defaultColumnWidth: const IntrinsicColumnWidth(),
                  children: _buildTableRows(),
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
                  icon: Icon(Icons.arrow_upward, color: AppColors.textPrimary),
                  onPressed: () => _tableScrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
                ),
                IconButton(
                  icon: Icon(Icons.arrow_downward, color: AppColors.textPrimary),
                  onPressed: () {
                    _tableScrollController.animateTo(_tableScrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                    print('[SERIAL_PORT] Scrolled table to latest data');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeInputField(TextEditingController controller, String label, {bool compact = false, double width = 120}) {
    return SizedBox(
      width: width, // Match File Name and Operator width
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.roboto(
            color: AppColors.textPrimary, // Full opacity for clarity
            fontSize: compact ? 12 : 14, // Match File Name/Operator label size
            fontWeight: FontWeight.w300, // Consistent with TextField style
          ),
          filled: true,
          fillColor: Colors.grey[50], // Match File Name/Operator
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(1),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20), // Match default TextField padding
        ),
        style: GoogleFonts.roboto(
          color: AppColors.textPrimary,
          fontSize: 14, // Slightly larger for readability
          fontWeight: FontWeight.w400, // Match File Name/Operator input text
        ),
        onChanged: (value) {
          _debounceTimer?.cancel();
          _debounceTimer = Timer(const Duration(milliseconds: 500), () {
            _updateScanInterval();
          });
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
      ),
      child: Text(text, style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildDateTimeDisplay() {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        final now = DateTime.now();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10)]),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.access_time, size: 16, color: AppColors.submitButton),
              const SizedBox(width: 8),
              Text('${now.hour}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}', style: GoogleFonts.roboto(color: AppColors.textPrimary)),
              const SizedBox(width: 16),
              Icon(Icons.calendar_today, size: 16, color: AppColors.submitButton),
              const SizedBox(width: 8),
              Text('${now.day}/${now.month}/${now.year}', style: GoogleFonts.roboto(color: AppColors.textPrimary)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLatestDataDisplay() {
    if (dataByChannel.isEmpty) return const SizedBox();
    final latestData = dataByChannel.entries.where((e) => e.value.isNotEmpty).map((e) => e.value.last).reduce((a, b) => a['Timestamp'] > b['Timestamp'] ? a : b);
    final config = channelConfigs[latestData['Channel']]!;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(
        'Latest: Channel ${config.channelName} - ${latestData['Time']} ${latestData['Date']} - ${latestData['Value'].toStringAsFixed(config.decimalPlaces)}${config.unit}',
        style: GoogleFonts.roboto(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildYAxisSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 5)]),
      child: DropdownButton<String>(
        value: yAxisType,
        onChanged: (String? newValue) => setState(() => yAxisType = newValue!),
        items: ['Load', 'Time'].map((value) => DropdownMenuItem<String>(value: value, child: Text(value, style: GoogleFonts.roboto(color: AppColors.textPrimary)))).toList(),
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
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
    Row(
    children: [
    Expanded(
    child: TextField(
    controller: _fileNameController,
    decoration: InputDecoration(
    labelText: 'File Name',
    filled: true,
    fillColor: Colors.grey[50],
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
    ),
    style: GoogleFonts.roboto(color: AppColors.textPrimary),
    ),
    ),
    const SizedBox(width: 16),
    Expanded(
    child: TextField(
    controller: _operatorController,
    decoration: InputDecoration(
    labelText: 'Operator',
    filled: true,
    fillColor: Colors.grey[50],
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
    ),
    style: GoogleFonts.roboto(color: AppColors.textPrimary),
    ),
    ),
    ],
    ),
    const SizedBox(height: 16),
    SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
    mainAxisAlignment: MainAxisAlignment.start,
    children: [
    Row(
    mainAxisSize: MainAxisSize.min,
    children: [
    Text('Scan Rate:', style: GoogleFonts.roboto(color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
    const SizedBox(width: 8),
    _buildTimeInputField(_scanRateHrController, 'Hr', width: 60),
    const SizedBox(width: 8),
    _buildTimeInputField(_scanRateMinController, 'Min', width: 60),
    const SizedBox(width: 8),
    _buildTimeInputField(_scanRateSecController, 'Sec', width: 60),
    ],
    ),
    const SizedBox(width: 16),
    Row(
    mainAxisSize: MainAxisSize.min,
    children: [
    Text('Test Duration:', style: GoogleFonts.roboto(color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
    const SizedBox(width: 8),
    _buildTimeInputField(_testDurationDayController, 'Day', width: 60),
    const SizedBox(width: 8),
    _buildTimeInputField(_testDurationHrController, 'Hr', width: 60),
    const SizedBox(width: 8),
    _buildTimeInputField(_testDurationMinController, 'Min', width: 60),
    const SizedBox(width: 8),
    _buildTimeInputField(_testDurationSecController, 'Sec', width: 60),
    ],
    ),
    ],
    ),
    ),
    ],
    ),
    ),
    );
  }

  Widget _buildBottomSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isScanning ? AppColors.submitButton.withOpacity(0.1) : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isScanning ? AppColors.submitButton.withOpacity(0.5) : Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              _buildControlButton('Start Scan', _startScan, disabled: isScanning),
              _buildControlButton('Stop Scan', _stopScan, color: Colors.orange[700], disabled: !isScanning),
              _buildControlButton('Cancel Scan', _cancelScan, color: AppColors.resetButton),
              _buildControlButton('Save Data', _saveData, color: Colors.green[700]),
              _buildControlButton('Multi File', () {}, color: Colors.purple[700]),
              _buildControlButton('Exit', () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const HomePage()));
              }, color: Colors.grey[600]),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isScanning)
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(AppColors.submitButton))),
                ),
              portMessage,
              if (errors.isNotEmpty && !errors.last.contains('Scanning'))
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Text(errors.last, style: GoogleFonts.roboto(color: errors.last.contains('Error') ? Colors.red : Colors.green, fontSize: 16)),
                ),
            ],
          ),
        ],
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
              child: Padding(padding: const EdgeInsets.all(16.0), child: _buildDataTable()),
            ),
          ),
        if (Global.selectedMode.value == 'Table' || Global.selectedMode.value == 'Combined') const SizedBox(height: 8),
        if (Global.selectedMode.value == 'Table' || Global.selectedMode.value == 'Combined') _buildLatestDataDisplay(),
        if (Global.selectedMode.value == 'Table' || Global.selectedMode.value == 'Combined') const SizedBox(height: 16),
        if (Global.selectedMode.value == 'Table' || Global.selectedMode.value == 'Combined') _buildBottomSection(),
      ],
    );
  }

  Widget _buildRightSection() {
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
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey[200]!),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: _fileNameController,
                            decoration: InputDecoration(
                              labelText: 'File Name',
                              filled: true,
                              fillColor: Colors.grey[50],
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            style: GoogleFonts.roboto(color: AppColors.textPrimary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: _operatorController,
                            decoration: InputDecoration(
                              labelText: 'Operator',
                              filled: true,
                              fillColor: Colors.grey[50],
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            style: GoogleFonts.roboto(color: AppColors.textPrimary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          children: [
                            Text(
                              'Scan Rate:',
                              style: GoogleFonts.roboto(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14, // Match TextField label size
                              ),
                            ),
                            const SizedBox(width: 8), // Increased spacing
                            _buildTimeInputField(_scanRateHrController, 'Hr', compact: true),
                            const SizedBox(width: 8),
                            _buildTimeInputField(_scanRateMinController, 'Min', compact: true),
                            const SizedBox(width: 8),
                            _buildTimeInputField(_scanRateSecController, 'Sec', compact: true),
                          ],
                        ),
                        const SizedBox(width: 8),
                        Row(
                          children: [
                            Text(
                              'Test Duration:',
                              style: GoogleFonts.roboto(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14, // Match TextField label size
                              ),
                            ),
                            const SizedBox(width: 8), // Increased spacing
                            _buildTimeInputField(_testDurationDayController, 'Day', compact: true),
                            const SizedBox(width: 8),
                            _buildTimeInputField(_testDurationHrController, 'Hr', compact: true),
                            const SizedBox(width: 8),
                            _buildTimeInputField(_testDurationMinController, 'Min', compact: true),
                            const SizedBox(width: 8),
                            _buildTimeInputField(_testDurationSecController, 'Sec', compact: true),
                          ],
                        ),
                        const SizedBox(width: 8),
                        Row(
                          children: [
                            Text(
                              'Segment:',
                              style: GoogleFonts.roboto(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14, // Match TextField label size
                              ),
                            ),
                            const SizedBox(width: 8), // Increased spacing
                            _buildTimeInputField(_graphVisibleHrController, 'Hr', compact: true),
                            const SizedBox(width: 8),
                            _buildTimeInputField(_graphVisibleMinController, 'Min', compact: true),
                          ],
                        ),
                        const SizedBox(width: 8),
                        _buildControlButton('Add Window', () => _openSecondaryWindow(null), color: AppColors.submitButton),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey[200]!),
                  ),
                  child: Padding(padding: const EdgeInsets.all(16.0), child: _buildGraph()),
                ),
              ),
              const SizedBox(height: 16),
              _buildBottomSection(),
            ],
          );
        } else {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey[200]!),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Graph Segment:',
                            style: GoogleFonts.roboto(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w500,
                              fontSize: 14, // Match TextField label size
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildTimeInputField(_graphVisibleHrController, 'Hr'),
                          const SizedBox(width: 8),
                          _buildTimeInputField(_graphVisibleMinController, 'Min'),
                        ],
                      ),
                      const SizedBox(width: 16),
                      _buildDateTimeDisplay(),
                      const SizedBox(width: 16),
                      _buildControlButton('Add Window', () => _openSecondaryWindow(null), color: AppColors.submitButton),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey[200]!),
                  ),
                  child: Padding(padding: const EdgeInsets.all(16.0), child: _buildGraph()),
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ValueListenableBuilder<String>(
          valueListenable: Global.selectedMode,
          builder: (context, mode, _) {
            final selectedMode = mode ?? 'Graph';
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: selectedMode == 'Table'
                  ? _buildLeftSection()
                  : selectedMode == 'Graph'
                  ? _buildRightSection()
                  : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: _buildLeftSection()),
                  const SizedBox(width: 16),
                  Expanded(flex: 3, child: _buildRightSection()),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
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
      port!.close();
    }
    _reconnectTimer?.cancel();
    _testDurationTimer?.cancel();
    _tableUpdateTimer?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }
}