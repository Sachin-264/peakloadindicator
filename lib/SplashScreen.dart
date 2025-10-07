import 'dart:async';
import 'dart:developer';
import 'dart:developer' as dart_developer;
import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:simple_animations/animation_builder/loop_animation_builder.dart';
import 'package:simple_animations/animation_builder/play_animation_builder.dart';
import 'package:video_player/video_player.dart';

// --- MAIN WIDGET ---
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late VideoPlayerController _videoController;
  late Animation<double> _contentFadeAnimation;
  late Animation<double> _dividerAnimation;
  late Animation<Offset> _slideAnimation;
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();

    // --- Video Controller Initialization ---
    _videoController = VideoPlayerController.asset('assets/images/splashscreen.mp4')
      ..initialize().then((_) {
        // Ensure the first frame is shown after the video is initialized
        setState(() {
          _isVideoInitialized = true;
        });
        _videoController.play();
        _videoController.setLooping(true); // Loop the video
      }).catchError((error) {
        dart_developer.log('Error initializing video: $error', name: 'VideoPlayerError');
        setState(() {
          _isVideoInitialized = false;
        });
      });

    // --- Animation Controller Initialization ---
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.2, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.1, 0.7, curve: Curves.easeInOutCubic),
    ));

    _dividerAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.4, 0.9, curve: Curves.easeOut),
      ),
    );

    _contentFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.6, 1.0, curve: Curves.easeIn),
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Background Video Player
          if (_isVideoInitialized)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _videoController.value.size.width,
                height: _videoController.value.size.height,
                child: VideoPlayer(_videoController),
              ),
            )
          else
          // Fallback color while video loads or if it fails
            Container(
              color: const Color(0xFF0d113e),
              alignment: Alignment.center,
              child: const Text('Loading background...', style: TextStyle(color: Colors.white24)),
            ),

          // 2. Drifting Particle Effect
          const _ParticleBackground(),

          // 3. Right-Side Frosted Glass
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: screenWidth / 2,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                child: Container(color: const Color(0xFF0d113e).withOpacity(0.3)),
              ),
            ),
          ),

          // 4. Animated UI Content
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 60.0),
              child: _SplashContent(
                slideAnimation: _slideAnimation,
                dividerAnimation: _dividerAnimation,
                contentFadeAnimation: _contentFadeAnimation,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- UI CONTENT WIDGET ---
class _SplashContent extends StatelessWidget {
  final Animation<Offset> slideAnimation;
  final Animation<double> dividerAnimation;
  final Animation<double> contentFadeAnimation;

  const _SplashContent({
    required this.slideAnimation,
    required this.dividerAnimation,
    required this.contentFadeAnimation,
  });

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: slideAnimation,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _ShimmerText(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Countron',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.montserrat(
                    fontSize: 50,
                    fontWeight: FontWeight.w300,
                    color: Colors.white.withOpacity(0.9),
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  'Smart Logger',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.montserrat(
                    fontSize: 52,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          _RevealedContent(
            dividerAnimation: dividerAnimation,
            contentFadeAnimation: contentFadeAnimation,
          ),
        ],
      ),
    );
  }
}

// --- WIDGET FOR REVEAL ANIMATION ---
class _RevealedContent extends StatelessWidget {
  final Animation<double> dividerAnimation;
  final Animation<double> contentFadeAnimation;

  const _RevealedContent({required this.dividerAnimation, required this.contentFadeAnimation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: dividerAnimation,
      builder: (context, child) {
        return Align(
          alignment: Alignment.centerRight,
          child: ClipRect(
            child: Align(
              alignment: Alignment.centerRight,
              widthFactor: dividerAnimation.value,
              child: child,
            ),
          ),
        );
      },
      child: FadeTransition(
        opacity: contentFadeAnimation,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const _AnimatedDivider(),
            const SizedBox(height: 30),
            Text(
              'Precision Monitoring, Redefined.',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'Lato',
                fontSize: 18,
                fontWeight: FontWeight.w400,
                color: Colors.white70,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 80),
            _AnimatedLoadingBar(listenable: contentFadeAnimation),
          ],
        ),
      ),
    );
  }
}

