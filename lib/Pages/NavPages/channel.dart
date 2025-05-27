class Channel {
  final double recNo;
  final String channelName;
  final String startingCharacter;
  final int dataLength;
  final int decimalPlaces;
  final String unit;
  final double chartMaximumValue;
  final double chartMinimumValue;
  final double targetAlarmMax;
  final double targetAlarmMin;
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
    required this.targetAlarmMax,
    required this.targetAlarmMin,
    required this.graphLineColour,
    required this.targetAlarmColour,
  });

  factory Channel.fromJson(Map<String, dynamic> json) {
    // Helper to safely parse dynamic values to int
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

    // Helper to safely parse dynamic values to double
    double _parseToDouble(dynamic value, double defaultValue) {
      if (value == null) return defaultValue;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? defaultValue;
      return defaultValue;
    }

    // Helper to parse color strings (hex RRGGBB, #RRGGBB, RRGGBBAA, #RRGGBBAA, or shorthand like F0C) to int (AARRGGBB)
    int _parseColor(dynamic colorValue, int defaultValue) {
      if (colorValue is String && colorValue.isNotEmpty) {
        String hex = colorValue.replaceAll('#', '').toUpperCase();

        // Expand shorthand hex (e.g., F0C to FF00CC)
        if (hex.length == 3) {
          hex = hex.split('').map((c) => c + c).join('');
        }

        // Add full opacity (FF) if RRGGBB
        if (hex.length == 6) {
          hex = 'FF$hex';
        }

        // Parse AARRGGBB
        if (hex.length == 8) {
          try {
            return int.parse(hex, radix: 16);
          } catch (e) {
            print('Error parsing color "$colorValue" (processed as "$hex"): $e');
            return defaultValue;
          }
        }
        print('Invalid color format "$colorValue". Using default.');
        return defaultValue;
      } else if (colorValue is int) {
        return colorValue;
      }
      return defaultValue;
    }

    // Default colors
    const int defaultGraphColor = 0xFF000000; // Black
    const int defaultAlarmColor = 0xFFFF0000; // Red

    return Channel(
      recNo: _parseToDouble(json['RecNo'], 0.0),
      channelName: json['ChannelName'] as String? ?? '',
      startingCharacter: json['StartingCharacter'] as String? ?? '',
      dataLength: _parseToInt(json['DataLength'], 7), // Default to 7 for format like 'L123.4'
      decimalPlaces: _parseToInt(json['DecimalPlaces'], 1), // Default to 1 decimal place
      unit: json['Unit'] as String? ?? '',
      chartMaximumValue: _parseToDouble(json['ChartMaximumValue'], 100.0),
      chartMinimumValue: _parseToDouble(json['ChartMinimumValue'], 0.0),
      targetAlarmMax: _parseToDouble(json['TargetAlarmMax'], 0.0),
      targetAlarmMin: _parseToDouble(json['TargetAlarmMin'], 0.0),
      graphLineColour: _parseColor(json['graphLineColour'], defaultGraphColor),
      targetAlarmColour: _parseColor(json['TargetAlarmColour'], defaultAlarmColor),
    );
  }

  Map<String, dynamic> toJson() {
    // Convert int color (AARRGGBB) to hex string (RRGGBB)
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
      'ChannelColour': _toColorHexString(graphLineColour),
      'TargetAlarmColour': _toColorHexString(targetAlarmColour),
    };
  }

  @override
  String toString() {
    return 'Channel('
        'recNo: $recNo, '
        'channelName: "$channelName", '
        'startingCharacter: "$startingCharacter", '
        'dataLength: $dataLength, '
        'decimalPlaces: $decimalPlaces, '
        'unit: "$unit", '
        'chartMaximumValue: $chartMaximumValue, '
        'chartMinimumValue: $chartMinimumValue, '
        'targetAlarmMax: $targetAlarmMax, '
        'targetAlarmMin: $targetAlarmMin, '
        'graphLineColour: #${graphLineColour.toRadixString(16).padLeft(8, '0').toUpperCase()}, '
        'targetAlarmColour: #${targetAlarmColour.toRadixString(16).padLeft(8, '0').toUpperCase()}'
        ')';
  }
}