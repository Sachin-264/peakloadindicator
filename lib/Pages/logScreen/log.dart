import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../constants/global.dart';
import '../../constants/theme.dart';


class LogPage extends StatefulWidget {
  static final List<String> _logs = [];

  const LogPage({super.key});

  static void addLog(String log) {
    _logs.insert(0, log);
    if (_logs.length > 100) _logs.removeLast();
  }

  static List<String> getRecentLogs(int count) {
    return _logs.take(count).toList();
  }

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
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
        return Container(
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
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Activity Log',
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: ThemeColors.getColor('dialogText', isDarkMode),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          LucideIcons.trash2,
                          color: ThemeColors.getColor('dialogText', isDarkMode),
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() {
                            LogPage._logs.clear();
                          });
                          LogPage.addLog('[$_currentTime] Cleared all logs');
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Track all application activities',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: ThemeColors.getColor('dialogSubText', isDarkMode),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: ThemeColors.getColor('cardBackground', isDarkMode),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            spreadRadius: 1,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        border: Border.all(
                          color: ThemeColors.getColor('cardBorder', isDarkMode),
                          width: 1,
                        ),
                      ),
                      child: LogPage._logs.isEmpty
                          ? Center(
                        child: Text(
                          'No logs available',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: ThemeColors.getColor('cardText', isDarkMode).withOpacity(0.7),
                          ),
                        ),
                      )
                          : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: LogPage._logs.length,
                        itemBuilder: (context, index) {
                          return FadeTransition(
                            opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
                              CurvedAnimation(
                                parent: _animationController,
                                curve: Interval(
                                  index / (LogPage._logs.length + 1),
                                  1.0,
                                  curve: Curves.easeOut,
                                ),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    margin: const EdgeInsets.only(top: 4),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: ThemeColors.getColor('buttonGradientStart', isDarkMode),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      LogPage._logs[index],
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        color: ThemeColors.getColor('cardText', isDarkMode),
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
            ),
          ),
        );
      },
    );
  }

  String get _currentTime => DateTime.now().toString().substring(0, 19);
}