import 'package:flutter/material.dart';

class ChannelDataProvider with ChangeNotifier {
  Map<String, Map<String, dynamic>> _windowData = {};

  void setWindowData(String windowKey, Map<String, dynamic> data) {
    _windowData[windowKey] = data;
    notifyListeners();
  }

  Map<String, dynamic>? getWindowData(String windowKey) {
    return _windowData[windowKey];
  }

  void removeWindowData(String windowKey) {
    _windowData.remove(windowKey);
    notifyListeners();
  }
}