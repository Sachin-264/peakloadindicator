import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/colors.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _cardController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _waveController;
  late Animation<double> _waveAnimation;
  bool _gifLoaded = false;
  static const Color _accentColor = Color(0xFF455A64);

  @override
  void initState() {
    super.initState();
    // Card animation
    _cardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _cardController, curve: Curves.easeInOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _cardController, curve: Curves.easeOutCubic),
    );
    _cardController.forward();

    // Pulse animation for GIF
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutSine),
    );
    _pulseController.repeat(reverse: true);

    // Waveform animation
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _waveAnimation = Tween<double>(begin: -0.5, end: 0.5).animate(
      CurvedAnimation(parent: _waveController, curve: Curves.easeInSine),
    );
    _waveController.repeat(reverse: true);

    // Preload GIF
    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(const AssetImage('assets/images/logo_animation.gif'), context)
          .then((_) {
        setState(() => _gifLoaded = true);
      }).catchError((error) {
        print('GIF loading error: $error');
        setState(() => _gifLoaded = false);
      });
    });
  }

  @override
  void dispose() {
    _cardController.dispose();
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background ?? Colors.white,
      body: Stack(
        children: [
          // Radial gradient background
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.5,
                colors: [
                  AppColors.background ?? Colors.white,
                  Colors.grey[100]!.withOpacity(0.5),
                ],
              ),
            ),
          ),
          // Animated waveform
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _waveController,
              builder: (context, child) {
                return CustomPaint(
                  painter: _WaveformBackgroundPainter(offset: _waveAnimation.value),
                );
              },
            ),
          ),
          // Main content
          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.9 > 500
                      ? 500
                      : MediaQuery.of(context).size.width * 0.9,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground ?? Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.headerBackground ?? Colors.grey.shade200,
                      width: 1.5,
                    ),
                    gradient: LinearGradient(
                      colors: [
                        Colors.white,
                        Colors.grey[100]!.withOpacity(0.3),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        blurRadius: 8,
                        spreadRadius: 1,
                        offset: const Offset(0, 2),
                      ),
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.05),
                        blurRadius: 20,
                        spreadRadius: 5,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ScaleTransition(
                        scale: _pulseAnimation,
                        child: Container(
                          width: 500,
                          height: 150,
                          decoration: BoxDecoration(
                            color: AppColors.cardBackground ?? Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.headerBackground ?? Colors.grey.shade200,
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _accentColor.withOpacity(0.1),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: _gifLoaded
                                ? Image.asset(
                              'assets/images/logo_animation.gif',
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                print('GIF render error: $error');
                                return Container(
                                  color: AppColors.cardBackground ?? Colors.white,
                                  child: Center(
                                    child: Icon(
                                      Icons.thermostat,
                                      color: _accentColor,
                                      size: 60,
                                    ),
                                  ),
                                );
                              },
                            )
                                : Center(
                              child: CircularProgressIndicator(
                                color: _accentColor,
                                strokeWidth: 3,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Countronics Smart Logger',
                        style: GoogleFonts.montserrat(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary ?? Colors.black87,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Precision Monitoring',
                        style: GoogleFonts.montserrat(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          fontStyle: FontStyle.italic,
                          color: (AppColors.textPrimary ?? Colors.black87).withOpacity(0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      const _CustomLoader(),
                      const SizedBox(height: 12),
                      Text(
                        'Initializing...',
                        style: GoogleFonts.montserrat(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: _accentColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomLoader extends StatefulWidget {
  const _CustomLoader();

  @override
  __CustomLoaderState createState() => __CustomLoaderState();
}

class __CustomLoaderState extends State<_CustomLoader> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _DualRingLoaderPainter(
              progress: _controller.value,
              accentColor: _SplashScreenState._accentColor,
            ),
          );
        },
      ),
    );
  }
}

class _DualRingLoaderPainter extends CustomPainter {
  final double progress;
  final Color accentColor;

  _DualRingLoaderPainter({required this.progress, required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final innerRadius = size.width / 3;

    // Inner ring (solid)
    final innerPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, innerRadius, innerPaint);

    // Outer ring (fading segments)
    const segmentCount = 10;
    const segmentAngle = 2 * 3.14159 / segmentCount;
    const arcSize = 3.14159 / 15;
    for (int i = 0; i < segmentCount; i++) {
      final startAngle = i * segmentAngle + progress * 2 * 3.14159;
      final opacity = (1.0 - (i / segmentCount)).clamp(0.3, 1.0);
      final outerPaint = Paint()
        ..color = accentColor.withOpacity(opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: outerRadius - 2),
        startAngle,
        arcSize,
        false,
        outerPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_DualRingLoaderPainter oldDelegate) => true;
}

class _WaveformBackgroundPainter extends CustomPainter {
  final double offset;

  _WaveformBackgroundPainter({required this.offset});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _SplashScreenState._accentColor.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final path = Path();
    const waveHeight = 12.0;
    const waveLength = 80.0;
    for (double y = 0; y < size.height; y += 120) {
      final adjustedY = y + offset * waveHeight;
      path.moveTo(0, adjustedY);
      for (double x = 0; x <= size.width; x += waveLength) {
        path.quadraticBezierTo(
          x + waveLength / 4,
          adjustedY - waveHeight,
          x + waveLength / 2,
          adjustedY,
        );
        path.quadraticBezierTo(
          x + 3 * waveLength / 4,
          adjustedY + waveHeight,
          x + waveLength,
          adjustedY,
        );
      }
      canvas.drawPath(path, paint);
      path.reset();
    }
  }

  @override
  bool shouldRepaint(_WaveformBackgroundPainter oldDelegate) => oldDelegate.offset != offset;
}
