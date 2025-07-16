import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart'; // Import bitsdojo_window
import '../../constants/database_manager.dart';
import '../../constants/theme.dart';
import '../../constants/global.dart';
import '../logScreen/log.dart';


class EditChannelScreen extends StatefulWidget {
  final Map<String, dynamic>? channel;

  const EditChannelScreen({super.key, this.channel});

  @override
  _EditChannelScreenState createState() => _EditChannelScreenState();
}

class _EditChannelScreenState extends State<EditChannelScreen> {
  final _formKey = GlobalKey<FormState>();
  final _channelNameController = TextEditingController();
  final _unitController = TextEditingController();
  final _targetAlarmMaxController = TextEditingController();
  final _targetAlarmMinController = TextEditingController();
  final _targetAlarmColourController = TextEditingController();
  final _graphLineColourController = TextEditingController();
  Color _selectedAlarmColor = Colors.red; // Default alarm color
  Color _selectedChannelColor = Colors.blue; // Default channel color

  @override
  void initState() {
    super.initState();
    if (widget.channel != null) {
      _channelNameController.text = widget.channel!['ChannelName'] ?? '';
      _unitController.text = widget.channel!['Unit'] ?? '';
      _targetAlarmMaxController.text = widget.channel!['TargetAlarmMax']?.toString() ?? '';
      _targetAlarmMinController.text = widget.channel!['TargetAlarmMin']?.toString() ?? '';
      _targetAlarmColourController.text = widget.channel!['TargetAlarmColour'] ?? 'FF0000';
      _graphLineColourController.text = widget.channel!['graphLineColour'] ?? '0000FF';
      try {
        _selectedAlarmColor = Color(int.parse('FF${_targetAlarmColourController.text}', radix: 16));
        _selectedChannelColor = Color(int.parse('FF${_graphLineColourController.text}', radix: 16));
      } catch (e) {
        _selectedAlarmColor = Colors.red; // Fallback alarm color
        _selectedChannelColor = Colors.blue; // Fallback channel color
      }
      LogPage.addLog('[$_currentTime] Loaded channel data: ${widget.channel!['ChannelName']}');
    } else {
      _targetAlarmColourController.text = 'FF0000'; // Default red
      _graphLineColourController.text = '0000FF'; // Default blue
      LogPage.addLog('[$_currentTime] Initialized new channel form');
    }
  }

