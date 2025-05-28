import 'package:flutter/material.dart';

enum ThemeMode { light, dark }

class ThemeColors {
  static dynamic getColor(String key, bool isDarkMode) {
    final mode = isDarkMode ? ThemeMode.dark : ThemeMode.light;
    switch (key) {
    // App Background
      case 'appBackground':
        return mode == ThemeMode.dark ? Colors.grey[900]! : const Color(0xFFF5F7FA);
      case 'appBackgroundSecondary':
        return mode == ThemeMode.dark ? Colors.grey[800]! : const Color(0xFFECEFF1);

    // Sidebar
      case 'sidebarBackground':
        return mode == ThemeMode.dark
            ? const Color(0xFF1E1E1E)
            : const Color(0xFFFFFFFF).withOpacity(0.95);
      case 'sidebarBorder':
        return mode == ThemeMode.dark
            ? Colors.white.withOpacity(0.1)
            : const Color(0xFF90CAF9);
      case 'sidebarGradientStart':
        return mode == ThemeMode.dark
            ? const Color(0xFF212121)
            : const Color(0xFF42A5F5);
      case 'sidebarGradientEnd':
        return mode == ThemeMode.dark
            ? const Color(0xFF121212)
            : const Color(0xFF1976D2);
      case 'sidebarText':
        return Colors.white;
      case 'sidebarIcon':
        return mode == ThemeMode.dark
            ? Colors.white.withOpacity(0.8)
            : Colors.white.withOpacity(0.9);
      case 'sidebarIconSelected':
        return mode == ThemeMode.dark
            ? const Color(0xFF26A69A)
            : Colors.white.withOpacity(0.9);
      case 'sidebarGlow':
        return mode == ThemeMode.dark
            ? const Color(0xFF26A69A)
            : const Color(0xFF64B5F6);

    // Dashboard Cards
      case 'cardBackground':
        return mode == ThemeMode.dark ? Colors.grey[800]!.withOpacity(0.9) : const Color(0xFFFFFFFF);
      case 'cardBorder':
        return mode == ThemeMode.dark ? Colors.white.withOpacity(0.1) : const Color(0xFFE0E4E8);
      case 'cardText': // Default text color for cards
        return mode == ThemeMode.dark ? Colors.white70 : const Color(0xFF455A64);
      case 'cardIcon':
        return mode == ThemeMode.dark ? Colors.teal[300]! : const Color(0xFF0288D1);
      case 'cardElevation':
        return mode == ThemeMode.dark ? 4.0 : 6.0;

    // Dialogs
      case 'dialogBackground':
        return mode == ThemeMode.dark ? Colors.grey[800]!.withOpacity(0.9) : const Color(0xFFFFFFFF);
      case 'dialogText': // Primary dialog text
        return mode == ThemeMode.dark ? Colors.white : const Color(0xFF1A237E);
      case 'dialogSubText': // Secondary dialog text (used for some grey text)
        return mode == ThemeMode.dark ? Colors.grey[400]! : const Color(0xFF455A64);

    // Dropdown (General)
      case 'dropdownBackground':
        return mode == ThemeMode.dark ? Colors.grey[800]! : const Color(0xFFFFFFFF);
      case 'dropdownHover':
        return mode == ThemeMode.dark ? Colors.grey[700]! : const Color(0xFFE3F2FD);

    // Text Field (General)
      case 'textFieldBackground':
        return mode == ThemeMode.dark ? Colors.grey[700]! : const Color(0xFFFFFFFF);
      case 'textFieldBorder': // Added for TextField borders if needed
        return mode == ThemeMode.dark ? Colors.white.withOpacity(0.2) : Colors.grey[300];

    // Table (General)
      case 'tableHeaderBackground':
        return mode == ThemeMode.dark ? Colors.grey[850]! : const Color(0xFFE3F2FD);
      case 'tableRowAlternate':
        return mode == ThemeMode.dark ? Colors.grey[850]! : const Color(0xFFECEFF1);

    // Buttons (General)
      case 'buttonGradientStart':
        return mode == ThemeMode.dark ? const Color(0xFF00695C) : const Color(0xFF0288D1);
      case 'buttonGradientEnd':
        return mode == ThemeMode.dark ? const Color(0xFF004D40) : const Color(0xFF01579B);
      case 'buttonHover':
        return mode == ThemeMode.dark ? Colors.teal[200]! : const Color(0xFF4FC3F7);
      case 'submitButton':
        return mode == ThemeMode.dark ? Colors.teal : const Color(0xFF0288D1);
      case 'resetButton':
        return mode == ThemeMode.dark ? Colors.red[400]! : const Color(0xFFEF5350);
      case 'errorText': // General error text color
        return mode == ThemeMode.dark ? Colors.red[300]! : const Color(0xFFD32F2F);

    // Title Bar
      case 'titleBarText':
        return mode == ThemeMode.dark ? Colors.white : const Color(0xFF1A237E);
      case 'titleBarIcon':
        return mode == ThemeMode.dark ? Colors.teal[300]! : const Color(0xFF0288D1);

    // --- NEW: SerialPortScreen Specific Colors ---
      case 'serialPortBackground':
        return mode == ThemeMode.dark ? Colors.grey[900]! : const Color(0xFFF0F2F5); // Slightly lighter light mode bg
      case 'serialPortCardBackground':
        return mode == ThemeMode.dark ? const Color(0xFF2C2C2C) : const Color(0xFFFFFFFF); // Deeper dark card, pure white light
      case 'serialPortCardBorder':
        return mode == ThemeMode.dark ? Colors.white.withOpacity(0.08) : Colors.grey[200]!; // Subtle border

      case 'serialPortInputFill':
        return mode == ThemeMode.dark ? Colors.grey[800]! : Colors.grey[50]!; // Clearer fill for inputs
      case 'serialPortInputLabel':
        return mode == ThemeMode.dark ? Colors.grey[400]! : Colors.grey[600]!; // Good contrast for labels
      case 'serialPortInputText':
        return mode == ThemeMode.dark ? Colors.white : Colors.grey[850]!; // Clear text input

      case 'serialPortDropdownBackground':
        return mode == ThemeMode.dark ? const Color(0xFF3A3A3A) : Colors.white; // Darker background for dropdown
      case 'serialPortDropdownText':
        return mode == ThemeMode.dark ? Colors.white : Colors.grey[850]!; // White text in dark mode, dark grey in light
      case 'serialPortDropdownIcon':
        return mode == ThemeMode.dark ? Colors.white70 : Colors.grey[700]!; // Visible icon

      case 'serialPortTableHeaderBackground':
        return mode == ThemeMode.dark ? const Color(0xFF383838) : const Color(0xFFE8F0FE); // Distinct header
      case 'serialPortTableRowEven':
        return mode == ThemeMode.dark ? const Color(0xFF2C2C2C) : Colors.white;
      case 'serialPortTableRowOdd':
        return mode == ThemeMode.dark ? const Color(0xFF333333) : const Color(0xFFF9FAFC); // Slight alternate tint

      case 'serialPortLiveValueBackground':
        return mode == ThemeMode.dark ? Colors.green.withOpacity(0.2) : Colors.green.withOpacity(0.1);
      case 'serialPortLiveValueText':
        return mode == ThemeMode.dark ? Colors.greenAccent[100]! : Colors.green[800]!; // Clear live data text

      case 'serialPortGraphAxisLabel':
        return mode == ThemeMode.dark ? Colors.white70 : Colors.grey[700]!; // Graph labels
      case 'serialPortGraphGridLine':
        return mode == ThemeMode.dark ? Colors.white.withOpacity(0.15) : Colors.grey[300]!; // Clearer grid lines

      case 'serialPortMessagePanelBackground':
        return mode == ThemeMode.dark ? const Color(0xFF282828) : const Color(0xFFF0F4F7); // Bottom panel background
      case 'serialPortMessageText': // For "Scanning active on COM6", "Ready to scan"
        return mode == ThemeMode.dark ? Colors.white70 : Colors.grey[700]!;
      case 'serialPortErrorTextSmall': // For concise error messages
        return mode == ThemeMode.dark ? Colors.red[300]! : Colors.red[700]!;


      default:
        return Colors.black; // Fallback
    }
  }

  static LinearGradient getButtonGradient(bool isDarkMode) {
    return LinearGradient(
      colors: [
        getColor('buttonGradientStart', isDarkMode),
        getColor('buttonGradientEnd', isDarkMode),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  static LinearGradient getDialogButtonGradient(bool isDarkMode, String type) {
    switch (type) {
      case 'backup':
        return LinearGradient(
          colors: [
            isDarkMode ? const Color(0xFF4CAF50) : const Color(0xFF66BB6A),
            isDarkMode ? const Color(0xFF388E3C) : const Color(0xFF388E3C),
          ],
        );
      default:
        return getButtonGradient(isDarkMode);
    }
  }

  static LinearGradient getTitleBarGradient(bool isDarkMode) {
    return LinearGradient(
      colors: isDarkMode
          ? [
        Colors.grey[850]!, // Deeper grey
        Colors.grey[900]!,
      ]
          : [
        const Color(0xFFBBDEFB), // Light blue
        const Color(0xFF64B5F6), // Vibrant blue
      ],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );
  }

  static LinearGradient getSidebarGradient(bool isDarkMode) {
    return LinearGradient(
      colors: [
        getColor('sidebarGradientStart', isDarkMode),
        getColor('sidebarGradientEnd', isDarkMode),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }
}