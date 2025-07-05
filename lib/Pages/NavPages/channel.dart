// lib/screens/serial_port/channel.dart
import 'package:flutter/material.dart';

class Channel {
  final double recNo;
  final String channelName;
  final String startingCharacter;
  final int dataLength;
  final int decimalPlaces;
  final String unit;
  final double chartMaximumValue;
  final double chartMinimumValue;
  final double? targetAlarmMax; // Nullable
  final double? targetAlarmMin; // Nullable
  final int graphLineColour;
  final int targetAlarmColour;

  Channel({
    required this.recNo,
    required this.channelName,
    required this.startingCharacter,
    required this.dataLength,
    required this.decimalPlaces,
    required this.unit,
    required this.chartMaximumValue,
    required this.chartMinimumValue,
    this.targetAlarmMax,
    this.targetAlarmMin,
    required this.graphLineColour,
    required this.targetAlarmColour,
  });

  factory Channel.fromJson(Map<String, dynamic> json) {
    int _parseToInt(dynamic value, int defaultValue) {
      if (value == null) return defaultValue;
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) {
        int? parsedInt = int.tryParse(value);
        if (parsedInt != null) return parsedInt;
        double? parsedDouble = double.tryParse(value);
        if (parsedDouble != null) return parsedDouble.toInt();
        return defaultValue;
      }
      return defaultValue;
    }

    double _parseToDouble(dynamic value, double defaultValue) {
      if (value == null) return defaultValue;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? defaultValue;
      return defaultValue;
    }

    double? _parseToNullableDouble(dynamic value) {
      if (value == null) return null;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    int _parseColor(dynamic colorValue, int defaultValue) {
      if (colorValue is String && colorValue.isNotEmpty) {
        String hex = colorValue.replaceAll('#', '').toUpperCase();
        if (hex.length == 3) hex = hex.split('').map((c) => c + c).join('');
        if (hex.length == 6) hex = 'FF$hex';
        if (hex.length == 8) {
          try {
            return int.parse(hex, radix: 16);
          } catch (e) {
            return defaultValue;
          }
        }
        return defaultValue;
      } else if (colorValue is int) {
        if (colorValue & 0xFF000000 == 0) return 0xFF000000 | colorValue;
        return colorValue;
      }
      return defaultValue;
    }

    const int defaultGraphColor = 0xFF00FF00;
    const int defaultAlarmColor = 0xFFFF0000;

    return Channel(
      recNo: _parseToDouble(json['RecNo'], 0.0),
      channelName: json['ChannelName'] as String? ?? '',
      startingCharacter: json['StartingCharacter'] as String? ?? '',
      dataLength: _parseToInt(json['DataLength'], 7),
      decimalPlaces: _parseToInt(json['DecimalPlaces'], 1),
      unit: json['Unit'] as String? ?? '',
      chartMaximumValue: _parseToDouble(json['ChartMaximumValue'], 100.0),
      chartMinimumValue: _parseToDouble(json['ChartMinimumValue'], 0.0),
      targetAlarmMax: _parseToNullableDouble(json['TargetAlarmMax']),
      targetAlarmMin: _parseToNullableDouble(json['TargetAlarmMin']),
      graphLineColour: _parseColor(json['graphLineColour'], defaultGraphColor),
      targetAlarmColour: _parseColor(json['TargetAlarmColour'], defaultAlarmColor),
    );
  }

  Map<String, dynamic> toJson() {
    String _toColorHexString(int colorValue) {
      return colorValue.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
    }

    return {
      'RecNo': recNo,
      'ChannelName': channelName,
      'StartingCharacter': startingCharacter,
      'DataLength': dataLength,
      'DecimalPlaces': decimalPlaces,
      'Unit': unit,
      'ChartMaximumValue': chartMaximumValue,
      'ChartMinimumValue': chartMinimumValue,
      'TargetAlarmMax': targetAlarmMax,
      'TargetAlarmMin': targetAlarmMin,
      'graphLineColour': _toColorHexString(graphLineColour),
      'TargetAlarmColour': _toColorHexString(targetAlarmColour),
    };
  }

  @override
  String toString() {
    return 'Channel('
        'recNo: $recNo, '
        'channelName: "$channelName", '
        'startingCharacter: "$startingCharacter", '
        'decimalPlaces: $decimalPlaces, '
        'targetAlarmMax: $targetAlarmMax, '
        'targetAlarmMin: $targetAlarmMin, '
        'graphLineColour: #${graphLineColour.toRadixString(16).padLeft(8, '0').toUpperCase()}'
        ')';
  }
}