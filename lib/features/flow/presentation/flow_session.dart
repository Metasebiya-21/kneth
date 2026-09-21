import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/api_client.dart';
import '../domain/flow_case_state.dart';
import 'flow_notifier.dart';

/// A narrow, stable interface for what sync and native_capture need from
/// flow — exactly the members `FlowController` (the old, deleted
/// `ChangeNotifier`) used to expose, so migrating flow didn't require
/// touching either of those already-migrated features' screen internals,
/// only the import path they get this from. See NOTES.md for why this
/// exists instead of those features reading flow's Riverpod providers
/// directly: they'd otherwise need to know about `flowNotifierProvider`,
/// `FlowViewState`'s variants, and unwrap `FlowViewReady` themselves —
/// this hides all of that behind the same handful of calls they already
/// had.
///
/// An interface, not a concrete class — the same shape as
/// `SyncRepository`/`MediaStorageRepository` — so sync's and
/// native_capture's own widget tests can implement a plain fake (no
/// Riverpod, no `WidgetRef`, no flow internals) instead of needing to spin
/// up flow's real provider graph just to exercise a screen that isn't
/// flow's own.
abstract class FlowSession {
  ApiClient get apiClient;
  Map<String, dynamic> get allValues;
  String get progressLabel;

  /// The current case's server-assigned id (see
  /// [ResolvedFlowManifest.caseId]) — sync needs this to call
  /// `ApiClient.submitCase` for real, per NOTES.md's Phase 1.
  String get caseId;
  void submitStage(Map<String, dynamic> values);
  Future<void> clearSaved();
}

/// The real [FlowSession], backed by flow's own Riverpod providers.
/// Constructed fresh by [FlowScreen] each time it hands off to another
/// feature's screen (native capture, sync).
class RiverpodFlowSession implements FlowSession {
  final WidgetRef _ref;

  const RiverpodFlowSession(this._ref);

  @override
  ApiClient get apiClient => _ref.read(apiClientProvider);

  @override
  Map<String, dynamic> get allValues => _readyCaseState.allValues;

  @override
  String get progressLabel => _readyCaseState.progressLabel;

  @override
  String get caseId => _readyCaseState.manifest.caseId;

  FlowCaseState get _readyCaseState {
    final state = _ref.read(flowNotifierProvider);
    if (state is! FlowViewReady) {
      throw StateError('FlowSession used while the flow is not ready (state: $state).');
    }
    return state.caseState;
  }

  @override
  void submitStage(Map<String, dynamic> values) {
    _ref.read(flowNotifierProvider.notifier).submitStage(values);
  }

  @override
  Future<void> clearSaved() => _ref.read(flowNotifierProvider.notifier).clearSaved();
}
