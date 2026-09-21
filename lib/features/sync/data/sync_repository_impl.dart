import '../../../services/api_client.dart';
import '../../../services/app_exception.dart';
import '../domain/document_kind_mapping.dart';
import '../domain/sync_repository.dart';
import '../domain/sync_status.dart';

/// The real implementation of [SyncRepository]: talks to [ApiClient] (the
/// app's shared network boundary — it lives outside this feature because
/// other features use it too, not just sync) and turns its calls into a
/// stream of [SyncStatus] progress updates.
///
/// This is the only file in the sync feature allowed to know that
/// "submitting a case" is actually `submitCase` followed by one
/// `uploadDocument` call per captured file — that's an infrastructure/
/// network-mechanics detail, not a business rule, so it lives here in
/// data/ rather than in a use case. See NOTES.md's Phase 2 for why this
/// replaced the earlier submit+finalize two-step shape, and for why
/// per-file sequencing (stop on the first failure, rather than attempt
/// every file and report which failed) stayed here too rather than
/// becoming its own use case: it's the same shape of decision the
/// original two-step sequencing already was — mechanical orchestration
/// with one simple, stated policy, not complex enough to warrant a
/// domain class of its own.
class SyncRepositoryImpl implements SyncRepository {
  final ApiClient apiClient;

  const SyncRepositoryImpl({required this.apiClient});

  @override
  Stream<SyncStatus> submitCase({
    required String? caseId,
    required Map<String, dynamic> values,
    required Map<String, String> mediaFilesByStage,
  }) async* {
    final totalSteps = 1 + mediaFilesByStage.length;
    try {
      yield SyncUploading(step: 1, totalSteps: totalSteps, label: 'Submitting case');
      final result = await apiClient.submitCase(caseId: caseId, values: values);

      if (mediaFilesByStage.isNotEmpty) {
        final recordId = result.recordId;
        if (recordId == null) {
          // A precondition/data-modeling gap, not a network outcome — the
          // same reasoning as ApiClientImpl.submitCase's null-caseId
          // guard: captured files exist but submitCase returned nothing
          // to upload them against (no GLOBAL-scope fields were
          // submitted). Failing loudly here, rather than silently
          // dropping the files, matches this codebase's standing rule
          // that an agent's captured document never just disappears.
          throw StateError(
            'submitCase returned no recordId, but captured documents exist for stages: '
            '${mediaFilesByStage.keys.join(', ')} — nothing to upload them against.',
          );
        }

        var step = 1;
        for (final entry in mediaFilesByStage.entries) {
          final stageId = entry.key;
          final filePath = entry.value;
          final kind = documentKindForStageId(stageId);
          if (kind == null) {
            throw StateError(
              'No confirmed DocumentKind mapping for stage "$stageId" — see NOTES.md\'s Phase 2.',
            );
          }
          step++;
          yield SyncUploading(step: step, totalSteps: totalSteps, label: 'Uploading $stageId');
          await apiClient.uploadDocument(recordId: recordId, kind: kind, filePath: filePath);
        }
      }

      yield const SyncSucceeded();
    } on AppException catch (e) {
      // The expected path — ApiClient only ever throws AppException (see
      // NOTES.md's Part 4) — passed through completely unchanged: not
      // wrapped, not re-stringified, not swallowed.
      yield SyncFailed(e);
    } catch (e) {
      // Defensive fallback for a genuinely unanticipated throw (including
      // the two StateErrors above), so this stream still only ever yields
      // an AppException-carrying SyncFailed, never a raw exception type
      // escaping some other way.
      yield SyncFailed(UnknownException(e.toString()));
    }
  }
}
