import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Global {
  // Add a GlobalKey for NavigatorState
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static ValueNotifier<String> selectedPort = ValueNotifier('No Ports');
  static ValueNotifier<Set> selectedRecNos = ValueNotifier({});
  static ValueNotifier<String> selectedMode = ValueNotifier('Combined');
  static ValueNotifier<int?>? selectedRecNo;

  static ValueNotifier<String?> selectedFileName = ValueNotifier(null);
  static ValueNotifier<String?> operatorName = ValueNotifier(null);
  static ValueNotifier<String?> selectedDBName = ValueNotifier(null);

  // Scanning Rate fields
  static ValueNotifier<int?> scanningRate = ValueNotifier(null);
  static ValueNotifier<int?> scanningRateHH = ValueNotifier(null);
  static ValueNotifier<int?> scanningRateMM = ValueNotifier(null);
  static ValueNotifier<int?> scanningRateSS = ValueNotifier(null);

  // Test Duration fields
  static ValueNotifier<int?> testDurationDD = ValueNotifier(null);
  static ValueNotifier<int?> testDurationHH = ValueNotifier(null);
  static ValueNotifier<int?> testDurationMM = ValueNotifier(null);
  static ValueNotifier<int?> testDurationSS = ValueNotifier(null);
  static ValueNotifier<String?> graphVisibleArea = ValueNotifier(null);

  // Port details
  static ValueNotifier<int> baudRate = ValueNotifier(9600);
  static ValueNotifier<int> dataBits = ValueNotifier(8);
  static ValueNotifier<String> parity = ValueNotifier('None');
  static ValueNotifier<int> stopBits = ValueNotifier(1);

  // Dark Mode
  static ValueNotifier<bool> isDarkMode = ValueNotifier<bool>(false);

  // Add isScanningNotifier to Global class
  static ValueNotifier<bool> isScanningNotifier = ValueNotifier<bool>(false);

  // Initialize theme from shared preferences
  static Future<void> initTheme() async {
    final prefs = await SharedPreferences.getInstance();
    isDarkMode.value = prefs.getBool('isDarkMode') ?? false;
  }

  // Save theme to shared preferences
  static Future<void> saveTheme(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', isDark);
    isDarkMode.value = isDark;
  }

  static final StreamController<Map<String, dynamic>> _graphDataStreamController =
  StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get graphDataStream => _graphDataStreamController.stream;
  static Sink<Map<String, dynamic>> get graphDataSink => _graphDataStreamController.sink;
  static bool get hasGraphDataListener => _graphDataStreamController.hasListener;
  // Good practice: a dispose method for global resources, though not automatically called for static classes
  static void dispose() {
    _graphDataStreamController.close();
    // No need to dispose ValueNotifiers as they are static and managed by Flutter.
    // If you had listeners that needed manual removal, you'd put them here.
  }
}