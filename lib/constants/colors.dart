import 'package:flutter/material.dart';

class AppColors {
  // Primary Backgrounds
  static const Color background = Color(0xFFF2F4F7); // A very light, clean grey-blue for the main app background
  static const Color cardBackground = Color(0xFFFFFFFF); // Pure white for cards and elevated elements

  // Text Colors
  static const Color textPrimary = Color(0xFF2C3E50); // Deep, rich dark blue-grey for main text
  static const Color textSecondary = Color(0xFF7F8C8D); // Muted grey for less important text

  // Accent Colors - A sophisticated deep teal
  static const Color accentColor = Color(0xFF006970);
  static const Color accentDark = Color(0xFF004D40); // Darker shade for some accents
  static const Color accentLight = Color(0xFF00BFA5); // Lighter shade for highlights

  // UI Element Colors
  static const Color headerBackground = Color(0xFFE0E6EB); // Light grey for borders, dividers, subtle fills
  static const Color inputBackground = Color(0xFFF9FAFC); // Very light off-white for text field backgrounds

  // Status Colors
  static const Color errorText = Color(0xFFE74C3C); // Vibrant red for errors
  static const Color successText = Color(0xFF28A745); // Standard green for success
  static const Color warningText = Color(0xFFF39C12); // Orange for warnings

  // Button Colors (can reuse accent/status colors)
  static const Color submitButton = accentColor; // Default submit is accent
  static const Color resetButton = errorText; // Default reset is error red
}