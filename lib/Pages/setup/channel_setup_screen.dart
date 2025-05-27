import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:libserialport/libserialport.dart';
// import 'package:shared_preferences/shared_preferences.dart'; // REMOVED: No longer needed for port settings
import 'package:sqflite_common_ffi/sqflite_ffi.dart'; // Keep for general database usage
import '../../constants/colors.dart'; // Ensure this path is correct
import '../../constants/database_manager.dart'; // Ensure this path is correct
import '../../constants/global.dart'; // Ensure this path is correct
import '../../constants/theme.dart'; // Ensure this path is correct
import 'AuthSettingScreen.dart';
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
  late Animation<double> _scaleAnimation;
  final Set<int> _selectedRecNos = {};
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  final TextEditingController _scanTimeController = TextEditingController();
  bool _isDropdownHovered = false;
  bool _isRowHovered = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _loadSavedPortDetails(); // This now uses DatabaseManager
    _fetchPorts();
    fetchChannels();
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scanTimeController.dispose();
    super.dispose();
  }

  // MODIFIED: Load port details from DatabaseManager
  Future<void> _loadSavedPortDetails() async {
    final savedSettings = await DatabaseManager().getComPortSettings();
    setState(() {
      Global.selectedPort.value = savedSettings?['selectedPort'] ?? 'No Ports Detected';
      Global.baudRate.value = savedSettings?['baudRate'] ?? 9600;
      Global.dataBits.value = savedSettings?['dataBits'] ?? 8;
      Global.parity.value = savedSettings?['parity'] ?? 'None';
      Global.stopBits.value = savedSettings?['stopBits'] ?? 1;
    });
  }

  // MODIFIED: Save port details to DatabaseManager
  Future<void> _savePortDetails(String port, int baudRate, int dataBits, String parity, int stopBits) async {
    await DatabaseManager().saveComPortSettings(port, baudRate, dataBits, parity, stopBits);
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

            portDetails.add('$portName → Baud: $baudRate, Data Bits: $dataBits, Parity: $parityString, Stop Bits: $stopBits');

            // If the previously selected port is found, update Global values
            // Or if no port was previously selected, and this is the first available port
            if (Global.selectedPort.value.startsWith(portName) || Global.selectedPort.value == 'No Ports Detected' || Global.selectedPort.value == 'Error Fetching Ports') {
              Global.selectedPort.value = '$portName → Baud: $baudRate, Data Bits: $dataBits, Parity: $parityString, Stop Bits: $stopBits';
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
          // If no port was selected or an error occurred, and ports are now detected, default to the first one
          if ((Global.selectedPort.value == 'No Ports Detected' || Global.selectedPort.value == 'Error Fetching Ports') && portDetails.isNotEmpty) {
            final firstPortInfo = portDetails[0];
            Global.selectedPort.value = firstPortInfo;
            final portName = firstPortInfo.split(' → ')[0];
            final details = firstPortInfo.split(' → ')[1];
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
          // Ensure Global.selectedPort is still one of the actual ports, or null if none
          if (!ports.contains(Global.selectedPort.value) && ports.isNotEmpty) {
            Global.selectedPort.value = ports[0];
          } else if (ports.isEmpty) {
            Global.selectedPort.value = 'No Ports Detected';
          }
        });
      } else {
        setState(() {
          ports = ['No Ports Detected'];
          Global.selectedPort.value = 'No Ports Detected';
          _savePortDetails('No Ports Detected', 9600, 8, 'None', 1); // Save default if no ports found
        });
      }
    } catch (e) {
      setState(() {
        ports = ['Error Fetching Ports'];
        Global.selectedPort.value = 'Error Fetching Ports';
        _savePortDetails('Error Fetching Ports', 9600, 8, 'None', 1); // Save error state default
      });
      print('Error fetching ports: $e'); // Log the actual error
    }
  }


  Future<void> fetchChannels() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final db = await DatabaseManager().database;
      final data = await db.query('ChannelSetup');
      final selectedData = await db.query('SelectChannel');
      final selectedRecNos = selectedData.map((item) => (item['RecNo'] as num).toInt()).toSet();

      setState(() {
        channels = data;
        _selectedRecNos.clear();
        _selectedRecNos.addAll(selectedRecNos);
        isLoading = false;
      });
    } catch (error) {
      setState(() {
        errorMessage = 'Error fetching channels: $error';
        isLoading = false;
      });
      print('Error fetching channels: $error');
    }
  }

  Future<void> deleteChannel(int recNo) async {
    try {
      final db = await DatabaseManager().database;
      await db.delete('ChannelSetup', where: 'RecNo = ?', whereArgs: [recNo]);
      await db.delete('SelectChannel', where: 'RecNo = ?', whereArgs: [recNo]);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Channel deleted successfully', style: GoogleFonts.montserrat(fontSize: 14)),
          backgroundColor: ThemeColors.getColor('submitButton', Global.isDarkMode.value),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      fetchChannels();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting channel: $e', style: GoogleFonts.montserrat(fontSize: 14)),
          backgroundColor: ThemeColors.getColor('errorText', Global.isDarkMode.value),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Future<void> _saveSelectedChannels() async {
    try {
      final db = await DatabaseManager().database;
      await db.delete('SelectChannel');
      for (int recNo in _selectedRecNos) {
        final channel = channels.firstWhere((c) => (c['RecNo'] as num).toInt() == recNo);
        await db.insert('SelectChannel', {
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
          content: Text('Selected channels saved: ${_selectedRecNos.length}',
              style: GoogleFonts.montserrat(fontSize: 14)),
          backgroundColor: ThemeColors.getColor('submitButton', Global.isDarkMode.value),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving channels: $e', style: GoogleFonts.montserrat(fontSize: 14)),
          backgroundColor: ThemeColors.getColor('errorText', Global.isDarkMode.value),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Future<void> _cancelSelection() async {
    try {
      final db = await DatabaseManager().database;
      await db.delete('SelectChannel');
      setState(() {
        _selectedRecNos.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Selections cleared', style: GoogleFonts.montserrat(fontSize: 14)),
          backgroundColor: ThemeColors.getColor('submitButton', Global.isDarkMode.value),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error clearing selections: $e', style: GoogleFonts.montserrat(fontSize: 14)),
          backgroundColor: ThemeColors.getColor('errorText', Global.isDarkMode.value),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Future<void> _showAutoStartDialog() async {
    TimeOfDay? dialogStartTime = _startTime;
    TimeOfDay? dialogEndTime = _endTime;
    final dialogScanTimeController = TextEditingController(text: _scanTimeController.text);

    try {
      final db = await DatabaseManager().database;
      final autoStartData = await db.query('AutoStart', limit: 1);
      if (autoStartData.isNotEmpty) {
        final autoStart = autoStartData.first;
        dialogStartTime = TimeOfDay(
          hour: (autoStart['StartTimeHr'] as num?)?.toInt() ?? 0,
          minute: (autoStart['StartTimeMin'] as num?)?.toInt() ?? 0,
        );
        dialogEndTime = TimeOfDay(
          hour: (autoStart['EndTimeHr'] as num?)?.toInt() ?? 0,
          minute: (autoStart['EndTimeMin'] as num?)?.toInt() ?? 0,
        );
        dialogScanTimeController.text = (autoStart['ScanTimeSec'] as num?)?.toInt().toString() ?? '';
      }
    } catch (e) {
      print('Error loading AutoStart settings: $e');
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 400,
              minWidth: 300,
            ),
            child: Card(
              elevation: ThemeColors.getColor('cardElevation', Global.isDarkMode.value),
              color: ThemeColors.getColor('dialogBackground', Global.isDarkMode.value),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Configure AutoStart',
                      style: GoogleFonts.montserrat(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: ThemeColors.getColor('dialogText', Global.isDarkMode.value),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Start Time',
                        style: GoogleFonts.montserrat(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: ThemeColors.getColor('dialogText', Global.isDarkMode.value),
                        ),
                      ),
                      subtitle: Text(
                        dialogStartTime != null ? dialogStartTime!.format(context) : 'Select time',
                        style: GoogleFonts.montserrat(
                          fontSize: 14,
                          color: ThemeColors.getColor('dialogSubText', Global.isDarkMode.value),
                        ),
                      ),
                      onTap: () async {
                        final selectedTime = await showTimePicker(
                          context: context,
                          initialTime: dialogStartTime ?? TimeOfDay.now(),
                          builder: (context, child) => Theme(
                            data: ThemeData(
                              colorScheme: ColorScheme(
                                brightness: Global.isDarkMode.value ? Brightness.dark : Brightness.light,
                                primary: ThemeColors.getColor('submitButton', Global.isDarkMode.value),
                                onPrimary: Colors.white,
                                secondary: ThemeColors.getColor('cardBackground', Global.isDarkMode.value),
                                onSecondary: ThemeColors.getColor('dialogText', Global.isDarkMode.value),
                                error: ThemeColors.getColor('errorText', Global.isDarkMode.value),
                                onError: Colors.white,
                                background: ThemeColors.getColor('dialogBackground', Global.isDarkMode.value),
                                onBackground: ThemeColors.getColor('dialogText', Global.isDarkMode.value),
                                surface: ThemeColors.getColor('dialogBackground', Global.isDarkMode.value),
                                onSurface: ThemeColors.getColor('dialogText', Global.isDarkMode.value),
                              ),
                            ),
                            child: child!,
                          ),
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
                        style: GoogleFonts.montserrat(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: ThemeColors.getColor('dialogText', Global.isDarkMode.value),
                        ),
                      ),
                      subtitle: Text(
                        dialogEndTime != null ? dialogEndTime!.format(context) : 'Select time',
                        style: GoogleFonts.montserrat(
                          fontSize: 14,
                          color: ThemeColors.getColor('dialogSubText', Global.isDarkMode.value),
                        ),
                      ),
                      onTap: () async {
                        final selectedTime = await showTimePicker(
                          context: context,
                          initialTime: dialogEndTime ?? TimeOfDay.now(),
                          builder: (context, child) => Theme(
                            data: ThemeData(
                              colorScheme: ColorScheme(
                                brightness: Global.isDarkMode.value ? Brightness.dark : Brightness.light,
                                primary: ThemeColors.getColor('submitButton', Global.isDarkMode.value),
                                onPrimary: Colors.white,
                                secondary: ThemeColors.getColor('cardBackground', Global.isDarkMode.value),
                                onSecondary: ThemeColors.getColor('dialogText', Global.isDarkMode.value),
                                error: ThemeColors.getColor('errorText', Global.isDarkMode.value),
                                onError: Colors.white,
                                background: ThemeColors.getColor('dialogBackground', Global.isDarkMode.value),
                                onBackground: ThemeColors.getColor('dialogText', Global.isDarkMode.value),
                                surface: ThemeColors.getColor('dialogBackground', Global.isDarkMode.value),
                                onSurface: ThemeColors.getColor('dialogText', Global.isDarkMode.value),
                              ),
                            ),
                            child: child!,
                          ),
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
                        labelStyle: GoogleFonts.montserrat(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: ThemeColors.getColor('dialogSubText', Global.isDarkMode.value),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: ThemeColors.getColor('cardBorder', Global.isDarkMode.value),
                            width: 1.5,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: ThemeColors.getColor('submitButton', Global.isDarkMode.value),
                            width: 2,
                          ),
                        ),
                        filled: true,
                        fillColor: ThemeColors.getColor('textFieldBackground', Global.isDarkMode.value),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      style: GoogleFonts.montserrat(
                        fontSize: 14,
                        color: ThemeColors.getColor('dialogText', Global.isDarkMode.value),
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
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.montserrat(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: ThemeColors.getColor('dialogSubText', Global.isDarkMode.value),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildButton(
                          text: 'Save',
                          icon: Icons.save,
                          gradient: ThemeColors.getDialogButtonGradient(Global.isDarkMode.value, 'backup'),
                          onTap: () async {
                            if (dialogStartTime != null && dialogEndTime != null && dialogScanTimeController.text.isNotEmpty) {
                              final scanTime = int.tryParse(dialogScanTimeController.text);
                              if (scanTime == null || scanTime <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Please enter a valid positive scan time',
                                        style: GoogleFonts.montserrat(fontSize: 14)),
                                    backgroundColor: ThemeColors.getColor('errorText', Global.isDarkMode.value),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    margin: const EdgeInsets.all(16),
                                  ),
                                );
                                return;
                              }
                              try {
                                final db = await DatabaseManager().database;
                                await db.delete('AutoStart');
                                await db.insert('AutoStart', {
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
                                    content: Text('AutoStart settings saved', style: GoogleFonts.montserrat(fontSize: 14)),
                                    backgroundColor: ThemeColors.getColor('submitButton', Global.isDarkMode.value),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    margin: const EdgeInsets.all(16),
                                  ),
                                );
                                Navigator.of(context).pop();
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error saving AutoStart settings: $e',
                                        style: GoogleFonts.montserrat(fontSize: 14)),
                                    backgroundColor: ThemeColors.getColor('errorText', Global.isDarkMode.value),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    margin: const EdgeInsets.all(16),
                                  ),
                                );
                              }
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Please fill all fields', style: GoogleFonts.montserrat(fontSize: 14)),
                                  backgroundColor: ThemeColors.getColor('errorText', Global.isDarkMode.value),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  margin: const EdgeInsets.all(16),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTableHeader(bool isDarkMode) {
    return Card(
      elevation: ThemeColors.getColor('cardElevation', isDarkMode),
      color: ThemeColors.getColor('tableHeaderBackground', isDarkMode),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
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
                activeColor: ThemeColors.getColor('submitButton', isDarkMode),
                checkColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                side: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode)),
              ),
            ),
            SizedBox(
              width: 50,
              child: Text(
                'S.No',
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: ThemeColors.getColor('dialogText', isDarkMode),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                'Channel',
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: ThemeColors.getColor('dialogText', isDarkMode),
                ),
              ),
            ),
            SizedBox(
              width: 60,
              child: Text(
                'Unit',
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: ThemeColors.getColor('dialogText', isDarkMode),
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                'Start Char',
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: ThemeColors.getColor('dialogText', isDarkMode),
                ),
              ),
            ),
            SizedBox(
              width: 80,
              child: Text(
                'Actions',
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: ThemeColors.getColor('dialogText', isDarkMode),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableRow(Map<String, dynamic> channel, int index, bool isDarkMode) {
    final recNo = (channel['RecNo'] as num).toInt();
    return MouseRegion(
      onEnter: (_) => setState(() => _isRowHovered = true),
      onExit: (_) => setState(() => _isRowHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: _selectedRecNos.contains(recNo)
              ? ThemeColors.getColor('submitButton', isDarkMode).withOpacity(0.2)
              : index.isEven
              ? ThemeColors.getColor('cardBackground', isDarkMode)
              : ThemeColors.getColor('tableRowAlternate', isDarkMode),
          border: Border(
            bottom: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode), width: 0.5),
          ),
          boxShadow: _isRowHovered
              ? [
            BoxShadow(
              color: ThemeColors.getColor('buttonHover', isDarkMode).withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ]
              : [],
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
                activeColor: ThemeColors.getColor('submitButton', isDarkMode),
                checkColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                side: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode)),
              ),
            ),
            SizedBox(
              width: 50,
              child: Text(
                '$recNo',
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  color: ThemeColors.getColor('cardText', isDarkMode),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                channel['ChannelName'] ?? '',
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  color: ThemeColors.getColor('cardText', isDarkMode),
                ),
              ),
            ),
            SizedBox(
              width: 60,
              child: Text(
                channel['Unit'] ?? '',
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  color: ThemeColors.getColor('cardText', isDarkMode),
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                channel['StartingCharacter'] ?? '',
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  color: ThemeColors.getColor('cardText', isDarkMode),
                ),
              ),
            ),
            SizedBox(
              width: 80,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.edit, color: ThemeColors.getColor('submitButton', isDarkMode), size: 22),
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => EditChannelScreen(channel: channel)),
                      );
                      if (result == true) {
                        fetchChannels();
                      }
                    },
                    tooltip: 'Edit Channel',
                  ),
                  IconButton(
                    icon: Icon(Icons.delete, color: ThemeColors.getColor('resetButton', isDarkMode), size: 22),
                    onPressed: () => deleteChannel(recNo),
                    tooltip: 'Delete Channel',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton({
    required String text,
    IconData? icon,
    required LinearGradient gradient,
    required VoidCallback onTap,
    bool isProminent = false,
  }) {
    bool isHovered = false;
    return StatefulBuilder(
      builder: (context, setState) => MouseRegion(
        onEnter: (_) => setState(() => isHovered = true),
        onExit: (_) => setState(() => isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(
              horizontal: isProminent ? 28 : 20,
              vertical: isProminent ? 16 : 12,
            ),
            decoration: BoxDecoration(
              gradient: isHovered
                  ? LinearGradient(
                colors: [
                  ThemeColors.getColor('buttonHover', Global.isDarkMode.value),
                  ThemeColors.getColor('buttonGradientEnd', Global.isDarkMode.value),
                ],
              )
                  : gradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isProminent ? 0.3 : 0.2),
                  blurRadius: isProminent ? 10 : 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Colors.white, size: 24),
                  const SizedBox(width: 10),
                ],
                Text(
                  text,
                  style: GoogleFonts.montserrat(
                    fontSize: isProminent ? 16 : 14,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Global.isDarkMode,
      builder: (context, isDarkMode, _) {
        return Scaffold(
          backgroundColor: ThemeColors.getColor('appBackground', isDarkMode),
          body: SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Port',
                          style: GoogleFonts.montserrat(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: ThemeColors.getColor('dialogText', isDarkMode),
                          ),
                        ),
                        const SizedBox(height: 16),
                        MouseRegion(
                          onEnter: (_) => setState(() => _isDropdownHovered = true),
                          onExit: (_) => setState(() => _isDropdownHovered = false),
                          child: Card(
                            elevation: _isDropdownHovered ? 8.0 : ThemeColors.getColor('cardElevation', isDarkMode),
                            color: ThemeColors.getColor('dropdownBackground', isDarkMode),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: Container(
                              padding: const EdgeInsets.all(20.0),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: _isDropdownHovered
                                      ? ThemeColors.getColor('submitButton', isDarkMode)
                                      : ThemeColors.getColor('cardBorder', isDarkMode),
                                  width: _isDropdownHovered ? 2.0 : 1.5,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
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
                                            labelStyle: GoogleFonts.montserrat(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                              color: ThemeColors.getColor('dialogSubText', isDarkMode),
                                            ),
                                            filled: true,
                                            fillColor: ThemeColors.getColor('dropdownBackground', isDarkMode),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              borderSide: BorderSide.none,
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              borderSide: BorderSide(
                                                color: ThemeColors.getColor('cardBorder', isDarkMode),
                                                width: 1.5,
                                              ),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              borderSide: BorderSide(
                                                color: ThemeColors.getColor('submitButton', isDarkMode),
                                                width: 2.5,
                                              ),
                                            ),
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                            prefixIcon: Icon(
                                              Icons.usb,
                                              size: 24,
                                              color: ThemeColors.getColor('cardIcon', isDarkMode),
                                            ),
                                          ),
                                          style: GoogleFonts.montserrat(
                                            fontSize: 14,
                                            color: ThemeColors.getColor('dialogText', isDarkMode),
                                          ),
                                          dropdownColor: isDarkMode ? ThemeColors.getColor('dropdownBackground', isDarkMode) : Colors.white, // Adjusted dropdown color for dark mode
                                          items: ports.map((port) {
                                            return DropdownMenuItem<String>(
                                              value: port,
                                              child: Text(
                                                port,
                                                style: GoogleFonts.montserrat(
                                                  fontSize: 14,
                                                  color: ThemeColors.getColor('dialogText', isDarkMode),
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (value) {
                                            if (value != null) {
                                              Global.selectedPort.value = value;
                                              // Extract port name and details from the string
                                              final parts = value.split(' → ');
                                              String portName = parts[0];
                                              if (parts.length > 1) { // Ensure details part exists
                                                final details = parts[1];
                                                final baudRate = int.tryParse(details.split(', ')[0].split(': ')[1]) ?? 9600;
                                                final dataBits = int.tryParse(details.split(', ')[1].split(': ')[1]) ?? 8;
                                                final parity = details.split(', ')[2].split(': ')[1];
                                                final stopBits = int.tryParse(details.split(', ')[3].split(': ')[1]) ?? 1;

                                                Global.baudRate.value = baudRate;
                                                Global.dataBits.value = dataBits;
                                                Global.parity.value = parity;
                                                Global.stopBits.value = stopBits;
                                                _savePortDetails(portName, baudRate, dataBits, parity, stopBits);
                                              } else {
                                                // Handle "No Ports Detected" or "Error Fetching Ports" case
                                                Global.baudRate.value = 9600;
                                                Global.dataBits.value = 8;
                                                Global.parity.value = 'None';
                                                Global.stopBits.value = 1;
                                                _savePortDetails(portName, 9600, 8, 'None', 1);
                                              }
                                            }
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  _buildButton(
                                    text: '',
                                    icon: Icons.refresh,
                                    gradient: ThemeColors.getDialogButtonGradient(isDarkMode, 'backup'),
                                    onTap: _fetchPorts,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'AutoStart Configuration',
                          style: GoogleFonts.montserrat(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: ThemeColors.getColor('dialogText', isDarkMode),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          elevation: ThemeColors.getColor('cardElevation', isDarkMode),
                          color: ThemeColors.getColor('cardBackground', isDarkMode),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: InkWell(
                            onTap: _showAutoStartDialog,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: ThemeColors.getColor('cardBorder', isDarkMode),
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.timer, color: ThemeColors.getColor('submitButton', isDarkMode), size: 28),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Configure AutoStart',
                                    style: GoogleFonts.montserrat(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: ThemeColors.getColor('dialogText', isDarkMode),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Authentication Settings',
                          style: GoogleFonts.montserrat(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: ThemeColors.getColor('dialogText', isDarkMode),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          elevation: ThemeColors.getColor('cardElevation', isDarkMode),
                          color: ThemeColors.getColor('cardBackground', isDarkMode),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const AuthSettingsScreen()),
                              );
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: ThemeColors.getColor('cardBorder', isDarkMode),
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.lock, color: ThemeColors.getColor('submitButton', isDarkMode), size: 28),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Configure Authentication',
                                    style: GoogleFonts.montserrat(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: ThemeColors.getColor('dialogText', isDarkMode),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Channels',
                          style: GoogleFonts.montserrat(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: ThemeColors.getColor('dialogText', isDarkMode),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          elevation: ThemeColors.getColor('cardElevation', isDarkMode),
                          color: ThemeColors.getColor('cardBackground', isDarkMode),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: ThemeColors.getColor('cardBorder', isDarkMode),
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            height: 400,
                            child: isLoading
                                ? Center(
                              child: CircularProgressIndicator(
                                color: ThemeColors.getColor('submitButton', isDarkMode),
                                strokeWidth: 3,
                              ),
                            )
                                : errorMessage != null
                                ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: ThemeColors.getColor('errorText', isDarkMode),
                                    size: 48,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    errorMessage!,
                                    style: GoogleFonts.montserrat(
                                      fontSize: 14,
                                      color: ThemeColors.getColor('dialogText', isDarkMode),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 24),
                                  _buildButton(
                                    text: 'Retry',
                                    icon: Icons.refresh,
                                    gradient: ThemeColors.getDialogButtonGradient(isDarkMode, 'backup'),
                                    onTap: fetchChannels,
                                  ),
                                ],
                              ),
                            )
                                : channels.isEmpty
                                ? Center(
                              child: Text(
                                'No channels found',
                                style: GoogleFonts.montserrat(
                                  fontSize: 14,
                                  color: ThemeColors.getColor('dialogText', isDarkMode),
                                ),
                              ),
                            )
                                : Scrollbar(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.vertical,
                                child: SizedBox(
                                  width: MediaQuery.of(context).size.width - 48,
                                  child: Column(
                                    children: [
                                      _buildTableHeader(isDarkMode),
                                      ...channels.asMap().entries.map((entry) {
                                        return _buildTableRow(entry.value, entry.key, isDarkMode);
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
                            _buildButton(
                              text: 'Reset',
                              icon: Icons.clear,
                              gradient: LinearGradient(
                                colors: [
                                  ThemeColors.getColor('resetButton', isDarkMode),
                                  ThemeColors.getColor('resetButton', isDarkMode).withOpacity(0.8),
                                ],
                              ),
                              onTap: _cancelSelection,
                            ),
                            const SizedBox(width: 16),
                            _buildButton(
                              text: 'Submit',
                              icon: Icons.check,
                              gradient: ThemeColors.getButtonGradient(isDarkMode),
                              onTap: _saveSelectedChannels,
                              isProminent: true,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}