class Channel {
  final int recNo;
  final String channelName;
  final String startingCharacter;
  final int dataLength;
  final int decimalPlaces;
  final String unit;
  final int chartMaximumValue;
  final int chartMinimumValue;
  final int targetAlarmMax;
  final int targetAlarmMin;
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
      recNo: json['RecNo'] as int,
      channelName: json['ChannelName'] as String,
      startingCharacter: json['StartingCharacter'] as String,
      dataLength: json['DataLength'] as int,
      decimalPlaces: json['DecimalPlaces'] as int,
      unit: json['Unit'] as String,
      chartMaximumValue: json['ChartMaximumValue'] as int,
      chartMinimumValue: json['ChartMinimumValue'] as int,
      targetAlarmMax: json['TargetAlarmMax'] as int,
      targetAlarmMin: json['TargetAlarmMin'] as int,
      graphLineColour: json['GraphLineColour'] as int,
      targetAlarmColour: json['TargetAlarmColour'] as int,
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