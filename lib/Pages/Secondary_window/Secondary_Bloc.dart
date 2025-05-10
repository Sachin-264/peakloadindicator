import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// Events
abstract class ChannelDataEvent {}

class Initialize extends ChannelDataEvent {
  final Map<String, dynamic> initialChannelData;
  Initialize(this.initialChannelData);
}

class UpdateChannelData extends ChannelDataEvent {
  final Map<String, dynamic> newChannelData;
  UpdateChannelData(this.newChannelData);
}

class SelectChannels extends ChannelDataEvent {
  final List<String> channels;
  SelectChannels(this.channels);
}

class SetDialogOpen extends ChannelDataEvent {
  final bool isOpen;
  SetDialogOpen(this.isOpen);
}

class SetInitialized extends ChannelDataEvent {
  final bool isInitialized;
  SetInitialized(this.isInitialized);
}

class SetAxisSelection extends ChannelDataEvent {
  final String xAxisType;
  final String? xAxisChannel;
  final String? yAxisChannel;
  SetAxisSelection(this.xAxisType, this.xAxisChannel, this.yAxisChannel);
}

class SetAxisConfigured extends ChannelDataEvent {
  final bool isConfigured;
  SetAxisConfigured(this.isConfigured);
}

class SetGraphDuration extends ChannelDataEvent {
  final int hours;
  final int minutes;
  SetGraphDuration(this.hours, this.minutes);
}

class SetChannelColor extends ChannelDataEvent {
  final String channelIndex;
  final Color color;
  SetChannelColor(this.channelIndex, this.color);
}

class SetZoomLevel extends ChannelDataEvent {
  final double level;
  final bool isZoomIn;
  SetZoomLevel(this.level, {this.isZoomIn = false});
}

class ToggleGrid extends ChannelDataEvent {}

class ToggleDataPoints extends ChannelDataEvent {}

class TogglePeak extends ChannelDataEvent {}

class SetSegment extends ChannelDataEvent {
  final int segment;
  SetSegment(this.segment);
}

// State
class ChannelDataState {
  final Map<String, dynamic> currentChannelData;
  final List<String> selectedChannels;
  final Map<String, Color> channelColors;
  final Map<String, String> channelNames;
  final Map<String, double?> maxLoadValues;
  final String? errorMessage;
  final bool isLoading;
  final bool isDialogOpen;
  final double zoomLevel;
  final bool showGrid;
  final bool showDataPoints;
  final bool showPeak;
  final bool isGraphUpdating;
  final double minYValue;
  final double maxYValue;
  final double minXValue;
  final double maxXValue;
  final int currentSegment;
  final int totalSegments;
  final double startTimeSeconds;
  final String xAxisType;
  final String? xAxisChannel;
  final String? yAxisChannel;
  final bool needsChannelSelection;
  final bool isInitialized;
  final bool isAxisConfigured;

  ChannelDataState({
    required this.currentChannelData,
    required this.selectedChannels,
    required this.channelColors,
    required this.channelNames,
    required this.maxLoadValues,
    this.errorMessage,
    required this.isLoading,
    required this.isDialogOpen,
    required this.zoomLevel,
    required this.showGrid,
    required this.showDataPoints,
    required this.showPeak,
    required this.isGraphUpdating,
    required this.minYValue,
    required this.maxYValue,
    required this.minXValue,
    required this.maxXValue,
    required this.currentSegment,
    required this.totalSegments,
    required this.startTimeSeconds,
    required this.xAxisType,
    this.xAxisChannel,
    this.yAxisChannel,
    required this.needsChannelSelection,
    required this.isInitialized,
    required this.isAxisConfigured,
  });

