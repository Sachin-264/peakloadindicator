import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import '../../constants/colors.dart';
import 'channel.dart';
import 'package:flutter/foundation.dart';

final serialPortProvider = StateNotifierProvider<SerialPortNotifier, SerialPortState>((ref) => SerialPortNotifier());

class SerialPortState {
  final String portName;
  final SerialPort? port;
  final Map<String, List<Map<String, dynamic>>> dataByChannel;
  final Map<double, Map<String, dynamic>> bufferedData;
  final String buffer;
  final Widget portMessage;
  final List<String> errors;
  final Map<String, Color> channelColors;
  final bool isScanning;
  final bool isCancelled;
  final bool isManuallyStopped;
  final SerialPortReader? reader;
  final StreamSubscription<Uint8List>? readerSubscription;
  final DateTime? lastDataTime;
  final int scanIntervalSeconds;
  final int currentGraphIndex;
  final Map<String, List<List<Map<String, dynamic>>>> segmentedDataByChannel;
  final String yAxisType;
  final String? selectedGraphChannel;
  final Timer? reconnectTimer;
  final int reconnectAttempts;
  final Map<String, Channel> channelConfigs;
  final TextEditingController fileNameController;
  final TextEditingController operatorController;
  final TextEditingController scanRateHrController;
  final TextEditingController scanRateMinController;
  final TextEditingController scanRateSecController;
  final TextEditingController testDurationDayController;
  final TextEditingController testDurationHrController;
  final TextEditingController testDurationMinController;
  final TextEditingController testDurationSecController;
  final TextEditingController graphVisibleHrController;
  final TextEditingController graphVisibleMinController;

  SerialPortState({
    required this.portName,
    this.port,
    this.dataByChannel = const {},
    this.bufferedData = const {},
    this.buffer = '',
    required this.portMessage,
    this.errors = const [],
    this.channelColors = const {},
    this.isScanning = false,
    this.isCancelled = false,
    this.isManuallyStopped = false,
    this.reader,
    this.readerSubscription,
    this.lastDataTime,
    this.scanIntervalSeconds = 1,
    this.currentGraphIndex = 0,
    this.segmentedDataByChannel = const {},
    this.yAxisType = 'Load',
    this.selectedGraphChannel,
    this.reconnectTimer,
    this.reconnectAttempts = 0,
    this.channelConfigs = const {},
    required this.fileNameController,
    required this.operatorController,
    required this.scanRateHrController,
    required this.scanRateMinController,
    required this.scanRateSecController,
    required this.testDurationDayController,
    required this.testDurationHrController,
    required this.testDurationMinController,
    required this.testDurationSecController,
    required this.graphVisibleHrController,
    required this.graphVisibleMinController,
  });

