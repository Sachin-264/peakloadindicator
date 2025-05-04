import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Global {
  static ValueNotifier<String> selectedPort = ValueNotifier('No Ports');
  static ValueNotifier<Set> selectedRecNos = ValueNotifier({});
  static ValueNotifier<String> selectedMode = ValueNotifier('Combined');
  static ValueNotifier<int?>? selectedRecNo;

  static ValueNotifier<String?> selectedFileName = ValueNotifier(null);
  static ValueNotifier<String?> operatorName = ValueNotifier(null);

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


}