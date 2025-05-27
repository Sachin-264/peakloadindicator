import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../constants/global.dart';
import '../../constants/theme.dart';
import '../../constants/database_manager.dart';
import '../logScreen/log.dart';
// import '../logScreen/log.dart';

class AuthSettingsScreen extends StatefulWidget {
  const AuthSettingsScreen({super.key});

  @override
  _AuthSettingsScreenState createState() => _AuthSettingsScreenState();
}

class _AuthSettingsScreenState extends State<AuthSettingsScreen>
    with SingleTickerProviderStateMixin {
  bool _isAuthEnabled = false;
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _companyAddressController = TextEditingController();
  String? _logoPath;
  bool _isLoading = true;
  bool _showSuccessAnimation = false;
  String? _errorMessage;
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
          _isAuthEnabled = (authData['isAuthEnabled'] as int) == 1;
          _usernameController.text = authData['username'] as String? ?? '';
          _passwordController.text = authData['password'] as String? ?? '';
          _companyNameController.text = authData['companyName'] as String? ?? '';
          _companyAddressController.text = authData['companyAddress'] as String? ?? '';
          _logoPath = authData['logoPath'] as String?;
          _isLoading = false;
        });
      } else {
        setState(() {
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

  Future<void> _saveAuthSettings() async {
    if (_isAuthEnabled &&
        (_usernameController.text.isEmpty || _passwordController.text.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline,
                  color: ThemeColors.getColor('errorText', _isDarkMode), size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Please enter both username and password.',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: ThemeColors.getColor('dialogText', _isDarkMode),
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: ThemeColors.getColor('cardBackground', _isDarkMode),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await DatabaseManager().saveAuthSettings(
        _isAuthEnabled,
        _usernameController.text,
        _passwordController.text,
        companyName: _companyNameController.text,
        companyAddress: _companyAddressController.text,
        logoPath: _logoPath,
      );
      setState(() {
        _isLoading = false;
        _showSuccessAnimation = true;
      });
      LogPage.addLog('[$_currentTime] Saved auth settings');
      await Future.delayed(const Duration(seconds: 1));
      setState(() {
        _showSuccessAnimation = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle,
                  color: ThemeColors.getColor('buttonGradientStart', _isDarkMode),
                  size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Settings saved successfully.',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: ThemeColors.getColor('dialogText', _isDarkMode),
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: ThemeColors.getColor('cardBackground', _isDarkMode),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to save settings. Please try again.';
      });
      LogPage.addLog('[$_currentTime] Error saving auth settings: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline,
                  color: ThemeColors.getColor('errorText', _isDarkMode), size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Error saving settings.',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: ThemeColors.getColor('dialogText', _isDarkMode),
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: ThemeColors.getColor('cardBackground', _isDarkMode),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _pickLogo() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final directory = await getApplicationDocumentsDirectory();
        final newPath = '${directory.path}/company_logo${result.files.single.extension}';
        await file.copy(newPath);
        setState(() {
          _logoPath = newPath;
        });
        LogPage.addLog('[$_currentTime] Uploaded company logo: $newPath');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to upload logo. Please try again.';
      });
      LogPage.addLog('[$_currentTime] Error uploading logo: $e');
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _companyNameController.dispose();
    _companyAddressController.dispose();
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
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  ThemeColors.getColor('appBackground', isDarkMode),
                  ThemeColors.getColor('appBackgroundSecondary', isDarkMode),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: _isLoading
                  ? Center(
                child: CircularProgressIndicator(
                  color: ThemeColors.getColor('buttonGradientStart', isDarkMode),
                  strokeWidth: 4,
                  backgroundColor: ThemeColors.getColor('cardBackground', isDarkMode),
                ),
              )
                  : _errorMessage != null
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: ThemeColors.getColor('errorText', isDarkMode),
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: GoogleFonts.poppins(
                        color: ThemeColors.getColor('dialogText', isDarkMode),
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    _buildButton(
                      text: 'Retry',
                      onTap: _loadAuthSettings,
                      isProminent: true,
                      isDarkMode: isDarkMode,
                    ),
                  ],
                ),
              )
                  : FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  children: [
                    _CustomTitleBar(),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildButton(
                              text: 'Back',
                              onTap: () => Navigator.of(context).pop(),
                              icon: Icons.arrow_back,
                              isDarkMode: isDarkMode,
                            ),
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: ThemeColors.getColor('cardBackground', isDarkMode),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: ThemeColors.getColor('cardBorder', isDarkMode),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Authentication Settings',
                                    style: GoogleFonts.poppins(
                                      fontSize: 20,
                                      color: ThemeColors.getColor('dialogText', isDarkMode),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Checkbox(
                                        value: _isAuthEnabled,
                                        onChanged: (value) {
                                          setState(() {
                                            _isAuthEnabled = value ?? false;
                                          });
                                          LogPage.addLog(
                                              '[$_currentTime] Toggled authentication: $_isAuthEnabled');
                                        },
                                        activeColor:
                                        ThemeColors.getColor('buttonGradientStart', isDarkMode),
                                        checkColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                      ),
                                      Text(
                                        'Enable Authentication',
                                        style: GoogleFonts.poppins(
                                          fontSize: 18,
                                          color: ThemeColors.getColor('dialogText', isDarkMode),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'When enabled, the app will require a username and password on startup.',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: ThemeColors.getColor('dialogSubText', isDarkMode),
                                      fontWeight: FontWeight.w500,
                                      height: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  if (_isAuthEnabled) ...[
                                    _buildTextField(
                                      controller: _usernameController,
                                      label: 'Username',
                                      icon: Icons.person,
                                      isDarkMode: isDarkMode,
                                    ),
                                    const SizedBox(height: 16),
                                    _buildTextField(
                                      controller: _passwordController,
                                      label: 'Password',
                                      icon: Icons.lock,
                                      obscureText: true,
                                      isDarkMode: isDarkMode,
                                    ),
                                    const SizedBox(height: 24),
                                  ],
                                  Divider(
                                    color: ThemeColors.getColor('cardBorder', isDarkMode),
                                    thickness: 1,
                                    height: 32,
                                  ),
                                  Text(
                                    'Company Details',
                                    style: GoogleFonts.poppins(
                                      fontSize: 20,
                                      color: ThemeColors.getColor('dialogText', isDarkMode),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _buildTextField(
                                    controller: _companyNameController,
                                    label: 'Company Name',
                                    icon: LucideIcons.building,
                                    isDarkMode: isDarkMode,
                                  ),
                                  const SizedBox(height: 16),
                                  _buildTextField(
                                    controller: _companyAddressController,
                                    label: 'Company Address',
                                    icon: LucideIcons.mapPin,
                                    maxLines: 3,
                                    isDarkMode: isDarkMode,
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    'Company Logo',
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      color: ThemeColors.getColor('dialogText', isDarkMode),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Container(
                                          height: 100,
                                          decoration: BoxDecoration(
                                            color: ThemeColors.getColor('cardBackground', isDarkMode)
                                                .withOpacity(0.8),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: ThemeColors.getColor('cardBorder', isDarkMode),
                                            ),
                                          ),
                                          child: _logoPath != null && File(_logoPath!).existsSync()
                                              ? Image.file(
                                            File(_logoPath!),
                                            fit: BoxFit.contain,
                                          )
                                              : Center(
                                            child: Text(
                                              'No logo uploaded',
                                              style: GoogleFonts.poppins(
                                                fontSize: 14,
                                                color: ThemeColors.getColor('cardText', isDarkMode)
                                                    .withOpacity(0.7),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      _buildButton(
                                        text: 'Upload Logo',
                                        onTap: _pickLogo,
                                        icon: LucideIcons.upload,
                                        isDarkMode: isDarkMode,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'These details will be used in generated PDF reports.',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: ThemeColors.getColor('dialogSubText', isDarkMode)
                                          .withOpacity(0.7),
                                      fontStyle: FontStyle.italic,
                                      height: 1.5,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 24),
                                  Row(
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
                                          });
                                          LogPage.addLog('[$_currentTime] Reset auth settings');
                                        },
                                        isDarkMode: isDarkMode,
                                      ),
                                      const SizedBox(width: 12),
                                      Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          _buildButton(
                                            text: 'Save',
                                            onTap: _saveAuthSettings,
                                            isProminent: true,
                                            isDarkMode: isDarkMode,
                                          ),
                                          if (_showSuccessAnimation)
                                            ScaleTransition(
                                              scale: _scaleAnimation,
                                              child: Icon(
                                                Icons.check_circle,
                                                color: ThemeColors.getColor(
                                                    'buttonGradientStart', isDarkMode),
                                                size: 40,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
        ],
        ),
        ),
        ),
        ),
        );
        },
    );
  }
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    int maxLines = 1,
    required bool isDarkMode,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      maxLines: maxLines,
      style: GoogleFonts.poppins(
        fontSize: 16,
        color: ThemeColors.getColor('cardText', isDarkMode),
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(
          fontSize: 14,
          color: ThemeColors.getColor('dialogSubText', isDarkMode),
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Icon(
          icon,
          color: ThemeColors.getColor('buttonGradientStart', isDarkMode),
          size: 24,
        ),
        filled: true,
        fillColor: ThemeColors.getColor('cardBackground', isDarkMode),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: ThemeColors.getColor('cardBorder', isDarkMode),
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: ThemeColors.getColor('buttonGradientStart', isDarkMode),
            width: 2,
          ),
        ),
      ),
    );
  }

  Widget _buildButton({
    required String text,
    required VoidCallback onTap,
    bool isProminent = false,
    IconData? icon,
    required bool isDarkMode,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: isProminent ? 40 : 24,
          vertical: isProminent ? 16 : 12,
        ),
        decoration: BoxDecoration(
          gradient: isProminent
              ? ThemeColors.getButtonGradient(isDarkMode)
              : LinearGradient(
            colors: [
              ThemeColors.getColor('dropdownBackground', isDarkMode),
              ThemeColors.getColor('dropdownBackground', isDarkMode),
            ],
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: ThemeColors.getColor('buttonGradientStart', isDarkMode)
                  .withOpacity(isProminent ? 0.4 : 0.3),
              blurRadius: isProminent ? 8 : 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                color: ThemeColors.getColor(
                    isProminent ? 'sidebarText' : 'dialogText', isDarkMode),
                size: 20,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: isProminent ? 18 : 16,
                color: ThemeColors.getColor(
                    isProminent ? 'sidebarText' : 'dialogText', isDarkMode),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomTitleBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Global.isDarkMode,
      builder: (context, isDarkMode, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: ThemeColors.getTitleBarGradient(isDarkMode),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Countronics Smart Logger',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: ThemeColors.getColor('titleBarText', isDarkMode),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: ThemeColors.getColor('buttonGradientStart', isDarkMode)
                      .withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Settings',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: ThemeColors.getColor('buttonGradientStart', isDarkMode),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
