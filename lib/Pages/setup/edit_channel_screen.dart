import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:peakloadindicator/Pages/setup/setup_api.dart';
import '../../constants/colors.dart';

class EditChannelScreen extends StatefulWidget {
  final Map<String, dynamic>? channel;

  const EditChannelScreen({super.key, this.channel});

  @override
  _EditChannelScreenState createState() => _EditChannelScreenState();
}

class _EditChannelScreenState extends State<EditChannelScreen> {
  final _formKey = GlobalKey<FormState>();
  final _channelNameController = TextEditingController();
  final _startingCharacterController = TextEditingController();
  final _dataLengthController = TextEditingController();
  final _decimalPlacesController = TextEditingController();
  final _unitController = TextEditingController();
  final _chartMaxController = TextEditingController();
  final _chartMinController = TextEditingController();
  final _targetAlarmMaxController = TextEditingController();
  final _targetAlarmMinController = TextEditingController();
  final _graphLineColourController = TextEditingController();
  final _targetAlarmColourController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.channel != null) {
      _channelNameController.text = widget.channel!['ChannelName'];
      _startingCharacterController.text = widget.channel!['StartingCharacter'];
      _dataLengthController.text = widget.channel!['DataLength'].toString();
      _decimalPlacesController.text = widget.channel!['DecimalPlaces'].toString();
      _unitController.text = widget.channel!['Unit'];
      _chartMaxController.text = widget.channel!['ChartMaximumValue'].toString();
      _chartMinController.text = widget.channel!['ChartMinimumValue'].toString();
      _targetAlarmMaxController.text = widget.channel!['TargetAlarmMax'].toString();
      _targetAlarmMinController.text = widget.channel!['TargetAlarmMin'].toString();
      _graphLineColourController.text = widget.channel!['GraphLineColour'].toString();
      _targetAlarmColourController.text = widget.channel!['TargetAlarmColour'].toString();
    }
  }

  Future<void> _saveChannel() async {
    if (_formKey.currentState!.validate()) {
      final channelData = <String, dynamic>{
        'ChannelName': _channelNameController.text,
        'StartingCharacter': _startingCharacterController.text,
        'DataLength': int.parse(_dataLengthController.text),
        'DecimalPlaces': int.parse(_decimalPlacesController.text),
        'Unit': _unitController.text,
        'ChartMaximumValue': int.parse(_chartMaxController.text),
        'ChartMinimumValue': int.parse(_chartMinController.text),
        'TargetAlarmMax': int.parse(_targetAlarmMaxController.text),
        'TargetAlarmMin': int.parse(_targetAlarmMinController.text),
        'GraphLineColour': int.parse(_graphLineColourController.text),
        'TargetAlarmColour': int.parse(_targetAlarmColourController.text),
      };

      try {
        String message;
        if (widget.channel != null) {
          channelData['RecNo'] = widget.channel!['RecNo'];
          print('Submitting edit: $channelData');
          message = await ApiService.editChannel(channelData);
        } else {
          print('Submitting add: $channelData');
          message = await ApiService.addChannel(channelData);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                message,
                style: GoogleFonts.poppins(fontSize: 16, color: Colors.white),
              ),
              backgroundColor: AppColors.submitButton,
            ),
          );
          Navigator.pop(context, true); // Return true to refresh main screen
        }
      } catch (e) {
        print('Error: $e');
        if (mounted) {
          // Extract a user-friendly message from the error
          String errorMessage = e.toString();
          if (errorMessage.contains('Cannot insert the value NULL into column \'RecNo\'')) {
            errorMessage = 'Failed to add channel: Record ID is required.';
          } else if (errorMessage.contains('Add Failed')) {
            errorMessage = 'Failed to add channel. Please check your input and try again.';
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                errorMessage,
                style: GoogleFonts.poppins(fontSize: 16, color: Colors.white),
              ),
              backgroundColor: AppColors.errorText,
            ),
          );
        }
      }
    }
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    required IconData icon,
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
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: TextFormField(
              controller: controller,
              decoration: InputDecoration(
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                prefixIcon: Icon(
                  icon,
                  size: 20,
                  color: AppColors.textPrimary.withOpacity(0.8),
                ),
              ),
              keyboardType: keyboardType,
              validator: validator,
              style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary),
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
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Expanded(
                  child: TextFormField(
                    controller: controller1,
                    decoration: InputDecoration(
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      prefixIcon: Icon(
                        icon1,
                        size: 20,
                        color: AppColors.textPrimary.withOpacity(0.8),
                      ),
                    ),
                    keyboardType: keyboardType,
                    validator: validator,
                    style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary),
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
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Expanded(
                  child: TextFormField(
                    controller: controller2,
                    decoration: InputDecoration(
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      prefixIcon: Icon(
                        icon2,
                        size: 20,
                        color: AppColors.textPrimary.withOpacity(0.8),
                      ),
                    ),
                    keyboardType: keyboardType,
                    validator: validator,
                    style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary),
                  ),
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.channel != null ? 'Edit Channel' : 'Add Channel',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: [
                      AppColors.cardBackground,
                      AppColors.cardBackground.withOpacity(0.95),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFormField(
                        controller: _channelNameController,
                        label: 'Channel Name',
                        validator: (value) => value!.isEmpty ? 'Required' : null,
                        icon: Icons.label,
                      ),
                      _buildFormField(
                        controller: _startingCharacterController,
                        label: 'Starting Character',
                        validator: (value) => value!.isEmpty ? 'Required' : null,
                        icon: Icons.text_fields,
                      ),
                      _buildFormFieldRow(
                        controller1: _dataLengthController,
                        label1: 'Data Length',
                        controller2: _decimalPlacesController,
                        label2: 'Decimal Places',
                        keyboardType: TextInputType.number,
                        validator: (value) => value!.isEmpty || int.tryParse(value) == null ? 'Valid number' : null,
                        icon1: Icons.numbers,
                        icon2: Icons.format_list_numbered,
                      ),
                      _buildFormField(
                        controller: _unitController,
                        label: 'Unit',
                        validator: (value) => value!.isEmpty ? 'Required' : null,
                        icon: Icons.straighten,
                      ),
                      _buildFormFieldRow(
                        controller1: _chartMaxController,
                        label1: 'Chart Max',
                        controller2: _chartMinController,
                        label2: 'Chart Min',
                        keyboardType: TextInputType.number,
                        validator: (value) => value!.isEmpty || int.tryParse(value) == null ? 'Valid number' : null,
                        icon1: Icons.arrow_upward,
                        icon2: Icons.arrow_downward,
                      ),
                      _buildFormFieldRow(
                        controller1: _targetAlarmMaxController,
                        label1: 'Alarm Max',
                        controller2: _targetAlarmMinController,
                        label2: 'Alarm Min',
                        keyboardType: TextInputType.number,
                        validator: (value) => value!.isEmpty || int.tryParse(value) == null ? 'Valid number' : null,
                        icon1: Icons.warning,
                        icon2: Icons.warning,
                      ),
                      _buildFormFieldRow(
                        controller1: _graphLineColourController,
                        label1: 'Graph Colour',
                        controller2: _targetAlarmColourController,
                        label2: 'Alarm Colour',
                        keyboardType: TextInputType.number,
                        validator: (value) => value!.isEmpty || int.tryParse(value) == null ? 'Valid number' : null,
                        icon1: Icons.color_lens,
                        icon2: Icons.color_lens,
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
                                'Cancel',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  color: Colors.white,
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
          ),
        ),
      ),
    );
  }
}