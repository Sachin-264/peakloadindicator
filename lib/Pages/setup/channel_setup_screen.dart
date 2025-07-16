import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:libserialport/libserialport.dart';

import '../../constants/database_manager.dart';
import '../../constants/global.dart';
import '../../constants/theme.dart';
import '../logScreen/log.dart';
import 'AuthSettingScreen.dart';
import 'edit_channel_screen.dart';

class ChannelSetupScreen extends StatefulWidget {
  const ChannelSetupScreen({super.key});

  @override
  _ChannelSetupScreenState createState() => _ChannelSetupScreenState();
}

class _ChannelSetupScreenState extends State<ChannelSetupScreen> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> channels = [];
  List<String> availablePorts = [];
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

  final List<int> standardBaudRates = [1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200];

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

    _initializeSettings();
    fetchChannels();
    _animationController.forward();
    _logActivity('ChannelSetupScreen initialized');
  }

  Future<void> _initializeSettings() async {
    await _loadSavedPortDetails();
    await _fetchPorts();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scanTimeController.dispose();
    super.dispose();
  }

  String get _currentTime => DateTime.now().toString().substring(0, 19);

  void _logActivity(String message) {
    LogPage.addLog('[$_currentTime] [ChannelSetup] $message');
  }

  Future<void> _loadSavedPortDetails() async {
    final savedSettings = await DatabaseManager().getComPortSettings();
    if (savedSettings != null && mounted) {
      setState(() {
        Global.selectedPort.value = savedSettings['selectedPort'] ?? 'No Ports Detected';
        Global.baudRate.value = savedSettings['baudRate'] ?? 9600;
        Global.dataBits.value = savedSettings['dataBits'] ?? 8;
        Global.parity.value = savedSettings['parity'] ?? 'None';
        Global.stopBits.value = savedSettings['stopBits'] ?? 1;
      });
      _logActivity('Loaded saved settings: Port=${Global.selectedPort.value}, Baud=${Global.baudRate.value}, DataBits=${Global.dataBits.value}, Parity=${Global.parity.value}, StopBits=${Global.stopBits.value}');
    } else {
      _logActivity('No saved COM port settings found. Using default values.');
    }
  }

  Future<void> _savePortDetails() async {
    final String portName = Global.selectedPort.value;
    final int baudRate = Global.baudRate.value;
    final int dataBits = Global.dataBits.value;
    final String parity = Global.parity.value;
    final int stopBits = Global.stopBits.value;

    if (portName == 'No Ports Detected' || portName == 'Error Fetching Ports') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Cannot save. No valid port selected.', style: GoogleFonts.montserrat()),
        backgroundColor: ThemeColors.getColor('errorText', Global.isDarkMode.value),
      ));
      _logActivity('Save aborted: Attempted to save invalid port ($portName).');
      return;
    }

    try {
      await DatabaseManager().saveComPortSettings(portName, baudRate, dataBits, parity, stopBits);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Port settings saved for $portName', style: GoogleFonts.montserrat()),
        backgroundColor: ThemeColors.getColor('submitButton', Global.isDarkMode.value),
      ));
      _logActivity('Port settings saved: Port=$portName, Baud=$baudRate, DataBits=$dataBits, Parity=$parity, StopBits=$stopBits');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error saving port settings: $e', style: GoogleFonts.montserrat()),
        backgroundColor: ThemeColors.getColor('errorText', Global.isDarkMode.value),
      ));
      _logActivity('Error saving port settings: $e');
    }
  }

  Future<void> _fetchPorts() async {
    _logActivity('Fetching available COM ports...');
    try {
      final portNames = SerialPort.availablePorts;

      setState(() {
        availablePorts = portNames;
        final String savedPortName = Global.selectedPort.value;

        if (availablePorts.contains(savedPortName)) {
          _logActivity('Saved port "$savedPortName" found and is available.');
        } else if (availablePorts.isNotEmpty) {
          final firstPortName = availablePorts.first;
          Global.selectedPort.value = firstPortName;
          _logActivity('Saved port "$savedPortName" not found. Defaulting to first available port: "$firstPortName".');
        } else {
          Global.selectedPort.value = 'No Ports Detected';
          _logActivity('No COM ports detected.');
        }
      });

    } catch (e) {
      _logActivity('CRITICAL Error fetching ports: $e');
      setState(() {
        availablePorts = [];
        Global.selectedPort.value = 'Error Fetching Ports';
      });
    }
  }

  Future<void> fetchChannels() async {
    setState(() {
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
      });
      _logActivity('Fetched ${channels.length} channels from ChannelSetup. ${selectedRecNos.length} selected.');
    } catch (error) {
      setState(() {
        errorMessage = 'Error fetching channels: $error';
      });
      _logActivity('Error fetching channels: $error');
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
      _logActivity('Channel $recNo deleted.');
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
      _logActivity('Error deleting channel $recNo: $e');
    }
  }

  Future<void> _saveSelectedChannels() async {
    try {
      final db = await DatabaseManager().database;
      await db.delete('SelectChannel');
      for (int recNo in _selectedRecNos) {
        final channel = channels.firstWhere((c) => (c['RecNo'] as num).toInt() == recNo);
        await db.insert('SelectChannel', {
          'RecNo': recNo, 'ChannelName': channel['ChannelName'], 'StartingCharacter': channel['StartingCharacter'],
          'DataLength': channel['DataLength'], 'Unit': channel['Unit'], 'DecimalPlaces': channel['DecimalPlaces'],
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Selected channels saved: ${_selectedRecNos.length}', style: GoogleFonts.montserrat(fontSize: 14)),
          backgroundColor: ThemeColors.getColor('submitButton', Global.isDarkMode.value),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      _logActivity('Saved ${_selectedRecNos.length} selected channels.');
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
      _logActivity('Error saving selected channels: $e');
    }
  }

  Future<void> _cancelSelection() async {
    try {
      final db = await DatabaseManager().database;
      await db.delete('SelectChannel');
      setState(() { _selectedRecNos.clear(); });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Selections cleared', style: GoogleFonts.montserrat(fontSize: 14)),
          backgroundColor: ThemeColors.getColor('submitButton', Global.isDarkMode.value),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      _logActivity('Channel selections cleared.');
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
      _logActivity('Error clearing channel selections: $e');
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
      _logActivity('AutoStart dialog opened. Current settings loaded.');
    } catch (e) {
      _logActivity('Error loading AutoStart settings for dialog: $e');
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400, minWidth: 300,),
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
                    Text('Configure AutoStart', style: GoogleFonts.montserrat(fontSize: 20, fontWeight: FontWeight.w700, color: ThemeColors.getColor('dialogText', Global.isDarkMode.value),)),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Start Time', style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.w600, color: ThemeColors.getColor('dialogText', Global.isDarkMode.value),)),
                      subtitle: Text(dialogStartTime != null ? dialogStartTime!.format(context) : 'Select time', style: GoogleFonts.montserrat(fontSize: 14, color: ThemeColors.getColor('dialogSubText', Global.isDarkMode.value),)),
                      onTap: () async {
                        final selectedTime = await showTimePicker(
                          context: context,
                          initialTime: dialogStartTime ?? TimeOfDay.now(),
                          builder: (context, child) => Theme(
                            data: ThemeData(
                              colorScheme: ColorScheme(
                                brightness: Global.isDarkMode.value ? Brightness.dark : Brightness.light,
                                primary: ThemeColors.getColor('submitButton', Global.isDarkMode.value), onPrimary: Colors.white,
                                secondary: ThemeColors.getColor('cardBackground', Global.isDarkMode.value), onSecondary: ThemeColors.getColor('dialogText', Global.isDarkMode.value),
                                error: ThemeColors.getColor('errorText', Global.isDarkMode.value), onError: Colors.white,
                                background: ThemeColors.getColor('dialogBackground', Global.isDarkMode.value), onBackground: ThemeColors.getColor('dialogText', Global.isDarkMode.value),
                                surface: ThemeColors.getColor('dialogBackground', Global.isDarkMode.value), onSurface: ThemeColors.getColor('dialogText', Global.isDarkMode.value),
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
                      title: Text('End Time', style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.w600, color: ThemeColors.getColor('dialogText', Global.isDarkMode.value),)),
                      subtitle: Text(dialogEndTime != null ? dialogEndTime!.format(context) : 'Select time', style: GoogleFonts.montserrat(fontSize: 14, color: ThemeColors.getColor('dialogSubText', Global.isDarkMode.value),)),
                      onTap: () async {
                        final selectedTime = await showTimePicker(
                          context: context,
                          initialTime: dialogEndTime ?? TimeOfDay.now(),
                          builder: (context, child) => Theme(
                            data: ThemeData(
                              colorScheme: ColorScheme(
                                brightness: Global.isDarkMode.value ? Brightness.dark : Brightness.light,
                                primary: ThemeColors.getColor('submitButton', Global.isDarkMode.value), onPrimary: Colors.white,
                                secondary: ThemeColors.getColor('cardBackground', Global.isDarkMode.value), onSecondary: ThemeColors.getColor('dialogText', Global.isDarkMode.value),
                                error: ThemeColors.getColor('errorText', Global.isDarkMode.value), onError: Colors.white,
                                background: ThemeColors.getColor('dialogBackground', Global.isDarkMode.value), onBackground: ThemeColors.getColor('dialogText', Global.isDarkMode.value),
                                surface: ThemeColors.getColor('dialogBackground', Global.isDarkMode.value), onSurface: ThemeColors.getColor('dialogText', Global.isDarkMode.value),
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
                        labelStyle: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w500, color: ThemeColors.getColor('dialogSubText', Global.isDarkMode.value),),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none,),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: ThemeColors.getColor('cardBorder', Global.isDarkMode.value), width: 1.5,),),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: ThemeColors.getColor('submitButton', Global.isDarkMode.value), width: 2,),),
                        filled: true,
                        fillColor: ThemeColors.getColor('textFieldBackground', Global.isDarkMode.value),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      style: GoogleFonts.montserrat(fontSize: 14, color: ThemeColors.getColor('dialogText', Global.isDarkMode.value),),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text('Cancel', style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w600, color: ThemeColors.getColor('dialogSubText', Global.isDarkMode.value),)),
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
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please enter a valid positive scan time', style: GoogleFonts.montserrat(fontSize: 14)), backgroundColor: ThemeColors.getColor('errorText', Global.isDarkMode.value), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), margin: const EdgeInsets.all(16),));
                                return;
                              }
                              try {
                                final db = await DatabaseManager().database;
                                await db.delete('AutoStart');
                                await db.insert('AutoStart', {
                                  'StartTimeHr': dialogStartTime!.hour, 'StartTimeMin': dialogStartTime!.minute,
                                  'EndTimeHr': dialogEndTime!.hour, 'EndTimeMin': dialogEndTime!.minute,
                                  'ScanTimeSec': scanTime,
                                });
                                setState(() {
                                  _startTime = dialogStartTime; _endTime = dialogEndTime; _scanTimeController.text = dialogScanTimeController.text;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('AutoStart settings saved', style: GoogleFonts.montserrat(fontSize: 14)), backgroundColor: ThemeColors.getColor('submitButton', Global.isDarkMode.value), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), margin: const EdgeInsets.all(16),));
                                Navigator.of(context).pop();
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving AutoStart settings: $e', style: GoogleFonts.montserrat(fontSize: 14)), backgroundColor: ThemeColors.getColor('errorText', Global.isDarkMode.value), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), margin: const EdgeInsets.all(16),));
                              }
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please fill all fields', style: GoogleFonts.montserrat(fontSize: 14)), backgroundColor: ThemeColors.getColor('errorText', Global.isDarkMode.value), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), margin: const EdgeInsets.all(16),));
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
            SizedBox(width: 50, child: Text('S.No', style: GoogleFonts.montserrat(fontWeight: FontWeight.w700, fontSize: 15, color: ThemeColors.getColor('dialogText', isDarkMode),),)),
            Expanded(flex: 2, child: Text('Channel', style: GoogleFonts.montserrat(fontWeight: FontWeight.w700, fontSize: 15, color: ThemeColors.getColor('dialogText', isDarkMode),),)),
            SizedBox(width: 60, child: Text('Unit', style: GoogleFonts.montserrat(fontWeight: FontWeight.w700, fontSize: 15, color: ThemeColors.getColor('dialogText', isDarkMode),),)),
            Expanded(flex: 1, child: Text('Start Char', style: GoogleFonts.montserrat(fontWeight: FontWeight.w700, fontSize: 15, color: ThemeColors.getColor('dialogText', isDarkMode),),)),
            SizedBox(width: 80, child: Text('Actions', style: GoogleFonts.montserrat(fontWeight: FontWeight.w700, fontSize: 15, color: ThemeColors.getColor('dialogText', isDarkMode),),)),
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
          border: Border(bottom: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode), width: 0.5),),
          boxShadow: _isRowHovered ? [BoxShadow(color: ThemeColors.getColor('buttonHover', isDarkMode).withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2),),] : [],
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
                    if (value == true) { _selectedRecNos.add(recNo); }
                    else { _selectedRecNos.remove(recNo); }
                  });
                },
                activeColor: ThemeColors.getColor('submitButton', isDarkMode),
                checkColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                side: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode)),
              ),
            ),
            SizedBox(width: 50, child: Text('$recNo', style: GoogleFonts.montserrat(fontSize: 13, color: ThemeColors.getColor('cardText', isDarkMode),),)),
            Expanded(flex: 2, child: Text(channel['ChannelName'] ?? '', style: GoogleFonts.montserrat(fontSize: 13, color: ThemeColors.getColor('cardText', isDarkMode),),)),
            SizedBox(width: 60, child: Text(channel['Unit'] ?? '', style: GoogleFonts.montserrat(fontSize: 13, color: ThemeColors.getColor('cardText', isDarkMode),),)),
            Expanded(flex: 1, child: Text(channel['StartingCharacter'] ?? '', style: GoogleFonts.montserrat(fontSize: 13, color: ThemeColors.getColor('cardText', isDarkMode),),)),
            SizedBox(
              width: 80,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.edit, color: ThemeColors.getColor('submitButton', isDarkMode), size: 22),
                    onPressed: () async {
                      final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => EditChannelScreen(channel: channel)),);
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
    bool isSmall = false,
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
            padding: EdgeInsets.symmetric(horizontal: isSmall ? 12 : (isProminent ? 28 : 20), vertical: isSmall ? 8 : (isProminent ? 16 : 12),),
            decoration: BoxDecoration(
              gradient: isHovered ? LinearGradient(colors: [ThemeColors.getColor('buttonHover', Global.isDarkMode.value), ThemeColors.getColor('buttonGradientEnd', Global.isDarkMode.value),]) : gradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(isProminent ? 0.3 : 0.2), blurRadius: isProminent ? 10 : 8, offset: const Offset(0, 4),),],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, color: Colors.white, size: isSmall ? 18 : 24), if (text.isNotEmpty) const SizedBox(width: 10)],
                if (text.isNotEmpty) Text(text, style: GoogleFonts.montserrat(fontSize: isProminent ? 16 : 14, color: Colors.white, fontWeight: FontWeight.w600,),),
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
                        Text('Port Configuration', style: GoogleFonts.montserrat(fontSize: 22, fontWeight: FontWeight.w700, color: ThemeColors.getColor('dialogText', isDarkMode))),
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
                                  color: _isDropdownHovered ? ThemeColors.getColor('submitButton', isDarkMode) : ThemeColors.getColor('cardBorder', isDarkMode),
                                  width: _isDropdownHovered ? 2.0 : 1.5,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: ValueListenableBuilder<String>(
                                          valueListenable: Global.selectedPort,
                                          builder: (context, selectedPortValue, _) {
                                            final String? currentSelection = availablePorts.contains(selectedPortValue) ? selectedPortValue : null;

                                            return DropdownButtonFormField<String>(
                                              value: currentSelection,
                                              hint: Text(selectedPortValue, style: GoogleFonts.montserrat(fontSize: 14, color: ThemeColors.getColor('dialogText', isDarkMode)), overflow: TextOverflow.ellipsis),
                                              decoration: InputDecoration(
                                                labelText: 'Port',
                                                labelStyle: GoogleFonts.montserrat(fontSize: 15, fontWeight: FontWeight.w500, color: ThemeColors.getColor('dialogSubText', isDarkMode)),
                                                filled: true,
                                                fillColor: ThemeColors.getColor('dropdownBackground', isDarkMode),
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode), width: 1.5)),
                                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: ThemeColors.getColor('submitButton', isDarkMode), width: 2.5)),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                                prefixIcon: Icon(Icons.usb, size: 24, color: ThemeColors.getColor('cardIcon', isDarkMode)),
                                              ),
                                              dropdownColor: isDarkMode ? ThemeColors.getColor('dropdownBackground', isDarkMode) : Colors.white,
                                              items: availablePorts.map((portName) {
                                                return DropdownMenuItem<String>(value: portName, child: Text(portName, style: GoogleFonts.montserrat(fontSize: 14, color: ThemeColors.getColor('dialogText', isDarkMode))));
                                              }).toList(),
                                              onChanged: (value) {
                                                if (value != null) {
                                                  Global.selectedPort.value = value;
                                                  _logActivity('User selected new port: $value');
                                                }
                                              },
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        flex: 1,
                                        child: ValueListenableBuilder<int>(
                                          valueListenable: Global.baudRate,
                                          builder: (context, selectedBaudRate, _) {
                                            return DropdownButtonFormField<int>(
                                              value: standardBaudRates.contains(selectedBaudRate) ? selectedBaudRate : null,
                                              hint: Text(selectedBaudRate.toString(), style: GoogleFonts.montserrat(fontSize: 14, color: ThemeColors.getColor('dialogText', isDarkMode))),
                                              decoration: InputDecoration(
                                                labelText: 'Baud Rate',
                                                labelStyle: GoogleFonts.montserrat(fontSize: 15, fontWeight: FontWeight.w500, color: ThemeColors.getColor('dialogSubText', isDarkMode)),
                                                filled: true,
                                                fillColor: ThemeColors.getColor('dropdownBackground', isDarkMode),
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode), width: 1.5)),
                                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: ThemeColors.getColor('submitButton', isDarkMode), width: 2.5)),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                              ),
                                              dropdownColor: isDarkMode ? ThemeColors.getColor('dropdownBackground', isDarkMode) : Colors.white,
                                              items: standardBaudRates.map((rate) {
                                                return DropdownMenuItem<int>(value: rate, child: Text(rate.toString(), style: GoogleFonts.montserrat(fontSize: 14, color: ThemeColors.getColor('dialogText', isDarkMode))));
                                              }).toList(),
                                              onChanged: (value) {
                                                if (value != null) {
                                                  Global.baudRate.value = value;
                                                  _logActivity('User changed baud rate to: $value');
                                                }
                                              },
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: _buildButton(text: 'Save Port Settings', icon: Icons.save, gradient: ThemeColors.getDialogButtonGradient(isDarkMode, 'backup'), onTap: _savePortDetails, isSmall: true),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text('AutoStart Configuration', style: GoogleFonts.montserrat(fontSize: 22, fontWeight: FontWeight.w700, color: ThemeColors.getColor('dialogText', isDarkMode))),
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
                              decoration: BoxDecoration(border: Border.all(color: ThemeColors.getColor('cardBorder', isDarkMode), width: 1.5), borderRadius: BorderRadius.circular(16)),
                              child: Row(
                                children: [
                                  Icon(Icons.timer, color: ThemeColors.getColor('submitButton', isDarkMode), size: 28),
                                  const SizedBox(width: 12),
                                  Text('Configure AutoStart', style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.w600, color: ThemeColors.getColor('dialogText', isDarkMode))),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text('Authentication Settings', style: GoogleFonts.montserrat(fontSize: 22, fontWeight: FontWeight.w700, color: ThemeColors.getColor('dialogText', isDarkMode))),
                        const SizedBox(height: 16),
                        Card(
                          elevation: ThemeColors.getColor('cardElevation', isDarkMode),
                          color: ThemeColors.getColor('cardBackground', isDarkMode),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: InkWell(
                            onTap: () {
                              Navigator.push(context, MaterialPageRoute(builder: (context) => const AuthSettingsScreen()));
                              _logActivity('Navigated to Authentication Settings.');
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(border: Border.all(color: ThemeColors.getColor('cardBorder', isDarkMode), width: 1.5), borderRadius: BorderRadius.circular(16)),
                              child: Row(
                                children: [
                                  Icon(Icons.lock, color: ThemeColors.getColor('submitButton', isDarkMode), size: 28),
                                  const SizedBox(width: 12),
                                  Text('Configure Authentication', style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.w600, color: ThemeColors.getColor('dialogText', isDarkMode))),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text('Channels', style: GoogleFonts.montserrat(fontSize: 22, fontWeight: FontWeight.w700, color: ThemeColors.getColor('dialogText', isDarkMode))),
                        const SizedBox(height: 16),
                        Card(
                          elevation: ThemeColors.getColor('cardElevation', isDarkMode),
                          color: ThemeColors.getColor('cardBackground', isDarkMode),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Container(
                            decoration: BoxDecoration(border: Border.all(color: ThemeColors.getColor('cardBorder', isDarkMode), width: 1.5), borderRadius: BorderRadius.circular(16)),
                            height: 400,
                            child: errorMessage != null
                                ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.error_outline, color: ThemeColors.getColor('errorText', isDarkMode), size: 48),
                                  const SizedBox(height: 16),
                                  Text(errorMessage!, style: GoogleFonts.montserrat(fontSize: 14, color: ThemeColors.getColor('dialogText', isDarkMode)), textAlign: TextAlign.center),
                                  const SizedBox(height: 24),
                                  _buildButton(text: 'Retry', icon: Icons.refresh, gradient: ThemeColors.getDialogButtonGradient(isDarkMode, 'backup'), onTap: fetchChannels),
                                ],
                              ),
                            )
                                : channels.isEmpty
                                ? Center(child: Text('No channels found', style: GoogleFonts.montserrat(fontSize: 14, color: ThemeColors.getColor('dialogText', isDarkMode))))
                                : Scrollbar(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.vertical,
                                child: SizedBox(
                                  width: MediaQuery.of(context).size.width - 48,
                                  child: Column(
                                    children: [
                                      _buildTableHeader(isDarkMode),
                                      ...channels.asMap().entries.map((entry) => _buildTableRow(entry.value, entry.key, isDarkMode)),
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
                            _buildButton(text: 'Reset', icon: Icons.clear, gradient: LinearGradient(colors: [ThemeColors.getColor('resetButton', isDarkMode), ThemeColors.getColor('resetButton', isDarkMode).withOpacity(0.8)]), onTap: _cancelSelection),
                            const SizedBox(width: 16),
                            _buildButton(text: 'Submit', icon: Icons.check, gradient: ThemeColors.getButtonGradient(isDarkMode), onTap: _saveSelectedChannels, isProminent: true),
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