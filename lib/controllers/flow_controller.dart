import 'dart:convert';

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

/// Drives a fully server-driven flow: it holds no local stage list at all,
/// just whatever stage [ApiClient.fetchNextStage] last returned. Each call
/// asks the (mocked) server "what's next", optionally informed by the
/// values just submitted, so branching is entirely the server's call.
class FlowController extends ChangeNotifier {
  final FlowManifest manifest;
  final ApiClient apiClient;

  Map<String, dynamic>? _currentStageJson;
  StageConfig? _currentStage;
  bool _isLoading;
  bool _isComplete;
  Object? _loadError;
  int _stepNumber;
  final Map<String, Map<String, dynamic>> _collectedValues;
  final List<_HistoryEntry> _history = [];

  String? _lastAfterStageId;
  Map<String, dynamic>? _lastSubmittedValues;

  /// Starts a fresh flow: kicks off fetching the first stage immediately.
  FlowController({required this.manifest, ApiClient? apiClient})
      : apiClient = apiClient ?? MockApiClient(),
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
  })  : apiClient = apiClient ?? MockApiClient(),
        _currentStageJson = currentStageJson,
        _currentStage = currentStageJson != null ? StageConfig.fromJson(currentStageJson) : null,
        _isLoading = false,
        _isComplete = isComplete,
        _stepNumber = stepNumber,
        _collectedValues = initialValues;

  /// True while a stage is being fetched (initial load, or after submit).
  bool get isLoading => _isLoading;

  /// True once the server has signaled there's no next stage.
  bool get isComplete => _isComplete;

  /// Set when the last fetch failed; cleared by [retry]/a successful fetch.
  Object? get loadError => _loadError;

  /// Only valid when [isLoading] is false, [loadError] is null, and
  /// [isComplete] is false.
  StageConfig get currentStage => _currentStage!;

  /// No fixed total is knowable ahead of time in a server-driven, possibly
  /// branching flow — this just reports how many stages have been reached.
  String get progressLabel => 'Step ${_stepNumber.toString().padLeft(2, '0')}';

  Map<String, dynamic> get allValues => {
        for (final entry in _collectedValues.entries)
          for (final value in entry.value.entries)
            '${entry.key}.${value.key}': value.value,
      };

  Map<String, dynamic> valuesForStage(String stageId) =>
      _collectedValues[stageId] ?? {};

  Future<void> submitStage(Map<String, dynamic> values) async {
    if (_isLoading || _isComplete || _currentStageJson == null) return;
    final stageId = currentStage.stageId;
    _collectedValues[stageId] = Map<String, dynamic>.from(values);
    _history.add(_HistoryEntry(stageJson: _currentStageJson!, stepNumber: _stepNumber));
    await _loadNext(afterStageId: stageId, submittedValues: values);
  }

  /// Re-attempts whatever fetch last failed.
  Future<void> retry() => _loadNext(
        afterStageId: _lastAfterStageId,
        submittedValues: _lastSubmittedValues,
      );

  /// Returns to the previously-visited stage, if any (client-side history —
  /// the server is only ever asked to go forward).
  void back() {
    if (_isLoading || _history.isEmpty) return;
    final previous = _history.removeLast();
    _currentStageJson = previous.stageJson;
    _currentStage = StageConfig.fromJson(previous.stageJson);
    _stepNumber = previous.stepNumber;
    _isComplete = false;
    _loadError = null;
    notifyListeners();
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
      // Only persist a known-good state — never a failed/ambiguous one.
      save();
    } catch (e) {
      _isLoading = false;
      _loadError = e;
      notifyListeners();
    }
  }

  String get _storageKey => 'sdui_flow_state_${manifest.flowId}';

  /// Persists the current stage descriptor and collected values so an
  /// in-progress case survives an app restart. Fire-and-forget is fine
  /// here since a save that loses a race with app termination just means
  /// the last stage isn't resumed.
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
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

  /// Clears any saved state for this flow, e.g. once a case has synced
  /// successfully or the user chooses to start over.
  Future<void> clearSaved() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  /// Reads saved state for [manifest], if any, and returns a
  /// [FlowController] restored to that point — without re-fetching
  /// anything — or null if there's no in-progress case saved.
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
