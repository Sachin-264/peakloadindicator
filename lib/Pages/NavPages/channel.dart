class Channel {
  final double recNo; // Changed to double to handle REAL
  final String channelName;
  final String startingCharacter;
  final int dataLength;
  final int decimalPlaces;
  final String unit;
  final double chartMaximumValue; // Changed to double to handle REAL
  final double chartMinimumValue; // Changed to double to handle REAL
  final double targetAlarmMax; // Changed to double to handle REAL
  final double targetAlarmMin; // Changed to double to handle REAL
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
    return Channel(
      recNo: (json['RecNo'] is int ? json['RecNo'].toDouble() : json['RecNo']) as double,
      channelName: json['ChannelName'] as String? ?? '',
      startingCharacter: json['StartingCharacter'] as String? ?? '',
      dataLength: json['DataLength'] as int? ?? 0,
      decimalPlaces: json['DecimalPlaces'] as int? ?? 0,
      unit: json['Unit'] as String? ?? '',
      chartMaximumValue: (json['ChartMaximumValue'] is int ? json['ChartMaximumValue'].toDouble() : json['ChartMaximumValue']) as double? ?? 0.0,
      chartMinimumValue: (json['ChartMinimumValue'] is int ? json['ChartMinimumValue'].toDouble() : json['ChartMinimumValue']) as double? ?? 0.0,
      targetAlarmMax: (json['TargetAlarmMax'] is int ? json['TargetAlarmMax'].toDouble() : json['TargetAlarmMax']) as double? ?? 0.0,
      targetAlarmMin: (json['TargetAlarmMin'] is int ? json['TargetAlarmMin'].toDouble() : json['TargetAlarmMin']) as double? ?? 0.0,
      graphLineColour: json['GraphLineColour'] as int? ?? 0,
      targetAlarmColour: json['TargetAlarmColour'] as int? ?? 0,
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
      'GraphLineColour': graphLineColour,
      'TargetAlarmColour': targetAlarmColour,
    };
  }

  @override
  String toString() {
    return 'Channel('
        'recNo: $recNo, '
        'channelName: $channelName, '
        'startingCharacter: $startingCharacter, '
        'unit: $unit, '
        'dataLength: $dataLength, '
        'decimalPlaces: $decimalPlaces'
        ')';
  }
}