
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:peakloadindicator/constants/theme.dart';
import '../constants/colors.dart';
import '../constants/global.dart';

class LoaderWidget extends StatefulWidget {
final Color? color; // Optional accent color
final double? size; // Optional spinner size
final String? text; // Optional loading text

const LoaderWidget({
super.key,
this.color,
this.size,
this.text,
});

@override
State<LoaderWidget> createState() => _LoaderWidgetState();
}

class _LoaderWidgetState extends State<LoaderWidget> with SingleTickerProviderStateMixin {
late AnimationController _animationController;
late Animation<double> _scaleAnimation;

@override
void initState() {
super.initState();
_animationController = AnimationController(
vsync: this,
duration: const Duration(milliseconds: 800),
)..repeat(reverse: true);
_scaleAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
);
}

@override
void dispose() {
_animationController.dispose();
super.dispose();
}

@override
Widget build(BuildContext context) {
return ValueListenableBuilder<bool>(
valueListenable: Global.isDarkMode,
builder: (context, isDarkMode, child) {
final accentColor = widget.color ?? Colors.blueGrey; // Default to match HomePage
final spinnerSize = widget.size ?? 60.0;
final loadingText = widget.text ?? 'Loading...';

return Center(
child: BackdropFilter(
filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
child: ScaleTransition(
scale: _scaleAnimation,
child: Container(
padding: const EdgeInsets.all(24),
decoration: BoxDecoration(
color: ThemeColors.getColor('cardBackground', isDarkMode).withOpacity(0.9),
borderRadius: BorderRadius.circular(16),
border: Border.all(
color: ThemeColors.getColor('cardBorder', isDarkMode),
width: 1,
),
boxShadow: [
BoxShadow(
color: Colors.black.withOpacity(isDarkMode ? 0.1 : 0.15),
blurRadius: 10,
spreadRadius: 2,
),
],
gradient: LinearGradient(
colors: [
ThemeColors.getColor('headerBackground', isDarkMode).withOpacity(0.3),
ThemeColors.getColor('cardBackground', isDarkMode).withOpacity(0.3),
],
begin: Alignment.topLeft,
end: Alignment.bottomRight,
),
),
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
SpinKitWaveSpinner(
color: accentColor,
size: spinnerSize,
waveColor: ThemeColors.getColor('buttonGradientStart', isDarkMode),
trackColor: ThemeColors.getColor('headerBackground', isDarkMode),
),
const SizedBox(height: 16),
Text(
loadingText,
style: GoogleFonts.poppins(
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
);
},
);
}
}