  ChannelDataState copyWith({
    Map<String, dynamic>? currentChannelData,
    List<String>? selectedChannels,
    Map<String, Color>? channelColors,
    Map<String, String>? channelNames,
    Map<String, double?>? maxLoadValues,
    String? errorMessage,
    bool? isLoading,
    bool? isDialogOpen,
    double? zoomLevel,
    bool? showGrid,
    bool? showDataPoints,
    bool? showPeak,
    bool? isGraphUpdating,
    double? minYValue,
    double? maxYValue,
    double? minXValue,
    double? maxXValue,
    int? currentSegment,
    int? totalSegments,
    double? startTimeSeconds,
    String? xAxisType,
    String? xAxisChannel,
    String? yAxisChannel,
    bool? needsChannelSelection,
    bool? isInitialized,
    bool? isAxisConfigured,
  }) {
    return ChannelDataState(
      currentChannelData: currentChannelData ?? this.currentChannelData,
      selectedChannels: selectedChannels ?? this.selectedChannels,
      channelColors: channelColors ?? this.channelColors,
      channelNames: channelNames ?? this.channelNames,
      maxLoadValues: maxLoadValues ?? this.maxLoadValues,
      errorMessage: errorMessage,
      isLoading: isLoading ?? this.isLoading,
      isDialogOpen: isDialogOpen ?? this.isDialogOpen,
      zoomLevel: zoomLevel ?? this.zoomLevel,
      showGrid: showGrid ?? this.showGrid,
      showDataPoints: showDataPoints ?? this.showDataPoints,
      showPeak: showPeak ?? this.showPeak,
      isGraphUpdating: isGraphUpdating ?? this.isGraphUpdating,
      minYValue: minYValue ?? this.minYValue,
      maxYValue: maxYValue ?? this.maxYValue,
      minXValue: minXValue ?? this.minXValue,
      maxXValue: maxXValue ?? this.maxXValue,
      currentSegment: currentSegment ?? this.currentSegment,
      totalSegments: totalSegments ?? this.totalSegments,
      startTimeSeconds: startTimeSeconds ?? this.startTimeSeconds,
      xAxisType: xAxisType ?? this.xAxisType,
      xAxisChannel: xAxisChannel ?? this.xAxisChannel,
      yAxisChannel: yAxisChannel ?? this.yAxisChannel,
      needsChannelSelection: needsChannelSelection ?? this.needsChannelSelection,
      isInitialized: isInitialized ?? this.isInitialized,
      isAxisConfigured: isAxisConfigured ?? this.isAxisConfigured,
    );
  }
}

// Bloc
class ChannelDataBloc extends Bloc<ChannelDataEvent, ChannelDataState> {
  List<Map<String, dynamic>> _dataUpdateQueue = [];

  ChannelDataBloc()
      : super(
    ChannelDataState(
      currentChannelData: {},
      selectedChannels: [],
      channelColors: {},
      channelNames: {},
      maxLoadValues: {},
      errorMessage: null,
      isLoading: true,
      isDialogOpen: false,
      zoomLevel: 1.0,
      showGrid: true,
      showDataPoints: false,
      showPeak: false,
      isGraphUpdating: false,
      minYValue: 0,
      maxYValue: 1000,
      minXValue: 0,
      maxXValue: 1000,
      currentSegment: 0,
      totalSegments: 1,
      startTimeSeconds: 0,
      xAxisType: 'time',
      xAxisChannel: null,
      yAxisChannel: null,
      needsChannelSelection: true,
      isInitialized: false,
      isAxisConfigured: false,
    ),
  ) {
    on<Initialize>(_onInitialize);
    on<UpdateChannelData>(_onUpdateChannelData);
    on<SelectChannels>(_onSelectChannels);
    on<SetDialogOpen>(_onSetDialogOpen);
    on<SetInitialized>(_onSetInitialized);
    on<SetAxisSelection>(_onSetAxisSelection);
    on<SetAxisConfigured>(_onSetAxisConfigured);
    on<SetGraphDuration>(_onSetGraphDuration);
    on<SetChannelColor>(_onSetChannelColor);
    on<SetZoomLevel>(_onSetZoomLevel);
    on<ToggleGrid>(_onToggleGrid);
    on<ToggleDataPoints>(_onToggleDataPoints);
    on<TogglePeak>(_onTogglePeak);
    on<SetSegment>(_onSetSegment);
  }

