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
  final dynamic graphLineColour; // Can be int or String from DB
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

  // --- NEW: copyWith method to solve the error ---
  /// Creates a copy of this Channel but with the given fields replaced with the new values.
  Channel copyWith({
    double? recNo,
    String? channelName,
    String? startingCharacter,
    int? dataLength,
    int? decimalPlaces,
    String? unit,
    double? chartMaximumValue,
    double? chartMinimumValue,
    double? targetAlarmMax,
    double? targetAlarmMin,
    dynamic graphLineColour,
    int? targetAlarmColour,
  }) {
    return Channel(
      recNo: recNo ?? this.recNo,
      channelName: channelName ?? this.channelName,
      startingCharacter: startingCharacter ?? this.startingCharacter,
      dataLength: dataLength ?? this.dataLength,
      decimalPlaces: decimalPlaces ?? this.decimalPlaces,
      unit: unit ?? this.unit,
      chartMaximumValue: chartMaximumValue ?? this.chartMaximumValue,
      chartMinimumValue: chartMinimumValue ?? this.chartMinimumValue,
      targetAlarmMax: targetAlarmMax ?? this.targetAlarmMax,
      targetAlarmMin: targetAlarmMin ?? this.targetAlarmMin,
      graphLineColour: graphLineColour ?? this.graphLineColour,
      targetAlarmColour: targetAlarmColour ?? this.targetAlarmColour,
    );
  }

  factory Channel.fromJson(Map<String, dynamic> json) {
    // --- Robust Parsing Helpers ---
    int _parseToInt(dynamic value, int defaultValue) {
      if (value == null) return defaultValue;
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value) ?? defaultValue;
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
      if (value == null || value.toString().isEmpty) return null;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    dynamic _parseGraphLineColour(dynamic colorValue) {
      if (colorValue is String && colorValue.isNotEmpty) {
        return colorValue;
      }
      if (colorValue is int) {
        return colorValue;
      }
      return '00FF00'; // Default to green hex string if invalid
    }

    int _parseTargetAlarmColour(dynamic colorValue) {
      const int defaultColor = 0xFFFF0000; // Red
      if (colorValue is String && colorValue.isNotEmpty) {
        String hex = colorValue.replaceAll('#', '').toUpperCase();
        if (hex.length == 6) hex = 'FF$hex';
        if (hex.length == 8) {
          return int.tryParse(hex, radix: 16) ?? defaultColor;
        }
      } else if (colorValue is int) {
        return colorValue;
      }
      return defaultColor;
    }
    // --- End of Parsing Helpers ---

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
      graphLineColour: _parseGraphLineColour(json['graphLineColour']),
      targetAlarmColour: _parseTargetAlarmColour(json['TargetAlarmColour']),
    );
  }

  Map<String, dynamic> toJson() {
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
      'graphLineColour': graphLineColour.toString(),
      'TargetAlarmColour': targetAlarmColour.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase(),
    };
  }
}