  Future<void> _saveChannel() async {
    if (_formKey.currentState!.validate()) {
      final channelData = <String, dynamic>{
        'ChannelName': _channelNameController.text,
        'Unit': _unitController.text,
        'TargetAlarmMax': int.parse(_targetAlarmMaxController.text),
        'TargetAlarmMin': int.parse(_targetAlarmMinController.text),
        'TargetAlarmColour': _targetAlarmColourController.text, // Hex code without #
        'graphLineColour': _graphLineColourController.text, // Hex code without #
      };

      try {
        final dbManager = DatabaseManager();
        final db = await dbManager.database;
        String message;

        if (widget.channel != null) {
          channelData['RecNo'] = widget.channel!['RecNo'];
          await db.update(
            'ChannelSetup',
            channelData,
            where: 'RecNo = ?',
            whereArgs: [widget.channel!['RecNo']],
          );
          message = 'Channel updated successfully';
          LogPage.addLog('[$_currentTime] Edited channel: ${channelData['ChannelName']}');
        } else {
          await db.insert('ChannelSetup', channelData);
          message = 'Channel added successfully';
          LogPage.addLog('[$_currentTime] Added new channel: ${channelData['ChannelName']}');
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                message,
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.white),
              ),
              backgroundColor: ThemeColors.getColor('submitButton', Global.isDarkMode.value),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              margin: const EdgeInsets.all(16),
            ),
          );
          Navigator.pop(context, true); // Return true to refresh main screen
        }
      } catch (e) {
        LogPage.addLog('Error: $e');
        String errorMessage = e.toString();
        if (errorMessage.contains('UNIQUE constraint failed')) {
          errorMessage = 'Failed to save channel: Channel name already exists.';
        } else if (errorMessage.contains('NOT NULL constraint failed')) {
          errorMessage = 'Failed to save channel: Record ID is required.';
        } else {
          errorMessage = 'Failed to save channel: Please check your input and try again.';
        }
        LogPage.addLog('[$_currentTime] Error saving channel: $errorMessage');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                errorMessage,
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.white),
              ),
              backgroundColor: ThemeColors.getColor('errorText', Global.isDarkMode.value),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      }
    }
  }

  void _openColorPicker({required bool isAlarmColor}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white, // White dialog background
        title: SingleChildScrollView(
          child: Column(
            children: [
              Text(
                isAlarmColor ? 'Select Alarm Colour' : 'Select Channel Colour',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              ColorPicker(
                pickerColor: isAlarmColor ? _selectedAlarmColor : _selectedChannelColor,
                onColorChanged: (color) {
                  setState(() {
                    if (isAlarmColor) {
                      _selectedAlarmColor = color;
                      _targetAlarmColourController.text =
                          color.value.toRadixString(16).substring(2).toUpperCase();
                    } else {
                      _selectedChannelColor = color;
                      _graphLineColourController.text =
                          color.value.toRadixString(16).substring(2).toUpperCase();
                    }
                  });
                },
                pickerAreaHeightPercent: 0.8,
                enableAlpha: false,
                displayThumbColor: true,
                paletteType: PaletteType.hsv,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ThemeColors.getColor('submitButton', Global.isDarkMode.value),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: Text(
                  'Confirm',
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
      ),
    );
  }

  // region UI Widgets
  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    required IconData icon,
    bool isColorField = false,
    bool isAlarmColor = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$label:',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: ThemeColors.getColor('dialogText', Global.isDarkMode.value),
              ),
            ),
          ),
          Expanded(
            child: TextFormField(
              controller: controller,
              decoration: InputDecoration(
                labelStyle: GoogleFonts.poppins(
                  fontSize: 14,
                  color: ThemeColors.getColor('dialogSubText', Global.isDarkMode.value),
                ),
                filled: true,
                fillColor: ThemeColors.getColor('cardBackground', Global.isDarkMode.value).withOpacity(0.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: ThemeColors.getColor('cardBorder', Global.isDarkMode.value),
                    width: 1,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: ThemeColors.getColor('cardBorder', Global.isDarkMode.value),
                    width: 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: ThemeColors.getColor('buttonGradientStart', Global.isDarkMode.value),
                    width: 1.5,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                prefixIcon: isColorField
                    ? GestureDetector(
                  onTap: () => _openColorPicker(isAlarmColor: isAlarmColor),
                  child: Container(
                    margin: const EdgeInsets.only(left: 12, right: 8),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isAlarmColor ? _selectedAlarmColor : _selectedChannelColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: ThemeColors.getColor('cardBorder', Global.isDarkMode.value),
                        width: 1,
                      ),
                    ),
                  ),
                )
                    : Icon(
                  icon,
                  size: 20,
                  color: ThemeColors.getColor('dialogSubText', Global.isDarkMode.value),
                ),
              ),
              keyboardType: keyboardType,
              validator: validator,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: ThemeColors.getColor('dialogText', Global.isDarkMode.value),
              ),
              readOnly: isColorField,
              onTap: isColorField ? () => _openColorPicker(isAlarmColor: isAlarmColor) : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormFieldRow({
    required TextEditingController controller1,
    required String label1,
    required TextEditingController controller2,
    required String label2,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    required IconData icon1,
    required IconData icon2,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 140,
                  child: Text(
                    '$label1:',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: ThemeColors.getColor('dialogText', Global.isDarkMode.value),
                    ),
                  ),
                ),
                Expanded(
                  child: TextFormField(
                    controller: controller1,
                    decoration: InputDecoration(
                      labelStyle: GoogleFonts.poppins(
                        fontSize: 14,
                        color: ThemeColors.getColor('dialogSubText', Global.isDarkMode.value),
                      ),
                      filled: true,
                      fillColor: ThemeColors.getColor('cardBackground', Global.isDarkMode.value).withOpacity(0.1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: ThemeColors.getColor('cardBorder', Global.isDarkMode.value),
                          width: 1,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: ThemeColors.getColor('cardBorder', Global.isDarkMode.value),
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: ThemeColors.getColor('buttonGradientStart', Global.isDarkMode.value),
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      prefixIcon: Icon(
                        icon1,
                        size: 20,
                        color: ThemeColors.getColor('dialogSubText', Global.isDarkMode.value),
                      ),
                    ),
                    keyboardType: keyboardType,
                    validator: validator,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: ThemeColors.getColor('dialogText', Global.isDarkMode.value),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 140,
                  child: Text(
                    '$label2:',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: ThemeColors.getColor('dialogText', Global.isDarkMode.value),
                    ),
                  ),
                ),
                Expanded(
                  child: TextFormField(
                    controller: controller2,
                    decoration: InputDecoration(
                      labelStyle: GoogleFonts.poppins(
                        fontSize: 14,
                        color: ThemeColors.getColor('dialogSubText', Global.isDarkMode.value),
                      ),
                      filled: true,
                      fillColor: ThemeColors.getColor('cardBackground', Global.isDarkMode.value).withOpacity(0.1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: ThemeColors.getColor('cardBorder', Global.isDarkMode.value),
                          width: 1,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: ThemeColors.getColor('cardBorder', Global.isDarkMode.value),
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: ThemeColors.getColor('buttonGradientStart', Global.isDarkMode.value),
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      prefixIcon: Icon(
                        icon2,
                        size: 20,
                        color: ThemeColors.getColor('dialogSubText', Global.isDarkMode.value),
                      ),
                    ),
                    keyboardType: keyboardType,
                    validator: validator,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: ThemeColors.getColor('dialogText', Global.isDarkMode.value),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackButton({required bool isDarkMode}) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: ThemeColors.getColor('cardBackground', isDarkMode),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: ThemeColors.getColor('cardBorder', isDarkMode)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back, color: ThemeColors.getColor('dialogText', isDarkMode), size: 18),
            const SizedBox(width: 8),
            Text('Back',
                style: GoogleFonts.poppins(
                    fontSize: 14, color: ThemeColors.getColor('dialogText', isDarkMode), fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
  // endregion

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Global.isDarkMode,
      builder: (context, isDarkMode, child) {
        final title = widget.channel != null ? 'Edit Channel' : 'Add Channel';

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  ThemeColors.getColor('appBackground', isDarkMode),
                  ThemeColors.getColor('appBackgroundSecondary', isDarkMode)
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              children: [
                _CustomTitleBar(title: title),
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildBackButton(isDarkMode: isDarkMode),
                          const SizedBox(height: 24),
                          Card(
                            elevation: 0,
                            color: Colors.transparent, // Card background is handled by container decoration
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: Container(
                              decoration: BoxDecoration(
                                color: ThemeColors.getColor('cardBackground', isDarkMode),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: ThemeColors.getColor('cardBorder', isDarkMode)),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8)],
                              ),
                              padding: const EdgeInsets.all(24.0),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Channel Configuration',
                                      style: GoogleFonts.poppins(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: ThemeColors.getColor('dialogText', isDarkMode),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    _buildFormField(
                                      controller: _channelNameController,
                                      label: 'Channel Name',
                                      validator: (value) => value!.isEmpty ? 'Required' : null,
                                      icon: Icons.label,
                                    ),
                                    _buildFormField(
                                      controller: _unitController,
                                      label: 'Unit',
                                      validator: (value) => value!.isEmpty ? 'Required' : null,
                                      icon: Icons.straighten,
                                    ),
                                    _buildFormFieldRow(
                                      controller1: _targetAlarmMaxController,
                                      label1: 'Alarm Max',
                                      controller2: _targetAlarmMinController,
                                      label2: 'Alarm Min',
                                      keyboardType: TextInputType.number,
                                      validator: (value) =>
                                      value!.isEmpty || int.tryParse(value) == null ? 'Valid number required' : null,
                                      icon1: Icons.warning,
                                      icon2: Icons.warning,
                                    ),
                                    _buildFormField(
                                      controller: _targetAlarmColourController,
                                      label: 'Alarm Colour',
                                      validator: (value) =>
                                      value!.isEmpty || RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(value)
                                          ? null
                                          : 'Valid 6-digit Hex code required',
                                      icon: Icons.color_lens,
                                      isColorField: true,
                                      isAlarmColor: true,
                                    ),
                                    _buildFormField(
                                      controller: _graphLineColourController,
                                      label: 'Channel Colour',
                                      validator: (value) =>
                                      value!.isEmpty || RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(value)
                                          ? null
                                          : 'Valid 6-digit Hex code required',
                                      icon: Icons.color_lens,
                                      isColorField: true,
                                      isAlarmColor: false,
                                    ),
                                    const SizedBox(height: 32),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        GestureDetector(
                                          onTap: () => Navigator.pop(context),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                            decoration: BoxDecoration(
                                              // Using a non-prominent gradient/color
                                              color: ThemeColors.getColor('cardBackground', isDarkMode),
                                              border: Border.all(color: ThemeColors.getColor('cardBorder', isDarkMode)),
                                              borderRadius: BorderRadius.circular(12),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withOpacity(0.1),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: Text(
                                              'Cancel',
                                              style: GoogleFonts.poppins(
                                                fontSize: 16,
                                                color: ThemeColors.getColor('dialogText', isDarkMode),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        GestureDetector(
                                          onTap: _saveChannel,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                            decoration: BoxDecoration(
                                              gradient: ThemeColors.getButtonGradient(isDarkMode),
                                              borderRadius: BorderRadius.circular(12),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: ThemeColors.getColor('submitButton', isDarkMode).withOpacity(0.3),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: Text(
                                              'Save',
                                              style: GoogleFonts.poppins(
                                                fontSize: 16,
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
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _channelNameController.dispose();
    _unitController.dispose();
    _targetAlarmMaxController.dispose();
    _targetAlarmMinController.dispose();
    _targetAlarmColourController.dispose();
    _graphLineColourController.dispose();
    super.dispose();
  }

  String get _currentTime => DateTime.now().toString().substring(0, 19);
}

// Custom Title Bar widget copied and adapted from AuthSettingsScreen
class _CustomTitleBar extends StatelessWidget {
  final String title;
  const _CustomTitleBar({required this.title});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Global.isDarkMode,
      builder: (context, isDarkMode, child) {
        final buttonColors = WindowButtonColors(
          iconNormal: ThemeColors.getColor('titleBarText', isDarkMode),
          mouseOver: ThemeColors.getColor('cardBackground', isDarkMode),
          mouseDown: ThemeColors.getColor('buttonGradientEnd', isDarkMode),
          iconMouseOver: ThemeColors.getColor('buttonGradientStart', isDarkMode),
          iconMouseDown: Colors.white,
        );

        final closeButtonColors = WindowButtonColors(
          mouseOver: const Color(0xFFD32F2F),
          mouseDown: const Color(0xFFB71C1C),
          iconNormal: ThemeColors.getColor('titleBarText', isDarkMode),
          iconMouseOver: Colors.white,
        );

        return Container(
          height: 40,
          decoration: BoxDecoration(gradient: ThemeColors.getTitleBarGradient(isDarkMode)),
          child: Row(
            children: [
              Expanded(
                child: MoveWindow(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16.0),
                      child: Text(
                        'Countronics Smart Logger - $title', // Use dynamic title
                        style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: ThemeColors.getColor('titleBarText', isDarkMode)),
                      ),
                    ),
                  ),
                ),
              ),
              MinimizeWindowButton(colors: buttonColors),
              MaximizeWindowButton(colors: buttonColors),
              CloseWindowButton(colors: closeButtonColors),
            ],
          ),
        );
      },
    );
  }
}