  void _onInitialize(Initialize event, Emitter<ChannelDataState> emit) {
    print('[CHANNEL_DATA_BLOC][INITIALIZE] Initializing with channel data');
    if (!state.isInitialized || !state.isAxisConfigured) {
      print('[CHANNEL_DATA_BLOC][INITIALIZE] Queuing initial data until axis configured');
      _dataUpdateQueue.add(event.initialChannelData);
      return;
    }
    final newState = _processChannelData(event.initialChannelData, state: state);
    emit(newState);
  }

  void _onUpdateChannelData(UpdateChannelData event, Emitter<ChannelDataState> emit) {
    print('[CHANNEL_DATA_BLOC][UPDATE_CHANNEL_DATA] Received new data, queue size: ${_dataUpdateQueue.length}');
    if (!state.isInitialized || !state.isAxisConfigured || state.isDialogOpen) {
      _dataUpdateQueue.add(event.newChannelData);
      print('[CHANNEL_DATA_BLOC][UPDATE_CHANNEL_DATA] Queued update, queue size: ${_dataUpdateQueue.length}');
      return;
    }
    final newState = _mergeChannelData(event.newChannelData, state: state);
    emit(newState);
  }

  void _onSelectChannels(SelectChannels event, Emitter<ChannelDataState> emit) {
    print('[CHANNEL_DATA_BLOC][SELECT_CHANNELS] Setting selected channels: ${event.channels}');
    final newState = state.copyWith(
      selectedChannels: event.channels.toSet().toList(),
      isLoading: false,
      needsChannelSelection: false,
    );
    final updatedState = _updateCalculations(newState);
    emit(updatedState);
  }

  void _onSetDialogOpen(SetDialogOpen event, Emitter<ChannelDataState> emit) {
    print('[CHANNEL_DATA_BLOC][SET_DIALOG_OPEN] Setting isDialogOpen: ${event.isOpen}, queue size: ${_dataUpdateQueue.length}');
    if (event.isOpen) {
      emit(state.copyWith(isDialogOpen: true));
    } else {
      if (_dataUpdateQueue.isNotEmpty && state.isInitialized && state.isAxisConfigured) {
        final latestData = _dataUpdateQueue.last;
        _dataUpdateQueue.clear();
        print('[CHANNEL_DATA_BLOC][SET_DIALOG_OPEN] Processing queued data');
        final newState = _mergeChannelData(latestData, state: state);
        emit(newState.copyWith(isDialogOpen: false));
      } else {
        emit(state.copyWith(isDialogOpen: false));
      }
    }
  }

  void _onSetInitialized(SetInitialized event, Emitter<ChannelDataState> emit) {
    print('[CHANNEL_DATA_BLOC][SET_INITIALIZED] Setting isInitialized: ${event.isInitialized}');
    emit(state.copyWith(isInitialized: event.isInitialized));
  }

  void _onSetAxisSelection(SetAxisSelection event, Emitter<ChannelDataState> emit) {
    print('[CHANNEL_DATA_BLOC][SET_AXIS_SELECTION] Setting xAxisType: ${event.xAxisType}, '
        'xAxisChannel: ${event.xAxisChannel}, yAxisChannel: ${event.yAxisChannel}');
    final newState = state.copyWith(
      xAxisType: event.xAxisType,
      xAxisChannel: event.xAxisChannel,
      yAxisChannel: event.yAxisChannel,
      isLoading: false,
    );
    final updatedState = _updateCalculations(newState);
    emit(updatedState);
  }

  void _onSetAxisConfigured(SetAxisConfigured event, Emitter<ChannelDataState> emit) {
    print('[CHANNEL_DATA_BLOC][SET_AXIS_CONFIGURED] Setting isAxisConfigured: ${event.isConfigured}');
    emit(state.copyWith(isAxisConfigured: event.isConfigured));
  }

