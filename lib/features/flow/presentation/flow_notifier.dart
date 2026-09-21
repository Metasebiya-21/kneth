import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../services/api_client.dart';
import '../../../services/app_exception.dart';
import '../domain/flow_case_state.dart';
import '../domain/flow_manifest.dart';
import '../domain/flow_repository.dart';
import '../domain/load_flow_case_use_case.dart';

/// The one [ApiClient] instance the whole app shares. Flow is the only
/// feature that reads this provider directly (to build [FlowRepository]
/// and to resolve DYNAMIC field options) — sync and native_capture still
/// get their [ApiClient] exactly the way they did before this migration,
/// via `FlowSession.apiClient`, never by importing this provider
/// themselves. See main.dart for the override.
final apiClientProvider = Provider<ApiClient>((ref) {
  throw UnimplementedError(
    'apiClientProvider has no default — it must be overridden, see main.dart.',
  );
});

/// See main.dart for the override (a real `FlowRepositoryImpl` built from
/// [apiClientProvider]).
final flowRepositoryProvider = Provider<FlowRepository>((ref) {
  throw UnimplementedError(
    'flowRepositoryProvider has no default — it must be overridden, see main.dart.',
  );
});

/// What the UI needs to know about the current attempt to load or refresh
/// a case: still working on it, ready with a [FlowCaseState], or failed.
/// This wraps the domain's [FlowCaseState] rather than being a domain type
/// itself — "is the load in progress/failed right now" describes this
/// screen session's current async operation, not a fact about the case
/// the way [FlowCaseState]'s own fields (stage index, collected values)
/// are. Compare with sync's `SyncStatus`, which *is* domain: it describes
/// real, meaningful states of a case upload, not just "is a Future
/// pending."
sealed class FlowViewState {
  const FlowViewState();
}

class FlowViewLoading extends FlowViewState {
  const FlowViewLoading();
}

class FlowViewReady extends FlowViewState {
  final FlowCaseState caseState;
  const FlowViewReady(this.caseState);
}

class FlowViewError extends FlowViewState {
  final AppException error;
  const FlowViewError(this.error);
}

final flowNotifierProvider = StateNotifierProvider<FlowNotifier, FlowViewState>((ref) {
  return FlowNotifier(ref.watch(flowRepositoryProvider));
});

/// Drives a single-fetch, single-submit flow case. [LoadFlowCaseUseCase]
/// is asked exactly once — via [start] for a brand new case, or [resume]
/// for a possibly-saved one — and from then on [submitStage]/[back] are
/// pure local moves over the in-memory [FlowCaseState] (via
/// [FlowCaseState.advanced]/[FlowCaseState.rewound]), saved after every
/// change. No further network call happens until sync (a different
/// feature entirely) submits the whole case.
class FlowNotifier extends StateNotifier<FlowViewState> {
  final FlowRepository _repository;
  late final LoadFlowCaseUseCase _loadCase = LoadFlowCaseUseCase(_repository);

  FlowManifest? _manifest;
  bool _lastLoadWasResume = false;

  FlowNotifier(this._repository) : super(const FlowViewLoading());

  /// Starts a brand-new case for [manifest] — always a fresh fetch,
  /// discarding anything saved.
  Future<void> start(FlowManifest manifest) async {
    _manifest = manifest;
    _lastLoadWasResume = false;
    await _load(() => _loadCase.start(manifest));
  }

  /// Resumes [manifest]'s saved case if one exists (refreshing it first if
  /// it's gone stale — see [LoadFlowCaseUseCase.resume]), or starts fresh
  /// if there's nothing to resume.
  Future<void> resume(FlowManifest manifest) async {
    _manifest = manifest;
    _lastLoadWasResume = true;
    await _load(() async => (await _loadCase.resume(manifest)) ?? await _loadCase.start(manifest));
  }

  /// Re-attempts whichever of [start]/[resume] was last tried.
  Future<void> retry() async {
    final manifest = _manifest;
    if (manifest == null) return;
    if (_lastLoadWasResume) {
      await resume(manifest);
    } else {
      await start(manifest);
    }
  }

  Future<void> _load(Future<FlowCaseState> Function() loader) async {
    state = const FlowViewLoading();
    try {
      final caseState = await loader();
      state = FlowViewReady(caseState);
      // Only persist a known-good state — never a failed/ambiguous one.
      await _repository.saveCaseState(caseState);
    } on AppException catch (e) {
      // The expected path — FlowRepositoryImpl's own ApiClient call only
      // ever throws AppException — passed through unchanged, the same
      // discipline SyncRepositoryImpl already follows.
      state = FlowViewError(e);
    } catch (e) {
      // Defensive fallback for a genuinely unanticipated non-AppException
      // throw, so this notifier's state still only ever carries an
      // AppException here too — see NOTES.md's Phase 4 for why
      // FlowViewError was widened from a bare Object to this.
      state = FlowViewError(UnknownException(e.toString()));
    }
  }

  /// Records [values] for the current stage and advances — a local move,
  /// no network call.
  void submitStage(Map<String, dynamic> values) {
    final current = state;
    if (current is! FlowViewReady) return;
    final next = current.caseState.advanced(values);
    state = FlowViewReady(next);
    _repository.saveCaseState(next);
  }

  /// Returns to the previously-visited stage, if any — a local move, no
  /// network call.
  void back() {
    final current = state;
    if (current is! FlowViewReady) return;
    state = FlowViewReady(current.caseState.rewound());
  }

  /// Clears any saved state for this case, e.g. once it's synced
  /// successfully.
  Future<void> clearSaved() async {
    final manifest = _manifest;
    if (manifest == null) return;
    await _repository.clearSavedCaseState(manifest.workflowId);
  }
}