  Map<String, List<Map<String, dynamic>>> get currentGraphDataByChannel {
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

  SerialPortState copyWith({
    String? portName,
    SerialPort? port,
    Map<String, List<Map<String, dynamic>>>? dataByChannel,
    Map<double, Map<String, dynamic>>? bufferedData,
    String? buffer,
    Widget? portMessage,
    List<String>? errors,
    Map<String, Color>? channelColors,
    bool? isScanning,
    bool? isCancelled,
    bool? isManuallyStopped,
    SerialPortReader? reader,
    StreamSubscription<Uint8List>? readerSubscription,
    DateTime? lastDataTime,
    int? scanIntervalSeconds,
    int? currentGraphIndex,
    Map<String, List<List<Map<String, dynamic>>>>? segmentedDataByChannel,
    String? yAxisType,
    String? selectedGraphChannel,
    Timer? reconnectTimer,
    int? reconnectAttempts,
    Map<String, Channel>? channelConfigs,
    TextEditingController? fileNameController,
    TextEditingController? operatorController,
    TextEditingController? scanRateHrController,
    TextEditingController? scanRateMinController,
    TextEditingController? scanRateSecController,
    TextEditingController? testDurationDayController,
    TextEditingController? testDurationHrController,
    TextEditingController? testDurationMinController,
    TextEditingController? testDurationSecController,
    TextEditingController? graphVisibleHrController,
    TextEditingController? graphVisibleMinController,
  }) {
    return SerialPortState(
      portName: portName ?? this.portName,
      port: port ?? this.port,
      dataByChannel: dataByChannel ?? this.dataByChannel,
      bufferedData: bufferedData ?? this.bufferedData,
      buffer: buffer ?? this.buffer,
      portMessage: portMessage ?? this.portMessage,
      errors: errors ?? this.errors,
      channelColors: channelColors ?? this.channelColors,
      isScanning: isScanning ?? this.isScanning,
      isCancelled: isCancelled ?? this.isCancelled,
      isManuallyStopped: isManuallyStopped ?? this.isManuallyStopped,
      reader: reader ?? this.reader,
      readerSubscription: readerSubscription ?? this.readerSubscription,
      lastDataTime: lastDataTime ?? this.lastDataTime,
      scanIntervalSeconds: scanIntervalSeconds ?? this.scanIntervalSeconds,
      currentGraphIndex: currentGraphIndex ?? this.currentGraphIndex,
      segmentedDataByChannel: segmentedDataByChannel ?? this.segmentedDataByChannel,
      yAxisType: yAxisType ?? this.yAxisType,
      selectedGraphChannel: selectedGraphChannel ?? this.selectedGraphChannel,
      reconnectTimer: reconnectTimer ?? this.reconnectTimer,
      reconnectAttempts: reconnectAttempts ?? this.reconnectAttempts,
      channelConfigs: channelConfigs ?? this.channelConfigs,
      fileNameController: fileNameController ?? this.fileNameController,
      operatorController: operatorController ?? this.operatorController,
      scanRateHrController: scanRateHrController ?? this.scanRateHrController,
      scanRateMinController: scanRateMinController ?? this.scanRateMinController,
      scanRateSecController: scanRateSecController ?? this.scanRateSecController,
      testDurationDayController: testDurationDayController ?? this.testDurationDayController,
      testDurationHrController: testDurationHrController ?? this.testDurationHrController,
      testDurationMinController: testDurationMinController ?? this.testDurationMinController,
      testDurationSecController: testDurationSecController ?? this.testDurationSecController,
      graphVisibleHrController: graphVisibleHrController ?? this.graphVisibleHrController,
      graphVisibleMinController: graphVisibleMinController ?? this.graphVisibleMinController,
    );
  }
}

class SerialPortNotifier extends StateNotifier<SerialPortState> {
  SerialPortNotifier()
      : super(SerialPortState(
    portName: '',
    portMessage: Text("Ready to start scanning", style: GoogleFonts.roboto(fontSize: 16)),
    fileNameController: TextEditingController(),
    operatorController: TextEditingController(),
    scanRateHrController: TextEditingController(text: '0'),
    scanRateMinController: TextEditingController(text: '0'),
    scanRateSecController: TextEditingController(text: '1'),
    testDurationDayController: TextEditingController(text: '0'),
    testDurationHrController: TextEditingController(text: '0'),
    testDurationMinController: TextEditingController(text: '0'),
    testDurationSecController: TextEditingController(text: '0'),
    graphVisibleHrController: TextEditingController(text: '0'),
    graphVisibleMinController: TextEditingController(text: '60'),
  ));

  static const int _maxReconnectAttempts = 5;
  static const int _minInactivityTimeoutSeconds = 5;
  static const int _maxInactivityTimeoutSeconds = 30;
  static const int _reconnectPeriodSeconds = 5;

  void listAvailablePorts() {
    final ports = SerialPort.availablePorts;
    debugPrint('Available ports: $ports');
  }

  void initialize(List<dynamic> selectedChannels, String portName) {
    debugPrint('Initializing serial port: $portName');
    listAvailablePorts();
    state = state.copyWith(portName: portName, port: SerialPort(portName));
    _initializeChannelConfigs(selectedChannels);
    _startReconnectTimer();
  }

  void _initializeChannelConfigs(List<dynamic> selectedChannels) {
    debugPrint('Initializing channel configs with ${selectedChannels.length} channels');
    Map<String, Channel> channelConfigs = {};
    Map<String, Color> channelColors = {};
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

    List<String> errors = List.from(state.errors);

    for (int i = 0; i < selectedChannels.length; i++) {
      final channelData = selectedChannels[i];
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
        errors.add('Invalid channel configuration at index $i: $e');
      }
    }