  void _onSetGraphDuration(SetGraphDuration event, Emitter<ChannelDataState> emit) {
    print('[CHANNEL_DATA_BLOC][SET_GRAPH_DURATION] Setting duration: ${event.hours} hr, ${event.minutes} min');
    final newState = _calculateGraphSegments(state);
    emit(newState);
  }

  void _onSetChannelColor(SetChannelColor event, Emitter<ChannelDataState> emit) {
    print('[CHANNEL_DATA_BLOC][SET_CHANNEL_COLOR] Setting color for ${event.channelIndex}: ${event.color}');
    final newColors = Map<String, Color>.from(state.channelColors);
    newColors[event.channelIndex] = event.color;
    emit(state.copyWith(channelColors: newColors));
  }

  void _onSetZoomLevel(SetZoomLevel event, Emitter<ChannelDataState> emit) {
    print('[CHANNEL_DATA_BLOC][SET_ZOOM_LEVEL] Setting zoomLevel: ${event.level}, isZoomIn: ${event.isZoomIn}');
    emit(state.copyWith(isGraphUpdating: true));
    final newZoomLevel = event.level.clamp(0.2, 5.0);
    Future.delayed(const Duration(milliseconds: 300), () {
      add(SetZoomLevel(newZoomLevel, isZoomIn: event.isZoomIn));
    });
    emit(state.copyWith(zoomLevel: newZoomLevel, isGraphUpdating: false));
  }

  void _onToggleGrid(ToggleGrid event, Emitter<ChannelDataState> emit) {
    print('[CHANNEL_DATA_BLOC][TOGGLE_GRID] Toggling grid');
    emit(state.copyWith(isGraphUpdating: true));
    Future.delayed(const Duration(milliseconds: 300), () {
      add(ToggleGrid());
    });
    emit(state.copyWith(showGrid: !state.showGrid, isGraphUpdating: false));
  }

  void _onToggleDataPoints(ToggleDataPoints event, Emitter<ChannelDataState> emit) {
    print('[CHANNEL_DATA_BLOC][TOGGLE_DATA_POINTS] Toggling data points');
    emit(state.copyWith(isGraphUpdating: true));
    Future.delayed(const Duration(milliseconds: 300), () {
      add(ToggleDataPoints());
    });
    emit(state.copyWith(showDataPoints: !state.showDataPoints, isGraphUpdating: false));
  }

  void _onTogglePeak(TogglePeak event, Emitter<ChannelDataState> emit) {
    print('[CHANNEL_DATA_BLOC][TOGGLE_PEAK] Toggling peak');
    emit(state.copyWith(isGraphUpdating: true));
    Future.delayed(const Duration(milliseconds: 300), () {
      add(TogglePeak());
    });
    emit(state.copyWith(showPeak: !state.showPeak, isGraphUpdating: false));
  }

  void _onSetSegment(SetSegment event, Emitter<ChannelDataState> emit) {
    print('[CHANNEL_DATA_BLOC][SET_SEGMENT] Setting segment: ${event.segment}');
    if (event.segment >= 0 && event.segment < state.totalSegments) {
      final newState = _calculateGraphSegments(state.copyWith(currentSegment: event.segment));
      emit(newState);
    }
  }

