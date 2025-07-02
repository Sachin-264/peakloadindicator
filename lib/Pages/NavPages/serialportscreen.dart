import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'dart:async';
import 'channel.dart'; // MODIFIED: Import the Channel class

class SerialPortScreen extends StatefulWidget {
  // MODIFIED: Accept the list of selected channels and a callback to go back.
  final List<Channel> selectedChannels;
  final VoidCallback onBack;

  const SerialPortScreen({
    super.key,
    required this.selectedChannels,
    required this.onBack,
  });

  @override
  State<SerialPortScreen> createState() => _SerialPortScreenState();
}

class _SerialPortScreenState extends State<SerialPortScreen> {
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _serialSubscription;
  final Map<String, List<String>> _dataByLetter = {};
  final List<String> _errors = [];
  bool _isPortOpen = false;
  bool _isReading = false;
  String _buffer = '';

  // MODIFIED: A map for quick lookup of a channel by its starting character.
  late final Map<String, Channel> _channelMap;

  @override
  void initState() {
    super.initState();
    print('SerialPortScreen initialized.');

    // MODIFIED: Populate the channel map from the widget's selectedChannels.
    // This makes it easy to check if incoming data belongs to a selected channel.
    _channelMap = {
      for (var channel in widget.selectedChannels)
        channel.startingCharacter: channel
    };
    print('Monitoring for channels with starting characters: ${_channelMap.keys.join(', ')}');

    _connectAndStartReading();
  }

  // ... (No changes to _connectAndStartReading method) ...
  void _connectAndStartReading() {
    // Ensure a clean slate before attempting a new connection
    _disconnectPort(clearErrors: true);

    const portName = 'COM6'; // Replace with your actual port name
    print('Attempting to connect to port: $portName');

    try {
      _port = SerialPort(portName);

      if (!_port!.openReadWrite()) {
        print('Failed to open port: $portName');
        setState(() {
          _errors.add('❌ Failed to open $portName');
          _isPortOpen = false;
          _isReading = false;
        });
        return;
      }

      print('Port $portName opened successfully');
      final config = SerialPortConfig()
        ..baudRate = 2400
        ..bits = 8
        ..parity = SerialPortParity.none
        ..stopBits = 1
        ..setFlowControl(SerialPortFlowControl.none);

      _port!.config = config;
      config.dispose();
      print('Serial port configuration applied: baudRate=2400, bits=8, parity=none, stopBits=1');

      _reader = SerialPortReader(_port!);
      print('SerialPortReader initialized');

      setState(() {
        _isPortOpen = true;
        _errors.add('✅ Port $portName opened.');
        print('Connection established (port open), now attempting to start reading.');
      });

      _startReading();
    } catch (e) {
      print('Exception during port connection: $e');
      setState(() {
        _errors.add('❌ Initialization failed: $e');
        _isPortOpen = false;
        _isReading = false;
      });
    }
  }

  void _startReading() {
    if (!_isPortOpen) {
      setState(() { _errors.add('⚠️ Port is not open. Cannot start reading.'); });
      return;
    }
    if (_isReading && _serialSubscription != null && !_serialSubscription!.isPaused) {
      setState(() { _errors.add('⚠️ Already reading.'); });
      return;
    }

    if (_serialSubscription != null && _serialSubscription!.isPaused) {
      _serialSubscription!.resume();
      print('Resumed serial port reading.');
      setState(() { _isReading = true; _errors.add('▶️ Reading resumed.'); });
      return;
    }

    _serialSubscription = _reader!.stream.listen((data) {
      final incoming = String.fromCharCodes(data);
      _buffer += incoming;

      final regex = RegExp(r'\.([A-Z0-9]{6})');
      final matches = regex.allMatches(_buffer).toList();

      for (final match in matches) {
        final extracted = match.group(1);
        if (extracted != null && extracted.length == 6) {
          // MODIFIED: Instead of grouping all data, first check if the
          // data's identifier matches one of our selected channels.
          final dataIdentifier = extracted[1]; // e.g., 'A' in '2A3961'

          // Use the channel map for an efficient check.
          if (_channelMap.containsKey(dataIdentifier)) {
            // This data belongs to a channel we are monitoring.
            setState(() {
              // Group by the same identifier.
              _dataByLetter.putIfAbsent(dataIdentifier, () => []).add(extracted);
            });
          }
        }
      }

      _buffer = _buffer.replaceAll(regex, '');
    }, onError: (error) {
      print('Serial port stream error: $error');
      setState(() { _errors.add('❌ Stream Error: $error'); _isReading = false; });
      _serialSubscription?.cancel();
      _serialSubscription = null;
    }, onDone: () {
      print('Serial port stream done.');
      setState(() { _errors.add('✅ Stream Done.'); _isReading = false; });
      _serialSubscription = null;
    });

    setState(() { _isReading = true; _errors.add('▶️ Started reading data.'); });
    print('Serial port reading started.');
  }