    if (channelConfigs.isEmpty) {
      state = state.copyWith(
        portMessage: Text('No valid channels configured', style: GoogleFonts.roboto(color: Colors.red, fontSize: 16)),
        errors: errors..add('No valid channels configured'),
      );
    } else {
      state = state.copyWith(channelConfigs: channelConfigs, channelColors: channelColors, errors: errors);
      debugPrint('Channel configs set: ${channelConfigs.keys.toList()}');
    }
  }

  void updateChannelColor(String channel, Color color) {
    state = state.copyWith(
      channelColors: {...state.channelColors, channel: color},
    );
    debugPrint('Updated color for channel $channel');
  }

  void _configurePort() {
    if (state.port == null || !state.port!.isOpen) {
      debugPrint('Cannot configure port: Port is null or not open');
      return;
    }
    final config = SerialPortConfig()
      ..baudRate = 2400
      ..bits = 8
      ..parity = SerialPortParity.none
      ..stopBits = 1
      ..setFlowControl(SerialPortFlowControl.none);
    state.port!.config = config;
    debugPrint('Port configured: baudRate=${config.baudRate}, bits=${config.bits}, '
        'parity=${config.parity}, stopBits=${config.stopBits}');
    config.dispose();
  }

  int _getInactivityTimeout() {
    int timeout = state.scanIntervalSeconds + 2;
    return timeout.clamp(_minInactivityTimeoutSeconds, _maxInactivityTimeoutSeconds);
  }

  void _startReconnectTimer() {
    state.reconnectTimer?.cancel();
    state = state.copyWith(
      reconnectTimer: Timer.periodic(Duration(seconds: _reconnectPeriodSeconds), (timer) {
        if (state.isCancelled || state.isManuallyStopped) {
          debugPrint('Autoreconnect: Stopped by user');
          return;
        }
        if (state.isScanning && state.lastDataTime != null && DateTime.now().difference(state.lastDataTime!).inSeconds > _getInactivityTimeout()) {
          debugPrint('No data received for ${_getInactivityTimeout()} seconds, reconnecting...');
          _autoStopAndReconnect();
        } else if (!state.isScanning) {
          debugPrint('Autoreconnect: Attempting to restart scan...');
          _autoStartScan();
        }
      }),
    );
    debugPrint('Reconnect timer started');
  }

  void _autoStopAndReconnect() {
    if (state.isScanning) {
      _stopScanInternal();
      state = state.copyWith(
        portMessage: Text('Port disconnected - Reconnecting...', style: GoogleFonts.roboto(color: Colors.orange, fontSize: 16)),
        errors: [...state.errors, 'Port disconnected - Reconnecting...'],
        reconnectAttempts: 0,
      );
    }
  }

  void _autoStartScan() {
    if (!state.isScanning && !state.isCancelled && !state.isManuallyStopped && state.reconnectAttempts < _maxReconnectAttempts) {
      try {
        debugPrint('Autoreconnect: Attempt ${state.reconnectAttempts + 1}/$_maxReconnectAttempts');
        if (state.port == null || !state.port!.isOpen) {
          state = state.copyWith(port: SerialPort(state.portName));
          if (!state.port!.openReadWrite()) {
            throw SerialPort.lastError!;
          }
        }
        _configurePort();
        state.port!.flush();
        _setupReader();
        state = state.copyWith(
          isScanning: true,
          portMessage: Text('Reconnected to ${state.portName} - Scanning resumed', style: GoogleFonts.roboto(color: Colors.green, fontSize: 16, fontWeight: FontWeight.w600)),
          errors: [...state.errors, 'Reconnected to ${state.portName} - Scanning resumed'],
          reconnectAttempts: 0,
        );
      } catch (e) {
        debugPrint('Autoreconnect: Error: $e');
        state = state.copyWith(
          portMessage: Text('Reconnect error: $e', style: GoogleFonts.roboto(color: Colors.red, fontSize: 16)),
          errors: [...state.errors, 'Reconnect error: $e'],
          reconnectAttempts: state.reconnectAttempts + 1,
        );
      }
    } else if (state.reconnectAttempts >= _maxReconnectAttempts) {
      state = state.copyWith(
        portMessage: Text('Reconnect failed after $_maxReconnectAttempts attempts', style: GoogleFonts.roboto(color: Colors.red, fontSize: 16)),
        errors: [...state.errors, 'Reconnect failed after $_maxReconnectAttempts attempts'],
      );
    }
  }

