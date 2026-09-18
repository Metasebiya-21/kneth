import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/flow_manifest.dart';
import '../models/stage_config.dart';
import '../services/api_client.dart';

class _HistoryEntry {
  final Map<String, dynamic> stageJson;
  final int stepNumber;

  _HistoryEntry({required this.stageJson, required this.stepNumber});
}

enum NavigationDirection { forward, backward }

/// Drives a fully server-driven flow: it holds no local stage list at all,
/// just whatever stage [ApiClient.fetchNextStage] last returned.
class FlowController extends ChangeNotifier {
  final FlowManifest manifest;
  final ApiClient apiClient;

  Map<String, dynamic>? _currentStageJson;
  StageConfig? _currentStage;
  bool _isLoading;
  bool _isComplete;
  Object? _loadError;
  int _stepNumber;
  NavigationDirection _direction = NavigationDirection.forward;
  final Map<String, Map<String, dynamic>> _collectedValues;
  final List<_HistoryEntry> _history = [];

  String? _lastAfterStageId;
  Map<String, dynamic>? _lastSubmittedValues;

  FlowController({required this.manifest, ApiClient? apiClient})
      : apiClient = apiClient ?? HttpApiClient(),
        _isLoading = true,
        _isComplete = false,
        _stepNumber = 0,
        _collectedValues = {} {
    _loadNext(afterStageId: null, submittedValues: null);
  }

  FlowController._restored({
    required this.manifest,
    ApiClient? apiClient,
    required Map<String, dynamic>? currentStageJson,
    required bool isComplete,
    required int stepNumber,
    required Map<String, Map<String, dynamic>> initialValues,
  })  : apiClient = apiClient ?? HttpApiClient(),
        _currentStageJson = currentStageJson,
        _currentStage = currentStageJson != null ? StageConfig.fromJson(currentStageJson) : null,
        _isLoading = false,
        _isComplete = isComplete,
        _stepNumber = stepNumber,
        _collectedValues = initialValues;

  bool get isLoading => _isLoading;
  bool get isComplete => _isComplete;
  Object? get loadError => _loadError;
  StageConfig get currentStage => _currentStage!;
  NavigationDirection get direction => _direction;

  String get progressLabel => 'Step ${_stepNumber.toString().padLeft(2, '0')}';
  int get stepNumber => _stepNumber;
  int get totalSteps => math.max(manifest.stageCount, _stepNumber);

  Map<String, dynamic> get allValues => {
        for (final entry in _collectedValues.entries)
          for (final value in entry.value.entries)
            '${entry.key}.${value.key}': value.value,
      };

  Map<String, dynamic> valuesForStage(String stageId) =>
      _collectedValues[stageId] ?? {};

  static String capitalizeWords(String input) {
    if (input.trim().isEmpty) return input;
    return input.split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + (word.length > 1 ? word.substring(1).toLowerCase() : '');
    }).join(' ');
  }

  static String normalizeEthiopianPhone(String input) {
    var clean = input.replaceAll(RegExp(r'[\s\-()]'), '');
    if (clean.startsWith('+251')) {
      return clean;
    } else if (clean.startsWith('251')) {
      return '+$clean';
    } else if (clean.startsWith('09') || clean.startsWith('07')) {
      return '+251${clean.substring(1)}';
    } else if (clean.startsWith('9') || clean.startsWith('7')) {
      return '+251$clean';
    }
    return clean;
  }

  Future<void> submitStage(Map<String, dynamic> values) async {
    if (_isLoading || _isComplete || _currentStageJson == null) return;
    _direction = NavigationDirection.forward;
    final stageId = currentStage.stageId;

    final sanitized = <String, dynamic>{};
    for (final entry in values.entries) {
      final key = entry.key;
      final val = entry.value;
      if (val is String) {
        final lower = key.toLowerCase();
        if (lower.contains('name') || lower.contains('mother') || lower.contains('father')) {
          sanitized[key] = capitalizeWords(val);
        } else if (lower.contains('phone') || lower.contains('mobile') || lower.contains('tel')) {
          sanitized[key] = normalizeEthiopianPhone(val);
        } else {
          sanitized[key] = val;
        }
      } else {
        sanitized[key] = val;
      }
    }

    _collectedValues[stageId] = sanitized;
    _history.add(_HistoryEntry(stageJson: _currentStageJson!, stepNumber: _stepNumber));
    await _loadNext(afterStageId: stageId, submittedValues: sanitized);
  }

  Future<void> retry() => _loadNext(
        afterStageId: _lastAfterStageId,
        submittedValues: _lastSubmittedValues,
      );

  void back() {
    if (_isLoading || _history.isEmpty) return;
    _direction = NavigationDirection.backward;
    final previous = _history.removeLast();
    _currentStageJson = previous.stageJson;
    _currentStage = StageConfig.fromJson(previous.stageJson);
    _stepNumber = previous.stepNumber;
    _isComplete = false;
    _loadError = null;
    notifyListeners();
    save();
  }

  Future<void> _loadNext({
    required String? afterStageId,
    required Map<String, dynamic>? submittedValues,
  }) async {
    _lastAfterStageId = afterStageId;
    _lastSubmittedValues = submittedValues;
    _isLoading = true;
    _loadError = null;
    notifyListeners();

    try {
      final nextJson = await apiClient.fetchNextStage(
        flowId: manifest.flowId,
        afterStageId: afterStageId,
        submittedValues: submittedValues,
      );
      if (nextJson == null) {
        _isComplete = true;
        _currentStageJson = null;
        _currentStage = null;
      } else {
        _currentStageJson = nextJson;
        _currentStage = StageConfig.fromJson(nextJson);
        _stepNumber++;
      }
      _isLoading = false;
      notifyListeners();
      save();
    } catch (e) {
      _isLoading = false;
      _loadError = e;
      notifyListeners();
    }
  }

  bool get hasCollectedData => _collectedValues.values.any(
        (map) => map.isNotEmpty && map.values.any((v) => v != null && v.toString().trim().isNotEmpty),
      );

  String get _storageKey => 'sdui_flow_state_${manifest.flowId}';

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    // Do not save as draft if no actual data has been entered
    if (!hasCollectedData) {
      await prefs.remove(_storageKey);
      return;
    }

    await prefs.setString(
      _storageKey,
      jsonEncode({
        'currentStageJson': _currentStageJson,
        'isComplete': _isComplete,
        'stepNumber': _stepNumber,
        'valuesByStage': _collectedValues,
      }),
    );
  }

  Future<void> clearSaved() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  static Future<FlowController?> restore({
    required FlowManifest manifest,
    ApiClient? apiClient,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('sdui_flow_state_${manifest.flowId}');
    if (raw == null) return null;

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final rawValues = decoded['valuesByStage'] as Map<String, dynamic>? ?? {};
    final valuesByStage = <String, Map<String, dynamic>>{
      for (final entry in rawValues.entries)
        entry.key: Map<String, dynamic>.from(entry.value as Map),
    };

    final hasData = valuesByStage.values.any(
      (map) => map.isNotEmpty && map.values.any((v) => v != null && v.toString().trim().isNotEmpty),
    );

    if (!hasData) {
      await prefs.remove('sdui_flow_state_${manifest.flowId}');
      return null;
    }

    return FlowController._restored(
      manifest: manifest,
      apiClient: apiClient,
      currentStageJson: decoded['currentStageJson'] as Map<String, dynamic>?,
      isComplete: decoded['isComplete'] as bool? ?? false,
      stepNumber: decoded['stepNumber'] as int? ?? 0,
      initialValues: valuesByStage,
    );
  }
}