  ChannelDataState _processChannelData(Map<String, dynamic> newChannelData, {required ChannelDataState state}) {
    try {
      if (newChannelData['dataPoints'] == null) {
        throw Exception('Invalid channel data: dataPoints is null');
      }
      print('[CHANNEL_DATA_BLOC][PROCESS_CHANNEL_DATA] Processing channel data');
      final dataPoints = newChannelData['dataPoints'] as List<dynamic>? ?? [];
      final newState = state.copyWith(
        currentChannelData: newChannelData,
        isLoading: !state.isInitialized || state.isDialogOpen || state.selectedChannels.isEmpty,
      );
      final initializedState = _initializeChannelData(newState);
      final validChannels = dataPoints
          .map((d) => d['channelIndex'] is int ? d['channelIndex'].toString() : (d['channelIndex'] as String? ?? ''))
          .toList();
      final filteredChannels = initializedState.selectedChannels.where((channel) => validChannels.contains(channel)).toList();
      final updatedState = initializedState.copyWith(
        selectedChannels: filteredChannels,
        needsChannelSelection: initializedState.channelNames.isEmpty || filteredChannels.isEmpty,
      );
      if (filteredChannels.isNotEmpty) {
        return _updateCalculations(updatedState.copyWith(isLoading: false));
      }
      return updatedState;
    } catch (e, stackTrace) {
      print('[CHANNEL_DATA_BLOC][PROCESS_CHANNEL_DATA] Error: $e\nStack trace: $stackTrace');
      return state.copyWith(
        errorMessage: 'Error processing channel data: $e',
        isLoading: false,
      );
    }
  }

  ChannelDataState _mergeChannelData(Map<String, dynamic> newChannelData, {required ChannelDataState state}) {
    try {
      if (newChannelData['dataPoints'] == null) {
        throw Exception('Invalid channel data: dataPoints is null');
      }
      print('[CHANNEL_DATA_BLOC][MERGE_CHANNEL_DATA] Merging new channel data');

      final currentDataPoints = state.currentChannelData['dataPoints'] as List<dynamic>? ?? [];
      final newDataPoints = newChannelData['dataPoints'] as List<dynamic>? ?? [];

      final mergedDataPoints = <String, Map<String, dynamic>>{};
      final existingTimestamps = <String, Set<double>>{};

      // Track existing timestamps to avoid duplicates
      for (var dataPoint in currentDataPoints) {
        final channelIndex = dataPoint['channelIndex'].toString();
        mergedDataPoints[channelIndex] = Map<String, dynamic>.from(dataPoint);
        final points = dataPoint['points'] as List<dynamic>? ?? [];
        existingTimestamps[channelIndex] = points
            .map((p) => (p['timestamp'] as num?)?.toDouble())
            .where((t) => t != null)
            .cast<double>()
            .toSet();
      }

      // Merge new data points, skipping duplicates
      for (var newDataPoint in newDataPoints) {
        final channelIndex = newDataPoint['channelIndex'].toString();
        final newPoints = newDataPoint['points'] as List<dynamic>? ?? [];
        final uniquePoints = <Map<String, dynamic>>[];

        for (var point in newPoints) {
          final timestamp = (point['timestamp'] as num?)?.toDouble();
          if (timestamp != null && !(existingTimestamps[channelIndex]?.contains(timestamp) ?? false)) {
            uniquePoints.add(Map<String, dynamic>.from(point));
          }
        }

        if (mergedDataPoints.containsKey(channelIndex)) {
          final existingPoints = mergedDataPoints[channelIndex]!['points'] as List<dynamic>? ?? [];
          mergedDataPoints[channelIndex]!['points'] = [...existingPoints, ...uniquePoints];
        } else {
          mergedDataPoints[channelIndex] = Map<String, dynamic>.from(newDataPoint);
          mergedDataPoints[channelIndex]!['points'] = uniquePoints;
        }
      }

      final mergedChannelData = {
        'dataPoints': mergedDataPoints.values.toList(),
      };

      final newState = state.copyWith(
        currentChannelData: mergedChannelData,
        isLoading: false,
      );

      return _updateCalculations(newState);
    } catch (e, stackTrace) {
      print('[CHANNEL_DATA_BLOC][MERGE_CHANNEL_DATA] Error: $e\nStack trace: $stackTrace');
      return state.copyWith(
        errorMessage: 'Error merging channel data: $e',
        isLoading: false,
      );
    }
  }