  // ... (No changes to _stopReading, _disconnectPort, dispose methods) ...
  void _stopReading() {
    if (!_isReading) {
      setState(() { _errors.add('⚠️ Not currently reading.'); });
      return;
    }
    if (_serialSubscription == null) {
      setState(() { _errors.add('⚠️ No active subscription to stop.'); });
      return;
    }

    _serialSubscription!.pause();
    print('Paused serial port reading.');
    setState(() { _isReading = false; _errors.add('⏸️ Reading paused.'); });
  }

  void _disconnectPort({bool clearErrors = false}) {
    print('Attempting to disconnect and clean up.');
    _serialSubscription?.cancel();
    _serialSubscription = null;
    _reader?.close();
    _reader = null;
    if (_isPortOpen) {
      _port?.close();
      print('Closed serial port.');
    }
    _port = null;

    setState(() {
      _isPortOpen = false;
      _isReading = false;
      _dataByLetter.clear();
      _buffer = '';
      if (clearErrors) {
        _errors.clear();
      }
      _errors.add('🛑 Disconnected from port.');
    });
  }

  @override
  void dispose() {
    print('Disposing SerialPortScreen widget.');
    _disconnectPort();
    super.dispose();
  }

  List<TableRow> _buildTableRows() {
    List<TableRow> tableRows = [];

    // MODIFIED: The headers are now derived from the selected channels, not dynamically.
    // This ensures the columns are always in the order provided by the selection screen.
    final List<Channel> selectedChannels = widget.selectedChannels;
    final int totalColumns = selectedChannels.isNotEmpty ? selectedChannels.length : 1;

    // Display status/error messages (this logic is largely unchanged, just adapted to columns)
    if (_errors.isNotEmpty) {
      for (final msg in _errors) {
        List<Widget> rowChildren = [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              msg,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: msg.startsWith('❌') ? Colors.red : (msg.startsWith('✅') ? Colors.green : (msg.startsWith('▶️') || msg.startsWith('⏸️') || msg.startsWith('🛑') || msg.startsWith('⚠️') ? Colors.orangeAccent : Colors.white70)),
              ),
            ),
          ),
        ];
        while (rowChildren.length < totalColumns) {
          rowChildren.add(const SizedBox.shrink());
        }
        tableRows.add(TableRow(children: rowChildren));
      }
    }

    // ... (Initial prompt logic is fine) ...
    bool showInitialPrompt = _dataByLetter.isEmpty && (_errors.isEmpty || (_errors.length == 1 && _errors.last.startsWith('🛑')));
    if (showInitialPrompt) {
      // ...
    }

    // MODIFIED: Build header row using the channel names from the selected channels.
    if (selectedChannels.isNotEmpty) {
      tableRows.add(
        TableRow(
          children: selectedChannels.map((channel) {
            return Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                channel.channelName, // Use the proper channel name for the header
                style: const TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            );
          }).toList(),
        ),
      );
    }

    // Find the maximum number of rows needed
    final maxRows = _dataByLetter.values.fold<int>(0, (max, list) => list.length > max ? list.length : max);

    // MODIFIED: Build data rows by iterating through the selected channels
    // to ensure the data appears in the correct column.
    for (int i = 0; i < maxRows; i++) {
      final rowCells = selectedChannels.map((channel) {
        // Use the channel's startingCharacter to look up its data
        final dataList = _dataByLetter[channel.startingCharacter] ?? [];
        final value = i < dataList.length ? dataList[i] : '';
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            value,
            textAlign: TextAlign.center,
          ),
        );
      }).toList();

      tableRows.add(TableRow(children: rowCells));
    }

    print('Built table with ${tableRows.length} rows, $totalColumns columns');
    return tableRows;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // MODIFIED: Add a leading back button to trigger the onBack callback.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Disconnect the port before going back to clean up resources.
            _disconnectPort();
            widget.onBack();
          },
          tooltip: 'Change Channels',
        ),
        title: const Text("RS232 Serial Reader"),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _isPortOpen ? null : _connectAndStartReading,
                  child: const Text('Connect'),
                ),
                ElevatedButton(
                  onPressed: _isPortOpen && !_isReading ? _startReading : null,
                  child: const Text('Start Reading'),
                ),
                ElevatedButton(
                  onPressed: _isReading ? _stopReading : null,
                  child: const Text('Stop Reading'),
                ),
                ElevatedButton(
                  onPressed: _isPortOpen ? _disconnectPort : null,
                  child: const Text('Disconnect'),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: Table(
                  border: TableBorder.all(color: Colors.grey),
                  defaultColumnWidth: const IntrinsicColumnWidth(),
                  children: _buildTableRows(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}