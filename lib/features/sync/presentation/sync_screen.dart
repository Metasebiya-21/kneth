import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/app_error_view.dart';
import '../../flow/presentation/flow_session.dart';
import '../data/sync_repository_impl.dart';
import '../domain/sync_repository.dart';
import '../domain/sync_status.dart';
import 'sync_notifier.dart';

/// "Sync now" screen shown after a flow completes — submits the collected
/// case and shows live progress, sourced from [syncNotifierProvider]
/// instead of a directly-instantiated engine.
///
/// [controller] used to be a `FlowController` (the old, now-deleted
/// `ChangeNotifier` that owned the whole flow). It's a [FlowSession] now —
/// flow's own narrow facade for exactly what other features need from it
/// (`apiClient`, `allValues`, `clearSaved()`) — but every member this file
/// calls on it is unchanged, which is why migrating flow only meant
/// updating this import, not this screen's own logic.
///
/// [SyncScreen] itself is a plain (non-Consumer) widget whose only job is
/// to open a [ProviderScope] that overrides [syncRepositoryProvider] — with
/// a real [SyncRepositoryImpl] built from `controller.apiClient` (the same
/// [ApiClient] instance the rest of this case is already using), or with
/// [repository] when a test passes one in. Every widget that actually
/// reads sync state lives *inside* that ProviderScope (see [_SyncView]) —
/// the same nested-override pattern this codebase uses for the
/// native-capture screens: a widget can't see an override it declares
/// in its own `build()`, only widgets further down the tree can, so the
/// "read" side has to be a separate widget below the override, not the
/// same one that declares it.
class SyncScreen extends StatelessWidget {
  final FlowSession controller;

  /// Normally left null — production code then gets a real
  /// [SyncRepositoryImpl] wired to `controller.apiClient`. Tests can pass
  /// a fake [SyncRepository] here instead; it's injected through the exact
  /// same [ProviderScope] override production uses, so a widget test never
  /// touches [SyncRepositoryImpl] or a real/mock [ApiClient] at all.
  final SyncRepository? repository;

  const SyncScreen({super.key, required this.controller, this.repository});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        syncRepositoryProvider.overrideWithValue(
          repository ?? SyncRepositoryImpl(apiClient: controller.apiClient),
        ),
      ],
      child: _SyncView(controller: controller),
    );
  }
}

class _SyncView extends ConsumerStatefulWidget {
  final FlowSession controller;

  const _SyncView({required this.controller});

  @override
  ConsumerState<_SyncView> createState() => _SyncViewState();
}

class _SyncViewState extends ConsumerState<_SyncView> {
  @override
  void initState() {
    super.initState();
    // Deferred a frame: submit() writes to the notifier's state, and doing
    // that synchronously inside initState (still part of this widget's
    // first build) is a well-known Riverpod hazard — "modified a provider
    // while the widget tree was building". Posting it for right after the
    // first frame avoids that.
    WidgetsBinding.instance.addPostFrameCallback((_) => _submit());
  }

  void _submit() {
    final values = widget.controller.allValues;
    // Keyed by stage id, not a flat list — SyncRepositoryImpl needs to
    // know which stage produced each file to map it onto a confirmed
    // DocumentKind (see NOTES.md's Phase 2). Every native-capture stage
    // submits its file under the field key 'filePath' (see
    // CapturedMedia's own doc comment), so 'stageId.filePath' is exactly
    // the dotted key each entry appears under.
    const suffix = '.filePath';
    final mediaFilesByStage = {
      for (final entry in values.entries)
        if (entry.key.endsWith(suffix) && entry.value != null)
          entry.key.substring(0, entry.key.length - suffix.length): entry.value as String,
    };

    // A liveness stage keeps the device's claim at 'stageId.attestedLiveness'
    // (a JSON map); each one is recorded against the case's individual record.
    const attestedSuffix = '.attestedLiveness';
    final attestedLivenessByStage = <String, Map<String, dynamic>>{
      for (final entry in values.entries)
        if (entry.key.endsWith(attestedSuffix) && entry.value is Map)
          entry.key.substring(0, entry.key.length - attestedSuffix.length):
              Map<String, dynamic>.from(entry.value as Map),
    };

    ref.read(syncNotifierProvider.notifier).submit(
          caseId: widget.controller.caseId,
          values: values,
          mediaFilesByStage: mediaFilesByStage,
          attestedLivenessByStage: attestedLivenessByStage,
        );
  }

  @override
  Widget build(BuildContext context) {
    // The case has been handed off to the backend once sync succeeds — no
    // need to resume it locally anymore. This is a side effect that
    // coordinates between two features (sync's status and the flow
    // feature's saved state), so it belongs here in the widget, not inside
    // SyncNotifier, which shouldn't need to know FlowController exists.
    ref.listen<SyncStatus>(syncNotifierProvider, (previous, next) {
      if (next is SyncSucceeded) {
        widget.controller.clearSaved();
      }
    });

    final status = ref.watch(syncNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Sync case')),
      body: Center(child: _buildBody(context, status)),
    );
  }

  Widget _buildBody(BuildContext context, SyncStatus status) {
    return switch (status) {
      SyncIdle() => const Text('Preparing...'),
      SyncUploading(:final step, :final totalSteps, :final label) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 220,
                child: LinearProgressIndicator(value: step / totalSteps),
              ),
              const SizedBox(height: 16),
              Text('$label ($step/$totalSteps)'),
            ],
          ),
        ),
      SyncSucceeded() => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 64),
              const SizedBox(height: 16),
              const Text('Case synced successfully'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      SyncFailed(:final exception) => AppErrorView(error: exception, onRetry: _submit),
    };
  }
}