  ChannelDataState _initializeChannelData(ChannelDataState state) {
    final channelColors = <String, Color>{};
    final channelNames = <String, String>{};
    final maxLoadValues = <String, double?>{};
    const List<Color> defaultColors = [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.purple,
      Colors.orange,
      Colors.teal,
      Colors.pink,
      Colors.cyan,
    ];

    try {
      final dataPoints = state.currentChannelData['dataPoints'] as List<dynamic>? ?? [];
      if (dataPoints.isEmpty) {
        return state.copyWith(
          errorMessage: 'No channel data available',
          isLoading: false,
          channelColors: channelColors,
          channelNames: channelNames,
          maxLoadValues: maxLoadValues,
        );
      }
      for (int i = 0; i < dataPoints.length; i++) {
        final channelData = dataPoints[i];
        final channelIndexRaw = channelData['channelIndex'];
        final channelIndex = channelIndexRaw is int ? channelIndexRaw.toString() : (channelIndexRaw as String? ?? 'Unknown_$i');
        final channelName = channelData['channelName'] as String? ?? 'Channel ${i + 1}';
        channelColors[channelIndex] = defaultColors[i % defaultColors.length];
        channelNames[channelIndex] = channelName;
      }
      return state.copyWith(
        channelColors: channelColors,
        channelNames: channelNames,
        maxLoadValues: maxLoadValues,
        errorMessage: null,
      );
    } catch (e) {
      return state.copyWith(
        errorMessage: 'Error initializing channel data: $e',
        isLoading: false,
        channelColors: channelColors,
        channelNames: channelNames,
        maxLoadValues: maxLoadValues,
      );
    }
  }

  ChannelDataState _updateCalculations(ChannelDataState state) {
    var newState = _calculateYRange(state);
    newState = _calculateXRange(newState);
    newState = _calculateMaxLoadValues(newState);
    newState = _calculateGraphSegments(newState);
    return newState;
  }

  ChannelDataState _calculateYRange(ChannelDataState state) {
    double minYValue = double.infinity;
    double maxYValue = -double.infinity;

    try {
      final dataPoints = state.currentChannelData['dataPoints'] as List<dynamic>? ?? [];
      for (var channelData in dataPoints) {
        final channelIndexRaw = channelData['channelIndex'];
        final channelIndex = channelIndexRaw is int ? channelIndexRaw.toString() : (channelIndexRaw as String? ?? '');
        if (!state.selectedChannels.contains(channelIndex)) {
          continue;
        }
        final points = channelData['points'] as List<dynamic>? ?? [];
        for (var point in points) {
          final value = (point['value'] as num?)?.toDouble();
          if (value != null && value.isFinite) {
            if (state.xAxisType == 'time' || (state.xAxisType == 'channel' && channelIndex == state.yAxisChannel)) {
              minYValue = minYValue.isFinite ? min(minYValue, value) : value;
              maxYValue = maxYValue.isFinite ? max(maxYValue, value) : value;
            }
          }
        }
      }

      if (!minYValue.isFinite || !maxYValue.isFinite) {
        minYValue = 0;
        maxYValue = 1000;
      } else {
        final range = maxYValue - minYValue;
        minYValue -= range * 0.05;
        maxYValue += range * 0.1;
      }
      return state.copyWith(minYValue: minYValue, maxYValue: maxYValue);
    } catch (e) {
      return state.copyWith(errorMessage: 'Error calculating Y range: $e');
    }
  }