// --- WIDGET FOR SHIMMER TEXT EFFECT ---
class _ShimmerText extends StatelessWidget {
  final Widget child;
  const _ShimmerText({required this.child});

  @override
  Widget build(BuildContext context) {
    return LoopAnimationBuilder<double>(
      tween: Tween(begin: -1.5, end: 1.5),
      duration: const Duration(seconds: 4),
      curve: Curves.easeInOut,
      builder: (context, value, _) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [Colors.white, Colors.white, Colors.white24, Colors.white, Colors.white],
              stops: [0.0, value - 0.1, value, value + 0.1, 1.0],
              tileMode: TileMode.clamp,
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcIn,
          child: child,
        );
      },
    );
  }
}

// --- WIDGETS FOR PARTICLE EFFECT ---
class _ParticleBackground extends StatelessWidget {
  const _ParticleBackground();

  @override
  Widget build(BuildContext context) {
    return PlayAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 800),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: child,
        );
      },
      child: const Stack(
        children: [
          _Particles(40),
        ],
      ),
    );
  }
}

class _Particles extends StatefulWidget {
  final int numberOfParticles;
  const _Particles(this.numberOfParticles);

  @override
  State<_Particles> createState() => _ParticlesState();
}

class _ParticlesState extends State<_Particles> {
  final Random random = Random();
  final List<_ParticleModel> particles = [];

  @override
  void initState() {
    super.initState();
    List.generate(widget.numberOfParticles, (index) {
      particles.add(_ParticleModel(random));
    });
  }

  @override
  Widget build(BuildContext context) {
    return LoopAnimationBuilder(
      tween: ConstantTween(1),
      builder: (context, _, __) {
        _simulateParticles();
        return CustomPaint(
          painter: _ParticlePainter(particles),
        );
      },
      duration: const Duration(seconds: 1),
    );
  }

  void _simulateParticles() {
    for (var particle in particles) {
      particle.move();
    }
  }
}

class _ParticleModel {
  late double x;
  late double y;
  late double speed;
  late double size;
  late Color color;
  final Random random;

  _ParticleModel(this.random) {
    _reset();
  }

  void _reset() {
    x = random.nextDouble() * 2 - 1;
    y = random.nextDouble() * 2 - 1;
    speed = random.nextDouble() * 0.008 + 0.002;
    size = random.nextDouble() * 2.5 + 1.5;
    color = Colors.white.withOpacity(random.nextDouble() * 0.4 + 0.1);
  }

  void move() {
    y -= speed;
    if (y < -1.1) {
      _reset();
      y = 1.1;
    }
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_ParticleModel> particles;
  _ParticlePainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    for (var particle in particles) {
      final pos = Offset(
        (particle.x * 0.5 + 0.5) * size.width,
        (particle.y * 0.5 + 0.5) * size.height,
      );
      paint.color = particle.color;
      canvas.drawCircle(pos, particle.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// --- REFACTORED DIVIDER AND LOADING BAR ---
class _AnimatedDivider extends StatelessWidget {
  const _AnimatedDivider();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      height: 2,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _AnimatedLoadingBar extends StatelessWidget {
  final Animation<double> listenable;
  const _AnimatedLoadingBar({required this.listenable});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('Initializing...', style: GoogleFonts.lato(fontSize: 14, color: Colors.white.withOpacity(0.75))),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 6,
            width: 200,
            color: Colors.white.withOpacity(0.2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AnimatedBuilder(
                animation: listenable,
                builder: (context, child) {
                  return FractionallySizedBox(
                    widthFactor: listenable.value,
                    child: child,
                  );
                },
                child: Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}