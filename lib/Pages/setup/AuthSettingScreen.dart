import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import '../../constants/global.dart';
import '../../constants/theme.dart';
import '../../constants/database_manager.dart';
import '../logScreen/log.dart';

class AuthSettingsScreen extends StatefulWidget {
  const AuthSettingsScreen({super.key});

  @override
  _AuthSettingsScreenState createState() => _AuthSettingsScreenState();
}

class _AuthSettingsScreenState extends State<AuthSettingsScreen>
    with SingleTickerProviderStateMixin {
  // UI State
  bool _isLoading = true;
  bool _showSuccessAnimation = false;
  String? _errorMessage;

  // Form Controllers
  bool _isAuthEnabled = false;
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _companyAddressController = TextEditingController();
  String? _logoPath;

  // Auto-Save feature state
  bool _isAutoSaveEnabled = false;
  final TextEditingController _autoSaveHoursController = TextEditingController();
  final TextEditingController _autoSaveMinutesController = TextEditingController();
  final TextEditingController _autoSaveSecondsController = TextEditingController();

  // Animation
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

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
    _loadAuthSettings();
    _animationController.forward();
  }

  Future<void> _loadAuthSettings() async {
    try {
      final authData = await DatabaseManager().getAuthSettings();
      if (authData != null) {
        setState(() {
          _isAuthEnabled = (authData['isAuthEnabled'] as int? ?? 0) == 1;
          _usernameController.text = authData['username'] as String? ?? '';
          _passwordController.text = authData['password'] as String? ?? '';
          _companyNameController.text = authData['companyName'] as String? ?? '';
          _companyAddressController.text = authData['companyAddress'] as String? ?? '';
          _logoPath = authData['logoPath'] as String?;

          _isAutoSaveEnabled = (authData['isAutoSaveEnabled'] as int? ?? 0) == 1;
          int totalSeconds = authData['autoSaveIntervalSeconds'] as int? ?? 30;
          _populateTimeControllers(totalSeconds);
          _isLoading = false;
        });
      } else {
        setState(() {
          _isAutoSaveEnabled = false;
          _populateTimeControllers(30);
          _isLoading = false;
        });
      }
      LogPage.addLog('[$_currentTime] Loaded auth settings');
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load settings. Please try again.';
      });
      LogPage.addLog('[$_currentTime] Error loading auth settings: $e');
    }
  }

  void _populateTimeControllers(int totalSeconds) {
    int hours = totalSeconds ~/ 3600;
    int minutes = (totalSeconds % 3600) ~/ 60;
    int seconds = totalSeconds % 60;
    _autoSaveHoursController.text = hours.toString();
    _autoSaveMinutesController.text = minutes.toString();
    _autoSaveSecondsController.text = seconds.toString();
  }

  int _calculateTotalSeconds() {
    final int hours = int.tryParse(_autoSaveHoursController.text) ?? 0;
    final int minutes = int.tryParse(_autoSaveMinutesController.text) ?? 0;
    final int seconds = int.tryParse(_autoSaveSecondsController.text) ?? 0;
    return (hours * 3600) + (minutes * 60) + seconds;
  }

  Future<void> _saveAuthSettings() async {
    if (_isAuthEnabled && (_usernameController.text.isEmpty || _passwordController.text.isEmpty)) {
      _showErrorSnackBar('Please enter both username and password.');
      return;
    }
    final int totalSaveInterval = _calculateTotalSeconds();
    if (_isAutoSaveEnabled && totalSaveInterval < 5) {
      _showErrorSnackBar('Auto-save interval must be at least 5 seconds.');
      return;
    }

    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      await DatabaseManager().saveAuthSettings(
        _isAuthEnabled,
        _usernameController.text,
        _passwordController.text,
        companyName: _companyNameController.text,
        companyAddress: _companyAddressController.text,
        logoPath: _logoPath,
        isAutoSaveEnabled: _isAutoSaveEnabled,
        autoSaveIntervalSeconds: totalSaveInterval,
      );
      setState(() { _isLoading = false; _showSuccessAnimation = true; });
      LogPage.addLog('[$_currentTime] Saved auth settings successfully');
      await Future.delayed(const Duration(seconds: 1));
      setState(() { _showSuccessAnimation = false; });
      _showSuccessSnackBar('Settings saved successfully.');
    } catch (e) {
      setState(() { _isLoading = false; });
      _showErrorSnackBar('Failed to save settings. Please try again.');
      LogPage.addLog('[$_currentTime] Error saving auth settings: $e');
    }
  }

  Future<void> _pickLogo() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final directory = await getApplicationDocumentsDirectory();
        final newPath = '${directory.path}/company_logo${result.files.single.extension}';
        await file.copy(newPath);
        setState(() { _logoPath = newPath; });
        LogPage.addLog('[$_currentTime] Uploaded company logo: $newPath');
      }
    } catch (e) {
      _showErrorSnackBar('Failed to upload logo. Please try again.');
      LogPage.addLog('[$_currentTime] Error uploading logo: $e');
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _companyNameController.dispose();
    _companyAddressController.dispose();
    _autoSaveHoursController.dispose();
    _autoSaveMinutesController.dispose();
    _autoSaveSecondsController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  bool get _isDarkMode => Global.isDarkMode.value;
  String get _currentTime => DateTime.now().toString().substring(0, 19);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Global.isDarkMode,
      builder: (context, isDarkMode, child) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [ThemeColors.getColor('appBackground', isDarkMode), ThemeColors.getColor('appBackgroundSecondary', isDarkMode)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: _isLoading
                ? _buildLoadingIndicator()
                : _errorMessage != null
                ? _buildErrorView()
                : FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  _CustomTitleBar(),
                  Expanded(child: _buildSettingsBody()),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingsBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildButton(text: 'Back', onTap: () => Navigator.of(context).pop(), icon: Icons.arrow_back, isDarkMode: _isDarkMode),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: ThemeColors.getColor('cardBackground', _isDarkMode),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ThemeColors.getColor('cardBorder', _isDarkMode), width: 1),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle('Authentication Settings'),
                _buildAuthSection(),
                const _SectionDivider(),
                _buildSectionTitle('Company Details'),
                _buildCompanySection(),
                const _SectionDivider(),
                _buildSectionTitle('General Settings'),
                _buildGeneralSettingsSection(),
                const SizedBox(height: 32),
                _buildActionButtons(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: Text(
            'Enable Auto-Save',
            style: GoogleFonts.poppins(fontSize: 18, color: ThemeColors.getColor('dialogText', _isDarkMode), fontWeight: FontWeight.w600),
          ),
          subtitle: _buildSubText('Automatically save test data at a set interval.'),
          value: _isAutoSaveEnabled,
          onChanged: (bool value) {
            setState(() {
              _isAutoSaveEnabled = value;
            });
          },
          secondary: Icon(LucideIcons.save, color: ThemeColors.getColor('buttonGradientStart', _isDarkMode)),
          activeColor: ThemeColors.getColor('buttonGradientStart', _isDarkMode),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 24),
        AbsorbPointer(
          absorbing: !_isAutoSaveEnabled,
          child: Opacity(
            opacity: _isAutoSaveEnabled ? 1.0 : 0.5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auto-Save Interval',
                  style: GoogleFonts.poppins(fontSize: 16, color: ThemeColors.getColor('dialogText', _isDarkMode), fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildTimeInputField(controller: _autoSaveHoursController, label: 'Hours', isDarkMode: _isDarkMode)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildTimeInputField(controller: _autoSaveMinutesController, label: 'Minutes', isDarkMode: _isDarkMode)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildTimeInputField(controller: _autoSaveSecondsController, label: 'Seconds', isDarkMode: _isDarkMode)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _buildButton(
          text: 'Reset',
          onTap: () {
            _usernameController.clear();
            _passwordController.clear();
            _companyNameController.clear();
            _companyAddressController.clear();
            setState(() {
              _isAuthEnabled = false;
              _logoPath = null;
              _isAutoSaveEnabled = false;
              _populateTimeControllers(30);
            });
            LogPage.addLog('[$_currentTime] Reset auth settings to default');
          },
          isDarkMode: _isDarkMode,
        ),
        const SizedBox(width: 12),
        Stack(
          alignment: Alignment.center,
          children: [
            _buildButton(text: 'Save', onTap: _saveAuthSettings, isProminent: true, isDarkMode: _isDarkMode),
            if (_showSuccessAnimation)
              ScaleTransition(
                scale: _scaleAnimation,
                child: Icon(Icons.check_circle, color: ThemeColors.getColor('buttonGradientStart', _isDarkMode), size: 40),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildAuthSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Checkbox(
            value: _isAuthEnabled,
            onChanged: (value) => setState(() => _isAuthEnabled = value ?? false),
            activeColor: ThemeColors.getColor('buttonGradientStart', _isDarkMode),
            checkColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          Text(
            'Enable Authentication',
            style: GoogleFonts.poppins(fontSize: 18, color: ThemeColors.getColor('dialogText', _isDarkMode), fontWeight: FontWeight.w600),
          ),
        ],
      ),
      const SizedBox(height: 16),
      _buildSubText('When enabled, the app will require a username and password on startup.'),
      const SizedBox(height: 24),
      if (_isAuthEnabled) ...[
        _buildTextField(controller: _usernameController, label: 'Username', icon: Icons.person, isDarkMode: _isDarkMode),
        const SizedBox(height: 16),
        _buildTextField(controller: _passwordController, label: 'Password', icon: Icons.lock, obscureText: true, isDarkMode: _isDarkMode),
      ],
    ],
  );

  Widget _buildCompanySection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _buildTextField(controller: _companyNameController, label: 'Company Name', icon: LucideIcons.building, isDarkMode: _isDarkMode),
      const SizedBox(height: 16),
      _buildTextField(controller: _companyAddressController, label: 'Company Address', icon: LucideIcons.mapPin, maxLines: 3, isDarkMode: _isDarkMode),
      const SizedBox(height: 24),
      Text(
        'Company Logo',
        style: GoogleFonts.poppins(fontSize: 16, color: ThemeColors.getColor('dialogText', _isDarkMode), fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: Container(
              height: 100,
              decoration: BoxDecoration(
                color: ThemeColors.getColor('cardBackground', _isDarkMode).withOpacity(0.8),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: ThemeColors.getColor('cardBorder', _isDarkMode)),
              ),
              child: _logoPath != null && File(_logoPath!).existsSync()
                  ? Image.file(File(_logoPath!), fit: BoxFit.contain)
                  : Center(child: _buildSubText('No logo uploaded')),
            ),
          ),
          const SizedBox(width: 12),
          _buildButton(text: 'Upload', onTap: _pickLogo, icon: LucideIcons.upload, isDarkMode: _isDarkMode),
        ],
      ),
      const SizedBox(height: 16),
      _buildInfoText('These details will be used in generated reports.'),
    ],
  );

  Widget _buildTimeInputField({required TextEditingController controller, required String label, required bool isDarkMode}) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: TextAlign.center,
      style: GoogleFonts.poppins(fontSize: 16, color: ThemeColors.getColor('cardText', isDarkMode), fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(fontSize: 14, color: ThemeColors.getColor('dialogSubText', isDarkMode)),
        filled: true,
        fillColor: ThemeColors.getColor('cardBackground', isDarkMode),
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode), width: 1.5)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ThemeColors.getColor('buttonGradientStart', isDarkMode), width: 2)),
      ),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String label, required IconData icon, bool obscureText = false, int maxLines = 1, required bool isDarkMode}) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      maxLines: maxLines,
      style: GoogleFonts.poppins(fontSize: 16, color: ThemeColors.getColor('cardText', isDarkMode), fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(fontSize: 14, color: ThemeColors.getColor('dialogSubText', isDarkMode), fontWeight: FontWeight.w500),
        prefixIcon: Icon(icon, color: ThemeColors.getColor('buttonGradientStart', isDarkMode), size: 24),
        filled: true,
        fillColor: ThemeColors.getColor('cardBackground', isDarkMode),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode), width: 1.5)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: ThemeColors.getColor('buttonGradientStart', isDarkMode), width: 2)),
      ),
    );
  }

  Widget _buildButton({required String text, required VoidCallback onTap, bool isProminent = false, IconData? icon, required bool isDarkMode}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: isProminent ? 32 : 20, vertical: isProminent ? 14 : 10),
        decoration: BoxDecoration(
          gradient: isProminent
              ? ThemeColors.getButtonGradient(isDarkMode)
              : LinearGradient(colors: [
            ThemeColors.getColor('dropdownBackground', isDarkMode),
            ThemeColors.getColor('dropdownBackground', isDarkMode),
          ]),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
                color: ThemeColors.getColor('buttonGradientStart', isDarkMode).withOpacity(isProminent ? 0.4 : 0.2),
                blurRadius: isProminent ? 8 : 4,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: ThemeColors.getColor(isProminent ? 'sidebarText' : 'dialogText', isDarkMode), size: 18),
              const SizedBox(width: 8),
            ],
            Text(
              text,
              style: GoogleFonts.poppins(
                  fontSize: isProminent ? 16 : 14,
                  color: ThemeColors.getColor(isProminent ? 'sidebarText' : 'dialogText', isDarkMode),
                  fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() => Center(
    child: CircularProgressIndicator(
        color: ThemeColors.getColor('buttonGradientStart', _isDarkMode),
        strokeWidth: 4,
        backgroundColor: ThemeColors.getColor('cardBackground', _isDarkMode)),
  );

  Widget _buildErrorView() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline, color: ThemeColors.getColor('errorText', _isDarkMode), size: 48),
        const SizedBox(height: 16),
        Text(_errorMessage!,
            style: GoogleFonts.poppins(color: ThemeColors.getColor('dialogText', _isDarkMode), fontSize: 18, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        _buildButton(text: 'Retry', onTap: _loadAuthSettings, isProminent: true, isDarkMode: _isDarkMode),
      ],
    ),
  );

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(isError ? Icons.error_outline : Icons.check_circle,
            color: isError ? ThemeColors.getColor('errorText', _isDarkMode) : ThemeColors.getColor('buttonGradientStart', _isDarkMode), size: 24),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: GoogleFonts.poppins(fontSize: 16, color: ThemeColors.getColor('dialogText', _isDarkMode)))),
      ]),
      backgroundColor: ThemeColors.getColor('cardBackground', _isDarkMode),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 4),
    ));
  }

  void _showErrorSnackBar(String message) => _showSnackBar(message, isError: true);
  void _showSuccessSnackBar(String message) => _showSnackBar(message, isError: false);

  Widget _buildSectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 16.0),
    child: Text(title, style: GoogleFonts.poppins(fontSize: 20, color: ThemeColors.getColor('dialogText', _isDarkMode), fontWeight: FontWeight.w700)),
  );

  Widget _buildSubText(String text) => Text(text,
      style: GoogleFonts.poppins(fontSize: 14, color: ThemeColors.getColor('dialogSubText', _isDarkMode), fontWeight: FontWeight.w500, height: 1.5));

  Widget _buildInfoText(String text) => Text(text,
      style: GoogleFonts.poppins(
          fontSize: 12, color: ThemeColors.getColor('dialogSubText', _isDarkMode).withOpacity(0.7), fontStyle: FontStyle.italic, height: 1.5),
      textAlign: TextAlign.center);
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0),
      child: Divider(color: ThemeColors.getColor('cardBorder', Global.isDarkMode.value), thickness: 1),
    );
  }
}

class _CustomTitleBar extends StatelessWidget {
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
                        'Countronics Smart Logger - Settings',
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