  void _setupReader() {
    if (state.port == null || !state.port!.isOpen) {
      debugPrint('Cannot setup reader: Port is null or not open');
      return;
    }
    state.reader?.close();
    state.readerSubscription?.cancel();
    final reader = SerialPortReader(state.port!);
    debugPrint('Reader initialized for port: ${state.portName}');

    final subscription = reader.stream.listen(
          (Uint8List data) {
        debugPrint('Raw bytes received: ${data.toList()}');
        final decoded = String.fromCharCodes(data).trim();
        debugPrint('Decoded data: "$decoded"');

        String newBuffer = state.buffer + decoded;

        debugPrint('Channel configs: ${state.channelConfigs.keys.toList()}');
        String regexPattern = state.channelConfigs.entries
            .map((e) => '\\${e.value.startingCharacter}[0-9]*\\.?[0-9]*')
            .join('|');
        final regex = RegExp(regexPattern);
        debugPrint('Regex pattern: $regexPattern');

        final matches = regex.allMatches(newBuffer).toList();
        debugPrint('Regex matches: ${matches.map((m) => m.group(0)).toList()}');

        for (final match in matches) {
          final extracted = match.group(0);
          if (extracted != null && state.channelConfigs.containsKey(extracted[0])) {
            debugPrint('Processing matched data: $extracted');
            _addToDataList(extracted);
          } else {
            debugPrint('No channel config for extracted data: $extracted');
          }
        }

        if (matches.isNotEmpty) {
          newBuffer = newBuffer.replaceAll(regex, '');
          debugPrint('Buffer after processing: "$newBuffer"');
        }

        if (newBuffer.length > 1000 && matches.isEmpty) {
          debugPrint('Buffer full, flushing. Buffer content: "$newBuffer"');
          newBuffer = '';
        }

        state = state.copyWith(buffer: newBuffer);
      },
      onError: (error) {
        debugPrint('Stream error: $error');
        state = state.copyWith(
          portMessage: Text('Error reading data: $error', style: GoogleFonts.roboto(color: Colors.red, fontSize: 16)),
          errors: [...state.errors, 'Error reading data: $error'],
        );
      },
      onDone: () {
        debugPrint('Stream done');
        if (state.isScanning) {
          state = state.copyWith(
            portMessage: Text('Port disconnected - Reconnecting...', style: GoogleFonts.roboto(color: Colors.orange, fontSize: 16)),
            errors: [...state.errors, 'Port disconnected - Reconnecting...'],
          );
        }
      },
    );

    state = state.copyWith(reader: reader, readerSubscription: subscription);
    debugPrint('Reader subscription active');
  }

  void startScan() {
    if (!state.isScanning) {
      try {
        debugPrint('Starting scan...');
        if (state.channelConfigs.isEmpty) {
          throw Exception('No channels configured');
        }
        if (state.port == null || !state.port!.isOpen) {
          state = state.copyWith(port: SerialPort(state.portName));
          if (!state.port!.openReadWrite()) {
            throw SerialPort.lastError!;
          }
        }
        _configurePort();
        state.port!.flush();
        _setupReader();
        state = state.copyWith(
          isScanning: true,
          isCancelled: false,
          isManuallyStopped: false,
          portMessage: Text('Scanning active on ${state.portName}', style: GoogleFonts.roboto(color: Colors.green, fontWeight: FontWeight.w600, fontSize: 16)),
          errors: [...state.errors, 'Scanning active on ${state.portName}'],
          currentGraphIndex: state.segmentedDataByChannel.isNotEmpty ? state.segmentedDataByChannel.values.first.length - 1 : 0,
          reconnectAttempts: 0,
        );
      } catch (e) {
        debugPrint('Error starting scan: $e');
        state = state.copyWith(
          portMessage: Text('Error starting scan: $e', style: GoogleFonts.roboto(color: Colors.red, fontSize: 16)),
          errors: [...state.errors, 'Error starting scan: $e'],
        );
      }
    }
  }

