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
import '../../constants/global.dart';
import '../../constants/database_manager.dart';
import '../../constants/sessionmanager.dart';
import '../../constants/theme.dart';
import '../Secondary_window/secondary_window.dart';
import '../homepage.dart';
import '../logScreen/log.dart'; // This import might become unused if LogPage is entirely removed
import 'channel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class SerialPortScreen extends StatefulWidget {
  final List<dynamic> selectedChannels;
  const SerialPortScreen({super.key, required this.selectedChannels});

  @override
  State<SerialPortScreen> createState() => _SerialPortScreenState();
}

class _SerialPortScreenState extends State<SerialPortScreen> {
  // --- Serial Port Variables ---
  String? _portName; // Will be loaded from DB
  int? _baudRate; // Will be loaded from DB
  int? _dataBits; // Will be loaded from DB
  String? _parity; // Will be loaded from DB
  int? _stopBits; // Will be loaded from DB

  SerialPort? port;
  Map<String, List<Map<String, dynamic>>> dataByChannel = {};
  Map<double, Map<String, dynamic>> _bufferedData = {};
  String buffer = "";
  late Widget portMessage =
  _buildDefaultPortMessage(); // Initialize with a default value
  List<String> errors = [];
  Map<String, Color> channelColors =
  {}; // Stores runtime colors, can be changed by user
  bool isScanning = false;
  bool isCancelled = false; // Flag to track if scan was explicitly cancelled
  bool isManuallyStopped = false;
  SerialPortReader? reader;
  StreamSubscription<Uint8List>? _readerSubscription;
  DateTime? lastDataTime;
  int scanIntervalSeconds = 1;
  int currentGraphIndex = 0;
  Map<String, List<List<Map<String, dynamic>>>> segmentedDataByChannel = {};
  final ScrollController _scrollController = ScrollController();
  final ScrollController _tableScrollController = ScrollController();
  String yAxisType = 'Load'; // Not actively used, but part of state
  Timer? _reconnectTimer;
  Timer? _testDurationTimer;
  Timer? _tableUpdateTimer;
  int _reconnectAttempts = 0;
  int _lastScanIntervalSeconds = 1;
  Timer? _debounceTimer;
  static const int _maxReconnectAttempts = 5;
  static const int _minInactivityTimeoutSeconds = 5;
  static const int _maxInactivityTimeoutSeconds = 30; // Corrected static const
  static const int _reconnectPeriodSeconds = 5;
  String? _selectedGraphChannel; // Null means "All Channels"
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

  Map<String, Channel> channelConfigs = {}; // Stores database channel configs
  final List<OverlayEntry> _windowEntries = [];

  // GlobalKey for ScaffoldMessenger context
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
  GlobalKey<ScaffoldMessengerState>();

