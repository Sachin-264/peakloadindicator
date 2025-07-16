import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../constants/colors.dart';
import '../../Pages/homepage.dart';
import '../../constants/database_manager.dart';
import '../../constants/theme.dart';
import '../../main.dart';
import '../logScreen/log.dart'; // Ensure CustomTitleBar is accessible

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _masterPasswordController = TextEditingController();
  final TextEditingController _newUsernameController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();

  // State variables for overall app loading (initial splash) and login process
  bool _isLoading = true; // For initial database check / app startup
  bool _isAuthenticating = false; // For specific login button loading
  bool _showSuccessAnimation = false; // For login button success checkmark
  String? _errorMessage;

  // State variables for password visibility
  bool _isPasswordObscured = true; // For login password field
  bool _isMasterPasswordObscured = true; // For master password field
  bool _isNewPasswordObscured = true; // For new password field in reset dialog

  // Animation controllers for different purposes
  late AnimationController _appLoadAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  late AnimationController _loginSuccessAnimationController;
  late Animation<double> _loginSuccessScaleAnimation;

  static const String _masterPassword = 'admin@1234';
  static const Color _accentColor = Color(0xFF455A64);

  @override
  void initState() {
    super.initState();

    // Initial App Load/Error Animations
    _appLoadAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _appLoadAnimationController, curve: Curves.easeInOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _appLoadAnimationController, curve: Curves.easeOut),
    );

    // Login Button Success Animation
    _loginSuccessAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _loginSuccessScaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _loginSuccessAnimationController, curve: Curves.easeOutBack),
    );

    _checkDatabase();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(const AssetImage('assets/images/logo_animation.gif'), context)
          .then((_) {
        LogPage.addLog('GIF preloaded successfully');
      }).catchError((error) {
        LogPage.addLog('GIF loading error: $error');
      });
    });
  }

  Future<void> _checkDatabase() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await DatabaseManager().database;
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      LogPage.addLog('Database initialization error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error initializing database. Please try again.';
        });
        _appLoadAnimationController.forward(from: 0.0);
      }
    }
  }

  Future<void> _login() async {
    if (_isAuthenticating || _showSuccessAnimation) {
      return;
    }

    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
      _showSuccessAnimation = false;
    });

    try {
      final authData = await DatabaseManager().getAuthSettings();
      await Future.delayed(const Duration(milliseconds: 800));

      if (authData != null) {
        final storedUsername = authData['username'] as String? ?? '';
        final storedPassword = authData['password'] as String? ?? '';
        if (_usernameController.text == storedUsername && _passwordController.text == storedPassword) {
          setState(() {
            _showSuccessAnimation = true;
          });
          _loginSuccessAnimationController.forward(from: 0.0);
          await Future.delayed(const Duration(seconds: 1));
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const HomePage()),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.error_outline, color: AppColors.errorText, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Incorrect username or password. Please try again.',
                        style: GoogleFonts.montserrat(
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                backgroundColor: AppColors.cardBackground,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                margin: const EdgeInsets.all(16),
                duration: const Duration(seconds: 4),
                elevation: 6,
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No authentication settings found. Please reset credentials.',
                        style: GoogleFonts.montserrat(
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                backgroundColor: AppColors.cardBackground,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                margin: const EdgeInsets.all(16),
                duration: const Duration(seconds: 5),
                elevation: 6,
              ) );
    }
    }
    } catch (e) {
    LogPage.addLog('Login error: $e');
    if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
    content: Row(
    children: [
    Icon(Icons.error_outline, color: AppColors.errorText, size: 24),
    const SizedBox(width: 8),
    Expanded(
    child: Text(
    'Error during login. Please try again.',
    style: GoogleFonts.montserrat(
    fontSize: 16,
    color: AppColors.textPrimary,
    ),
    ),
    ),
    ],
    ),
    backgroundColor: AppColors.cardBackground,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    margin: const EdgeInsets.all(16),
    duration: const Duration(seconds: 4),
    elevation: 6,
    ),
    );
    }
    } finally {
    if (mounted) {
    setState(() {
    _isAuthenticating = false;
    });
    }
    }
  }

  void _showForgotPasswordDialog() {
    bool isResetting = false;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              backgroundColor: AppColors.cardBackground,
              contentPadding: const EdgeInsets.all(24),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.vpn_key, color: _accentColor, size: 40),
                    const SizedBox(height: 16),
                    Text(
                      'Master Password Required',
                      style: GoogleFonts.montserrat(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Enter the master password to reset credentials.',
                      style: GoogleFonts.montserrat(
                        fontSize: 14,
                        color: AppColors.textPrimary.withOpacity(0.7),
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _masterPasswordController,
                      label: 'Master Password',
                      icon: Icons.vpn_key,
                      obscureText: _isMasterPasswordObscured,
                      onVisibilityToggle: () {
                        setDialogState(() {
                          _isMasterPasswordObscured = !_isMasterPasswordObscured;
                        });
                      },
                    ),
                    if (isResetting) ...[
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: _newUsernameController,
                        label: 'New Username',
                        icon: Icons.person,
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: _newPasswordController,
                        label: 'New Password',
                        icon: Icons.lock,
                        obscureText: _isNewPasswordObscured,
                        onVisibilityToggle: () {
                          setDialogState(() {
                            _isNewPasswordObscured = !_isNewPasswordObscured;
                          });
                        },
                      ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildButton(
                          text: 'Cancel',
                          color: Colors.grey[400]!,
                          textColor: AppColors.textPrimary,
                          onTap: () {
                            _masterPasswordController.clear();
                            _newUsernameController.clear();
                            _newPasswordController.clear();
                            Navigator.of(context).pop();
                          },
                        ),
                        _buildButton(
                          text: isResetting ? 'Reset Password' : 'Verify',
                          color: _accentColor,
                          textColor: Colors.white,
                          onTap: () async {
                            if (_masterPasswordController.text == _masterPassword) {
                              if (isResetting) {
                                if (_newUsernameController.text.isEmpty || _newPasswordController.text.isEmpty) {
                                  Navigator.of(context).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Please enter both username and password.',
                                              style: GoogleFonts.montserrat(
                                                fontSize: 16,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      backgroundColor: AppColors.cardBackground,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      margin: const EdgeInsets.all(16),
                                      duration: const Duration(seconds: 4),
                                      elevation: 6,
                                    ),
                                  );
                                  return;
                                }
                                try {
                                  await DatabaseManager().saveAuthSettings(
                                    true,
                                    _newUsernameController.text,
                                    _newPasswordController.text,
                                  );
                                  Navigator.of(context).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          Icon(Icons.check_circle, color: _accentColor, size: 24),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Password reset successfully.',
                                              style: GoogleFonts.montserrat(
                                                fontSize: 16,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      backgroundColor: AppColors.cardBackground,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      margin: const EdgeInsets.all(16),
                                      duration: const Duration(seconds: 3),
                                      elevation: 6,
                                    ),
                                  );
                                  _usernameController.clear();
                                  _passwordController.clear();
                                } catch (e) {
                                  LogPage.addLog('Password reset error: $e');
                                  Navigator.of(context).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          Icon(Icons.error_outline, color: AppColors.errorText, size: 24),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Error resetting password. Please try again.',
                                              style: GoogleFonts.montserrat(
                                                fontSize: 16,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      backgroundColor: AppColors.cardBackground,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      margin: const EdgeInsets.all(16),
                                      duration: const Duration(seconds: 4),
                                      elevation: 6,
                                    ),
                                  );
                                }
                                _masterPasswordController.clear();
                                _newUsernameController.clear();
                                _newPasswordController.clear();
                              } else {
                                setDialogState(() {
                                  isResetting = true;
                                });
                              }
                            } else {
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      Icon(Icons.error_outline, color: AppColors.errorText, size: 24),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Invalid master password. Please try again.',
                                          style: GoogleFonts.montserrat(
                                            fontSize: 16,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  backgroundColor: AppColors.cardBackground,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  margin: const EdgeInsets.all(16),
                                  duration: const Duration(seconds: 4),
                                  elevation: 6,
                                ),
                              );
                              _masterPasswordController.clear();
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _masterPasswordController.dispose();
    _newUsernameController.dispose();
    _newPasswordController.dispose();
    _appLoadAnimationController.dispose();
    _loginSuccessAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56.0),
        child: CustomTitleBar(title: 'Countronics Smart Logger', customColor: Colors.white),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedWaveformBackground(),
          ),
          Positioned.fill(
            child: LoggerPulseBackground(),
          ),
          Positioned.fill(
            child: AnimatedIconBackground(),
          ),
          SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              transitionBuilder: (child, animation) {
                if (child.key == const ValueKey('loadingScreen') || child.key == const ValueKey('errorScreen')) {
                  return FadeTransition(opacity: animation, child: child);
                }
                return child;
              },
              child: _isLoading
                  ? _buildLoadingWidget()
                  : _errorMessage != null
                  ? _buildErrorWidget()
                  : _buildLoginForm(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Center(
      key: const ValueKey('loadingScreen'),
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/logo_animation.gif',
                width: 180,
                height: 180,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.thermostat,
                    color: _accentColor,
                    size: 100,
                  );
                },
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (frame == null) {
                    return SizedBox(
                      width: 100,
                      height: 100,
                      child: CircularProgressIndicator(
                        color: _accentColor,
                        strokeWidth: 4,
                      ),
                    );
                  }
                  return child;
                },
              ),
              const SizedBox(height: 24),
              Text(
                'Initializing Application...',
                style: GoogleFonts.montserrat(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Please wait while we prepare your workspace.',
                style: GoogleFonts.montserrat(
                  fontSize: 16,
                  color: AppColors.textPrimary.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      key: const ValueKey('errorScreen'),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          width: 400,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.headerBackground,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.2),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                color: AppColors.errorText,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage ?? 'Unknown Error',
                style: GoogleFonts.montserrat(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              _buildButton(
                text: 'Retry',
                color: _accentColor,
                textColor: Colors.white,
                onTap: () {
                  setState(() {
                    _errorMessage = null;
                    _isLoading = true;
                  });
                  _appLoadAnimationController.reset();
                  _checkDatabase();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return LayoutBuilder(
      key: const ValueKey('loginForm'),
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 24),
                Center(
                  child: SizedBox(
                    width: constraints.maxWidth * 0.9 > 400 ? 400 : constraints.maxWidth * 0.9,
                    child: Column(
                      children: [
                        Container(
                          width: 400,
                          height: 120,
                          decoration: BoxDecoration(
                            color: AppColors.cardBackground,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.headerBackground,
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.1),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              'assets/images/logo_animation.gif',
                              fit: BoxFit.cover,
                              color: AppColors.headerBackground.withOpacity(0.5),
                              colorBlendMode: BlendMode.multiply,
                              errorBuilder: (context, error, stackTrace) {
                                LogPage.addLog('GIF render error: $error');
                                return Container(
                                  color: AppColors.cardBackground,
                                  child: Center(
                                    child: Icon(
                                      Icons.thermostat,
                                      color: _accentColor,
                                      size: 48,
                                    ),
                                  ),
                                );
                              },
                              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                                if (frame == null) {
                                  return Center(
                                    child: CircularProgressIndicator(
                                      color: _accentColor,
                                      strokeWidth: 2,
                                    ),
                                  );
                                }
                                return child;
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Countronics Smart Logger',
                          style: GoogleFonts.montserrat(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppColors.cardBackground,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.headerBackground,
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.1),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'System Access',
                                style: GoogleFonts.montserrat(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildTextField(
                                controller: _usernameController,
                                label: 'Username',
                                icon: Icons.person,
                                obscureText: false,
                              ),
                              const SizedBox(height: 12),
                              _buildTextField(
                                controller: _passwordController,
                                label: 'Password',
                                icon: Icons.lock,
                                obscureText: _isPasswordObscured,
                                onVisibilityToggle: () {
                                  setState(() {
                                    _isPasswordObscured = !_isPasswordObscured;
                                  });
                                },
                              ),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _showForgotPasswordDialog,
                                  child: Text(
                                    'Reset Credentials',
                                    style: GoogleFonts.montserrat(
                                      fontSize: 14,
                                      color: _accentColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              GestureDetector(
                                onTap: _isAuthenticating || _showSuccessAnimation ? null : _login,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                                  decoration: BoxDecoration(
                                    color: (_isAuthenticating || _showSuccessAnimation)
                                        ? _accentColor.withOpacity(0.7)
                                        : _accentColor,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _accentColor.withOpacity(0.4),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    transitionBuilder: (Widget child, Animation<double> animation) {
                                      return FadeTransition(
                                        opacity: animation,
                                        child: ScaleTransition(scale: animation, child: child),
                                      );
                                    },
                                    child: _isAuthenticating
                                        ? SizedBox(
                                      key: const ValueKey('loginLoader'),
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                        : _showSuccessAnimation
                                        ? ScaleTransition(
                                      key: const ValueKey('loginSuccess'),
                                      scale: _loginSuccessScaleAnimation,
                                      child: const Icon(
                                        Icons.check_circle,
                                        color: Colors.white,
                                        size: 30,
                                      ),
                                    )
                                        : Text(
                                      key: const ValueKey('loginText'),
                                      'Login',
                                      style: GoogleFonts.montserrat(
                                        fontSize: 18,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    VoidCallback? onVisibilityToggle,
  }) {
    // Determine if this is a password field based on the icon
    final isPasswordField = icon == Icons.lock || icon == Icons.vpn_key;

    return TextField(
      controller: controller,
      obscureText: obscureText,
      style: GoogleFonts.montserrat(
        fontSize: 16,
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.montserrat(
          fontSize: 14,
          color: AppColors.textPrimary.withOpacity(0.6),
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Icon(
          icon,
          color: _accentColor,
          size: 24,
        ),
        suffixIcon: isPasswordField
            ? IconButton(
          icon: Icon(
            obscureText ? Icons.visibility_off : Icons.visibility,
            color: _accentColor,
            size: 24,
          ),
          tooltip: obscureText ? 'Show password' : 'Hide password',
          onPressed: onVisibilityToggle,
        )
            : null,
        filled: true,
        fillColor: AppColors.cardBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: AppColors.headerBackground,
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: _accentColor,
            width: 2,
          ),
        ),
      ),
    );
  }

  Widget _buildButton({
    required String text,
    required Color color,
    required Color textColor,
    required VoidCallback onTap,
    bool isProminent = false,
    IconData? icon,
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
          color: color,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(isProminent ? 0.4 : 0.3),
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
                color: textColor,
                size: 20,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              text,
              style: GoogleFonts.montserrat(
                fontSize: isProminent ? 18 : 16,
                color: textColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AnimatedIconBackground extends StatefulWidget {
  const AnimatedIconBackground({super.key});

  @override
  _AnimatedIconBackgroundState createState() => _AnimatedIconBackgroundState();
}

class _AnimatedIconBackgroundState extends State<AnimatedIconBackground> with TickerProviderStateMixin {
  final List<Map<String, dynamic>> icons = [];
  final List<AnimationController> _controllers = [];
  final List<Animation<double>> _fadeAnimations = [];
  final List<Animation<double>> _scaleAnimations = [];
  final random = Random();
  final List<IconData> materialIcons = [
    Icons.thermostat,
    Icons.water_drop,
    Icons.sensors,
    Icons.graphic_eq,
    Icons.timer,
    Icons.wifi,
  ];

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 12; i++) {
      final controller = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 1000 + random.nextInt(1000)),
      );
      final fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      );
      final scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      );

      _controllers.add(controller);
      _fadeAnimations.add(fadeAnimation);
      _scaleAnimations.add(scaleAnimation);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = MediaQuery.of(context).size;
      icons.clear();
      for (int i = 0; i < 12; i++) {
        double x, y;
        final contentLeft = size.width * 0.25;
        final contentRight = size.width * 0.75;
        final contentTop = size.height * 0.25;
        final contentBottom = size.height * 0.75;

        do {
          x = random.nextDouble() * size.width;
          y = random.nextDouble() * size.height;
        } while (x > contentLeft && x < contentRight && y > contentTop && y < contentBottom);

        icons.add({
          'x': x,
          'y': y,
          'icon': materialIcons[random.nextInt(materialIcons.length)],
          'size': 30 + random.nextDouble() * 20,
          'opacity': 0.2 + random.nextDouble() * 0.1,
        });

        Future.delayed(Duration(milliseconds: random.nextInt(500)), () {
          if (mounted) _controllers[i].repeat(reverse: true);
        });
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: List.generate(icons.length, (index) {
        return AnimatedBuilder(
          animation: _controllers[index],
          builder: (context, child) {
            return Positioned(
              left: icons[index]['x'],
              top: icons[index]['y'],
              child: Opacity(
                opacity: _fadeAnimations[index].value * icons[index]['opacity'],
                child: Transform.scale(
                  scale: _scaleAnimations[index].value,
                  child: Icon(
                    icons[index]['icon'],
                    color: _LoginPageState._accentColor,
                    size: icons[index]['size'],
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

class AnimatedWaveformBackground extends StatefulWidget {
  const AnimatedWaveformBackground({super.key});

  @override
  _AnimatedWaveformBackgroundState createState() => _AnimatedWaveformBackgroundState();
}

class _AnimatedWaveformBackgroundState extends State<AnimatedWaveformBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
    _animation = Tween<double>(begin: 0.0, end: 2 * pi).animate(
      CurvedAnimation(parent: _controller, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return CustomPaint(
          painter: WaveformBackgroundPainter(phase: _animation.value),
          child: Container(),
        );
      },
    );
  }
}

class WaveformBackgroundPainter extends CustomPainter {
  final double phase;
  static const Color _accentColor = Color(0xFF455A64);

  WaveformBackgroundPainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final waves = [
      {'amplitude': 20.0, 'frequency': 0.002, 'offset': 0.2, 'opacity': 0.15},
      {'amplitude': 15.0, 'frequency': 0.003, 'offset': 0.4, 'opacity': 0.1},
      {'amplitude': 25.0, 'frequency': 0.0015, 'offset': 0.6, 'opacity': 0.2},
    ];

    for (var wave in waves) {
      final amplitude = wave['amplitude'] as double;
      final frequency = wave['frequency'] as double;
      final offset = wave['offset'] as double;
      final opacity = wave['opacity'] as double;

      final paint = Paint()
        ..shader = LinearGradient(
          colors: [
            _accentColor.withOpacity(opacity),
            _accentColor.withOpacity(opacity * 0.5),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
        ..style = PaintingStyle.fill;

      final path = Path();
      path.moveTo(0, size.height * offset);

      for (double x = 0; x <= size.width; x += 1) {
        final y = size.height * offset + sin((x * frequency + phase) * 2 * pi) * amplitude;
        path.lineTo(x, y);
      }

      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant WaveformBackgroundPainter oldDelegate) {
    return oldDelegate.phase != phase;
  }
}

class LoggerPulseBackground extends StatefulWidget {
  const LoggerPulseBackground({super.key});

  @override
  _LoggerPulseBackgroundState createState() => _LoggerPulseBackgroundState();
}

class _LoggerPulseBackgroundState extends State<LoggerPulseBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return CustomPaint(
          painter: LoggerPulsePainter(progress: _animation.value),
          child: Container(),
        );
      },
    );
  }
}

class LoggerPulsePainter extends CustomPainter {
  final double progress;
  static const Color _accentColor = Color(0xFF455A64);

  LoggerPulsePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _accentColor.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    const pulseCount = 4;
    const dashLength = 20.0;
    const gapLength = 10.0;
    const verticalSpacing = 80.0;

    for (int i = 0; i < pulseCount; i++) {
      final y = size.height * (0.1 + i * verticalSpacing / size.height);
      final path = Path();
      final offset = progress * (dashLength + gapLength);

      for (double x = -offset; x < size.width; x += dashLength + gapLength) {
        if (x + dashLength >= 0) {
          path.moveTo(x, y);
          path.lineTo(x + dashLength, y);
        }
      }

      final opacity = 0.3 + 0.2 * sin(progress * 2 * pi + i * pi / 2);
      paint.color = _accentColor.withOpacity(opacity);

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant LoggerPulsePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}