  void stopScan() {
    _stopScanInternal();
    state = state.copyWith(
      isManuallyStopped: true,
      portMessage: Text('Scanning stopped manually', style: GoogleFonts.roboto(fontSize: 16)),
      errors: [...state.errors, 'Scanning stopped manually'],
    );
  }

  void _stopScanInternal() {
    if (state.isScanning) {
      try {
        debugPrint('Stopping scan...');
        state.readerSubscription?.cancel();
        state.reader?.close();
        if (state.port != null && state.port!.isOpen) {
          state.port!.close();
        }
        state = state.copyWith(
          isScanning: false,
          reader: null,
          readerSubscription: null,
          portMessage: Text('Scanning stopped', style: GoogleFonts.roboto(fontSize: 16)),
          errors: [...state.errors, 'Scanning stopped'],
        );
      } catch (e) {
        debugPrint('Error stopping scan: $e');
        state = state.copyWith(
          portMessage: Text('Error stopping scan: $e', style: GoogleFonts.roboto(color: Colors.red, fontSize: 16)),
          errors: [...state.errors, 'Error stopping scan: $e'],
        );
      }
    }
  }

  void cancelScan() {
    try {
      debugPrint('Cancelling scan...');
      state.readerSubscription?.cancel();
      state.reader?.close();
      if (state.port != null && state.port!.isOpen) {
        state.port!.close();
      }
      state = state.copyWith(
        isScanning: false,
        isCancelled: true,
        dataByChannel: {},
        bufferedData: {},
        buffer: '',
        segmentedDataByChannel: {},
        errors: ['Scan cancelled'],
        currentGraphIndex: 0,
        reader: null,
        readerSubscription: null,
        port: null,
        portMessage: Text('Scan cancelled', style: GoogleFonts.roboto(fontSize: 16)),
      );
      state = state.copyWith(port: SerialPort(state.portName));
    } catch (e) {
      debugPrint('Error cancelling scan: $e');
      state = state.copyWith(
        portMessage: Text('Error cancelling scan: $e', style: GoogleFonts.roboto(color: Colors.red, fontSize: 16)),
        errors: [...state.errors, 'Error cancelling scan: $e'],
      );
    }
  }

  void _addToDataList(String data) {
    DateTime now = DateTime.now();
    updateScanInterval();

    final channel = data[0];
    if (!state.channelConfigs.containsKey(channel)) {
      debugPrint('Unknown channel: $channel');
      return;
    }

    final config = state.channelConfigs[channel]!;
    if (data.length < 2) {
      debugPrint('Invalid data length for channel $channel: $data (expected at least 2 characters)');
      return;
    }

    final valueStr = data.substring(1);
    double? value = double.tryParse(valueStr);
    if (value == null) {
      debugPrint('Invalid value format for channel $channel: $valueStr');
      return;
    }
    double timestamp = now.millisecondsSinceEpoch.toDouble();

    debugPrint('[SERIAL_PORT] Processing data for channel $channel: $value at timestamp $timestamp');

    Map<String, List<Map<String, dynamic>>> newDataByChannel = {...state.dataByChannel};
    Map<String, dynamic> newData = {
      'Serial No': '${(newDataByChannel[channel]?.length ?? 0) + 1}',
      'Time': "${now.hour}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}",
      'Date': "${now.day}/${now.month}/${now.year}",
      'Timestamp': timestamp,
      'Value_$channel': value,
      'Channel_$channel': channel,
    };

    newDataByChannel.putIfAbsent(channel, () => []).add({
      ...newData,
      'Value': value,
      'Channel': channel,
      'Data': data,
    });

    Map<String, List<List<Map<String, dynamic>>>> newSegmentedData = _segmentData(newData, newDataByChannel);

    state = state.copyWith(
      dataByChannel: newDataByChannel,
      segmentedDataByChannel: newSegmentedData,
      bufferedData: {}, // Clear buffer after processing
      lastDataTime: now,
      currentGraphIndex: newSegmentedData.isNotEmpty ? newSegmentedData.values.first.length - 1 : state.currentGraphIndex,
    );

    debugPrint('[SERIAL_PORT] Added data for channel $channel at timestamp $timestamp');
    _sendRealTimeData();
  }