  // Helper for consistent log timestamp
  String get _currentTime => DateFormat('HH:mm:ss').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    print('[$_currentTime] SERIAL PORT SCREEN: Initialized.');
    _loadComPortSettings(); // Load settings first
    _initializeChannelConfigs();
    _startReconnectTimer();
  }

  // Default port message initialization
  Widget _buildDefaultPortMessage() {
    print('[$_currentTime] SERIAL PORT SCREEN: Building default port message.');
    return Text("Loading COM port settings...",
        style: GoogleFonts.roboto(
            fontSize: 16,
            color: ThemeColors.getColor(
                'serialPortMessageText', Global.isDarkMode.value)));
  }

  Future<void> _loadComPortSettings() async {
    print('[$_currentTime] SERIAL PORT SCREEN: Attempting to load COM Port settings from database...');
    try {
      final settings = await DatabaseManager().getComPortSettings();
      if (settings != null) {
        if (mounted) {
          setState(() {
            _portName = settings['selectedPort'] as String?;
            _baudRate = settings['baudRate'] as int?;
            _dataBits = settings['dataBits'] as int?;
            _parity = settings['parity'] as String?;
            _stopBits = settings['stopBits'] as int?;
            portMessage = Text(
                _portName != null
                    ? "Ready to start scanning on $_portName"
                    : "Port not configured",
                style: GoogleFonts.roboto(
                    fontSize: 16,
                    color: ThemeColors.getColor(
                        'serialPortMessageText', Global.isDarkMode.value)));
            print(
                '[$_currentTime] SERIAL PORT SCREEN: COM Port settings loaded: Port=$_portName, BaudRate=$_baudRate, DataBits=$_dataBits, Parity=$_parity, StopBits=$_stopBits. Ready to scan.');
          });
        }
      } else {
        if (mounted) {
          setState(() {
            portMessage = Text(
                "No COM port settings found in database. Using default fallback settings.",
                style: GoogleFonts.roboto(
                    color: ThemeColors.getColor(
                        'serialPortErrorTextSmall', Global.isDarkMode.value),
                    fontSize: 16));
            _portName = 'COM6'; // Default fallback
            _baudRate = 2400; // Default fallback
            _dataBits = 8; // Default fallback
            _parity = 'None'; // Default fallback
            _stopBits = 1; // Default fallback
            print(
                '[$_currentTime] SERIAL PORT SCREEN: No COM Port settings found, using defaults: COM6, 2400 baud. Please configure in settings.');
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          portMessage = Text("Error loading port settings: $e",
              style: GoogleFonts.roboto(
                  color: ThemeColors.getColor(
                      'serialPortErrorTextSmall', Global.isDarkMode.value),
                  fontSize: 16));
          errors.add('Error loading port settings: $e');
          print('[$_currentTime] SERIAL PORT SCREEN: Error loading COM Port settings: $e');
        });
      }
      _portName = 'COM6'; // Default fallback on error
      _baudRate = 2400; // Default fallback
      _dataBits = 8; // Default fallback
      _parity = 'None'; // Default fallback
      _stopBits = 1; // Default fallback
    }
    _initPort(); // Initialize port after settings are loaded
  }

  void _initPort() {
    print('[$_currentTime] SERIAL PORT SCREEN: Initializing serial port object for $_portName...');
    if (_portName == null || _portName!.isEmpty) {
      if (mounted) {
        setState(() {
          portMessage = Text("COM Port name is not configured.",
              style: GoogleFonts.roboto(
                  color: ThemeColors.getColor(
                      'serialPortErrorTextSmall', Global.isDarkMode.value),
                  fontSize: 16));
          errors.add("COM Port name is not configured.");
        });
      }
      print(
          '[$_currentTime] SERIAL PORT SCREEN: COM Port name not configured. Cannot initialize serial port object.');
      return;
    }

    if (port != null) {
      try {
        if (port!.isOpen) {
          port!.close();
          print('[$_currentTime] SERIAL PORT SCREEN: Closed previously open port.');
        }
        port!.dispose(); // Dispose previous port instance
        print('[$_currentTime] SERIAL PORT SCREEN: Disposed previous port instance.');
      } catch (e) {
        print('[$_currentTime] SERIAL PORT SCREEN: Error cleaning up previous port: $e');
      }
    }

    try {
      port = SerialPort(_portName!);
      print('[$_currentTime] SERIAL PORT SCREEN: SerialPort object created for $_portName.');
    } on SerialPortError catch (e) {
      print('[$_currentTime] SERIAL PORT SCREEN: SerialPortError initializing SerialPort object: ${e.message}');
      if (mounted) {
        setState(() {
          portMessage = Text('Error initializing port $_portName: ${e.message}',
              style: GoogleFonts.roboto(
                  color: ThemeColors.getColor(
                      'serialPortErrorTextSmall', Global.isDarkMode.value),
                  fontSize: 16));
          errors.add('Error initializing port $_portName: ${e.message}');
        });
      }
      port = null;
    } catch (e) {
      print('[$_currentTime] SERIAL PORT SCREEN: Generic error initializing SerialPort object: $e');
      if (mounted) {
        setState(() {
          portMessage = Text('Error initializing port $_portName: $e',
              style: GoogleFonts.roboto(
                  color: ThemeColors.getColor(
                      'serialPortErrorTextSmall', Global.isDarkMode.value),
                  fontSize: 16));
          errors.add('Error initializing port $_portName: $e');
        });
      }
      port = null;
    }
  }

  void _initializeChannelConfigs() {
    print('[$_currentTime] SERIAL PORT SCREEN: Initializing channel configurations from selectedChannels list...');
    channelConfigs.clear();
    channelColors.clear();

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

        Color channelColor = Color(channel.graphLineColour);
        if (channel.graphLineColour == 0 || channelColor.alpha == 0) {
          channelColor = fallbackColors[i % fallbackColors.length];
          print(
              '[$_currentTime] SERIAL PORT SCREEN: Invalid graphLineColour for channel ${channel.channelName} (${channelId}), using fallback color: ${channelColor.toHexString()}.');
        } else {
          print(
              '[$_currentTime] SERIAL PORT SCREEN: Configured channel ${channel.channelName} (${channelId}) with color: ${channelColor.toHexString()}.');
        }
        channelColors[channelId] = channelColor;
      } catch (e) {
        print('[$_currentTime] SERIAL PORT SCREEN: Error configuring channel at index $i: $e');
        if (mounted) {
          setState(() {
            errors.add('Invalid channel configuration at index $i: $e');
          });
        }
      }
    }

    if (channelConfigs.isEmpty) {
      if (mounted) {
        setState(() {
          portMessage = Text('No valid channels configured',
              style: GoogleFonts.roboto(
                  color: ThemeColors.getColor(
                      'serialPortErrorTextSmall', Global.isDarkMode.value),
                  fontSize: 16));
          errors.add('No valid channels configured');
        });
      }
      print('[$_currentTime] SERIAL PORT SCREEN: No valid channels configured. Cannot proceed with scanning.');
    } else {
      print('[$_currentTime] SERIAL PORT SCREEN: ${channelConfigs.length} channels configured successfully.');
    }
  }

  void _showColorPicker(String channelId, bool isDarkMode) {
    print('[$_currentTime] SERIAL PORT SCREEN: Opening color picker for channel ${channelConfigs[channelId]?.channelName ?? channelId}.');
    Color tempSelectedColor = channelColors[channelId]!;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateInDialog) {
            bool isDefault = false;

            return AlertDialog(
              backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
              title: Text(
                  'Select Color for Channel ${channelConfigs[channelId]?.channelName ?? 'Unknown'}',
                  style: GoogleFonts.roboto(
                      color: ThemeColors.getColor('dialogText', isDarkMode))),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ColorPicker(
                      pickerColor: tempSelectedColor,
                      onColorChanged: (Color color) {
                        setStateInDialog(() {
                          tempSelectedColor = color;
                        });
                      },
                      showLabel: true,
                      pickerAreaHeightPercent: 0.8,
                      labelTypes: const [],
                      colorPickerWidth: 300,
                      portraitOnly: true,
                      displayThumbColor: true,
                      pickerAreaBorderRadius: BorderRadius.circular(10),
                    ),
                    Row(
                      children: [
                        Checkbox(
                          value: isDefault,
                          onChanged: (bool? newValue) {
                            setStateInDialog(() {
                              isDefault = newValue ?? false;
                              print('[$_currentTime] SERIAL PORT SCREEN: "Set as Default" checkbox changed to ${isDefault ? 'checked' : 'unchecked'} for channel ${channelConfigs[channelId]?.channelName}.');
                            });
                          },
                          activeColor: ThemeColors.getColor('submitButton', isDarkMode),
                        ),
                        Text('Set as Default in Database',
                            style: GoogleFonts.roboto(
                                color: ThemeColors.getColor(
                                    'dialogSubText', isDarkMode))),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    print('[$_currentTime] SERIAL PORT SCREEN: Color picker "Done" button pressed for channel ${channelConfigs[channelId]?.channelName}.');
                    if (mounted) {
                      setState(() {
                        channelColors[channelId] = tempSelectedColor;
                      });
                    }

                    if (isDefault) {
                      _updateChannelColorInDatabase(channelId, tempSelectedColor);
                    }

                    Navigator.of(context).pop();
                  },
                  child: Text('Done',
                      style: GoogleFonts.roboto(
                          color: ThemeColors.getColor(
                              'submitButton', isDarkMode))),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _updateChannelColorInDatabase(String channelId, Color color) async {
    print('[$_currentTime] SERIAL PORT SCREEN: Attempting to update default graph color for channel ${channelConfigs[channelId]?.channelName ?? channelId} to ${color.toHexString()} in database.');
    try {
      final database = await DatabaseManager().database;
      final channel = channelConfigs[channelId]!;
      int colorValue = color.value;

      await database.update(
        'ChannelSetup',
        {'graphLineColour': colorValue},
        where: 'StartingCharacter = ? AND RecNo = ?',
        whereArgs: [channelId, channel.recNo],
      );

      print(
          '[$_currentTime] SERIAL PORT SCREEN: Channel ${channel.channelName} (RecNo: ${channel.recNo}) graph color updated as default in DB to ${color.toHexString()}.');
    } catch (e) {
      print('[$_currentTime] SERIAL PORT SCREEN: Error updating channel color in database: $e');
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('Error saving default color: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _configurePort() {
    print('[$_currentTime] SERIAL PORT SCREEN: Configuring serial port $_portName...');
    if (port == null || !port!.isOpen) {
      print('[$_currentTime] SERIAL PORT SCREEN: Port is null or not open. Cannot configure.');
      return;
    }
    final config = SerialPortConfig();

    config
      ..baudRate = _baudRate ?? 2400
      ..bits = _dataBits ?? 8
      ..parity = (_parity == 'Even'
          ? SerialPortParity.even
          : _parity == 'Odd'
          ? SerialPortParity.odd
          : SerialPortParity.none)
      ..stopBits = _stopBits ?? 1
      ..setFlowControl(SerialPortFlowControl.none);

    try {
      port!.config = config;
      print(
          '[$_currentTime] SERIAL PORT SCREEN: Serial port $_portName configured successfully: BaudRate=${config.baudRate}, DataBits=${config.bits}, Parity=${_parity}, StopBits=${config.stopBits}.');
    } catch (e) {
      print('[$_currentTime] SERIAL PORT SCREEN: Serial port configuration error for $_portName: $e');
      if (mounted) {
        setState(() {
          portMessage = Text('Port config error: $e',
              style: GoogleFonts.roboto(
                  color: ThemeColors.getColor(
                      'serialPortErrorTextSmall', Global.isDarkMode.value),
                  fontSize: 16));
          errors.add('Port config error: $e');
        });
      }
    } finally {
      config.dispose();
    }
  }

  int _getInactivityTimeout() {
    int timeout = scanIntervalSeconds + 10;
    int clampedTimeout = timeout
        .clamp(_minInactivityTimeoutSeconds, _maxInactivityTimeoutSeconds)
        .toInt();
    print('[$_currentTime] SERIAL PORT SCREEN: Calculated inactivity timeout: $clampedTimeout seconds (based on scan interval $scanIntervalSeconds).');
    return clampedTimeout;
  }

  void _updateGraphData(Map<String, dynamic> newData) {
    final channelKey = newData['Channel'] as String?;
    if (channelKey == null) {
      print('[$_currentTime] SERIAL PORT SCREEN: Attempted to update graph data for null channel key. Skipping.');
      return;
    }
    dataByChannel[channelKey] = [
      ...(dataByChannel[channelKey] ?? []),
      newData,
    ];
    Global.graphDataSink.add({
      'dataByChannel': Map.from(dataByChannel),
      'channelColors': Map.from(channelColors),
      'channelConfigs': Map.from(channelConfigs),
      'isDarkMode': Global.isDarkMode.value,
    });
    print('[$_currentTime] SERIAL PORT SCREEN: Graph data sink updated for channel $channelKey.');
  }

  void _openFloatingGraphWindow() {
    print('[$_currentTime] SERIAL PORT SCREEN: "Add Window" button pressed. Opening new floating graph window.');
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
            entry.markNeedsBuild();
          },
          onClose: (closedEntry) {
            _windowEntries.remove(closedEntry);
            print('[$_currentTime] SERIAL PORT SCREEN: Floating graph window closed.');
          },
        ),
      );
    });

    Overlay.of(context)?.insert(entry);
    _windowEntries.add(entry);
    print('[$_currentTime] SERIAL PORT SCREEN: New floating graph window opened successfully.');
  }

  void _startReconnectTimer() {
    _reconnectTimer?.cancel();
    print('[$_currentTime] SERIAL PORT SCREEN: Auto-reconnect timer started with ${_reconnectPeriodSeconds}s interval.');
    _reconnectTimer =
        Timer.periodic(Duration(seconds: _reconnectPeriodSeconds), (timer) {
          if (isCancelled || isManuallyStopped) {
            print('[$_currentTime] SERIAL PORT SCREEN: Autoreconnect: Stopped by user action (cancelled or manually stopped).');
            timer.cancel();
            return;
          }
          if (isScanning &&
              lastDataTime != null &&
              DateTime.now().difference(lastDataTime!).inSeconds >
                  _getInactivityTimeout()) {
            print('[$_currentTime] SERIAL PORT SCREEN: Inactivity detected. No data received for ${_getInactivityTimeout()} seconds. Attempting to reconnect serial port.');
            _autoStopAndReconnect();
          } else if (!isScanning) {
            print('[$_currentTime] SERIAL PORT SCREEN: Autoreconnect: Scan is not active. Attempting to start scan.');
            _autoStartScan();
          }
        });
  }

  void _autoStopAndReconnect() {
    print('[$_currentTime] SERIAL PORT SCREEN: Autoreconnect triggered: No data for ${_getInactivityTimeout()} seconds.');
    if (isScanning) {
      print(
          '[$_currentTime] SERIAL PORT SCREEN: Initiating auto-reconnect: Stopping current scan due to inactivity.');
      _stopScanInternal();
      if (mounted) {
        setState(() {
          portMessage = Text('Port disconnected - Reconnecting...',
              style: GoogleFonts.roboto(color: Colors.orange, fontSize: 16));
          errors.add('Port disconnected - Reconnecting...');
        });
      }
      _reconnectAttempts = 0;
    }
  }

  void _autoStartScan() {
    if (!isScanning &&
        !isCancelled &&
        !isManuallyStopped &&
        _reconnectAttempts < _maxReconnectAttempts) {
      try {
        print('[$_currentTime] SERIAL PORT SCREEN: Autoreconnect: Attempt ${_reconnectAttempts + 1}/$_maxReconnectAttempts to restart scan.');
        if (_portName == null || _portName!.isEmpty) {
          throw Exception('Port name not set. Cannot auto-reconnect.');
        }

        if (port == null || !port!.isOpen) {
          _initPort();
          if (port == null) {
            throw Exception('Failed to re-initialize port $_portName.');
          }
          if (!port!.openReadWrite()) {
            final lastError = SerialPort.lastError;
            throw Exception(
                'Failed to re-open port for read/write: ${lastError?.message ?? "Unknown error"}');
          }
          print('[$_currentTime] SERIAL PORT SCREEN: Serial port $_portName re-opened for auto-reconnect.');
        }

        _configurePort();
        _setupReader();
        if (mounted) {
          setState(() {
            isScanning = true;
            portMessage = Text('Reconnected to $_portName - Scanning resumed',
                style: GoogleFonts.roboto(
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                    fontSize: 16));
            errors.add('Reconnected to $_portName - Scanning resumed');
          });
        }
        _reconnectAttempts = 0;
        _startTableUpdateTimer();
        _addTableRow(); // Add a row immediately on reconnect to update view
        print(
            '[$_currentTime] SERIAL PORT SCREEN: Auto-reconnected to $_portName. Scanning resumed successfully.');
      } catch (e) {
        print('[$_currentTime] SERIAL PORT SCREEN: Autoreconnect: Error attempting to restart scan: $e');
        if (mounted) {
          setState(() {
            portMessage = Text('Reconnect error: $e',
                style: GoogleFonts.roboto(
                    color: ThemeColors.getColor(
                        'serialPortErrorTextSmall', Global.isDarkMode.value),
                    fontSize: 16));
            errors.add('Reconnect error: $e');
          });
        }
        _reconnectAttempts++;
      }
    } else if (_reconnectAttempts >= _maxReconnectAttempts) {
      if (mounted) {
        setState(() {
          portMessage = Text(
              'Reconnect failed after $_maxReconnectAttempts attempts',
              style: GoogleFonts.roboto(
                  color: ThemeColors.getColor(
                      'serialPortErrorTextSmall', Global.isDarkMode.value),
                  fontSize: 16));
          errors.add('Reconnect failed after $_maxReconnectAttempts attempts');
          isManuallyStopped = true; // Prevent further auto-attempts
        });
      }
      print(
          '[$_currentTime] SERIAL PORT SCREEN: Auto-reconnect failed after $_maxReconnectAttempts attempts. Stopping auto-reconnect attempts.');
    }
  }

  void _setupReader() {
    print('[$_currentTime] SERIAL PORT SCREEN: Setting up SerialPortReader...');
    if (port == null || !port!.isOpen) {
      print('[$_currentTime] SERIAL PORT SCREEN: Port is null or not open. Cannot set up reader.');
      return;
    }
    _readerSubscription?.cancel();
    reader?.close();
    print('[$_currentTime] SERIAL PORT SCREEN: Existing reader subscription and reader closed (if any).');


    reader = SerialPortReader(port!,
        timeout: 500); // 500ms timeout for read operations
    _readerSubscription = reader!.stream.listen(
          (Uint8List data) {
        final decoded = String.fromCharCodes(data);
        buffer += decoded;
        print('[$_currentTime] RAW SERIAL DATA RECEIVED: "$decoded" (Current buffer: "$buffer")'); // MAJOR LOG: RAW DATA HERE

        String regexPattern = channelConfigs.entries
            .map((e) => '\\${e.value.startingCharacter}[0-9]+\\.[0-9]+')
            .join('|');
        final regex = RegExp(regexPattern);
        final matches = regex.allMatches(buffer).toList();

        print('[$_currentTime] SERIAL PORT SCREEN: Scanning buffer with regex: "$regexPattern". Found ${matches.length} matches.');

        for (final match in matches) {
          final extracted = match.group(0);
          if (extracted != null &&
              extracted.isNotEmpty &&
              channelConfigs.containsKey(extracted[0])) {
            _addToDataList(extracted);
            print('[$_currentTime] SERIAL PORT SCREEN: Successfully processed data point: "$extracted".'); // LOG: PARSED DATA POINT
          } else {
            print('[$_currentTime] SERIAL PORT SCREEN: Discarding unrecognized match or channel ID: "$extracted".');
          }
        }

        if (matches.isNotEmpty) {
          // Remove only the matched parts from the buffer to handle partial messages correctly
          buffer = buffer.replaceAll(regex, '');
          print('[$_currentTime] SERIAL PORT SCREEN: Matches removed from buffer. Remaining buffer: "$buffer".');
        }

        if (buffer.length > 1000 && matches.isEmpty) {
          print(
              '[$_currentTime] SERIAL PORT SCREEN: WARNING: Buffer length > 1000 characters and no matches found. Clearing buffer to prevent overflow, potential malformed data stream. Buffer content: "$buffer"');
          buffer = ''; // Clear buffer to prevent indefinite growth from malformed data
        }
        lastDataTime = DateTime.now();
      },
      onError: (error) {
        print('[$_currentTime] SERIAL PORT SCREEN: SerialPortReader stream error: $error');
        if (mounted) {
          setState(() {
            portMessage = Text('Error reading data: $error',
                style: GoogleFonts.roboto(
                    color: ThemeColors.getColor(
                        'serialPortErrorTextSmall', Global.isDarkMode.value),
                    fontSize: 16));
            errors.add('Error reading data: $error');
          });
        }
        // Attempt to re-establish connection if an error occurs during reading
        if (isScanning && !isCancelled && !isManuallyStopped) {
          print('[$_currentTime] SERIAL PORT SCREEN: Stream error detected while scanning. Attempting auto-reconnect.');
          _autoStopAndReconnect();
        }
      },
      onDone: () {
        print('[$_currentTime] SERIAL PORT SCREEN: SerialPortReader stream completed (onDone callback).');
        if (isScanning && !isCancelled && !isManuallyStopped) {
          if (mounted) {
            setState(() {
              portMessage = Text('Port disconnected - Reconnecting...',
                  style:
                  GoogleFonts.roboto(color: Colors.orange, fontSize: 16));
              errors.add('Port disconnected - Reconnecting...');
            });
          }
          print('[$_currentTime] SERIAL PORT SCREEN: Serial port disconnected unexpectedly. Attempting to reconnect via auto-reconnect logic.');
          _autoStopAndReconnect(); // Trigger reconnect logic
        }
      },
    );
    print('[$_currentTime] SERIAL PORT SCREEN: SerialPortReader stream listener activated.');
  }

  void _startScan() {
    print('[$_currentTime] SERIAL PORT SCREEN: "Start Scan" button pressed.');
    if (!isScanning) {
      try {
        print('[$_currentTime] SERIAL PORT SCREEN: Attempting to start data scan on $_portName.');
        if (channelConfigs.isEmpty) {
          throw Exception('No channels configured. Please configure channels in settings.');
        }
        if (_portName == null || _portName!.isEmpty) {
          throw Exception('COM Port not configured. Please select a port in settings.');
        }

        if (port == null || !port!.isOpen) {
          _initPort();
          if (port == null) {
            throw Exception('Failed to initialize port $_portName before starting scan.');
          }
          if (!port!.openReadWrite()) {
            final lastError = SerialPort.lastError;
            throw Exception(
                'Failed to open port $_portName for read/write: ${lastError?.message ?? "Unknown error"}');
          }
          print('[$_currentTime] SERIAL PORT SCREEN: Serial port $_portName opened for read/write.');
        }

        _configurePort();
        _setupReader();
        if (mounted) {
          setState(() {
            isScanning = true;
            isCancelled = false;
            isManuallyStopped = false;
            portMessage = Text('Scanning active on $_portName',
                style: GoogleFonts.roboto(
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                    fontSize: 16));
            errors.add('Scanning active on $_portName');
            // Ensure graph index is set to the last segment if data exists
            if (segmentedDataByChannel.isNotEmpty &&
                segmentedDataByChannel.values.any((list) => list.isNotEmpty)) {
              currentGraphIndex =
                  segmentedDataByChannel.values.first.length - 1;
              print('[$_currentTime] SERIAL PORT SCREEN: Setting graph index to last segment on start: $currentGraphIndex');
            }
          });
        }
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
          print('[$_currentTime] SERIAL PORT SCREEN: Test duration set for ${Duration(seconds: testDurationSeconds).inMinutes} minutes. Automatic stop configured.');
          _testDurationTimer =
              Timer(Duration(seconds: testDurationSeconds), () {
                if (mounted) {
                  _stopScan();
                  setState(() {
                    portMessage = Text('Test duration reached, scanning stopped',
                        style:
                        GoogleFonts.roboto(color: Colors.blue, fontSize: 16));
                    errors.add('Test duration reached, scanning stopped');
                  });
                }
                print(
                    '[$_currentTime] SERIAL PORT SCREEN: Test duration of ${Duration(seconds: testDurationSeconds).inMinutes} minutes reached. Scanning stopped automatically.');
              });
        } else {
          print('[$_currentTime] SERIAL PORT SCREEN: Test duration set to 0 or less, no automatic stop timer initiated.');
        }
        print('[$_currentTime] SERIAL PORT SCREEN: Data scan started successfully on $_portName.');
      } catch (e) {
        print('[$_currentTime] SERIAL PORT SCREEN: Error starting scan: $e');
        if (mounted) {
          setState(() {
            portMessage = Text('Error starting scan: $e',
                style: GoogleFonts.roboto(
                    color: ThemeColors.getColor(
                        'serialPortErrorTextSmall', Global.isDarkMode.value),
                    fontSize: 16));
            errors.add('Error starting scan: $e');
          });
        }
        if (e.toString().contains('busy') ||
            e.toString().contains('Access denied')) {
          _cancelScan(); // Force cancel if port is busy/denied to reset state
        }
      }
    } else {
      print('[$_currentTime] SERIAL PORT SCREEN: "Start Scan" button clicked, but scan is already active. Ignoring.');
    }
  }

  void _stopScan() {
    print('[$_currentTime] SERIAL PORT SCREEN: "Stop Scan" button pressed. Initiating manual scan stop.');
    _stopScanInternal();
    if (mounted) {
      setState(() {
        isManuallyStopped = true;
        portMessage = Text('Scanning stopped manually',
            style: GoogleFonts.roboto(
                color: ThemeColors.getColor(
                    'serialPortMessageText', Global.isDarkMode.value),
                fontSize: 16));
        errors.add('Scanning stopped manually');
      });
    }
    _testDurationTimer?.cancel();
    _tableUpdateTimer?.cancel();
    print('[$_currentTime] SERIAL PORT SCREEN: Scanning stopped manually.');
  }

  void _stopScanInternal() {
    if (isScanning) {
      try {
        print('[$_currentTime] SERIAL PORT SCREEN: Stopping scan internally...');
        _readerSubscription?.cancel();
        _readerSubscription = null; // Clear reference
        reader?.close();
        reader = null; // Clear reference
        if (port != null && port!.isOpen) {
          port!.close();
          print('[$_currentTime] SERIAL PORT SCREEN: Serial port $_portName closed.');
        }
        if (mounted) {
          setState(() {
            isScanning = false;
            portMessage = Text('Scanning stopped',
                style: GoogleFonts.roboto(
                    color: ThemeColors.getColor(
                        'serialPortMessageText', Global.isDarkMode.value),
                    fontSize: 16));
            errors.add('Scanning stopped');
          });
        }
        print('[$_currentTime] SERIAL PORT SCREEN: Internal scan stop completed successfully.');
      } catch (e) {
        print('[$_currentTime] SERIAL PORT SCREEN: Error during internal scan stop: $e');
        if (mounted) {
          setState(() {
            portMessage = Text('Error stopping scan: $e',
                style: GoogleFonts.roboto(
                    color: ThemeColors.getColor(
                        'serialPortErrorTextSmall', Global.isDarkMode.value),
                    fontSize: 16));
            errors.add('Error stopping scan: $e');
          });
        }
      }
    } else {
      print('[$_currentTime] SERIAL PORT SCREEN: Internal stop requested, but scan was not active. Ignoring.');
    }
  }

  void _cancelScan() {
    print('[$_currentTime] SERIAL PORT SCREEN: "Cancel Scan" button pressed. Initiating scan cancellation and data clear.');
    try {
      print('[$_currentTime] SERIAL PORT SCREEN: Cancelling scan...');
      _readerSubscription?.cancel();
      _readerSubscription = null;
      reader?.close();
      reader = null;
      if (port != null && port!.isOpen) {
        port!.close();
        print('[$_currentTime] SERIAL PORT SCREEN: Serial port $_portName closed during cancellation.');
      }
      if (mounted) {
        setState(() {
          isScanning = false;
          isCancelled = true;
          isManuallyStopped = true;
          dataByChannel.clear();
          _bufferedData.clear();
          buffer = "";
          segmentedDataByChannel.clear();
          errors.clear();
          currentGraphIndex = 0;
          portMessage = Text('Scan cancelled',
              style: GoogleFonts.roboto(
                  color: ThemeColors.getColor(
                      'serialPortMessageText', Global.isDarkMode.value),
                  fontSize: 16));
          errors.add('Scan cancelled');
        });
      }
      _initPort(); // Re-initialize port object for future use
      _testDurationTimer?.cancel();
      _tableUpdateTimer?.cancel();
      _debounceTimer?.cancel();
      print('[$_currentTime] SERIAL PORT SCREEN: Data scan cancelled. All buffered and displayed data cleared. Port re-initialized for future scans.');
    } catch (e) {
      print('[$_currentTime] SERIAL PORT SCREEN: Error during scan cancellation: $e');
      if (mounted) {
        setState(() {
          portMessage = Text('Error cancelling scan: $e',
              style: GoogleFonts.roboto(
                  color: ThemeColors.getColor(
                      'serialPortErrorTextSmall', Global.isDarkMode.value),
                  fontSize: 16));
          errors.add('Error cancelling scan: $e');
        });
      }
    }
  }

  void _startTableUpdateTimer() {
    _tableUpdateTimer?.cancel();
    if (scanIntervalSeconds < 1) {
      scanIntervalSeconds = 1;
      print('[$_currentTime] SERIAL PORT SCREEN: Scan interval corrected to minimum 1 second (was $scanIntervalSeconds).');
    }
    if (scanIntervalSeconds != _lastScanIntervalSeconds) {
      _lastScanIntervalSeconds = scanIntervalSeconds;
      print('[$_currentTime] SERIAL PORT SCREEN: Table update timer interval changed to $scanIntervalSeconds seconds.');
    }
    _tableUpdateTimer =
        Timer.periodic(Duration(seconds: scanIntervalSeconds), (_) {
          if (!isScanning || isCancelled || isManuallyStopped) {
            _tableUpdateTimer?.cancel();
            print('[$_currentTime] SERIAL PORT SCREEN: Table update timer cancelled because scan is no longer active or was stopped/cancelled.');
            return;
          }
          _addTableRow();
        });
    print('[$_currentTime] SERIAL PORT SCREEN: Started table update timer with interval $scanIntervalSeconds seconds.');
  }

  void _addTableRow() {
    DateTime now = DateTime.now();
    double timestamp = now.millisecondsSinceEpoch.toDouble();
    String time =
        "${now.hour}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
    String date = "${now.day}/${now.month}/${now.year}";

    Map<String, Map<String, dynamic>> latestChannelData = {};
    double intervalStart = timestamp - (scanIntervalSeconds * 1000);
    var recentTimestamps = _bufferedData.keys
        .where((t) => t >= intervalStart && t <= timestamp)
        .toList()
      ..sort();

    print('[$_currentTime] SERIAL PORT SCREEN: Adding new table row for timestamp $timestamp. Checking buffered data (last $scanIntervalSeconds seconds).');

    for (var channel in channelConfigs.keys) {
      Map<String, dynamic>? latestData;
      for (var t in recentTimestamps.reversed) {
        if (_bufferedData[t]?.containsKey(channel) == true) {
          latestData = _bufferedData[t]![channel];
          print('[$_currentTime] SERIAL PORT SCREEN: Latest buffered data for channel $channel: ${latestData?['Value']} at ${DateFormat('HH:mm:ss.SSS').format(DateTime.fromMillisecondsSinceEpoch(t.toInt()))}.');
          break;
        }
      }
      latestChannelData[channel] = latestData ?? {'Value': 0.0, 'Data': ''};
    }

    // Clear old data from buffer
    _bufferedData.removeWhere((t, _) => t < intervalStart);
    print('[$_currentTime] SERIAL PORT SCREEN: Cleaned old data from _bufferedData. Current size: ${_bufferedData.length}.');


    if (mounted) {
      setState(() {
        Map<String, dynamic> newData = {
          'Serial No':
          '${(dataByChannel.isNotEmpty ? dataByChannel.values.first.length : 0) + 1}',
          'Time': time,
          'Date': date,
          'Timestamp': timestamp,
        };

        bool anyChannelDataAdded = false; // Track if any channel actually added data
        channelConfigs.keys.forEach((channel) {
          double value =
              (latestChannelData[channel]!['Value'] as num?)?.toDouble() ?? 0.0;
          newData['Value_$channel'] = value.isFinite ? value : 0.0;
          newData['Channel_$channel'] = channel;

          var channelData = {
            ...newData,
            'Value': newData['Value_$channel'],
            'Channel': channel,
            'Data': latestChannelData[channel]!['Data'] ?? '',
          };

          dataByChannel.putIfAbsent(channel, () => []).add(channelData);
          _updateGraphData(channelData);
          anyChannelDataAdded = true;
          print('[$_currentTime] SERIAL PORT SCREEN: Table row data for channel $channel: Value=${value.toStringAsFixed(2)}.');
        });

        if (anyChannelDataAdded) {
          _segmentData(newData);
          lastDataTime = now;
          print('[$_currentTime] SERIAL PORT SCREEN: New table row added and graph data updated for timestamp ${timestamp.toInt()}.');
        } else {
          print('[$_currentTime] SERIAL PORT SCREEN: No new valid channel data to add to table row at timestamp ${timestamp.toInt()}.');
        }


        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
            print('[$_currentTime] SERIAL PORT SCREEN: Graph scroll controller moved to end.');
          }
          if (_tableScrollController.hasClients) {
            _tableScrollController.animateTo(
              _tableScrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
            print('[$_currentTime] SERIAL PORT SCREEN: Table scroll controller moved to end.');
          }
        });

        if (segmentedDataByChannel.isNotEmpty &&
            segmentedDataByChannel.values.any((list) => list.isNotEmpty)) {
          currentGraphIndex = segmentedDataByChannel.values.first.length - 1;
          print('[$_currentTime] SERIAL PORT SCREEN: Graph index updated to last segment: $currentGraphIndex.');
        }
      });
    }
  }

  void _addToDataList(String data) {
    DateTime now = DateTime.now();
    final channelId = data[0];
    if (!channelConfigs.containsKey(channelId)) {
      print('[$_currentTime] SERIAL PORT SCREEN: WARNING: Unknown channel ID "$channelId" from data "$data". Skipping.');
      return;
    }

    final config = channelConfigs[channelId]!;
    final valueStr = data.substring(1);
    double value = double.tryParse(valueStr) ?? 0.0;
    double timestamp = now.millisecondsSinceEpoch.toDouble();

    _bufferedData.putIfAbsent(timestamp, () => {});
    _bufferedData[timestamp]![channelId] = {
      'Value': value,
      'Time':
      "${now.hour}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}",
      'Date': "${now.day}/${now.month}/${now.year}",
      'Data': data,
      'Timestamp': timestamp,
      'Channel': channelId,
    };
    print('[$_currentTime] SERIAL PORT SCREEN: BUFFERED DATA: Channel=$channelId, Value=${value.toStringAsFixed(2)}, RawString="$data", Timestamp=${timestamp.toInt()}.'); // LOG: BUFFERED DATA
  }

  void _segmentData(Map<String, dynamic> newData) {
    int graphVisibleSeconds = _calculateDurationInSeconds('0',
        _graphVisibleHrController.text, _graphVisibleMinController.text, '0');
    if (graphVisibleSeconds <= 0) {
      print('[$_currentTime] SERIAL PORT SCREEN: Invalid graph visible duration: $graphVisibleSeconds seconds. Using default (3600s).');
      graphVisibleSeconds = 3600; // Default to 1 hour if invalid
    }

    double newTimestamp = newData['Timestamp'] as double;
    print('[$_currentTime] SERIAL PORT SCREEN: Segmenting data for new timestamp: ${newTimestamp.toInt()}.');

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
        print('[$_currentTime] SERIAL PORT SCREEN: Created initial graph segment for channel $channelId.');
        return;
      }

      List<Map<String, dynamic>> lastSegment =
          segmentedDataByChannel[channelId]!.last;
      double lastSegmentStartTime = lastSegment.first['Timestamp'] as double;

      if ((newTimestamp - lastSegmentStartTime) / 1000 >= graphVisibleSeconds) {
        segmentedDataByChannel[channelId]!.add([
          {
            ...newData,
            'Value': newData['Value_$channelId'] ?? 0.0,
            'Channel': channelId,
          }
        ]);
        print('[$_currentTime] SERIAL PORT SCREEN: New graph segment created for channel $channelId at timestamp $newTimestamp (visible duration ${graphVisibleSeconds}s exceeded).');
      } else {
        segmentedDataByChannel[channelId]!.last.add({
          ...newData,
          'Value': newData['Value_$channelId'] ?? 0.0,
          'Channel': channelId,
        });
        // print('[$_currentTime] SERIAL PORT SCREEN: Added data to existing segment for channel $channelId.'); // Too verbose
      }
    });

    if (segmentedDataByChannel.isNotEmpty &&
        segmentedDataByChannel.values.any((list) => list.isNotEmpty)) {
      if (mounted) {
        setState(() {
          currentGraphIndex = segmentedDataByChannel.values.first.length - 1;
          print('[$_currentTime] SERIAL PORT SCREEN: Current graph index set to last segment: $currentGraphIndex.');
        });
      }
    }
  }

  int _calculateDurationInSeconds(
      String day, String hr, String min, String sec) {
    int duration = ((int.tryParse(day) ?? 0) * 86400) +
        ((int.tryParse(hr) ?? 0) * 3600) +
        ((int.tryParse(min) ?? 0) * 60) +
        (int.tryParse(sec) ?? 0);
    print('[$_currentTime] SERIAL PORT SCREEN: Calculated duration: $day D, $hr H, $min M, $sec S = $duration seconds.');
    return duration;
  }

  void _updateScanInterval() {
    final newInterval = _calculateDurationInSeconds(
      '0',
      _scanRateHrController.text,
      _scanRateMinController.text,
      _scanRateSecController.text,
    );
    if (newInterval != scanIntervalSeconds) {
      if (mounted) {
        setState(() {
          scanIntervalSeconds = newInterval < 1 ? 1 : newInterval;
          print('[$_currentTime] SERIAL PORT SCREEN: Scan interval updated to: $scanIntervalSeconds seconds.');
        });
      }
      if (isScanning) {
        _startTableUpdateTimer();
      }
    } else {
      print('[$_currentTime] SERIAL PORT SCREEN: Scan interval unchanged ($newInterval seconds).');
    }
  }

  Future<void> _saveData(bool isDarkMode) async {
    print('[$_currentTime] SERIAL PORT SCREEN: "Save Data" button pressed. Initiating data saving process.');
    Database? newSessionDatabase;
    try {
      String fileName = _fileNameController.text.trim();
      String operatorName = _operatorController.text.trim();

      if (fileName.isEmpty) {
        fileName =
        'Data_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}';
        if (mounted) {
          _fileNameController.text = fileName;
        }
        print(
            '[$_currentTime] SERIAL PORT SCREEN: File Name was empty, auto-generated: $fileName');
      }
      if (operatorName.isEmpty) {
        operatorName = 'Operator';
        if (mounted) {
          _operatorController.text = operatorName;
        }
        print(
            '[$_currentTime] SERIAL PORT SCREEN: Operator Name was empty, auto-filled with: $operatorName');
      }

      print('[$_currentTime] SERIAL PORT SCREEN: Saving data to databases started...');

      if (!mounted) {
        print('[$_currentTime] SERIAL PORT SCREEN: Widget unmounted, cannot show save dialog.');
        return;
      }
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                  ThemeColors.getColor('submitButton', isDarkMode)),
            ),
          );
        },
      );

      final appDocumentsDir = await getApplicationSupportDirectory();
      final dataFolder =
      Directory(path.join(appDocumentsDir.path, 'CountronicsData'));
      if (!await dataFolder.exists()) {
        await dataFolder.create(recursive: true);
        print('[$_currentTime] SERIAL PORT SCREEN: Created data directory: ${dataFolder.path}.');
      }
      print('[$_currentTime] SERIAL PORT SCREEN: Data folder path: ${dataFolder.path}');

      final now = DateTime.now();
      final dateTimeString = DateFormat('yyyyMMddHHmmss').format(now);
      final newDbFileName = 'serial_port_data_$dateTimeString.db';
      final newDbPathFull = path.join(dataFolder.path, newDbFileName);
      print('[$_currentTime] SERIAL PORT SCREEN: New database full path: $newDbPathFull');
      print('[$_currentTime] SERIAL PORT SCREEN: Session data will be saved to database: $newDbFileName.');

      final mainDatabase = await DatabaseManager().database;
      print('[$_currentTime] SERIAL PORT SCREEN: Main database connection obtained.');

      newSessionDatabase =
      await SessionDatabaseManager().openSessionDatabase(newDbFileName);
      print('[$_currentTime] SERIAL PORT SCREEN: Session database "$newDbFileName" opened.');


      SharedPreferences prefs = await SharedPreferences.getInstance();
      int recNo =
          prefs.getInt('recNo') ?? 5; // Default value needs to be consistent
      print('[$_currentTime] SERIAL PORT SCREEN: Current record number (RecNo) from SharedPreferences: $recNo.');

      final testPayload = _prepareTestPayload(recNo, newDbFileName);
      final test1Payload = _prepareTest1Payload(recNo);
      final test2Payload = _prepareTest2Payload(recNo);
      print('[$_currentTime] SERIAL PORT SCREEN: Prepared Test, Test1, and Test2 payloads for saving.');


      await mainDatabase.insert(
        'Test',
        testPayload,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print('[$_currentTime] SERIAL PORT SCREEN: Inserted data into main database "Test" table.');

      await newSessionDatabase.insert(
        'Test',
        testPayload,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print('[$_currentTime] SERIAL PORT SCREEN: Inserted data into session database "Test" table.');

      await newSessionDatabase.transaction((txn) async {
        for (var entry in test1Payload) {
          await txn.insert(
            'Test1',
            entry,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
      print('[$_currentTime] SERIAL PORT SCREEN: Inserted ${test1Payload.length} entries into session database "Test1" table within a transaction.');

      await newSessionDatabase.insert(
        'Test2',
        test2Payload,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print('[$_currentTime] SERIAL PORT SCREEN: Inserted data into session database "Test2" table.');

      await prefs.setInt('recNo', recNo + 1);
      print('[$_currentTime] SERIAL PORT SCREEN: Updated "recNo" in SharedPreferences to ${recNo + 1}.');

      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else if (!mounted) {
        print('[$_currentTime] SERIAL PORT SCREEN: Widget unmounted before dialog could be popped.');
        return;
      }

      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('Data saved successfully to databases'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
      print(
          '[$_currentTime] SERIAL PORT SCREEN: Data saved successfully to $newDbFileName.');
    } catch (e, s) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else if (!mounted) {
        print('[$_currentTime] SERIAL PORT SCREEN: Widget unmounted during save error, skipping dialog pop.');
      }
      print('[$_currentTime] SERIAL PORT SCREEN: Error saving data to databases: $e\nStackTrace: $s');
      if (mounted) {
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text('Error saving data: $e'),
            backgroundColor: ThemeColors.getColor('errorText', isDarkMode),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (newSessionDatabase != null && newSessionDatabase.isOpen) {
        await newSessionDatabase.close();
        print('[$_currentTime] SERIAL PORT SCREEN: Session database connection closed.');
      }
    }
  }

  Map<String, dynamic> _prepareTestPayload(int recNo, String newDbFileName) {
    print('[$_currentTime] SERIAL PORT SCREEN: Preparing Test table payload for RecNo $recNo.');
    Map<String, dynamic> payload = {
      "RecNo": recNo.toDouble(),
      "FName": _fileNameController.text,
      "OperatorName": _operatorController.text,
      "TDate": DateFormat('yyyy-MM-dd').format(
          DateTime.now()),
      "TTime": DateFormat('HH:mm:ss').format(
          DateTime.now()),
      "ScanningRate": scanIntervalSeconds.toDouble(),
      "ScanningRateHH": double.tryParse(_scanRateHrController.text) ?? 0.0,
      "ScanningRateMM": double.tryParse(_scanRateMinController.text) ?? 0.0,
      "ScanningRateSS": double.tryParse(_scanRateSecController.text) ?? 0.0,
      "TestDurationDD": double.tryParse(_testDurationDayController.text) ?? 0.0,
      "TestDurationHH": double.tryParse(_testDurationHrController.text) ?? 0.0,
      "TestDurationMM": double.tryParse(_testDurationMinController.text) ?? 0.0,
      "TestDurationSS": double.tryParse(_testDurationSecController.text) ?? 0.0,
      "GraphVisibleArea": _calculateDurationInSeconds(
          '0',
          _graphVisibleHrController.text,
          _graphVisibleMinController.text,
          '0')
          .toDouble(),
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
      "MaxYAxis": channelConfigs.isNotEmpty
          ? channelConfigs.values
          .map((c) => c.chartMaximumValue)
          .fold(double.negativeInfinity, max)
          : 100.0,
      "MinYAxis": channelConfigs.isNotEmpty
          ? channelConfigs.values
          .map((c) => c.chartMinimumValue)
          .fold(double.infinity, min)
          : 0.0,
      "DBName": newDbFileName,
    };
    return payload;
  }

  List<Map<String, dynamic>> _prepareTest1Payload(int recNo) {
    print('[$_currentTime] SERIAL PORT SCREEN: Preparing Test1 table payload for RecNo $recNo.');
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
    print('[$_currentTime] SERIAL PORT SCREEN: Found ${timestamps.length} unique timestamps for Test1 payload.');

    for (int i = 0; i < timestamps.length; i++) {
      final timestamp = timestamps[i];
      final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp.toInt());

      Map<String, dynamic> payloadEntry = {
        "RecNo": recNo.toDouble(),
        "SNo": (i + 1).toDouble(),
        "SlNo": (i + 1).toDouble(),
        "ChangeTime": _formatTime(scanIntervalSeconds *
            (i +
                1)), // This might not be precise, consider using actual elapsed time
        "AbsDate": DateFormat('yyyy-MM-dd').format(dateTime),
        "AbsTime": DateFormat('HH:mm:ss').format(dateTime),
        "AbsDateTime": DateFormat('yyyy-MM-dd HH:mm:ss').format(dateTime),
        "Shown": "Y",
        "AbsAvg": 0.0,
      };

      for (int j = 1; j <= 100; j++) {
        payloadEntry["AbsPer$j"] =
        null; // Initialize to null
      }

      for (int j = 0; j < sortedChannels.length && j < 100; j++) {
        final channelId = sortedChannels[j];
        final channelDataList = dataByChannel[channelId];
        final Map<String, dynamic> dataEntryForTimestamp = channelDataList
            ?.firstWhere(
              (d) => (d['Timestamp'] as double?) == timestamp,
          orElse: () =>
          <String, dynamic>{}, // Return empty map if not found
        ) ??
            {};
        if (dataEntryForTimestamp.isNotEmpty &&
            dataEntryForTimestamp['Value'] != null &&
            (dataEntryForTimestamp['Value'] as num).isFinite) {
          payloadEntry["AbsPer${j + 1}"] =
              (dataEntryForTimestamp['Value'] as num).toDouble();
        }
      }
      payload.add(payloadEntry);
    }
    print('[$_currentTime] SERIAL PORT SCREEN: Test1 payload prepared with ${payload.length} entries.');
    return payload;
  }

  Map<String, dynamic> _prepareTest2Payload(int recNo) {
    print('[$_currentTime] SERIAL PORT SCREEN: Preparing Test2 table payload for RecNo $recNo.');
    final sortedChannels = channelConfigs.keys.toList()..sort();
    Map<String, dynamic> payload = {
      "RecNo": recNo.toDouble(),
    };

    for (int i = 1; i <= 100; i++) {
      String channelName = '';
      if (i <= sortedChannels.length) {
        final channelId = sortedChannels[i - 1];
        channelName = channelConfigs[channelId]?.channelName ?? '';
      }
      payload["ChannelName$i"] = channelName;
    }
    print('[$_currentTime] SERIAL PORT SCREEN: Test2 payload prepared.');
    return payload;
  }

  String _formatTime(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    String formattedTime =
        '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    return formattedTime;
  }

  void _showPreviousGraph() {
    if (segmentedDataByChannel.isNotEmpty &&
        segmentedDataByChannel.values.any((list) => list.isNotEmpty) &&
        currentGraphIndex > 0) {
      if (mounted) {
        setState(() {
          currentGraphIndex--;
          print('[$_currentTime] SERIAL PORT SCREEN: Navigated to previous graph segment (Index: $currentGraphIndex).');
        });
      }
    } else {
      print('[$_currentTime] SERIAL PORT SCREEN: Attempted to navigate to previous graph segment, but already at the first segment or no data available.');
    }
  }

  void _showNextGraph() {
    int maxIndex = (segmentedDataByChannel.values.firstOrNull?.length ?? 1) - 1;
    if (segmentedDataByChannel.isNotEmpty &&
        segmentedDataByChannel.values.any((list) => list.isNotEmpty) &&
        currentGraphIndex < maxIndex) {
      if (mounted) {
        setState(() {
          currentGraphIndex++;
          print('[$_currentTime] SERIAL PORT SCREEN: Navigated to next graph segment (Index: $currentGraphIndex).');
        });
      }
    } else {
      print('[$_currentTime] SERIAL PORT SCREEN: Attempted to navigate to next graph segment, but already at the last segment or no data available.');
    }
  }

  Map<String, List<Map<String, dynamic>>> get _currentGraphDataByChannel {
    Map<String, List<Map<String, dynamic>>> currentData = {};
    if (segmentedDataByChannel.isEmpty ||
        segmentedDataByChannel.values.every((list) => list.isEmpty)) {
      return {};
    }

    channelConfigs.keys.forEach((channelId) {
      if (segmentedDataByChannel.containsKey(channelId) &&
          currentGraphIndex < segmentedDataByChannel[channelId]!.length) {
        currentData[channelId] =
        segmentedDataByChannel[channelId]![currentGraphIndex];
      } else {
        currentData[channelId] = [];
      }
    });
    // print('[$_currentTime] SERIAL PORT SCREEN: Retrieving graph data for segment $currentGraphIndex.'); // Too verbose
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
              icon: Icon(Icons.chevron_left,
                  color: ThemeColors.getColor('sidebarIcon',
                      isDarkMode)),
              onPressed: _showPreviousGraph),
          Text(
              'Segment ${currentGraphIndex + 1}/${segmentedDataByChannel.values.first.length}',
              style: GoogleFonts.roboto(
                  color: ThemeColors.getColor(
                      'serialPortGraphAxisLabel', isDarkMode),
                  fontWeight: FontWeight.w500)),
          IconButton(
              icon: Icon(Icons.chevron_right,
                  color: ThemeColors.getColor('sidebarIcon',
                      isDarkMode)),
              onPressed: _showNextGraph),
        ],
      ),
    );
  }

  Widget _buildGraph(bool isDarkMode) {
    final currentGraphData = _currentGraphDataByChannel;

    List<LineChartBarData> lineBarsData = [];
    Map<int, String> barIndexToChannelId = {};

    double minX;
    double maxX;
    double minY = double.infinity;
    double maxY = -double.infinity;
    Set<double> uniqueTimestamps = {};

    int segmentHours = int.tryParse(_graphVisibleHrController.text) ?? 0;
    int segmentMinutes = int.tryParse(_graphVisibleMinController.text) ?? 60;
    double segmentSeconds = (segmentHours * 3600) + (segmentMinutes * 60);
    double segmentDurationMs = segmentSeconds * 1000;
    if (segmentDurationMs <= 0)
      segmentDurationMs = 3600 * 1000; // Default to 1 hour if invalid/zero

    final channelsToPlot = _selectedGraphChannel != null
        ? [_selectedGraphChannel!]
        : channelConfigs.keys.toList();
    channelsToPlot.sort();

    double segmentStartTimeMs;
    if (segmentedDataByChannel.isNotEmpty &&
        segmentedDataByChannel.values.any((list) => list.isNotEmpty)) {
      double tempMinTimestamp = double.infinity;
      for (var channelId in channelConfigs.keys) {
        if (segmentedDataByChannel.containsKey(channelId) &&
            currentGraphIndex < segmentedDataByChannel[channelId]!.length &&
            segmentedDataByChannel[channelId]![currentGraphIndex].isNotEmpty) {
          final segment = segmentedDataByChannel[channelId]![currentGraphIndex];
          if (segment.first['Timestamp'] is num) {
            tempMinTimestamp = min(tempMinTimestamp,
                (segment.first['Timestamp'] as num).toDouble());
          }
        }
      }
      segmentStartTimeMs = (tempMinTimestamp != double.infinity)
          ? tempMinTimestamp
          : (DateTime.now().millisecondsSinceEpoch.toDouble() -
          segmentDurationMs);
    } else {
      segmentStartTimeMs =
          DateTime.now().millisecondsSinceEpoch.toDouble() - segmentDurationMs;
    }
    double segmentEndTimeMs = segmentStartTimeMs + segmentDurationMs;

    minX = segmentStartTimeMs;
    maxX = segmentEndTimeMs;

    if (currentGraphData.isEmpty ||
        currentGraphData.values.every((data) => data.isEmpty)) {
      return Center(
        child: Text(
          'Waiting for channel data...',
          style: GoogleFonts.roboto(
              color: ThemeColors.getColor('cardText', isDarkMode),
              fontSize: 18),
        ),
      );
    }

    for (var channelId in channelsToPlot) {
      if (!channelConfigs.containsKey(channelId) ||
          !channelColors.containsKey(channelId)) {
        print(
            '[$_currentTime] SERIAL PORT SCREEN: Skipping graph for channel $channelId: Missing configuration or color.');
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
          print('[$_currentTime] SERIAL PORT SCREEN: Invalid data point for graph (timestamp: $timestamp, value: $value). Skipping.');
          continue;
        }

        uniqueTimestamps.add(timestamp);
        FlSpot spot = FlSpot(timestamp, value);

        bool isAboveMaxAlarm =
            config.targetAlarmMax != null && value > config.targetAlarmMax!;
        bool isBelowMinAlarm =
            config.targetAlarmMin != null && value < config.targetAlarmMin!;

        if (isAboveMaxAlarm || isBelowMinAlarm) {
          alarmSpots.add(spot);
          // print('[$_currentTime] SERIAL PORT SCREEN: Target Alarm: Alarm triggered for channel ${config.channelName} (Value: $value, Max: ${config.targetAlarmMax}, Min: ${config.targetAlarmMin})'); // Verbose
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
                show: _showGraphDots,
                getDotPainter: (spot, percent, bar, index) {
                  return FlDotCirclePainter(
                    radius: _showGraphDots ? 4 : 0,
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
            dotData: FlDotData(
                show: true, // Always show dots for alarm spots
                getDotPainter: (spot, percent, bar, index) {
                  return FlDotCirclePainter(
                    radius: 5,
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

    if (minY == double.infinity || maxY == -double.infinity) {
      minY = 0.0;
      maxY = 100.0;
      print('[$_currentTime] SERIAL PORT SCREEN: Graph Y-axis values were infinite, defaulting to 0-100.');
    } else {
      double yRange = maxY - minY;
      if (yRange == 0) {
        maxY += 10;
        minY -= (minY > 0 ? 1 : 0);
        print('[$_currentTime] SERIAL PORT SCREEN: Graph Y-axis range was zero, adjusting for visibility.');
      } else {
        maxY += yRange * 0.1;
        minY -= yRange * 0.05;
        print('[$_currentTime] SERIAL PORT SCREEN: Graph Y-axis range adjusted by 10% for padding.');
      }
      bool allChannelsMinNonNegative =
      channelConfigs.values.every((c) => c.chartMinimumValue >= 0);
      if (minY < 0 && allChannelsMinNonNegative) {
        minY = 0;
        print('[$_currentTime] SERIAL PORT SCREEN: Graph Y-axis minimum clamped to 0 as all channels have non-negative chartMinimumValue.');
      }
    }

    double intervalY = (maxY - minY) / 5;
    if (intervalY <= 0 || !intervalY.isFinite) {
      intervalY = (maxY > 0)
          ? maxY / 5
          : 1;
      if (intervalY <= 0) intervalY = 1.0;
      print('[$_currentTime] SERIAL PORT SCREEN: Graph Y-axis interval adjusted to ${intervalY.toStringAsFixed(2)} due to invalid/zero calculation.');
    }
    print('[$_currentTime] SERIAL PORT SCREEN: Graph Y-axis range: ${minY.toStringAsFixed(2)} to ${maxY.toStringAsFixed(2)}, Interval: ${intervalY.toStringAsFixed(2)}.');


    Widget legend = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: channelsToPlot
            .where((channelId) =>
        channelConfigs.containsKey(channelId) &&
            channelColors.containsKey(channelId))
            .map((channelId) {
          final color = channelColors[channelId];
          final channelName =
              channelConfigs[channelId]?.channelName ?? 'Unknown';
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                print('[$_currentTime] SERIAL PORT SCREEN: Tapped legend for channel $channelId, opening color picker.');
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
                    Text('Channel $channelName',
                        style: GoogleFonts.roboto(
                            color: ThemeColors.getColor(
                                'serialPortGraphAxisLabel', isDarkMode),
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(width: 4),
                    Icon(Icons.palette,
                        size: 16,
                        color: ThemeColors.getColor('serialPortDropdownIcon',
                            isDarkMode)),
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
        Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: legend),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 24.0, 16.0, 16.0),
            child: LineChart(
              LineChartData(
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots
                          .map((spot) {
                        if (!spot.x.isFinite || !spot.y.isFinite) {
                          return null;
                        }
                        final channelId =
                        barIndexToChannelId[spot.barIndex];
                        if (channelId == null ||
                            !channelConfigs.containsKey(channelId)) {
                          return null;
                        }

                        final channelName =
                            channelConfigs[channelId]?.channelName ??
                                'Unknown';
                        final unit = channelConfigs[channelId]?.unit ?? '';
                        return LineTooltipItem(
                          'Channel $channelName\n${spot.y.toStringAsFixed(2)} $unit\n${DateFormat('HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(spot.x.toInt()))}',
                          GoogleFonts.roboto(
                              color: Colors.black,
                              fontWeight: FontWeight.w600,
                              fontSize: 12),
                        );
                      })
                          .where((item) => item != null)
                          .toList()
                          .cast<LineTooltipItem>();
                    },
                    tooltipBorder: BorderSide(
                        color:
                        ThemeColors.getColor('tooltipBorder', isDarkMode)),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: intervalY,
                  getDrawingVerticalLine: (value) {
                    return FlLine(
                        color: ThemeColors.getColor(
                            'serialPortGraphGridLine', isDarkMode),
                        strokeWidth: 1);
                  },
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                        color: ThemeColors.getColor(
                            'serialPortGraphGridLine', isDarkMode),
                        strokeWidth: 1);
                  },
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    axisNameWidget: Text(
                      'Load (${channelConfigs.isNotEmpty ? channelConfigs.values.first.unit : "Unit"})',
                      style: GoogleFonts.roboto(
                          color: ThemeColors.getColor(
                              'serialPortGraphAxisLabel', isDarkMode),
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      interval: intervalY,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.isFinite ? value.toStringAsFixed(2) : '',
                          style: GoogleFonts.roboto(
                              color: ThemeColors.getColor(
                                  'serialPortGraphAxisLabel', isDarkMode),
                              fontSize: 12),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    axisNameWidget: Text(
                      'Time',
                      style: GoogleFonts.roboto(
                          color: ThemeColors.getColor(
                              'serialPortGraphAxisLabel', isDarkMode),
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize:
                      70, // Increased to accommodate rotated labels
                      getTitlesWidget: (value, meta) {
                        if (meta.appliedInterval > 0 &&
                            uniqueTimestamps.isNotEmpty) {
                          final dateTime = DateTime.fromMillisecondsSinceEpoch(
                              value.toInt());
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Transform.rotate(
                              angle: pi / 2, // Rotate by 90 degrees
                              alignment: Alignment.center,
                              child: Align(
                                alignment: Alignment
                                    .centerRight, // Align text to the right after rotation
                                child: Text(
                                  '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}',
                                  style: GoogleFonts.roboto(
                                      color: ThemeColors.getColor(
                                          'serialPortGraphAxisLabel',
                                          isDarkMode),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                      interval: segmentDurationMs /
                          5, // Display ~5 labels across the segment
                    ),
                  ),
                ),
                borderData: FlBorderData(
                    show: true,
                    border: Border.all(
                        color: ThemeColors.getColor(
                            'serialPortCardBorder', isDarkMode))),
                minX: minX,
                maxX: maxX,
                minY: minY,
                maxY: maxY,
                lineBarsData: lineBarsData,
                clipData: FlClipData.all(),
                extraLinesData: const ExtraLinesData(extraLinesOnTop: true),
              ),
              key: ValueKey(channelColors.hashCode ^
              currentGraphIndex ^
              segmentedDataByChannel.hashCode ^
              _selectedGraphChannel.hashCode ^
              _showGraphDots.hashCode),
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
    const int maxRows = 100; // Limit to last 100 rows for performance

    if (dataByChannel.isEmpty ||
        dataByChannel.values.every((list) => list == null || list.isEmpty)) {
      tableRows.add(
        TableRow(
          children: List.generate(
            columnCount > 0 ? columnCount : 1, // Ensure at least one cell for 'No data'
                (index) => Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text(
                index == 0 ? 'No data available' : '',
                style: GoogleFonts.roboto(
                    color: ThemeColors.getColor('cardText', isDarkMode),
                    fontSize: 14),
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
    // print('[$_currentTime] SERIAL PORT SCREEN: Building table rows. Total unique timestamps: ${timestamps.length}.');

    // Get the starting index to display only the last 'maxRows'
    final startIndex =
    timestamps.length > maxRows ? timestamps.length - maxRows : 0;

    // Add header row
    tableRows.add(
      TableRow(
        decoration: BoxDecoration(
            color: ThemeColors.getColor(
                'serialPortTableHeaderBackground', isDarkMode)),
        children: headers.map((header) {
          return Padding(
            padding: const EdgeInsets.all(12.0),
            child: Text(
              header == 'Time'
                  ? 'Time'
                  : channelConfigs[header]?.channelName ?? header, // Use channel name for headers
              style: GoogleFonts.roboto(
                  fontWeight: FontWeight.bold,
                  color: ThemeColors.getColor('dialogText',
                      isDarkMode), // Changed to dialogText for better contrast
                  fontSize: 14),
            ),
          );
        }).toList(),
      ),
    );

    // Add data rows
    for (int i = startIndex; i < timestamps.length; i++) {
      final timestamp = timestamps[i];
      String timeForRow = '';
      // Find the time for this timestamp from any channel's data
      for (var channelKey in sortedChannelKeys) {
        final channelDataList = dataByChannel[channelKey];
        Map<String, dynamic> dataEntry = {};
        if (channelDataList != null) {
          dataEntry = channelDataList.firstWhere(
                (d) => (d['Timestamp'] as double?) == timestamp,
            orElse: () => <String, dynamic>{}, // Return empty map if not found
          );
        }
        if (dataEntry.isNotEmpty && dataEntry.containsKey('Time')) {
          timeForRow = dataEntry['Time'] as String? ?? '';
          if (timeForRow.isNotEmpty) break; // Found time, no need to check other channels
        }
      }

      final rowCells = headers.map((header) {
        if (header == 'Time') {
          return Padding(
            padding: const EdgeInsets.all(12.0),
            child: Text(
              timeForRow,
              style: GoogleFonts.roboto(
                color: i == timestamps.length - 1 // Highlight the last row
                    ? Colors.green // Green for latest time
                    : ThemeColors.getColor('serialPortInputText', isDarkMode),
                fontWeight: i == timestamps.length - 1
                    ? FontWeight.bold
                    : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          );
        }
        final channelKey = header; // header is the channel ID here
        final channelDataList = dataByChannel[channelKey];
        Map<String, dynamic> channelDataEntry =
        {}; // Default to empty map
        if (channelDataList != null) {
          channelDataEntry = channelDataList.firstWhere(
                (d) => (d['Timestamp'] as double?) == timestamp,
            orElse: () => <String, dynamic>{},
          );
        }

        String valueText = '';
        if (channelDataEntry.isNotEmpty &&
            channelDataEntry['Value'] != null &&
            channelConfigs[channelKey] != null) {
          final config = channelConfigs[channelKey]!;
          final value = channelDataEntry['Value'];
          if (value is num && value.isFinite) {
            valueText =
            '${(value as num).toStringAsFixed(config.decimalPlaces)}${config.unit}';
          }
        }

        return Padding(
            padding: const EdgeInsets.all(12.0),
            child: Text(
              valueText,
              style: GoogleFonts.roboto(
                color: i == timestamps.length - 1 && valueText.isNotEmpty
                    ? Colors.green // Green for latest channel value
                    : ThemeColors.getColor('serialPortInputText', isDarkMode),
                fontWeight: i == timestamps.length - 1 && valueText.isNotEmpty
                    ? FontWeight.bold
                    : FontWeight.normal,
                fontSize: 14,
              ),
            ));
      }).toList();

      tableRows.add(
        TableRow(
          decoration: BoxDecoration(
              color: i % 2 == 0
                  ? ThemeColors.getColor('serialPortTableRowEven', isDarkMode)
                  : ThemeColors.getColor('serialPortTableRowOdd', isDarkMode)),
          children: rowCells,
        ),
      );
    }
    return tableRows;
  }

  Widget _buildDataTable(bool isDarkMode) {
    return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: ThemeColors.getColor('serialPortCardBorder', isDarkMode)),
        ),
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
                    border: TableBorder.all(
                        color: ThemeColors.getColor(
                            'serialPortCardBorder', isDarkMode)),
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
                      icon: Icon(Icons.arrow_upward,
                          color: ThemeColors.getColor('sidebarIcon', isDarkMode)),
                      onPressed: () {
                        _tableScrollController.animateTo(0,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut);
                        print('[$_currentTime] SERIAL PORT SCREEN: Table scrolled to top.');
                      }),
                  IconButton(
                    icon: Icon(Icons.arrow_downward,
                        color: ThemeColors.getColor('sidebarIcon', isDarkMode)),
                    onPressed: () {
                      _tableScrollController.animateTo(
                        _tableScrollController.position.maxScrollExtent,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                      print('[$_currentTime] SERIAL PORT SCREEN: Table scrolled to latest data.');
                    },
                  ),
                ],
              ),
            ),
          ],
        ));
  }

  Widget _buildTimeInputField(
      TextEditingController controller, String label, bool isDarkMode,
      {bool compact = false, double width = 60}) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly
        ],
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
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 8, vertical: 8),
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
            if (mounted) {
              if (controller == _scanRateHrController ||
                  controller == _scanRateMinController ||
                  controller == _scanRateSecController) {
                print('[$_currentTime] SERIAL PORT SCREEN: Scan rate input changed. Value: "$value" for $label.');
                _updateScanInterval();
              } else if (controller == _graphVisibleHrController ||
                  controller == _graphVisibleMinController) {
                print('[$_currentTime] SERIAL PORT SCREEN: Graph visible area input changed. Value: "$value" for $label. Triggering UI rebuild.');
                setState(() {}); // Rebuild to update graph axis
              }
              if (controller == _fileNameController) {
                print('[$_currentTime] SERIAL PORT SCREEN: File Name input changed to: "${controller.text}"');
              } else if (controller == _operatorController) {
                print('[$_currentTime] SERIAL PORT SCREEN: Operator Name input changed to: "${controller.text}"');
              } else if (controller == _testDurationDayController ||
                  controller == _testDurationHrController ||
                  controller == _testDurationMinController ||
                  controller == _testDurationSecController) {
                print('[$_currentTime] SERIAL PORT SCREEN: Test Duration input changed. Value: "${controller.text}" for $label.');
              }
            }
          });
        },
      ),
    );
  }

  Widget _buildControlButton(
      String text, VoidCallback? onPressed, bool isDarkMode,
      {Color? color, bool? disabled}) {
    return ElevatedButton(
      onPressed: disabled == true ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor:
        color ?? ThemeColors.getColor('submitButton', isDarkMode),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        foregroundColor: Colors.white,
      ),
      child: Text(text,
          style: GoogleFonts.roboto(
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
            color: ThemeColors.getColor('buttonGradientStart', isDarkMode)
                .withOpacity(0.3),
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
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  void _showModeSelectionDialog(bool isDarkMode) {
    print('[$_currentTime] SERIAL PORT SCREEN: "Mode" button pressed. Displaying mode selection dialog.');
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
          title: Text('Select Display Mode',
              style: GoogleFonts.roboto(
                  color: ThemeColors.getColor('dialogText', isDarkMode))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                title: Text('Combined (Table & Graph)',
                    style: GoogleFonts.roboto(
                        color:
                        ThemeColors.getColor('dialogSubText', isDarkMode))),
                value: 'Combined',
                groupValue: Global.selectedMode.value,
                onChanged: (String? value) {
                  if (value != null) {
                    Global.selectedMode.value = value;
                    Navigator.of(dialogContext)
                        .pop(); // Close dialog on selection
                    print(
                        '[$_currentTime] SERIAL PORT SCREEN: Display mode changed to Combined.');
                  }
                },
                activeColor: ThemeColors.getColor('submitButton', isDarkMode),
              ),
              RadioListTile<String>(
                title: Text('Table Only',
                    style: GoogleFonts.roboto(
                        color:
                        ThemeColors.getColor('dialogSubText', isDarkMode))),
                value: 'Table',
                groupValue: Global.selectedMode.value,
                onChanged: (String? value) {
                  if (value != null) {
                    Global.selectedMode.value = value;
                    Navigator.of(dialogContext)
                        .pop(); // Close dialog on selection
                    print(
                        '[$_currentTime] SERIAL PORT SCREEN: Display mode changed to Table Only.');
                  }
                },
                activeColor: ThemeColors.getColor('submitButton', isDarkMode),
              ),
              RadioListTile<String>(
                title: Text('Graph Only',
                    style: GoogleFonts.roboto(
                        color:
                        ThemeColors.getColor('dialogSubText', isDarkMode))),
                value: 'Graph',
                groupValue: Global.selectedMode.value,
                onChanged: (String? value) {
                  if (value != null) {
                    Global.selectedMode.value = value;
                    Navigator.of(dialogContext)
                        .pop(); // Close dialog on selection
                    print(
                        '[$_currentTime] SERIAL PORT SCREEN: Display mode changed to Graph Only.');
                  }
                },
                activeColor: ThemeColors.getColor('submitButton', isDarkMode),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                print('[$_currentTime] SERIAL PORT SCREEN: Mode selection dialog closed.');
              },
              child: Text('Close',
                  style: GoogleFonts.roboto(
                      color: ThemeColors.getColor('submitButton', isDarkMode))),
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
                    color: ThemeColors.getColor(
                        'serialPortInputLabel', isDarkMode),
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor:
                  ThemeColors.getColor('serialPortInputFill', isDarkMode),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  isDense: true,
                ),
                style: GoogleFonts.roboto(
                  color:
                  ThemeColors.getColor('serialPortInputText', isDarkMode),
                  fontSize: 14,
                ),
                onChanged: (val) {
                  // Logging handled by _buildTimeInputField debounce
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: _operatorController,
                decoration: InputDecoration(
                  labelText: 'Operator',
                  labelStyle: GoogleFonts.roboto(
                    color: ThemeColors.getColor(
                        'serialPortInputLabel', isDarkMode),
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor:
                  ThemeColors.getColor('serialPortInputFill', isDarkMode),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  isDense: true,
                ),
                style: GoogleFonts.roboto(
                  color:
                  ThemeColors.getColor('serialPortInputText', isDarkMode),
                  fontSize: 14,
                ),
                onChanged: (val) {
                  // Logging handled by _buildTimeInputField debounce
                },
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
                  _buildTimeInputField(_scanRateHrController, 'Hr', isDarkMode,
                      compact: true, width: 45),
                  const SizedBox(width: 2),
                  _buildTimeInputField(
                      _scanRateMinController, 'Min', isDarkMode,
                      compact: true, width: 45),
                  const SizedBox(width: 2),
                  _buildTimeInputField(
                      _scanRateSecController, 'Sec', isDarkMode,
                      compact: true, width: 45),
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
                  _buildTimeInputField(
                      _testDurationDayController, 'Day', isDarkMode,
                      compact: true, width: 45),
                  const SizedBox(width: 2),
                  _buildTimeInputField(
                      _testDurationHrController, 'Hr', isDarkMode,
                      compact: true, width: 45),
                  const SizedBox(width: 2),
                  _buildTimeInputField(
                      _testDurationMinController, 'Min', isDarkMode,
                      compact: true, width: 45),
                  const SizedBox(width: 2),
                  _buildTimeInputField(
                      _testDurationSecController, 'Sec', isDarkMode,
                      compact: true, width: 45),
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
        color: isScanning
            ? ThemeColors.getColor('submitButton', isDarkMode).withOpacity(0.1)
            : ThemeColors.getColor(
            'serialPortMessagePanelBackground', isDarkMode),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isScanning
                ? ThemeColors.getColor('submitButton', isDarkMode)
                .withOpacity(0.5)
                : ThemeColors.getColor('serialPortCardBorder', isDarkMode)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              _buildControlButton('Start Scan', _startScan, isDarkMode,
                  disabled: isScanning),
              _buildControlButton('Stop Scan', _stopScan, isDarkMode,
                  color: Colors.orange[700], disabled: !isScanning),
              _buildControlButton('Cancel Scan', _cancelScan, isDarkMode,
                  color: ThemeColors.getColor('resetButton', isDarkMode)),
              _buildControlButton(
                  'Save Data', () => _saveData(isDarkMode), isDarkMode,
                  color: Colors.green[700]),
              _buildControlButton('Mode',
                      () => _showModeSelectionDialog(isDarkMode), isDarkMode,
                  color: Colors.purple[700]),
              if (isCancelled) // Only show Exit button after scan is cancelled
                _buildControlButton('Exit', () {
                  print('[$_currentTime] SERIAL PORT SCREEN: "Exit" button pressed. Navigating to HomePage.');
                  Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const HomePage()));
                }, isDarkMode,
                    color: ThemeColors.getColor('cardText',
                        isDarkMode)), // Using cardText for a neutral exit button
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment
                .bottomCenter, // Align content to the bottom center
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
                              ThemeColors.getColor(
                                  'submitButton', isDarkMode))),
                    ),
                  ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      portMessage,
                      if (!isCancelled) // Inform user about Exit button visibility
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            "The 'Exit' button will appear after cancelling the scan.",
                            style: GoogleFonts.roboto(
                                color: ThemeColors.getColor('dialogSubText',
                                    isDarkMode),
                                fontSize: 12,
                                fontStyle: FontStyle.italic),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (errors.isNotEmpty) // Display specific errors if present
                        Builder(
                          builder: (context) {
                            String messageToDisplay = '';
                            // Filter out "Scanning active" or "Reconnected" messages from general errors list
                            List<String> actualErrors = errors
                                .where((e) =>
                            !e.contains('Scanning active') &&
                                !e.contains('Reconnected'))
                                .toList();

                            if (actualErrors.isNotEmpty) {
                              messageToDisplay = actualErrors.last;
                            }
                            return Text(
                              messageToDisplay,
                              style: GoogleFonts.roboto(
                                  color: messageToDisplay.contains('Error') ||
                                      messageToDisplay.contains('failed') ||
                                      messageToDisplay
                                          .contains('disconnected')
                                      ? ThemeColors.getColor(
                                      'serialPortErrorTextSmall',
                                      isDarkMode)
                                      : ThemeColors.getColor(
                                      'serialPortMessageText',
                                      isDarkMode),
                                  fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1, // Keep error messages concise
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
      crossAxisAlignment:
      CrossAxisAlignment.stretch, // Make children stretch horizontally
      children: [
        Flexible(
          flex: 2, // Allocate 2 parts of space for input
          child: Card(
            elevation: 0,
            color: ThemeColors.getColor('serialPortCardBackground', isDarkMode),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                    color: ThemeColors.getColor(
                        'serialPortCardBorder', isDarkMode))),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: _buildFullInputSectionContent(
                  isDarkMode), // Full input fields
            ),
          ),
        ),
        const SizedBox(height: 16),

        Expanded(
          flex: 6, // Allocate 6 parts for table
          child: Card(
            elevation: 0,
            color: ThemeColors.getColor('serialPortCardBackground', isDarkMode),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                    color: ThemeColors.getColor(
                        'serialPortCardBorder', isDarkMode))),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: _buildDataTable(
                  isDarkMode), // Table showing live data
            ),
          ),
        ),
        const SizedBox(height: 16),

        Flexible(
          flex: 2, // Allocate 2 parts for control buttons
          child: _buildBottomSectionContent(
              isDarkMode), // Control buttons and status
        ),
      ],
    );
  }

  Widget _buildRightSection(bool isDarkMode) {
    final isCompact = MediaQuery.of(context).size.width < 600;

    Widget graphControlBar = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Segment:',
                  style: GoogleFonts.roboto(
                      color: ThemeColors.getColor('dialogText', isDarkMode),
                      fontWeight: FontWeight.w500,
                      fontSize: 13)),
              const SizedBox(width: 4),
              _buildTimeInputField(_graphVisibleHrController, 'Hr', isDarkMode,
                  compact: true, width: 45),
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
              color: ThemeColors.getColor(
                  'serialPortDropdownBackground', isDarkMode),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                    color:
                    ThemeColors.getColor('serialPortCardBorder', isDarkMode)
                        .withOpacity(0.5),
                    blurRadius: 5)
              ],
            ),
            child: DropdownButton<String?>(
              value: _selectedGraphChannel,
              hint: Text('All Channels',
                  style: GoogleFonts.roboto(
                      color: ThemeColors.getColor(
                          'serialPortDropdownText', isDarkMode))),
              onChanged: (String? newValue) {
                if (mounted) {
                  setState(() {
                    _selectedGraphChannel = newValue;
                    print('[$_currentTime] SERIAL PORT SCREEN: Graph channel filter changed to: ${newValue ?? "All Channels"}.');
                  });
                }
              },
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All Channels',
                      style: GoogleFonts.roboto(
                          color: ThemeColors.getColor(
                              'serialPortDropdownText', isDarkMode))),
                ),
                ...channelConfigs.keys
                    .map((channelId) => DropdownMenuItem<String>(
                  value: channelId,
                  child: Text(
                    'Channel ${channelConfigs[channelId]!.channelName}',
                    style: GoogleFonts.roboto(
                        color: ThemeColors.getColor(
                            'serialPortDropdownText', isDarkMode)),
                  ),
                )),
              ],
              underline: Container(), // Remove default underline
              icon: Icon(Icons.arrow_drop_down,
                  color: ThemeColors.getColor(
                      'serialPortDropdownIcon', isDarkMode)),
              dropdownColor: ThemeColors.getColor(
                  'serialPortDropdownBackground',
                  isDarkMode), // Dropdown background color
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Show Dots:',
                style: GoogleFonts.roboto(
                  color: ThemeColors.getColor('dialogText', isDarkMode),
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              Switch(
                value: _showGraphDots,
                onChanged: (bool value) {
                  if (mounted) {
                    setState(() {
                      _showGraphDots = value;
                      print('[$_currentTime] SERIAL PORT SCREEN: Graph "Show Dots" toggled to: $value.');
                    });
                  }
                },
                activeColor: ThemeColors.getColor('submitButton', isDarkMode),
                inactiveThumbColor:
                ThemeColors.getColor('resetButton', isDarkMode),
                inactiveTrackColor:
                ThemeColors.getColor('secondaryButton', isDarkMode)
                    .withOpacity(0.3),
              ),
            ],
          ),
          const SizedBox(width: 8),
          _buildStyledAddButton(isDarkMode),
        ],
      ),
    );

    Widget graphView = Expanded(
      child: Card(
        elevation: 0,
        color: ThemeColors.getColor('serialPortCardBackground', isDarkMode),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
                color:
                ThemeColors.getColor('serialPortCardBorder', isDarkMode))),
        child: Padding(
            padding: EdgeInsets.all(isCompact ? 8.0 : 16.0),
            child: _buildGraph(isDarkMode)),
      ),
    );

    return ValueListenableBuilder<String>(
      valueListenable: Global.selectedMode,
      builder: (context, mode, _) {
        final selectedMode = mode ?? 'Graph'; // Default to Graph if null
        // print('[$_currentTime] SERIAL PORT SCREEN: Building right section. Current display mode: $selectedMode.');

        if (selectedMode == 'Graph') {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 0,
                color: ThemeColors.getColor(
                    'serialPortCardBackground', isDarkMode),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                        color: ThemeColors.getColor(
                            'serialPortCardBorder', isDarkMode))),
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
                                labelStyle: GoogleFonts.roboto(
                                    color: ThemeColors.getColor(
                                        'serialPortInputLabel', isDarkMode),
                                    fontSize: 13),
                                filled: true,
                                fillColor: ThemeColors.getColor(
                                    'serialPortInputFill', isDarkMode),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide.none),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: isCompact ? 8 : 10),
                                isDense: true,
                              ),
                              style: GoogleFonts.roboto(
                                  color: ThemeColors.getColor(
                                      'serialPortInputText', isDarkMode),
                                  fontSize: 14),
                              onChanged: (val) {}, // Logging already handled
                            )),
                        const SizedBox(width: 8),
                        SizedBox(
                            width: isCompact ? 100 : 120,
                            child: TextField(
                              controller: _operatorController,
                              decoration: InputDecoration(
                                labelText: 'Operator',
                                labelStyle: GoogleFonts.roboto(
                                    color: ThemeColors.getColor(
                                        'serialPortInputLabel', isDarkMode),
                                    fontSize: 13),
                                filled: true,
                                fillColor: ThemeColors.getColor(
                                    'serialPortInputFill', isDarkMode),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide.none),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: isCompact ? 8 : 10),
                                isDense: true,
                              ),
                              style: GoogleFonts.roboto(
                                  color: ThemeColors.getColor(
                                      'serialPortInputText', isDarkMode),
                                  fontSize: 14),
                              onChanged: (val) {}, // Logging already handled
                            )),
                        const SizedBox(width: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Scan Rate:',
                                style: GoogleFonts.roboto(
                                    color: ThemeColors.getColor(
                                        'dialogText', isDarkMode),
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13)),
                            const SizedBox(width: 4),
                            _buildTimeInputField(
                                _scanRateHrController, 'Hr', isDarkMode,
                                compact: true, width: 45),
                            const SizedBox(width: 4),
                            _buildTimeInputField(
                                _scanRateMinController, 'Min', isDarkMode,
                                compact: true, width: 45),
                            const SizedBox(width: 4),
                            _buildTimeInputField(
                                _scanRateSecController, 'Sec', isDarkMode,
                                compact: true, width: 45),
                          ],
                        ),
                        const SizedBox(width: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Test Duration:',
                                style: GoogleFonts.roboto(
                                    color: ThemeColors.getColor(
                                        'dialogText', isDarkMode),
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13)),
                            const SizedBox(width: 4),
                            _buildTimeInputField(
                                _testDurationDayController, 'Day', isDarkMode,
                                compact: true, width: 45),
                            const SizedBox(width: 4),
                            _buildTimeInputField(
                                _testDurationHrController, 'Hr', isDarkMode,
                                compact: true, width: 45),
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
                        graphControlBar,
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              graphView,
              const SizedBox(height: 16),
              _buildBottomSectionContent(isDarkMode),
            ],
          );
        } else if (selectedMode == 'Combined') {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 0,
                color: ThemeColors.getColor(
                    'serialPortCardBackground', isDarkMode),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                        color: ThemeColors.getColor(
                            'serialPortCardBorder', isDarkMode))),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child:
                  graphControlBar, // Graph controls only for combined mode
                ),
              ),
              const SizedBox(height: 16),
              graphView,
            ],
          );
        } else {
          return const SizedBox
              .shrink(); // Right section is empty in 'Table Only' mode
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _scaffoldMessengerKey, // Attach ScaffoldMessenger to handle snackbars
      child: Scaffold(
        backgroundColor: ThemeColors.getColor(
            'serialPortBackground', Global.isDarkMode.value),
        body: SafeArea(
          child: ValueListenableBuilder<String>(
            valueListenable: Global.selectedMode,
            builder: (context, mode, _) {
              final isDarkMode = Global.isDarkMode.value;
              final selectedMode =
                  mode ?? 'Graph'; // Default to 'Graph' if mode is null
              // print('[$_currentTime] SERIAL PORT SCREEN: Building main layout for mode: $selectedMode.');

              if (selectedMode == 'Table') {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildLeftSection(
                      isDarkMode), // Only left section for 'Table Only'
                );
              } else if (selectedMode == 'Graph') {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildRightSection(
                      isDarkMode), // Only right section for 'Graph Only'
                );
              } else {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment
                        .stretch, // Make columns stretch vertically
                    children: [
                      Expanded(
                          flex: 1, // Equal width for both sections
                          child: _buildLeftSection(
                              isDarkMode)), // Left section (input, table, controls)
                      const SizedBox(width: 16),
                      Expanded(
                          flex: 1,
                          child: _buildRightSection(
                              isDarkMode)), // Right section (graph, its controls)
                    ],
                  ),
                );
              }
            },
          ),
        ),
      ),
    );
  }

  @override
  Future<void> dispose() async {
    print('[$_currentTime] SERIAL PORT SCREEN: Dispose method called. Cleaning up resources.');

    // Remove any active overlay windows
    for (var entry in _windowEntries) {
      entry.remove();
      print('[$_currentTime] SERIAL PORT SCREEN: Removed floating graph window overlay entry.');
    }
    _windowEntries.clear();

    // Dispose controllers
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
    print('[$_currentTime] SERIAL PORT SCREEN: All TextEditingControllers and ScrollControllers disposed.');

    // Cancel subscriptions and close readers
    if (_readerSubscription != null) {
      await _readerSubscription!.cancel();
      _readerSubscription = null;
      print('[$_currentTime] SERIAL PORT SCREEN: SerialPortReader subscription cancelled.');
    }
    if (reader != null) {
      reader!.close();
      reader = null;
      print('[$_currentTime] SERIAL PORT SCREEN: SerialPortReader closed.');
    }

    // Close and dispose serial port
    if (port != null) {
      try {
        if (port!.isOpen) {
          port!.close();
          print('[$_currentTime] SERIAL PORT SCREEN: Serial port $_portName closed during dispose.');
        }
        await Future.delayed(const Duration(milliseconds: 100)); // Give a brief moment for port to truly close
        port!.dispose();
        print('[$_currentTime] SERIAL PORT SCREEN: Serial port $_portName disposed.');
      } catch (e) {
        print('[$_currentTime] SERIAL PORT SCREEN: Error during serial port cleanup in dispose: $e');
      } finally {
        port = null;
      }
    }

    // Cancel timers
    _reconnectTimer?.cancel();
    _testDurationTimer?.cancel();
    _tableUpdateTimer?.cancel();
    _debounceTimer?.cancel();
    print('[$_currentTime] SERIAL PORT SCREEN: All active timers cancelled.');

    await Future(() => super.dispose());
    print('[$_currentTime] SERIAL PORT SCREEN: Serial Port Screen disposal completed.');
  }
}
