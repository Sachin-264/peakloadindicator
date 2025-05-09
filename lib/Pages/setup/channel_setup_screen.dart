import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:libserialport/libserialport.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../constants/colors.dart';
import '../../constants/global.dart';
import 'edit_channel_screen.dart';

class ChannelSetupScreen extends StatefulWidget {
  const ChannelSetupScreen({super.key});

  @override
  _ChannelSetupScreenState createState() => _ChannelSetupScreenState();
}

class _ChannelSetupScreenState extends State<ChannelSetupScreen> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> channels = [];
  List<String> ports = [];
  bool isLoading = true;
  String? errorMessage;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Database _database;
  final Set<int> _selectedRecNos = {};
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  final TextEditingController _scanTimeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _initDatabase();
    _loadSavedPortDetails();
    _fetchPorts();
  }

  Future<void> _initDatabase() async {
    try {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final databasesPath = await getDatabasesPath();
      final dbPath = path.join(databasesPath, 'Countronics.db');
      _database = await openDatabase(dbPath);
      fetchChannels();
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = 'Error initializing database: $e';
      });
      print('Error initializing database: $e');
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scanTimeController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedPortDetails() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      Global.selectedPort.value = prefs.getString('selectedPort') ?? 'No Ports Detected';
      Global.baudRate.value = prefs.getInt('baudRate') ?? 9600;
      Global.dataBits.value = prefs.getInt('dataBits') ?? 8;
      Global.parity.value = prefs.getString('parity') ?? 'None';
      Global.stopBits.value = prefs.getInt('stopBits') ?? 1;
      print('Loaded port details: Port=${Global.selectedPort.value}, Baud=${Global.baudRate.value}, '
          'DataBits=${Global.dataBits.value}, Parity=${Global.parity.value}, StopBits=${Global.stopBits.value}');
    });
  }

  Future<void> _savePortDetails(String port, int baudRate, int dataBits, String parity, int stopBits) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedPort', port);
    await prefs.setInt('baudRate', baudRate);
    await prefs.setInt('dataBits', dataBits);
    await prefs.setString('parity', parity);
    await prefs.setInt('stopBits', stopBits);
    print('Saved port details: Port=$port, Baud=$baudRate, DataBits=$dataBits, Parity=$parity, StopBits=$stopBits');
  }

  Future<void> _fetchPorts() async {
    try {
      final availablePorts = SerialPort.availablePorts;
      List<String> portDetails = [];

      if (availablePorts.isNotEmpty) {
        for (final portName in availablePorts) {
          final port = SerialPort(portName);
          if (port.openReadWrite()) {
            final config = port.config;
            final baudRate = config.baudRate;
            final dataBits = config.bits;
            final stopBits = config.stopBits;
            final parity = config.parity;

            String parityString;
            switch (parity) {
              case SerialPortParity.none:
                parityString = "None";
                break;
              case SerialPortParity.even:
                parityString = "Even";
                break;
              case SerialPortParity.odd:
                parityString = "Odd";
                break;
              default:
                parityString = "Unknown";
            }

            portDetails.add(
                '$portName → Baud: $baudRate, Data Bits: $dataBits, Parity: $parityString, Stop Bits: $stopBits');

            if (Global.selectedPort.value == portName || Global.selectedPort.value == 'No Ports Detected') {
              Global.baudRate.value = baudRate;
              Global.dataBits.value = dataBits;
              Global.parity.value = parityString;
              Global.stopBits.value = stopBits;
              _savePortDetails(portName, baudRate, dataBits, parityString, stopBits);
            }

            port.close();
          } else {
            portDetails.add('$portName → (Could not open port)');
          }
        }

        setState(() {
          ports = portDetails;
          if (Global.selectedPort.value == 'No Ports Detected' && portDetails.isNotEmpty) {
            Global.selectedPort.value = portDetails[0];
          }
        });
      } else {
        setState(() {
          ports = ['No Ports Detected'];
          Global.selectedPort.value = 'No Ports Detected';
          _savePortDetails('No Ports Detected', 9600, 8, 'None', 1);
        });
      }

      _animationController.forward();
    } catch (e) {
      setState(() {
        ports = ['Error Fetching Ports'];
        Global.selectedPort.value = 'Error Fetching Ports';
        _savePortDetails('Error Fetching Ports', 9600, 8, 'None', 1);
      });
    }
  }

  Future<void> fetchChannels() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final data = await _database.query('ChannelSetup');
      final selectedData = await _database.query('SelectChannel');
      final selectedRecNos = selectedData.map((item) => (item['RecNo'] as num).toInt()).toSet();

      setState(() {
        channels = data;
        _selectedRecNos.clear();
        _selectedRecNos.addAll(selectedRecNos);
        isLoading = false;
      });
      _animationController.forward();
    } catch (e) {
      setState(() {
        errorMessage = 'Error fetching channels: $e';
        isLoading = false;
      });
      print('Error fetching channels: $e');
    }
  }

  Future<void> deleteChannel(int recNo) async {
    try {
      print('Deleting channel with RecNo: $recNo');
      await _database.delete('ChannelSetup', where: 'RecNo = ?', whereArgs: [recNo]);
      await _database.delete('SelectChannel', where: 'RecNo = ?', whereArgs: [recNo]);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Channel deleted successfully', style: GoogleFonts.poppins(fontSize: 14)),
          backgroundColor: AppColors.submitButton,
        ),
      );
      fetchChannels();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting channel: $e', style: GoogleFonts.poppins(fontSize: 14)),
          backgroundColor: AppColors.errorText,
        ),
      );
    }
  }

  Future<void> _saveSelectedChannels() async {
    try {
      await _database.delete('SelectChannel');
      for (int recNo in _selectedRecNos) {
        final channel = channels.firstWhere((c) => (c['RecNo'] as num).toInt() == recNo);
        await _database.insert('SelectChannel', {
          'RecNo': recNo,
          'ChannelName': channel['ChannelName'],
          'StartingCharacter': channel['StartingCharacter'],
          'DataLength': channel['DataLength'],
          'Unit': channel['Unit'],
          'DecimalPlaces': channel['DecimalPlaces'],
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Selected channels saved: ${_selectedRecNos.length}',
            style: GoogleFonts.poppins(fontSize: 14),
          ),
          backgroundColor: AppColors.submitButton,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving channels: $e', style: GoogleFonts.poppins(fontSize: 14)),
          backgroundColor: AppColors.errorText,
        ),
      );
    }
  }

  Future<void> _cancelSelection() async {
    try {
      await _database.delete('SelectChannel');
      setState(() {
        _selectedRecNos.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Selections cleared', style: GoogleFonts.poppins(fontSize: 14)),
          backgroundColor: AppColors.submitButton,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error clearing selections: $e', style: GoogleFonts.poppins(fontSize: 14)),
          backgroundColor: AppColors.errorText,
        ),
      );
    }
  }

  Future<bool> _showPasswordDialog() async {
    String password = '';
    const correctPassword = 'admin123';
    bool isPasswordCorrect = false;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Enter Password', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          content: TextField(
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Password',
              labelStyle: GoogleFonts.poppins(),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (value) {
              password = value;
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel', style: GoogleFonts.poppins()),
            ),
            TextButton(
              onPressed: () {
                if (password == correctPassword) {
                  isPasswordCorrect = true;
                  Navigator.of(context).pop();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Incorrect password', style: GoogleFonts.poppins()),
                      backgroundColor: AppColors.errorText,
                    ),
                  );
                }
              },
              child: Text('Submit', style: GoogleFonts.poppins()),
            ),
          ],
        );
      },
    );

    return isPasswordCorrect;
  }

  Future<void> _showAutoStartDialog() async {
    // Fetch saved AutoStart settings
    TimeOfDay? dialogStartTime = _startTime;
    TimeOfDay? dialogEndTime = _endTime;
    final dialogScanTimeController = TextEditingController(text: _scanTimeController.text);

    try {
      final autoStartData = await _database.query('AutoStart', limit: 1);
      if (autoStartData.isNotEmpty) {
        final autoStart = autoStartData.first;
        dialogStartTime = TimeOfDay(
          hour: autoStart['StartTimeHr'] as int? ?? 0,
          minute: autoStart['StartTimeMin'] as int? ?? 0,
        );
        dialogEndTime = TimeOfDay(
          hour: autoStart['EndTimeHr'] as int? ?? 0,
          minute: autoStart['EndTimeMin'] as int? ?? 0,
        );
        dialogScanTimeController.text = (autoStart['ScanTimeSec'] as int? ?? '').toString();
      }
    } catch (e) {
      print('Error loading AutoStart settings: $e');
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.transparent,
          contentPadding: EdgeInsets.zero,
          content: Card(
            color: Colors.white,
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Configure AutoStart',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Start Time',
                      style: GoogleFonts.poppins(fontSize: 16, color: AppColors.textPrimary),
                    ),
                    subtitle: Text(
                      dialogStartTime != null ? dialogStartTime!.format(context) : 'Select time',
                      style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary.withOpacity(0.7)),
                    ),
                    onTap: () async {
                      final selectedTime = await showTimePicker(
                        context: context,
                        initialTime: dialogStartTime ?? TimeOfDay.now(),
                        builder: (context, child) {
                          return Theme(
                            data: ThemeData.light().copyWith(
                              colorScheme: ColorScheme.light(
                                primary: AppColors.submitButton,
                                onPrimary: Colors.white,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (selectedTime != null) {
                        setDialogState(() {
                          dialogStartTime = selectedTime;
                        });
                      }
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'End Time',
                      style: GoogleFonts.poppins(fontSize: 16, color: AppColors.textPrimary),
                    ),
                    subtitle: Text(
                      dialogEndTime != null ? dialogEndTime!.format(context) : 'Select time',
                      style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary.withOpacity(0.7)),
                    ),
                    onTap: () async {
                      final selectedTime = await showTimePicker(
                        context: context,
                        initialTime: dialogEndTime ?? TimeOfDay.now(),
                        builder: (context, child) {
                          return Theme(
                            data: ThemeData.light().copyWith(
                              colorScheme: ColorScheme.light(
                                primary: AppColors.submitButton,
                                onPrimary: Colors.white,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (selectedTime != null) {
                        setDialogState(() {
                          dialogEndTime = selectedTime;
                        });
                      }
                    },
                  ),
                  TextField(
                    controller: dialogScanTimeController,
                    decoration: InputDecoration(
                      labelText: 'Scan Time (seconds)',
                      labelStyle: GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.textPrimary.withOpacity(0.5)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.submitButton),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      if (value.isNotEmpty && !RegExp(r'^\d+$').hasMatch(value)) {
                        dialogScanTimeController.text = value.replaceAll(RegExp(r'[^\d]'), '');
                        dialogScanTimeController.selection = TextSelection.fromPosition(
                          TextPosition(offset: dialogScanTimeController.text.length),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                'Cancel',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: AppColors.resetButton,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (dialogStartTime != null && dialogEndTime != null && dialogScanTimeController.text.isNotEmpty) {
                  final scanTime = int.tryParse(dialogScanTimeController.text);
                  if (scanTime == null || scanTime <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Please enter a valid positive scan time', style: GoogleFonts.poppins(fontSize: 14)),
                        backgroundColor: AppColors.errorText,
                      ),
                    );
                    return;
                  }
                  try {
                    await _database.delete('AutoStart');
                    await _database.insert('AutoStart', {
                      'StartTimeHr': dialogStartTime!.hour,
                      'StartTimeMin': dialogStartTime!.minute,
                      'EndTimeHr': dialogEndTime!.hour,
                      'EndTimeMin': dialogEndTime!.minute,
                      'ScanTimeSec': scanTime,
                    });
                    setState(() {
                      _startTime = dialogStartTime;
                      _endTime = dialogEndTime;
                      _scanTimeController.text = dialogScanTimeController.text;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('AutoStart settings saved', style: GoogleFonts.poppins(fontSize: 14)),
                        backgroundColor: AppColors.submitButton,
                      ),
                    );
                    Navigator.of(context).pop();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error saving AutoStart settings: $e', style: GoogleFonts.poppins(fontSize: 14)),
                        backgroundColor: AppColors.errorText,
                      ),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Please fill all fields', style: GoogleFonts.poppins(fontSize: 14)),
                      backgroundColor: AppColors.errorText,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.submitButton,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: Text(
                'Save',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.headerBackground, AppColors.headerBackground.withOpacity(0.9)],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Checkbox(
              value: channels.isNotEmpty && _selectedRecNos.length == channels.length,
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _selectedRecNos.clear();
                    _selectedRecNos.addAll(channels.map((c) => (c['RecNo'] as num).toInt()));
                  } else {
                    _selectedRecNos.clear();
                  }
                });
              },
              activeColor: AppColors.submitButton,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              'S.No',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Colors.black,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Channel',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Colors.black,
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              'Unit',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Colors.black,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              'Start Char',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Colors.black,
              ),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              'Actions',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(Map<String, dynamic> channel, int index) {
    final recNo = (channel['RecNo'] as num).toInt();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: _selectedRecNos.contains(recNo)
            ? AppColors.selectedRow.withOpacity(0.3)
            : AppColors.cardBackground,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Checkbox(
              value: _selectedRecNos.contains(recNo),
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _selectedRecNos.add(recNo);
                  } else {
                    _selectedRecNos.remove(recNo);
                  }
                });
              },
              activeColor: AppColors.submitButton,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              '$recNo',
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textPrimary),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              channel['ChannelName'] ?? '',
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textPrimary),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              channel['Unit'] ?? '',
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textPrimary),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              channel['StartingCharacter'] ?? '',
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textPrimary),
            ),
          ),
          SizedBox(
            width: 80,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: AppColors.submitButton, size: 20),
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EditChannelScreen(channel: channel),
                      ),
                    );
                    if (result == true) {
                      fetchChannels();
                    }
                  },
                  tooltip: 'Edit Channel',
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: AppColors.resetButton, size: 20),
                  onPressed: () => deleteChannel(recNo),
                  tooltip: 'Delete Channel',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select Port',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 1,
                    color: AppColors.cardBackground,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.15)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: ValueListenableBuilder<String>(
                              valueListenable: Global.selectedPort,
                              builder: (context, selectedPort, _) {
                                return DropdownButtonFormField<String>(
                                  value: ports.contains(selectedPort)
                                      ? selectedPort
                                      : ports.isNotEmpty
                                      ? ports[0]
                                      : null,
                                  decoration: InputDecoration(
                                    labelText: 'Port',
                                    labelStyle: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: AppColors.textPrimary.withOpacity(0.8),
                                    ),
                                    filled: true,
                                    fillColor: Colors.white.withOpacity(0.1),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: AppColors.textPrimary.withOpacity(0.5),
                                        width: 1,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: AppColors.textPrimary.withOpacity(0.5),
                                        width: 1,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: AppColors.submitButton,
                                        width: 1.5,
                                      ),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    prefixIcon: Icon(
                                      Icons.usb,
                                      size: 20,
                                      color: AppColors.textPrimary.withOpacity(0.8),
                                    ),
                                  ),
                                  style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary),
                                  dropdownColor: AppColors.cardBackground,
                                  items: ports.map((port) {
                                    return DropdownMenuItem<String>(
                                      value: port,
                                      child: Text(port, style: GoogleFonts.poppins(fontSize: 14)),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value != null) {
                                      Global.selectedPort.value = value;
                                      final portName = value.split(' → ')[0];
                                      final details = value.split(' → ')[1];
                                      final baudRate = int.parse(details.split(', ')[0].split(': ')[1]);
                                      final dataBits = int.parse(details.split(', ')[1].split(': ')[1]);
                                      final parity = details.split(', ')[2].split(': ')[1];
                                      final stopBits = int.parse(details.split(', ')[3].split(': ')[1]);
                                      Global.baudRate.value = baudRate;
                                      Global.dataBits.value = dataBits;
                                      Global.parity.value = parity;
                                      Global.stopBits.value = stopBits;
                                      _savePortDetails(portName, baudRate, dataBits, parity, stopBits);
                                    }
                                  },
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          InkWell(
                            onTap: _fetchPorts,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.submitButton,
                                    AppColors.submitButton.withOpacity(0.9),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.refresh,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'AutoStart Configuration',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 1,
                    color: AppColors.cardBackground,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: InkWell(
                      onTap: _showAutoStartDialog,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.timer, color: AppColors.submitButton),
                            const SizedBox(width: 12),
                            Text(
                              'Configure AutoStart Settings',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Channels',
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: AppColors.submitButton, size: 30),
                        onPressed: () async {
                          final isAuthorized = await _showPasswordDialog();
                          if (isAuthorized) {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const EditChannelScreen()),
                            );
                            if (result == true) {
                              fetchChannels();
                            }
                          }
                        },
                        tooltip: 'Add Channel',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 1,
                    color: AppColors.cardBackground,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.15)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      height: 400,
                      child: isLoading
                          ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.submitButton,
                          strokeWidth: 2,
                        ),
                      )
                          : errorMessage != null
                          ? Center(
                        child: Text(
                          errorMessage!,
                          style: GoogleFonts.poppins(
                            color: AppColors.errorText,
                            fontSize: 14,
                          ),
                        ),
                      )
                          : channels.isEmpty
                          ? Center(
                        child: Text(
                          'No channels found',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      )
                          : Scrollbar(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SizedBox(
                            width: MediaQuery.of(context).size.width - 32,
                            child: Column(
                              children: [
                                _buildTableHeader(),
                                ...channels.asMap().entries.map((entry) {
                                  return _buildTableRow(entry.value, entry.key);
                                }),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: _cancelSelection,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.resetButton,
                                AppColors.resetButton.withOpacity(0.9),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.resetButton.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Text(
                            'Reset',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _saveSelectedChannels,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.submitButton,
                                AppColors.submitButton.withOpacity(0.9),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.submitButton.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Text(
                            'Submit',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}