  Map<String, List<List<Map<String, dynamic>>>> _segmentData(Map<String, dynamic> newData, Map<String, List<Map<String, dynamic>>> newDataByChannel) {
    int graphVisibleSeconds = calculateDurationInSeconds(
      '0',
      state.graphVisibleHrController.text,
      state.graphVisibleMinController.text,
      '0',
    );
    debugPrint('Graph visible seconds: $graphVisibleSeconds');
    if (graphVisibleSeconds == 0) return state.segmentedDataByChannel;

    Map<String, List<List<Map<String, dynamic>>>> newSegmentedData = {...state.segmentedDataByChannel};

    state.channelConfigs.keys.forEach((channel) {
      newSegmentedData.putIfAbsent(channel, () => []);
      if (newSegmentedData[channel]!.isEmpty) {
        newSegmentedData[channel]!.add([
          {
            ...newData,
            'Value': newData['Value_$channel'] ?? 0.0,
            'Channel': channel,
          }
        ]);
        debugPrint('[SERIAL_PORT] Created new segment for channel $channel at timestamp ${newData['Timestamp']}');
        return;
      }

      DateTime firstDataTime = DateTime.fromMillisecondsSinceEpoch(newSegmentedData[channel]!.last.first['Timestamp'].toInt());
      DateTime newDataTime = DateTime.fromMillisecondsSinceEpoch(newData['Timestamp'].toInt());
      if (newDataTime.difference(firstDataTime).inSeconds >= graphVisibleSeconds) {
        newSegmentedData[channel]!.add([
          {
            ...newData,
            'Value': newData['Value_$channel'] ?? 0.0,
            'Channel': channel,
          }
        ]);
        debugPrint('[SERIAL_PORT] Added new segment for channel $channel at timestamp ${newData['Timestamp']}');
      } else {
        newSegmentedData[channel]!.last.add({
          ...newData,
          'Value': newData['Value_$channel'] ?? 0.0,
          'Channel': channel,
        });
        debugPrint('[SERIAL_PORT] Added data to existing segment for channel $channel at timestamp ${newData['Timestamp']}');
      }
    });

    return newSegmentedData;
  }

  Map<String, dynamic> prepareChannelData(String? channel) {
    Map<String, dynamic> data = {
      'channelName': channel == null ? 'All Channels' : state.channelConfigs[channel]!.channelName,
      'dataPoints': [],
    };

    debugPrint('Preparing data for channel: $channel');
    debugPrint('Segmented data keys: ${state.segmentedDataByChannel.keys}');
    debugPrint('Data by channel keys: ${state.dataByChannel.keys}');

    if (channel == null) {
      state.channelConfigs.keys.forEach((ch) {
        List<Map<String, dynamic>> points = (state.segmentedDataByChannel[ch]?.last ??
            state.dataByChannel[ch] ??
            []).map((d) => {
          'time': d['Time'],
          'value': d['Value'] as double,
        }).toList();
        data['dataPoints'].add({
          'channelIndex': ch,
          'channelName': state.channelConfigs[ch]!.channelName,
          'points': points,
        });
        debugPrint('[SERIAL_PORT] Prepared data for channel $ch: ${points.length} points');
      });
    } else {
      List<Map<String, dynamic>> points = (state.segmentedDataByChannel[channel]?.last ??
          state.dataByChannel[channel] ??
          []).map((d) => {
        'time': d['Time'],
        'value': d['Value'] as double,
      }).toList();
      data['dataPoints'] = points;
      debugPrint('[SERIAL_PORT] Prepared data for channel $channel: ${points.length} points');
    }

    return data;
  }

  void _sendRealTimeData() async {
    if (state.selectedGraphChannel != null) {
      final channelData = prepareChannelData(state.selectedGraphChannel);
      try {
        await DesktopMultiWindow.invokeMethod(0, 'updateData', jsonEncode({
          'channel': state.selectedGraphChannel,
          'channelData': channelData,
        }));
        debugPrint('[SERIAL_PORT] Sent real-time data to secondary window for channel ${state.selectedGraphChannel}');
      } catch (e) {
        debugPrint('[SERIAL_PORT] Error sending real-time data to secondary window: $e');
      }
    }
  }

