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
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../constants/colors.dart';
import '../../constants/global.dart';
import 'package:flutter/foundation.dart';

import '../NavPages/channel.dart';
import '../Secondary_window/secondary_window.dart';
import '../homepage.dart';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class AutoStartScreen extends StatefulWidget {
  final List<dynamic> selectedChannels;
  final double endTimeHr;
  final double endTimeMin;
  final double scanTimeSec;
  const AutoStartScreen({super.key, required this.selectedChannels,required this.endTimeHr,
    required this.endTimeMin,
    required this.scanTimeSec,});

  @override
  State<AutoStartScreen> createState() => _AutoStartScreenState();
}

class _AutoStartScreenState extends State<AutoStartScreen> {
  final String portName = 'COM6';
  SerialPort? port;
  Map<String, List<Map<String, dynamic>>> dataByChannel = {};
  Map<double, Map<String, dynamic>> _bufferedData = {};
  String buffer = "";
  Widget portMessage = Text(
      "Ready to start scanning", style: GoogleFonts.roboto(fontSize: 16));
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

  @override
  void initState() {
    super.initState();
    _initPort();
    _initializeChannelConfigs();
    _startReconnectTimer();
    _scanRateSecController.text = widget.scanTimeSec.toInt().toString();
    scanIntervalSeconds = widget.scanTimeSec.toInt();
    _lastScanIntervalSeconds = scanIntervalSeconds;
    final now = DateTime.now();
    final endTimeToday = DateTime(
        now.year, now.month, now.day, widget.endTimeHr.toInt(), widget.endTimeMin.toInt());
    final endTime = now.isAfter(endTimeToday)
        ? endTimeToday.add(Duration(days: 1)) // Next day if end time passed
        : endTimeToday;
    final duration = endTime.difference(now);
    final durationHours = duration.inHours;
    final durationMinutes = duration.inMinutes % 60;
    _testDurationHrController.text = durationHours.toString();
    _testDurationMinController.text = durationMinutes.toString();

    _initPort();
    _initializeChannelConfigs();
    _startReconnectTimer();
    _startEndTimeCheck(); // Start end time check
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
      if (now.hour == endHour && now.minute == endMinute) {
        debugPrint('End time reached: $endHour:$endMinute, stopping scan and saving data');
        timer.cancel();
        if (isScanning) {
          _stopScan();
          _saveData();
          setState(() {
            portMessage = Text('End time reached, scan stopped and data saved',
                style: GoogleFonts.roboto(color: Colors.blue, fontSize: 16));
            errors.add('End time reached, scan stopped and data saved');
          });
          // Navigate back to HomePage
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomePage()),
          );
        }
      }
    });
  }

  void _initPort() {
    port = SerialPort(portName);
    debugPrint('Initialized port: $portName');
  }

  void _initializeChannelConfigs() {
    print('[SerialPortScreen] _initializeChannelConfigs called');
    channelConfigs.clear();
    print('[SerialPortScreen] _initializeChannelConfigs: channelConfigs cleared');
    channelColors.clear();
    print('[SerialPortScreen] _initializeChannelConfigs: channelColors cleared');

    // Define fallback colors in case graphLineColour is invalid
    const List<Color> fallbackColors = [
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
      print('[SerialPortScreen] _initializeChannelConfigs: Processing channelData at index $i: $channelData');
      try {
        Channel channel;
        if (channelData is Channel) {
          channel = channelData;
          print('[SerialPortScreen] _initializeChannelConfigs: channelData is Channel type');
        } else if (channelData is Map<String, dynamic>) {
          channel = Channel.fromJson(channelData);
          print('[SerialPortScreen] _initializeChannelConfigs: channelData is Map, created Channel fromJson');
        } else {
          print('[SerialPortScreen] _initializeChannelConfigs: Invalid channel data type at index $i');
          throw Exception('Invalid channel data type at index $i');
        }

        // Use startingCharacter as the channel ID
        final channelId = channel.startingCharacter;
        print('[SerialPortScreen] _initializeChannelConfigs: channelId = $channelId (from startingCharacter) for channel ${channel.channelName}');

        channelConfigs[channelId] = channel;

        // Set initial color from graphLineColour (AARRGGBB format)
        Color channelColor = Color(channel.graphLineColour);
        // Validate if color is reasonable; if not, use fallback
        if (channelColor.alpha == 0 && channelColor.red == 0 && channelColor.green == 0 && channelColor.blue == 0) {
          print('[SerialPortScreen] _initializeChannelConfigs: Invalid graphLineColour for channel $channelId, using fallback color');
          channelColor = fallbackColors[i % fallbackColors.length];
        }
        channelColors[channelId] = channelColor;

        debugPrint('[SerialPortScreen] Configured channel $channelId: ${channel.toString()} with color ${channelColor.toString()}');
      } catch (e) {
        debugPrint('[SerialPortScreen] Error configuring channel at index $i: $e');
        setState(() {
          print('[SerialPortScreen] _initializeChannelConfigs: setState due to error configuring channel');
          errors.add('Invalid channel configuration at index $i: $e');
          print('[SerialPortScreen] _initializeChannelConfigs: Added error: "Invalid channel configuration at index $i: $e"');
        });
      }
    }
    print('[SerialPortScreen] _initializeChannelConfigs: Finished loop, channelConfigs = $channelConfigs');

    if (channelConfigs.isEmpty) {
      print('[SerialPortScreen] _initializeChannelConfigs: No valid channels configured');
      setState(() {
        print('[SerialPortScreen] _initializeChannelConfigs: setState due to no valid channels');
        portMessage = Text('No valid channels configured',
            style: GoogleFonts.roboto(color: Colors.red, fontSize: 16));
        errors.add('No valid channels configured');
        print('[SerialPortScreen] _initializeChannelConfigs: Added error: "No valid channels configured"');
      });
    }
    print('[SerialPortScreen] _initializeChannelConfigs finished');
  }

  void _showColorPicker(String channel) {
    showDialog(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: Text('Select Color for Channel ${channelConfigs[channel]
                ?.channelName ?? 'Unknown'}'),
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
                child: Text('Done',
                    style: GoogleFonts.roboto(color: AppColors.submitButton)),
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
    try {
      port!.config = config;
      debugPrint(
          'Port configured: baudRate=${config.baudRate}, bits=${config.bits}');
    } catch (e) {
      debugPrint('Error configuring port: $e');
      setState(() {
        portMessage = Text('Port config error: $e',
            style: GoogleFonts.roboto(color: Colors.red, fontSize: 16));
        errors.add('Port config error: $e');
      });
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
    // Example: Update dataByChannel and send to stream
    dataByChannel[newData['Channel']] = [
      ...(dataByChannel[newData['Channel']] ?? []),
      newData,
    ];
    Global.graphDataSink.add({
      'dataByChannel': Map.from(dataByChannel),
      'channelColors': Map.from(channelColors),
      'channelConfigs': Map.from(channelConfigs),
    });
    print('[AutoStartScreen] Sent graph data update: ${dataByChannel.keys}');
  }

  void _openFloatingGraphWindow() {
    late OverlayEntry entry;
    Offset position = Offset(100, 100);

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
          portMessage = Text('Reconnected to $portName - Scanning resumed',
              style: GoogleFonts.roboto(color: Colors.green,
                  fontSize: 16,
                  fontWeight: FontWeight.w600));
          errors.add('Reconnected to $portName - Scanning resumed');
        });
        _reconnectAttempts = 0;
        // Restart the table update timer to ensure table updates
        _startTableUpdateTimer();
        // Immediately add a table row to reflect any buffered data
        _addTableRow();
      } catch (e) {
        debugPrint('Autoreconnect: Error: $e');
        setState(() {
          portMessage = Text('Reconnect error: $e',
              style: GoogleFonts.roboto(color: Colors.red, fontSize: 16));
          errors.add('Reconnect error: $e');
        });
        _reconnectAttempts++;
      }
    } else if (_reconnectAttempts >= _maxReconnectAttempts) {
      setState(() {
        portMessage =
            Text('Reconnect failed after $_maxReconnectAttempts attempts',
                style: GoogleFonts.roboto(color: Colors.red, fontSize: 16));
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
        // debugPrint('Raw data received: $decoded');
        buffer += decoded;

        String regexPattern = channelConfigs.entries.map((e) => '\\${e.value
            .startingCharacter}[0-9]*\\.[0-9]').join('|');
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
          buffer = '';
        }
      },
      onError: (error) {
        debugPrint('Stream error: $error');
        setState(() {
          portMessage = Text('Error reading data: $error',
              style: GoogleFonts.roboto(color: Colors.red, fontSize: 16));
          errors.add('Error reading data: $error');
        });
      },
      onDone: () {
        debugPrint('Stream done');
        if (isScanning) {
          setState(() {
            portMessage = Text('Port disconnected - Reconnecting...',
                style: GoogleFonts.roboto(color: Colors.orange, fontSize: 16));
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
          portMessage = Text('Scanning active on $portName',
              style: GoogleFonts.roboto(color: Colors.green,
                  fontWeight: FontWeight.w600,
                  fontSize: 16));
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
          _testDurationTimer =
              Timer(Duration(seconds: testDurationSeconds), () {
                _stopScan();
                setState(() {
                  portMessage = Text('Test duration reached, scanning stopped',
                      style: GoogleFonts.roboto(
                          color: Colors.blue, fontSize: 16));
                  errors.add('Test duration reached, scanning stopped');
                });
                debugPrint(
                    '[SERIAL_PORT] Test duration of $testDurationSeconds seconds reached, stopped scanning');
              });
        }
      } catch (e) {
        debugPrint('Error starting scan: $e');
        setState(() {
          portMessage = Text('Error starting scan: $e',
              style: GoogleFonts.roboto(color: Colors.red, fontSize: 16));
          errors.add('Error starting scan: $e');
        });
        if (e.toString().contains('busy') ||
            e.toString().contains('Access denied')) {
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
      portMessage = Text(
          'Scanning stopped manually', style: GoogleFonts.roboto(fontSize: 16));
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
          portMessage =
              Text('Scanning stopped', style: GoogleFonts.roboto(fontSize: 16));
          errors.add('Scanning stopped');
        });
      } catch (e) {
        debugPrint('Error stopping scan: $e');
        setState(() {
          portMessage = Text('Error stopping scan: $e',
              style: GoogleFonts.roboto(color: Colors.red, fontSize: 16));
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
        portMessage =
            Text('Scan cancelled', style: GoogleFonts.roboto(fontSize: 16));
        errors.add('Scan cancelled');
      });
      _initPort();
      _testDurationTimer?.cancel();
      _tableUpdateTimer?.cancel();
    } catch (e) {
      debugPrint('Error cancelling scan: $e');
      setState(() {
        portMessage = Text('Error cancelling scan: $e',
            style: GoogleFonts.roboto(color: Colors.red, fontSize: 16));
        errors.add('Error cancelling scan: $e');
      });
    }
  }

  void _startTableUpdateTimer() {
    _tableUpdateTimer?.cancel();
    if (scanIntervalSeconds < 1) {
      scanIntervalSeconds = 1;
    }
    if (scanIntervalSeconds != _lastScanIntervalSeconds) {
      _lastScanIntervalSeconds = scanIntervalSeconds;
      debugPrint(
          'Table update timer interval changed to $scanIntervalSeconds seconds');
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
    debugPrint(
        'Started table update timer with interval $scanIntervalSeconds seconds');
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

      if (segmentedDataByChannel.isNotEmpty) {
        currentGraphIndex = segmentedDataByChannel.values.first.length - 1;
      }
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
      debugPrint(
          'Invalid data length for channel $channel: $data (expected ${config
              .dataLength})');
      return;
    }

    final valueStr = data.substring(1);
    double value = double.tryParse(valueStr) ?? 0.0;
    double timestamp = now.millisecondsSinceEpoch.toDouble();

    // Buffer the data without immediately updating the UI
    _bufferedData.putIfAbsent(timestamp, () => {});
    _bufferedData[timestamp]![channel] = {
      'Value': value,
      'Time': "${now.hour}:${now.minute.toString().padLeft(2, '0')}:${now.second
          .toString().padLeft(2, '0')}",
      'Date': "${now.day}/${now.month}/${now.year}",
      'Data': data,
      'Timestamp': timestamp,
      'Channel': channel,
    };

    // debugPrint('[SERIAL_PORT] Buffered data for channel $channel at timestamp $timestamp: $value');
  }

  void _segmentData(Map<String, dynamic> newData) {
    int graphVisibleSeconds = _calculateDurationInSeconds(
        '0', _graphVisibleHrController.text, _graphVisibleMinController.text,
        '0');
    if (graphVisibleSeconds <= 0) {
      debugPrint(
          '[SEGMENT_DATA] Invalid graph visible duration: $graphVisibleSeconds seconds');
      return;
    }

    double newTimestamp = newData['Timestamp'] as double;
    channelConfigs.keys.forEach((channel) {
      segmentedDataByChannel.putIfAbsent(channel, () => []);

      if (segmentedDataByChannel[channel]!.isEmpty) {
        segmentedDataByChannel[channel]!.add([
          {
            ...newData,
            'Value': newData['Value_$channel'] ?? 0.0,
            'Channel': channel,
          }
        ]);
        // debugPrint('[SERIAL_PORT] Created new segment for channel $channel at timestamp $newTimestamp');
        return;
      }

      List<Map<String, dynamic>> lastSegment = segmentedDataByChannel[channel]!
          .last;
      double lastSegmentStartTime = lastSegment.first['Timestamp'] as double;

      if ((newTimestamp - lastSegmentStartTime) / 1000 >= graphVisibleSeconds) {
        segmentedDataByChannel[channel]!.add([
          {
            ...newData,
            'Value': newData['Value_$channel'] ?? 0.0,
            'Channel': channel,
          }
        ]);
        debugPrint(
            '[SERIAL_PORT] Added new segment for channel $channel at timestamp $newTimestamp');
      } else {
        segmentedDataByChannel[channel]!.last.add({
          ...newData,
          'Value': newData['Value_$channel'] ?? 0.0,
          'Channel': channel,
        });
        // debugPrint('[SERIAL_PORT] Added data to existing segment for channel $channel at timestamp $newTimestamp');
      }
    });

    if (segmentedDataByChannel.isNotEmpty) {
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
    }
  }



  Future<void> _saveData() async {
    try {
      debugPrint('Saving data to databases started...');

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
      final databaseFactory = databaseFactoryFfi;

      // Get the application documents directory
      final appDocumentsDir = await getApplicationDocumentsDirectory();

      // Create a dedicated folder for new database files
      final dataFolder = Directory(path.join(appDocumentsDir.path, 'CountronicsData'));
      if (!await dataFolder.exists()) {
        await dataFolder.create(recursive: true);
      }
      debugPrint('Data folder: ${dataFolder.path}');

      // Generate a datetime-based filename for the new database
      final now = DateTime.now();
      final dateTimeString = DateFormat('yyyyMMddHHmmss').format(now);
      final newDbPath = path.join(dataFolder.path, 'serial_port_data_$dateTimeString.db');
      debugPrint('New database path: $newDbPath');

      // Main database path
      final databasesPath = await getDatabasesPath();
      final mainDbPath = path.join(databasesPath, 'Countronics.db');
      debugPrint('Main database path: $mainDbPath');

      //Password
      const String dbPassword = 'Countronics2025';

      // Open the new database
      final newDatabase = await databaseFactory.openDatabase(
        newDbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('PRAGMA key = "$dbPassword"');
            await db.execute('''
            CREATE TABLE IF NOT EXISTS Test (
              RecNo REAL PRIMARY KEY,
              FName TEXT,
              OperatorName TEXT,
              TDate TEXT,
              TTime TEXT,
              ScanningRate REAL,
              ScanningRateHH REAL,
              ScanningRateMM REAL,
              ScanningRateSS REAL,
              TestDurationDD REAL,
              TestDurationHH REAL,
              TestDurationMM REAL,
              GraphVisibleArea REAL,
              BaseLine REAL,
              FullScale REAL,
              Descrip TEXT,
              AbsorptionPer REAL,
              NOR REAL,
              FLName TEXT,
              XAxis TEXT,
              XAxisRecNo REAL,
              XAxisUnit TEXT,
              XAxisCode REAL,
              TotalChannel INTEGER,
              MaxYAxis REAL,
              MinYAxis REAL,
              DBName TEXT
            )
            ''');
            await db.execute('''
            CREATE TABLE IF NOT EXISTS Test1 (
              RecNo REAL,
              SNo REAL,
              SlNo REAL,
              ChangeTime TEXT,
              AbsDate TEXT,
              AbsTime TEXT,
              AbsDateTime TEXT,
              Shown TEXT,
              AbsAvg REAL,
              ${List.generate(50, (i) => 'AbsPer${i + 1} REAL').join(', ')}
            )
            ''');
            await db.execute('''
            CREATE TABLE IF NOT EXISTS Test2 (
              RecNo REAL PRIMARY KEY,
              ${List.generate(50, (i) => 'ChannelName${i + 1} TEXT').join(', ')}
            )
            ''');
          },
          onOpen: (db) async {
            // Ensure the database is opened with the correct key
            await db.execute('PRAGMA key = "$dbPassword"');
          },
        ),
      );

      // Open the main database
      final mainDatabase = await databaseFactory.openDatabase(
        mainDbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('PRAGMA key = "$dbPassword"');
            await db.execute('''
            CREATE TABLE IF NOT EXISTS Test (
              RecNo REAL PRIMARY KEY,
              FName TEXT,
              OperatorName TEXT,
              TDate TEXT,
              TTime TEXT,
              ScanningRate REAL,
              ScanningRateHH REAL,
              ScanningRateMM REAL,
              ScanningRateSS REAL,
              TestDurationDD REAL,
              TestDurationHH REAL,
              TestDurationMM REAL,
              GraphVisibleArea REAL,
              BaseLine REAL,
              FullScale REAL,
              Descrip TEXT,
              AbsorptionPer REAL,
              NOR REAL,
              FLName TEXT,
              XAxis TEXT,
              XAxisRecNo REAL,
              XAxisUnit TEXT,
              XAxisCode REAL,
              TotalChannel INTEGER,
              MaxYAxis REAL,
              MinYAxis REAL,
              DBName TEXT
            )
            ''');
          },
          onOpen: (db) async {
            // Ensure the database is opened with the correct key
            await db.execute('PRAGMA key = "$dbPassword"');
          },
        ),
      );

      SharedPreferences prefs = await SharedPreferences.getInstance();
      int recNo = prefs.getInt('recNo') ?? 5;
      debugPrint('Current record number: $recNo');

      final testPayload = _prepareTestPayload(recNo, newDbPath);
      final test1Payload = _prepareTest1Payload(recNo);
      final test2Payload = _prepareTest2Payload(recNo);

      debugPrint('Test payload: $testPayload');
      debugPrint('Test1 payload: $test1Payload');
      debugPrint('Test2 payload: $test2Payload');

      // Insert into main database (Test table only)
      await mainDatabase.insert(
        'Test',
        testPayload,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint('Inserted into main database Test table: $testPayload');

      // Insert into new database (Test, Test1, Test2 tables)
      await newDatabase.insert(
        'Test',
        testPayload,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint('Inserted into new database Test table: $testPayload');

      for (var entry in test1Payload) {
        await newDatabase.insert(
          'Test1',
          entry,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      debugPrint('Inserted ${test1Payload.length} entries into new database Test1 table');

      await newDatabase.insert(
        'Test2',
        test2Payload,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint('Inserted into new database Test2 table: $test2Payload');

      await prefs.setInt('recNo', recNo + 1);
      debugPrint('Record number updated to: ${recNo + 1}');

      await newDatabase.close();
      await mainDatabase.close();

      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Data saved successfully to databases'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      Navigator.of(context).pop();
      debugPrint('Error saving data to databases: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving data: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Map<String, dynamic> _prepareTestPayload(int recNo, String newDbPath) {
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
      "DBName": path.basename(newDbPath), // Store the new database filename
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

    debugPrint('[SERIAL_PORT] Prepared Test1 payload with ${payload.length} entries');
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
    if (currentGraphIndex > 0) {
      setState(() => currentGraphIndex--);
      debugPrint(
          '[SERIAL_PORT] Navigated to previous graph segment: $currentGraphIndex');
    }
  }

  void _showNextGraph() {
    if (currentGraphIndex <
        (segmentedDataByChannel.values.firstOrNull?.length ?? 1) - 1) {
      setState(() => currentGraphIndex++);
      debugPrint(
          '[SERIAL_PORT] Navigated to next graph segment: $currentGraphIndex');
    }
  }

  Map<String, List<Map<String, dynamic>>> get _currentGraphDataByChannel {
    Map<String, List<Map<String, dynamic>>> currentData = {};
    dataByChannel.forEach((channel, data) {
      if (segmentedDataByChannel[channel] != null &&
          currentGraphIndex < segmentedDataByChannel[channel]!.length) {
        currentData[channel] =
        segmentedDataByChannel[channel]![currentGraphIndex];
      } else {
        currentData[channel] = data;
      }
    });
    return currentData;
  }

  Widget _buildGraphNavigation() {
    if (segmentedDataByChannel.isEmpty ||
        segmentedDataByChannel.values.first.length <= 1)
      return const SizedBox();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
              icon: Icon(Icons.chevron_left, color: AppColors.textPrimary),
              onPressed: _showPreviousGraph),
          Text('Segment ${currentGraphIndex + 1}/${segmentedDataByChannel.values
              .first.length}',
              style: GoogleFonts.roboto(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
          IconButton(
              icon: Icon(Icons.chevron_right, color: AppColors.textPrimary),
              onPressed: _showNextGraph),
        ],
      ),
    );
  }

  Widget _buildGraph() {
    print('[SerialPortScreen] _buildGraph called.');
    if (_currentGraphDataByChannel.isEmpty ||
        _currentGraphDataByChannel.values.every((data) => data.isEmpty)) {
      print('[SerialPortScreen] _buildGraph: Waiting for channel data or current graph data is empty.');
      return Center(
        child: Text(
          'Waiting for channel data...',
          style: GoogleFonts.roboto(color: Colors.grey[600], fontSize: 18),
        ),
      );
    }
    print('[SerialPortScreen] _buildGraph: Preparing to build graph with ${_currentGraphDataByChannel.length} channels in current view.');

    List<LineChartBarData> lineBarsData = [];
    double minX = double.infinity;
    double maxX = -double.infinity;
    double minY = double.infinity;
    double maxY = -double.infinity;
    Set<double> uniqueTimestamps = {};

    int segmentHours = int.tryParse(_graphVisibleHrController.text) ?? 0;
    int segmentMinutes = int.tryParse(_graphVisibleMinController.text) ?? 60;
    double segmentSeconds = (segmentHours * 3600) + (segmentMinutes * 60);
    double segmentDurationMs = segmentSeconds * 1000;
    print('[SerialPortScreen] _buildGraph: segmentDurationMs = $segmentDurationMs');

    final channelsToPlot = _selectedGraphChannel != null ? [_selectedGraphChannel!] : channelConfigs.keys.toList();
    print('[SerialPortScreen] _buildGraph: Channels to plot: $channelsToPlot. Selected graph channel: $_selectedGraphChannel');

    for (var channel in channelsToPlot) {
      print('[SerialPortScreen] _buildGraph: Processing channel "$channel" for graph line.');
      if (!channelConfigs.containsKey(channel) || !channelColors.containsKey(channel)) {
        debugPrint('[SerialPortScreen] Skipping channel $channel: Missing configuration or color');
        continue;
      }

      final config = channelConfigs[channel]!;
      final defaultColor = channelColors[channel]!;
      final alarmColor = Color(config.targetAlarmColour);
      final channelData = _currentGraphDataByChannel[channel] ?? [];
      print('[SerialPortScreen] _buildGraph: Channel "$channel" has ${channelData.length} data points in current view.');

      if (channelData.isEmpty) {
        debugPrint('[SerialPortScreen] No data available for channel $channel');
        continue;
      }

      double segmentStartTimeMs = channelData.isNotEmpty
          ? (channelData.first['Timestamp'] as num?)?.toDouble() ?? DateTime.now().millisecondsSinceEpoch.toDouble()
          : DateTime.now().millisecondsSinceEpoch.toDouble();
      double segmentEndTimeMs = segmentStartTimeMs + segmentDurationMs;
      print('[SerialPortScreen] _buildGraph: For channel "$channel", segmentStartTimeMs: $segmentStartTimeMs, segmentEndTimeMs: $segmentEndTimeMs');

      // Split data into segments based on alarm thresholds
      List<FlSpot> normalSpots = [];
      List<FlSpot> alarmSpots = [];

      for (var d in channelData) {
        double timestamp = (d['Timestamp'] as num?)?.toDouble() ?? 0.0;
        double value = (d['Value'] as num?)?.toDouble() ?? 0.0;
        if (!timestamp.isFinite || !value.isFinite || timestamp < segmentStartTimeMs || timestamp >= segmentEndTimeMs) {
          continue;
        }

        uniqueTimestamps.add(timestamp);
        FlSpot spot = FlSpot(timestamp, value);
        if (value > config.targetAlarmMax || value < config.targetAlarmMin) {
          alarmSpots.add(spot);
        } else {
          normalSpots.add(spot);
        }
      }

      // Add normal line
      if (normalSpots.isNotEmpty) {
        lineBarsData.add(
          LineChartBarData(
            spots: normalSpots,
            isCurved: true,
            color: defaultColor,
            barWidth: 3,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ),
        );
        print('[SerialPortScreen] _buildGraph: Added normal LineChartBarData for channel "$channel" with ${normalSpots.length} spots.');
      }

      // Add alarm line
      if (alarmSpots.isNotEmpty) {
        lineBarsData.add(
          LineChartBarData(
            spots: alarmSpots,
            isCurved: true,
            color: alarmColor,
            barWidth: 3,
            dotData: FlDotData(show: true, getDotPainter: (spot, percent, bar, index) {
              return FlDotCirclePainter(
                radius: 6,
                color: alarmColor,
                strokeWidth: 1,
                strokeColor: Colors.white,
              );
            }),
            belowBarData: BarAreaData(show: false),
          ),
        );
        print('[SerialPortScreen] _buildGraph: Added alarm LineChartBarData for channel "$channel" with ${alarmSpots.length} spots.');
      }

      // Update bounds
      final allSpots = [...normalSpots, ...alarmSpots];
      if (allSpots.isNotEmpty) {
        final xValues = allSpots.map((s) => s.x).where((x) => x.isFinite);
        final yValues = allSpots.map((s) => s.y).where((y) => y.isFinite);
        if (xValues.isNotEmpty && yValues.isNotEmpty) {
          minX = min(minX, xValues.reduce(min));
          maxX = max(maxX, xValues.reduce(max));
          minY = min(minY, yValues.reduce(min));
          maxY = max(maxY, yValues.reduce(max));
          print('[SerialPortScreen] _buildGraph: Updated graph bounds: minX=$minX, maxX=$maxX, minY=$minY, maxY=$maxY');
        }
      }
    }

    if (lineBarsData.isEmpty || minX == double.infinity || maxX == -double.infinity) {
      print('[SerialPortScreen] _buildGraph: No lineBarsData or invalid bounds, setting default graph range.');
      minX = DateTime.now().millisecondsSinceEpoch.toDouble() - segmentDurationMs;
      maxX = DateTime.now().millisecondsSinceEpoch.toDouble();
      minY = 0.0;
      maxY = 100.0;
    } else {
      double yRange = maxY - minY;
      print('[SerialPortScreen] _buildGraph: yRange = $yRange. Current minY=$minY, maxY=$maxY');
      if (yRange == 0) {
        maxY += 10;
        minY -= (minY > 0 ? 1 : 0);
      } else {
        maxY += yRange * 0.1;
        minY -= yRange * 0.05;
      }
      if (minY < 0 && minY != 0) minY = 0;
      print('[SerialPortScreen] _buildGraph: Adjusted Y-axis range: minY=$minY, maxY=$maxY');
    }

    List<double> sortedTimestamps = uniqueTimestamps.toList()..sort();
    print('[SerialPortScreen] _buildGraph: Unique sorted timestamps for X-axis labels: ${sortedTimestamps.length} items.');

    double intervalY = (maxY - minY) / 5;
    if (intervalY == 0 || !intervalY.isFinite) {
      intervalY = (maxY > 0) ? maxY / 5 : 1;
      print('[SerialPortScreen] _buildGraph: intervalY was zero or non-finite, adjusted to $intervalY');
    }
    print('[SerialPortScreen] _buildGraph: Calculated intervalY: $intervalY');

    Widget legend = Wrap(
      spacing: 16,
      runSpacing: 8,
      children: channelsToPlot
          .where((channel) => channelConfigs.containsKey(channel) && channelColors.containsKey(channel))
          .map((channel) {
        print('[SerialPortScreen] _buildGraph: Building legend item for channel "$channel"');
        final color = channelColors[channel];
        final channelName = channelConfigs[channel]?.channelName ?? 'Unknown';
        return GestureDetector(
          onTap: () {
            print('[SerialPortScreen] _buildGraph: Legend item tapped for channel "$channel", showing color picker.');
            _showColorPicker(channel);
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 12, height: 12, color: color),
              const SizedBox(width: 4),
              Text('Channel $channelName', style: GoogleFonts.roboto(
                  color: AppColors.textPrimary, fontSize: 12)),
            ],
          ),
        );
      }).toList(),
    );
    print('[SerialPortScreen] _buildGraph: Legend built.');

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
                    getTooltipItems: (touchedSpots) {
                      print('[SerialPortScreen] _buildGraph (getTooltipItems): Touched spots: $touchedSpots');
                      return touchedSpots.map((spot) {
                        if (!spot.x.isFinite || !spot.y.isFinite) {
                          print('[SerialPortScreen] _buildGraph (getTooltipItems): Invalid spot data, returning null tooltip.');
                          return null;
                        }
                        if (spot.barIndex < 0 || spot.barIndex >= lineBarsData.length) {
                          print('[SerialPortScreen] _buildGraph (getTooltipItems): spot.barIndex ${spot.barIndex} out of bounds for lineBarsData (length ${lineBarsData.length}).');
                          return null;
                        }
                        // Find the channel by checking which LineChartBarData the spot belongs to
                        String? channel;
                        for (var ch in channelsToPlot) {
                          if (lineBarsData[spot.barIndex].color == channelColors[ch] ||
                              lineBarsData[spot.barIndex].color == Color(channelConfigs[ch]?.targetAlarmColour ?? 0)) {
                            channel = ch;
                            break;
                          }
                        }
                        if (channel == null) {
                          print('[SerialPortScreen] _buildGraph (getTooltipItems): Could not determine channel for barIndex ${spot.barIndex}.');
                          return null;
                        }
                        final channelName = channelConfigs[channel]?.channelName ?? 'Unknown';
                        final unit = channelConfigs[channel]?.unit ?? '';
                        print('[SerialPortScreen] _buildGraph (getTooltipItems): Creating tooltip for channel $channelName, spot: $spot');
                        return LineTooltipItem(
                          'Channel $channelName\n${spot.y.toStringAsFixed(2)} $unit\n${DateTime.fromMillisecondsSinceEpoch(spot.x.toInt()).toString().split('.')[0]}',
                          GoogleFonts.roboto(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 12),
                        );
                      }).where((item) => item != null).toList().cast<LineTooltipItem>();
                    },
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: intervalY,
                  getDrawingVerticalLine: (value) {
                    print('[SerialPortScreen] _buildGraph (getDrawingVerticalLine): Checking value $value for vertical line.');
                    return sortedTimestamps.contains(value)
                        ? FlLine(color: Colors.grey.withOpacity(0.3), strokeWidth: 1)
                        : FlLine(color: Colors.transparent);
                  },
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
                      getTitlesWidget: (value, meta) {
                        print('[SerialPortScreen] _buildGraph (leftTitles getTitlesWidget): Value: $value, Meta: $meta');
                        return Text(
                          value.isFinite ? value.toStringAsFixed(2) : '',
                          style: GoogleFonts.roboto(color: AppColors.textPrimary, fontSize: 12),
                        );
                      },
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
                        print('[SerialPortScreen] _buildGraph (bottomTitles getTitlesWidget): Value: $value, Meta: $meta');
                        if (!sortedTimestamps.contains(value)) {
                          print('[SerialPortScreen] _buildGraph (bottomTitles getTitlesWidget): Value $value not in sortedTimestamps, returning SizedBox.');
                          return const SizedBox();
                        }
                        final dateTime = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}',
                            style: GoogleFonts.roboto(
                                color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
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
                clipData: FlClipData(top: false, bottom: true, left: true, right: true),
                extraLinesData: ExtraLinesData(extraLinesOnTop: true),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<TableRow> _buildTableRows() {
    List<TableRow> tableRows = [];
    final headers = ['Time', ...channelConfigs.keys.toList()
      ..sort()
    ];
    final columnCount = headers.length;
    const int maxRows = 100;

    if (dataByChannel.isEmpty) {
      tableRows.add(
        TableRow(
          children: List.generate(
            columnCount,
                (index) =>
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    index == 0 ? 'No data available' : '',
                    style: GoogleFonts.roboto(
                        color: AppColors.textPrimary, fontSize: 14),
                  ),
                ),
          ),
        ),
      );
      return tableRows;
    }

    final timestamps = dataByChannel.values.firstOrNull?.map((
        d) => d['Timestamp'] as double).toSet().toList() ?? [];
    timestamps.sort();
    final startIndex = timestamps.length > maxRows
        ? timestamps.length - maxRows
        : 0;

    tableRows.add(
      TableRow(
        decoration: BoxDecoration(color: Colors.grey[200]),
        children: headers.map((header) {
          return Padding(
            padding: const EdgeInsets.all(12.0),
            child: Text(
              header == 'Time' ? 'Time' : channelConfigs[header]?.channelName ??
                  'Unknown',
              style: GoogleFonts.roboto(fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  fontSize: 14),
            ),
          );
        }).toList(),
      ),
    );

    for (int i = startIndex; i < timestamps.length; i++) {
      final timestamp = timestamps[i];
      final data = dataByChannel[headers[1]]?.firstWhere((
          d) => d['Timestamp'] == timestamp, orElse: () => {}) ?? {};
      final time = data['Time'] as String? ?? '';

      final rowCells = headers.map((header) {
        if (header == 'Time') {
          return Padding(
            padding: const EdgeInsets.all(12.0),
            child: Text(
              time,
              style: GoogleFonts.roboto(
                color: i == timestamps.length - 1 ? Colors.green : AppColors
                    .textPrimary,
                fontWeight: i == timestamps.length - 1
                    ? FontWeight.bold
                    : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          );
        }
        final channel = header;
        final channelData = dataByChannel[channel]?.firstWhere((
            d) => d['Timestamp'] == timestamp, orElse: () => {}) ?? {};
        final config = channelConfigs[channel]!;
        final value = channelData['Value'] != null ? '${channelData['Value']
            .toStringAsFixed(config.decimalPlaces)}${config.unit}' : '';
        return Padding(
          padding: const EdgeInsets.all(12.0),
          child: Text(
            value,
            style: GoogleFonts.roboto(
              color: i == timestamps.length - 1 && value.isNotEmpty ? Colors
                  .green : AppColors.textPrimary,
              fontWeight: i == timestamps.length - 1 && value.isNotEmpty
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
              color: i % 2 == 0 ? Colors.white : Colors.grey[50]),
          children: rowCells,
        ),
      );
    }

    // debugPrint('[SERIAL_PORT] Built ${tableRows.length} table rows (limited to last $maxRows)');
    return tableRows;
  }

  Widget _buildDataTable() {
    // debugPrint('dataByChannel: ${dataByChannel.length} channels, ${dataByChannel.values.firstOrNull?.length ?? 0} entries');
    return Container(
      height: 400,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!)),
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
                  onPressed: () => _tableScrollController.animateTo(
                      0, duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut),
                ),
                IconButton(
                  icon: Icon(
                      Icons.arrow_downward, color: AppColors.textPrimary),
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

  Widget _buildTimeInputField(TextEditingController controller, String label,
      {bool compact = false, double width = 120}) {
    return SizedBox(
      width: compact ? 60 : width,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.roboto(
            color: AppColors.textPrimary,
            fontSize: compact ? 12 : 14,
            fontWeight: FontWeight.w300,
          ),
          filled: true,
          fillColor: Colors.grey[50],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 20),
        ),
        style: GoogleFonts.roboto(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w400,
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

  Widget _buildControlButton(String text, VoidCallback? onPressed,
      {Color? color, bool? disabled}) {
    return ElevatedButton(
      onPressed: disabled == true ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color ?? AppColors.submitButton,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(text, style: GoogleFonts.roboto(
          color: Colors.white, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildStyledAddButton() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[600]!, Colors.blue[400]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
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

  Widget _buildLatestDataDisplay() {
    if (dataByChannel.isEmpty) return const SizedBox();
    final latestData = dataByChannel.entries.where((e) => e.value.isNotEmpty)
        .map((e) => e.value.last)
        .reduce((a, b) => a['Timestamp'] > b['Timestamp'] ? a : b);
    final config = channelConfigs[latestData['Channel']]!;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8)),
      child: Text(
        'Latest: Channel ${config
            .channelName} - ${latestData['Time']} ${latestData['Date']} - ${latestData['Value']
            .toStringAsFixed(config.decimalPlaces)}${config.unit}',
        style: GoogleFonts.roboto(
            color: AppColors.textPrimary, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildFullInputSection() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey[200]!)),
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
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none),
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
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none),
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
                      Text('Scan Rate:', style: GoogleFonts.roboto(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500)),
                      const SizedBox(width: 8),
                      _buildTimeInputField(
                          _scanRateHrController, 'Hr', width: 60),
                      const SizedBox(width: 8),
                      _buildTimeInputField(
                          _scanRateMinController, 'Min', width: 60),
                      const SizedBox(width: 8),
                      _buildTimeInputField(
                          _scanRateSecController, 'Sec', width: 60),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Test Duration:', style: GoogleFonts.roboto(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500)),
                      const SizedBox(width: 8),
                      _buildTimeInputField(
                          _testDurationDayController, 'Day', width: 60),
                      const SizedBox(width: 8),
                      _buildTimeInputField(
                          _testDurationHrController, 'Hr', width: 60),
                      const SizedBox(width: 8),
                      _buildTimeInputField(
                          _testDurationMinController, 'Min', width: 60),
                      const SizedBox(width: 8),
                      _buildTimeInputField(
                          _testDurationSecController, 'Sec', width: 60),
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
        color: isScanning ? AppColors.submitButton.withOpacity(0.1) : Colors
            .grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isScanning ? AppColors.submitButton.withOpacity(0.5) : Colors
                .grey[200]!),
      ),
      child: Column(
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              _buildControlButton(
                  'Start Scan', _startScan, disabled: isScanning),
              _buildControlButton(
                  'Stop Scan', _stopScan, color: Colors.orange[700],
                  disabled: !isScanning),
              _buildControlButton(
                  'Cancel Scan', _cancelScan, color: AppColors.resetButton),
              _buildControlButton(
                  'Save Data', _saveData, color: Colors.green[700]),
              _buildControlButton(
                  'Multi File', () {}, color: Colors.purple[700]),
              _buildControlButton('Exit', () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (context) => const HomePage()));
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
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.submitButton))),
                ),
              portMessage,
              if (errors.isNotEmpty && !errors.last.contains('Scanning'))
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Text(errors.last,
                      style: GoogleFonts.roboto(
                          color: errors.last.contains('Error')
                              ? Colors.red
                              : Colors.green, fontSize: 16)),
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
        if (Global.selectedMode.value == 'Table' ||
            Global.selectedMode.value == 'Combined')
          Expanded(
            child: Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey[200]!)),
              child: Padding(padding: const EdgeInsets.all(16.0),
                  child: _buildDataTable()),
            ),
          ),
        if (Global.selectedMode.value == 'Table' ||
            Global.selectedMode.value == 'Combined') const SizedBox(height: 8),
        if (Global.selectedMode.value == 'Table' ||
            Global.selectedMode.value == 'Combined') _buildLatestDataDisplay(),
        if (Global.selectedMode.value == 'Table' ||
            Global.selectedMode.value == 'Combined') const SizedBox(height: 16),
        if (Global.selectedMode.value == 'Table' ||
            Global.selectedMode.value == 'Combined') _buildBottomSection(),
      ],
    );
  }

  Widget _buildRightSection() {
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
                color: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey[200]!)),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.start,
                      children: [
                        SizedBox(
                          width: isCompact ? 100 : 120,
                          child: TextField(
                            controller: _fileNameController,
                            decoration: InputDecoration(
                              labelText: 'File Name',
                              filled: true,
                              fillColor: Colors.grey[50],
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none),
                            ),
                            style: GoogleFonts.roboto(
                                color: AppColors.textPrimary),
                          ),
                        ),
                        SizedBox(
                          width: isCompact ? 100 : 120,
                          child: TextField(
                            controller: _operatorController,
                            decoration: InputDecoration(
                              labelText: 'Operator',
                              filled: true,
                              fillColor: Colors.grey[50],
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none),
                            ),
                            style: GoogleFonts.roboto(
                                color: AppColors.textPrimary),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Scan Rate:',
                                style: GoogleFonts.roboto(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(width: 4),
                            _buildTimeInputField(
                                _scanRateHrController, 'Hr', compact: true),
                            const SizedBox(width: 4),
                            _buildTimeInputField(
                                _scanRateMinController, 'Min', compact: true),
                            const SizedBox(width: 4),
                            _buildTimeInputField(
                                _scanRateSecController, 'Sec', compact: true),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Test Duration:',
                                style: GoogleFonts.roboto(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(width: 4),
                            _buildTimeInputField(
                                _testDurationDayController, 'Day',
                                compact: true),
                            const SizedBox(width: 4),
                            _buildTimeInputField(
                                _testDurationHrController, 'Hr', compact: true),
                            const SizedBox(width: 4),
                            _buildTimeInputField(
                                _testDurationMinController, 'Min',
                                compact: true),
                            const SizedBox(width: 4),
                            _buildTimeInputField(
                                _testDurationSecController, 'Sec',
                                compact: true),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Segment:',
                                style: GoogleFonts.roboto(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(width: 4),
                            _buildTimeInputField(
                                _graphVisibleHrController, 'Hr', compact: true),
                            const SizedBox(width: 4),
                            _buildTimeInputField(
                                _graphVisibleMinController, 'Min',
                                compact: true),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12,
                              vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.grey.withOpacity(0.1),
                                  blurRadius: 5)
                            ],
                          ),
                          child: DropdownButton<String?>(
                            value: _selectedGraphChannel,
                            hint: Text('All Channels',
                                style: GoogleFonts.roboto(
                                    color: AppColors.textPrimary)),
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
                                        color: AppColors.textPrimary)),
                              ),
                              ...channelConfigs.keys.map(
                                      (channel) =>
                                      DropdownMenuItem<String>(
                                        value: channel,
                                        child: Text(
                                          'Channel ${channelConfigs[channel]!
                                              .channelName}',
                                          style: GoogleFonts.roboto(
                                              color: AppColors.textPrimary),
                                        ),
                                      )),
                            ],
                            underline: Container(),
                            icon: const Icon(Icons.arrow_drop_down,
                                color: AppColors.textPrimary),
                          ),
                        ),
                        _buildStyledAddButton(),
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
                      side: BorderSide(color: Colors.grey[200]!)),
                  child: Padding(
                      padding: EdgeInsets.all(isCompact ? 8.0 : 16.0),
                      child: _buildGraph()),
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
                    side: BorderSide(color: Colors.grey[200]!)),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Graph Segment:',
                              style: GoogleFonts.roboto(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w500)),
                          const SizedBox(width: 8),
                          _buildTimeInputField(_graphVisibleHrController, 'Hr'),
                          const SizedBox(width: 8),
                          _buildTimeInputField(
                              _graphVisibleMinController, 'Min'),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.grey.withOpacity(0.1),
                                  blurRadius: 5)
                            ]),
                        child: DropdownButton<String?>(
                          value: _selectedGraphChannel,
                          hint: Text('All Channels',
                              style: GoogleFonts.roboto(
                                  color: AppColors.textPrimary)),
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
                                        color: AppColors.textPrimary))),
                            ...channelConfigs.keys.map((channel) =>
                                DropdownMenuItem<String>(
                                  value: channel,
                                  child: Text(
                                      'Channel ${channelConfigs[channel]!
                                          .channelName}',
                                      style: GoogleFonts.roboto(
                                          color: AppColors.textPrimary)),
                                )),
                          ],
                          underline: Container(),
                          icon: const Icon(Icons.arrow_drop_down,
                              color: AppColors.textPrimary),
                        ),
                      ),
                      _buildStyledAddButton(),
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
                      side: BorderSide(color: Colors.grey[200]!)),
                  child: Padding(
                      padding: EdgeInsets.all(isCompact ? 8.0 : 16.0),
                      child: _buildGraph()),
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
      port!.close();
    }
    _reconnectTimer?.cancel();
    _testDurationTimer?.cancel();
    _tableUpdateTimer?.cancel();
    _debounceTimer?.cancel();
    _endTimeTimer?.cancel();
    super.dispose();
  }
}