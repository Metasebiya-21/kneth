import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../domain/sync_repository.dart';
import '../domain/sync_status.dart';

/// Provides the [SyncRepository] the notifier below should talk to.
///
/// This provider has no real implementation of its own — it always throws
/// if read directly. [SyncScreen] always overrides it (normally with a
/// real `SyncRepositoryImpl` built from the current `ApiClient`; tests can
/// override it with a fake instead) before any widget underneath it can
/// read [syncNotifierProvider]. This "placeholder that must be overridden"
/// pattern is the same one already used in this codebase for
/// kifiya_rendering_engine's own providers — see
/// RenderingEngineStageScreen — so a missing override fails loudly instead
/// of silently talking to the wrong backend.
final syncRepositoryProvider = Provider<SyncRepository>((ref) {
  throw UnimplementedError(
    'syncRepositoryProvider has no default — it must be overridden, see SyncScreen.',
  );
});

/// Exposes the in-progress [SyncStatus] to widgets, and lets them trigger
/// (or retry) a submission via [SyncNotifier.submit].
final syncNotifierProvider = StateNotifierProvider.autoDispose<SyncNotifier, SyncStatus>((ref) {
  return SyncNotifier(ref.watch(syncRepositoryProvider));
});

/// Why [StateNotifier] and not [AsyncNotifier]: [AsyncNotifier] is shaped
/// for "run one Future, get one value back" (its state is
/// loading/data/error). Our source is a [Stream] that emits *several*
/// [SyncStatus] values over time (uploading step 1, then step 2, then
/// succeeded/failed), and we already have a type — [SyncStatus] — that
/// represents every one of those points directly. [StateNotifier] just
/// holds "the current [SyncStatus]" and lets us push a new one in every
/// time the stream emits, which matches the shape of the problem with no
/// translation needed. It also gives us an explicit [submit] method to
/// call from the screen — the equivalent of the old `SyncScreen`'s
/// `_start()`/`_retry()`, which doesn't map as naturally onto
/// [AsyncNotifier]'s "runs automatically" `build()`.
class SyncNotifier extends StateNotifier<SyncStatus> {
  final SyncRepository _repository;
  StreamSubscription<SyncStatus>? _subscription;

  SyncNotifier(this._repository) : super(const SyncIdle());

  /// Starts (or restarts, e.g. on retry) submitting the case, updating
  /// [state] as progress comes in from the repository's stream.
  void submit({
    required String? caseId,
    required Map<String, dynamic> values,
    required Map<String, String> mediaFilesByStage,
  }) {
    _subscription?.cancel();
    state = const SyncIdle();
    _subscription = _repository
        .submitCase(caseId: caseId, values: values, mediaFilesByStage: mediaFilesByStage)
        .listen((status) => state = status);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