  int calculateDurationInSeconds(String day, String hr, String min, String sec) {
    return ((int.tryParse(day) ?? 0) * 86400) +
        ((int.tryParse(hr) ?? 0) * 3600) +
        ((int.tryParse(min) ?? 0) * 60) +
        (int.tryParse(sec) ?? 0);
  }

  void updateScanInterval() {
    int scanIntervalSeconds = calculateDurationInSeconds(
      '0',
      state.scanRateHrController.text,
      state.scanRateMinController.text,
      state.scanRateSecController.text,
    );
    debugPrint('Scan interval updated: $scanIntervalSeconds seconds');
    state = state.copyWith(scanIntervalSeconds: scanIntervalSeconds);
  }

  Future<Map<String, dynamic>> saveData() async {
    try {
      debugPrint('Saving data started...');

      SharedPreferences prefs = await SharedPreferences.getInstance();
      int recNo = prefs.getInt('recNo') ?? 5;
      debugPrint('Current record number: $recNo');

      final testPayload = _prepareTestPayload(recNo);
      final test1Payload = _prepareTest1Payload(recNo);
      final test2Payload = _prepareTest2Payload(recNo);

      debugPrint('Test payload: $testPayload');
      debugPrint('Test1 payload: $test1Payload');
      debugPrint('Test2 payload: $test2Payload');

      final Map<String, dynamic> jsonData = {
        "Test": [testPayload],
        "Test1": test1Payload,
        "Test2": [test2Payload],
      };

      debugPrint('Final JSON payload: ${jsonEncode(jsonData)}');

      final response = await http.post(
        Uri.parse('http://localhost/Table/save_post.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(jsonData),
      );

      debugPrint('Response status code: ${response.statusCode}');
      debugPrint('Response body: ${response.body}');

      if (response.statusCode == 200) {
        await prefs.setInt('recNo', recNo + 1);
        debugPrint('Record number updated to: ${recNo + 1}');
        return {'success': true, 'message': 'Data saved successfully: ${response.body}'};
      } else {
        return {'success': false, 'message': 'Failed to save: ${response.body}'};
      }
    } catch (e) {
      debugPrint('Error occurred: $e');
      return {'success': false, 'message': 'Error saving data: $e'};
    }
  }

  Map<String, dynamic> _prepareTestPayload(int recNo) {
    return {
      "RecNo": recNo,
      "FName": state.fileNameController.text,
      "OperatorName": state.operatorController.text,
      "TDate": DateTime.now().toString().split(' ')[0],
      "TTime": DateTime.now().toString().split(' ')[1].split('.')[0],
      "ScanningRate": state.scanIntervalSeconds.toDouble(),
      "ScanningRateHH": double.tryParse(state.scanRateHrController.text) ?? 0.0,
      "ScanningRateMM": double.tryParse(state.scanRateMinController.text) ?? 0.0,
      "ScanningRateSS": double.tryParse(state.scanRateSecController.text) ?? 0.0,
      "TestDurationDD": double.tryParse(state.testDurationDayController.text) ?? 0.0,
      "TestDurationHH": double.tryParse(state.testDurationHrController.text) ?? 0.0,
      "TestDurationMM": double.tryParse(state.testDurationMinController.text) ?? 0.0,
      "GraphVisibleArea": 0.0,
      "BaseLine": 0.0,
      "FullScale": 0.0,
      "Descrip": "",
      "AbsorptionPer": 0.0,
      "Widowed": 0,
      "FLName": "${state.fileNameController.text}.csv",
      "XAxis": "Time",
      "XAxisRecNo": 1.0,
      "XAxisUnit": "s",
      "XAxisCode": 1.0,
      "TotalChannel": state.channelConfigs.keys.length,
      "MaxYAxis": state.channelConfigs.isNotEmpty ? state.channelConfigs.values.first.chartMaximumValue.toDouble() : 100.0,
      "MinYAxis": state.channelConfigs.isNotEmpty ? state.channelConfigs.values.first.chartMinimumValue.toDouble() : 0.0,
    };
  }

  List<Map<String, dynamic>> _prepareTest1Payload(int recNo) {
    List<Map<String, dynamic>> payload = [];
    final sortedChannels = state.channelConfigs.keys.toList()..sort();
    final timestamps = state.dataByChannel.values.firstOrNull?.map((d) => d['Timestamp'] as double).toSet().toList() ?? [];
    timestamps.sort();

    for (int i = 0; i < timestamps.length; i++) {
      final timestamp = timestamps[i];
      final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp.toInt());
      final data = state.dataByChannel[sortedChannels.first]?.firstWhere((d) => d['Timestamp'] == timestamp, orElse: () => {}) ?? {};

      Map<String, dynamic> payloadEntry = {
        "RecNo": recNo,
        "SNo": i + 1,
        "SlNo": i + 1,
        "ChangeTime": _formatTime(state.scanIntervalSeconds * (i + 1)),
        "AbsDate": "${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}",
        "AbsTime": "${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}",
        "AbsDateTime": "${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}",
        "Shown": i % 2 == 0 ? "Y" : "N",
        "AbsAvg": 0.0,
      };

      for (int j = 1; j <= 12; j++) {
        payloadEntry["AbsPer$j"] = null;
      }

      for (int j = 0; j < sortedChannels.length && j < 12; j++) {
        final channel = sortedChannels[j];
        final channelData = state.dataByChannel[channel]?.firstWhere((d) => d['Timestamp'] == timestamp, orElse: () => {}) ?? {};
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
    final sortedChannels = state.channelConfigs.keys.toList()..sort();
    Map<String, dynamic> payload = {
      "RecNo": recNo,
    };

    for (int i = 1; i <= 25; i++) {
      payload["Channel$i"] = null;
      payload["ChannelName$i"] = null;
      payload["ChannelUnit$i"] = null;
      payload["ChannelMin$i"] = null;
      payload["ChannelMax$i"] = null;
      payload["ChannelDecimal$i"] = null;
    }

    for (int i = 0; i < sortedChannels.length && i < 25; i++) {
      final channel = sortedChannels[i];
      final config = state.channelConfigs[channel]!;
      payload["Channel${i + 1}"] = config.startingCharacter;
      payload["ChannelName${i + 1}"] = config.channelName;
      payload["ChannelUnit${i + 1}"] = config.unit;
      payload["ChannelMin${i + 1}"] = config.chartMinimumValue.toDouble();
      payload["ChannelMax${i + 1}"] = config.chartMaximumValue.toDouble();
      payload["ChannelDecimal${i + 1}"] = config.decimalPlaces.toDouble();
    }

    debugPrint('[SERIAL_PORT] Prepared Test2 payload with ${sortedChannels.length} channels');
    return payload;
  }

  String _formatTime(int seconds) {
    int hrs = seconds ~/ 3600;
    int mins = (seconds % 3600) ~/ 60;
    int secs = seconds % 60;
    return "${hrs.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}";
  }

  void showPreviousGraph() {
    if (state.currentGraphIndex > 0) {
      state = state.copyWith(currentGraphIndex: state.currentGraphIndex - 1);
      debugPrint('[SERIAL_PORT] Showing previous graph segment: ${state.currentGraphIndex}');
    }
  }

  void showNextGraph() {
    if (state.segmentedDataByChannel.isNotEmpty && state.currentGraphIndex < state.segmentedDataByChannel.values.first.length - 1) {
      state = state.copyWith(currentGraphIndex: state.currentGraphIndex + 1);
      debugPrint('[SERIAL_PORT] Showing next graph segment: ${state.currentGraphIndex}');
    }
  }

  void updateSelectedGraphChannel(String? channel) {
    state = state.copyWith(selectedGraphChannel: channel);
    debugPrint('[SERIAL_PORT] Updated selected graph channel to: $channel');
  }

  @override
  void dispose() {
    state.readerSubscription?.cancel();
    state.reader?.close();
    if (state.port != null && state.port!.isOpen) {
      state.port!.close();
    }
    state.reconnectTimer?.cancel();
    state.fileNameController.dispose();
    state.operatorController.dispose();
    state.scanRateHrController.dispose();
    state.scanRateMinController.dispose();
    state.scanRateSecController.dispose();
    state.testDurationDayController.dispose();
    state.testDurationHrController.dispose();
    state.testDurationMinController.dispose();
    state.testDurationSecController.dispose();
    state.graphVisibleHrController.dispose();
    state.graphVisibleMinController.dispose();
    debugPrint('[SERIAL_PORT] Disposed SerialPortNotifier');
    super.dispose();
  }
}