  ChannelDataState _calculateXRange(ChannelDataState state) {
    double minXValue = double.infinity;
    double maxXValue = -double.infinity;

    try {
      if (state.xAxisType == 'time') {
        return state.copyWith(minXValue: 0, maxXValue: 3600); // Default for time-based axis
      }
      final dataPoints = state.currentChannelData['dataPoints'] as List<dynamic>? ?? [];
      for (var channelData in dataPoints) {
        final channelIndexRaw = channelData['channelIndex'];
        final channelIndex = channelIndexRaw is int ? channelIndexRaw.toString() : (channelIndexRaw as String? ?? '');
        if (channelIndex != state.xAxisChannel) {
          continue;
        }
        final points = channelData['points'] as List<dynamic>? ?? [];
        for (var point in points) {
          final value = (point['value'] as num?)?.toDouble();
          if (value != null && value.isFinite) {
            minXValue = minXValue.isFinite ? min(minXValue, value) : value;
            maxXValue = maxXValue.isFinite ? max(maxXValue, value) : value;
          }
        }
      }

      if (!minXValue.isFinite || !maxXValue.isFinite) {
        minXValue = 0;
        maxXValue = 1000;
      } else {
        final range = maxXValue - minXValue;
        minXValue -= range * 0.05;
        maxXValue += range * 0.1;
      }
      return state.copyWith(minXValue: minXValue, maxXValue: maxXValue);
    } catch (e) {
      return state.copyWith(errorMessage: 'Error calculating X range: $e');
    }
  }

  ChannelDataState _calculateMaxLoadValues(ChannelDataState state) {
    final maxLoadValues = <String, double?>{};
    try {
      final dataPoints = state.currentChannelData['dataPoints'] as List<dynamic>? ?? [];
      for (var channelData in dataPoints) {
        final channelIndexRaw = channelData['channelIndex'];
        final channelIndex = channelIndexRaw is int ? channelIndexRaw.toString() : (channelIndexRaw as String? ?? '');
        if (!state.selectedChannels.contains(channelIndex)) {
          continue;
        }
        final points = channelData['points'] as List<dynamic>? ?? [];
        double? maxValue;
        for (var point in points) {
          final value = (point['value'] as num?)?.toDouble();
          if (value != null && value.isFinite) {
            maxValue = maxValue == null ? value : max(maxValue, value);
          }
        }
        if (channelIndex.isNotEmpty && maxValue != null) {
          maxLoadValues[channelIndex] = maxValue;
        }
      }
      return state.copyWith(maxLoadValues: maxLoadValues);
    } catch (e) {
      return state.copyWith(errorMessage: 'Error calculating max load values: $e');
    }
  }

  ChannelDataState _calculateGraphSegments(ChannelDataState state) {
    int graphVisibleSeconds = 3600; // Default to 1 hour
    try {
      double minTime = double.infinity;
      double maxTime = -double.infinity;

      final dataPoints = state.currentChannelData['dataPoints'] as List<dynamic>? ?? [];
      for (var channelData in dataPoints) {
        final channelIndexRaw = channelData['channelIndex'];
        final channelIndex = channelIndexRaw is int ? channelIndexRaw.toString() : (channelIndexRaw as String? ?? '');
        if (!state.selectedChannels.contains(channelIndex)) continue;
        final points = channelData['points'] as List<dynamic>? ?? [];
        for (var point in points) {
          final timestamp = (point['timestamp'] as num?)?.toDouble();
          if (timestamp != null && timestamp.isFinite) {
            minTime = min(minTime, timestamp / 1000);
            maxTime = max(maxTime, timestamp / 1000);
          }
        }
      }

      if (minTime != double.infinity && maxTime != -double.infinity) {
        final duration = maxTime - minTime;
        final totalSegments = (duration / graphVisibleSeconds).ceil();
        final newTotalSegments = totalSegments == 0 ? 1 : totalSegments;
        final newCurrentSegment = min(state.currentSegment, newTotalSegments - 1);
        final startTimeSeconds = maxTime - graphVisibleSeconds;
        return state.copyWith(
          totalSegments: newTotalSegments,
          currentSegment: newCurrentSegment,
          startTimeSeconds: startTimeSeconds,
        );
      }
      return state.copyWith(
        totalSegments: 1,
        currentSegment: 0,
        startTimeSeconds: 0,
      );
    } catch (e) {
      return state.copyWith(errorMessage: 'Error calculating graph segments: $e');
    }
  }
}