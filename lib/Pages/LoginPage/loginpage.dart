import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../constants/colors.dart';
import '../../Pages/homepage.dart';
import '../../constants/database_manager.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _masterPasswordController = TextEditingController();
  final TextEditingController _newUsernameController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  bool _isLoading = true;
  bool _showSuccessAnimation = false;
  String? _errorMessage;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  static const String _masterPassword = 'admin@1234';
  static const Color _accentColor = Color(0xFF455A64); // Muted blue-grey

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
    _checkDatabase();
    _animationController.forward();

    // Preload GIF
    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(const AssetImage('assets/images/logo_animation.gif'), context)
          .then((_) {
        print('GIF preloaded successfully');
      }).catchError((error) {
        print('GIF loading error: $error');
      });
    });
  }

  Future<void> _checkDatabase() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null; // Clear any previous error
    });

    try {
      await DatabaseManager().database;
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Database initialization error: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error initializing database. Please try again.';
      });
    }
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authData = await DatabaseManager().getAuthSettings();
      if (authData != null) {
        final storedUsername = authData['username'] as String? ?? '';
        final storedPassword = authData['password'] as String? ?? '';
        if (_usernameController.text == storedUsername && _passwordController.text == storedPassword) {
          setState(() {
            _showSuccessAnimation = true;
          });
          await Future.delayed(const Duration(seconds: 1));
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomePage()),
          );
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Invalid username or password';
          });
          await Future.delayed(const Duration(milliseconds: 300));
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
        setState(() {
          _isLoading = false;
          _errorMessage = 'No authentication settings found';
        });
      }
    } catch (e) {
      print('Login error: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error during login. Please try again.';
      });
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
              content: Container(
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
                      obscureText: true,
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
                        obscureText: true,
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
                                          Icon(Icons.error_outline, color: AppColors.errorText, size: 24),
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
                                    ),
                                  );
                                  return;
                                }
                                try {
                                  await DatabaseManager().saveAuthSettings(
                                    true,
                                    _newUsernameController.text,
                                    _newPasswordController.text
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
                                    ),
                                  );
                                } catch (e) {
                                  print('Password reset error: $e');
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
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: WaveformBackgroundPainter(),
            ),
          ),
          Positioned.fill(
            child: AnimatedIconBackground(),
          ),
          SafeArea(
            child: _isLoading
                ? Center(
              child: CircularProgressIndicator(
                color: _accentColor,
                strokeWidth: 4,
                backgroundColor: AppColors.headerBackground,
              ),
            )
                : _errorMessage != null
                ? Center(
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
                        _errorMessage!,
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
                            _errorMessage = null; // Clear error
                            _isLoading = true; // Show loading
                          });
                          _checkDatabase(); // Retry database check
                        },
                      ),
                    ],
                  ),
                ),
              ),
            )
                : FadeTransition(
              opacity: _fadeAnimation,
              child: LayoutBuilder(
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
                            child: Container(
                              width: constraints.maxWidth * 0.9 > 400
                                  ? 400
                                  : constraints.maxWidth * 0.9,
                              child: Column(
                                children: [
                                  // GIF
                                  Container(
                                    width: 400,
                                    height: 120,
                                    decoration: BoxDecoration(
                                      color: AppColors.cardBackground,
                                      borderRadius:
                                      BorderRadius.circular(12),
                                      border: Border.all(
                                        color:
                                        AppColors.headerBackground,
                                        width: 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.grey
                                              .withOpacity(0.1),
                                          blurRadius: 8,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius:
                                      BorderRadius.circular(12),
                                      child: Image.asset(
                                        'assets/images/logo_animation.gif',
                                        fit: BoxFit.cover,
                                        color: AppColors
                                            .headerBackground
                                            .withOpacity(0.5),
                                        colorBlendMode:
                                        BlendMode.multiply,
                                        errorBuilder: (context, error,
                                            stackTrace) {
                                          print(
                                              'GIF render error: $error');
                                          return Container(
                                            color: AppColors
                                                .cardBackground,
                                            child: Center(
                                              child: Icon(
                                                Icons.thermostat,
                                                color: _accentColor,
                                                size: 48,
                                              ),
                                            ),
                                          );
                                        },
                                        frameBuilder: (context, child,
                                            frame, wasSynchronouslyLoaded) {
                                          if (frame == null) {
                                            return Center(
                                              child:
                                              CircularProgressIndicator(
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
                                  // Login Form
                                  Container(
                                    padding: const EdgeInsets.all(24),
                                    decoration: BoxDecoration(
                                      color: AppColors.cardBackground,
                                      borderRadius:
                                      BorderRadius.circular(12),
                                      border: Border.all(
                                        color: AppColors
                                            .headerBackground,
                                        width: 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.grey
                                              .withOpacity(0.1),
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
                                            color:
                                            AppColors.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        _buildTextField(
                                          controller:
                                          _usernameController,
                                          label: 'Username',
                                          icon: Icons.person,
                                          obscureText: false,
                                        ),
                                        const SizedBox(height: 12),
                                        _buildTextField(
                                          controller:
                                          _passwordController,
                                          label: 'Password',
                                          icon: Icons.lock,
                                          obscureText: true,
                                        ),
                                        const SizedBox(height: 12),
                                        Align(
                                          alignment:
                                          Alignment.centerRight,
                                          child: TextButton(
                                            onPressed:
                                            _showForgotPasswordDialog,
                                            child: Text(
                                              'Reset Credentials',
                                              style: GoogleFonts
                                                  .montserrat(
                                                fontSize: 14,
                                                color: _accentColor,
                                                fontWeight:
                                                FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            _buildButton(
                                              text: 'Login',
                                              color: _accentColor,
                                              textColor: Colors.white,
                                              onTap: _login,
                                              isProminent: true,
                                            ),
                                            if (_showSuccessAnimation)
                                              ScaleTransition(
                                                scale: _scaleAnimation,
                                                child: Icon(
                                                  Icons.check_circle,
                                                  color: _accentColor,
                                                  size: 40,
                                                ),
                                              ),
                                          ],
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
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
  }) {
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

class _AnimatedIconBackgroundState extends State<AnimatedIconBackground>
    with TickerProviderStateMixin {
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
    // Initialize animation controllers
    for (int i = 0; i < 12; i++) {
      final controller = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 1000 + random.nextInt(1000)), // 1-2s
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

    // Generate icons after first frame to access MediaQuery
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = MediaQuery.of(context).size;
      icons.clear();
      for (int i = 0; i < 12; i++) {
        double x, y;
        do {
          x = random.nextDouble() * size.width;
          y = random.nextDouble() * size.height;
        } while (_isInContentArea(x, y, size));

        icons.add({
          'x': x,
          'y': y,
          'icon': materialIcons[random.nextInt(materialIcons.length)],
          'size': 30 + random.nextDouble() * 20, // 30-50px
          'opacity': 0.2 + random.nextDouble() * 0.1, // 0.2-0.3
        });

        // Start animation with random delay
        Future.delayed(Duration(milliseconds: random.nextInt(500)), () {
          if (mounted) _controllers[i].repeat(reverse: true);
        });
      }
      setState(() {});
    });
  }

  bool _isInContentArea(double x, double y, Size size) {
    // Define content area (roughly the middle 50% of the screen)
    final contentLeft = size.width * 0.25;
    final contentRight = size.width * 0.75;
    final contentTop = size.height * 0.25;
    final contentBottom = size.height * 0.75;
    return x > contentLeft && x < contentRight && y > contentTop && y < contentBottom;
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

class WaveformBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _LoginPageState._accentColor.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final path = Path();
    const waveHeight = 12.0;
    const waveLength = 50.0;
    for (double y = 0; y < size.height; y += 80) {
      path.moveTo(0, y);
      for (double x = 0; x <= size.width; x += waveLength) {
        path.quadraticBezierTo(
          x + waveLength / 4,
          y - waveHeight,
          x + waveLength / 2,
          y,
        );
        path.quadraticBezierTo(
          x + 3 * waveLength / 4,
          y + waveHeight,
          x + waveLength,
          y,
        );
      }
    }
    canvas.drawPath(path, paint);
    path.close();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}