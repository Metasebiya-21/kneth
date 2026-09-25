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
/// `uploadDocument` (individual) or `uploadBusinessDocument` (business,
/// chosen by the file's `DocumentKind`) call per captured file — that's an infrastructure/
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
    Map<String, Map<String, dynamic>> attestedLivenessByStage = const {},
  }) async* {
    final totalSteps = 1 + mediaFilesByStage.length + attestedLivenessByStage.length;
    try {
      yield SyncUploading(step: 1, totalSteps: totalSteps, label: 'Submitting case');
      final result = await apiClient.submitCase(caseId: caseId, values: values);

      if (mediaFilesByStage.isNotEmpty || attestedLivenessByStage.isNotEmpty) {
        // Resolve every step's target BEFORE uploading anything, so a step that
        // can never be sent fails the sync up front rather than after earlier
        // ones already went out. Nothing is silently dropped: a stage with no
        // confirmed kind, a document whose record submitCase didn't create (an
        // individual document with no `recordId`, a business one with no
        // `businessRecordId` — i.e. no GLOBAL fields of that side were
        // submitted), or an attested liveness claim with no `recordId`, or a
        // malformed one, is a hard failure.
        final plan = <_SyncStep>[];
        for (final entry in mediaFilesByStage.entries) {
          final stageId = entry.key;
          final target = documentTargetForStageId(stageId);
          if (target == null) {
            throw StateError(
              'No confirmed DocumentKind mapping for stage "$stageId" — see NOTES.md\'s Phase 2.',
            );
          }
          final recordId = switch (target.owner) {
            DocumentOwner.individual => result.recordId,
            DocumentOwner.business => result.businessRecordId,
          };
          if (recordId == null) {
            throw StateError(
              'submitCase returned no ${target.owner == DocumentOwner.business ? 'businessRecordId' : 'recordId'}, '
              'but a captured ${target.owner.name} document (${target.kind}) exists for stage "$stageId" — '
              'nothing to upload it against.',
            );
          }
          plan.add(_DocumentStep(stageId: stageId, filePath: entry.value, target: target, recordId: recordId));
        }
        for (final entry in attestedLivenessByStage.entries) {
          final stageId = entry.key;
          final recordId = result.recordId;
          if (recordId == null) {
            throw StateError(
              'submitCase returned no recordId, but stage "$stageId" holds a device-attested liveness claim — '
              'nothing to record it against.',
            );
          }
          final claim = entry.value;
          final verdict = claim['attestedLivenessVerdict'];
          final flags = claim['attestedAntiSpoofingFlags'];
          if (verdict is! bool || flags is! Map) {
            throw StateError('The attested liveness claim for stage "$stageId" is malformed.');
          }
          plan.add(_AttestationStep(
            stageId: stageId,
            recordId: recordId,
            verdict: verdict,
            flags: Map<String, dynamic>.from(flags),
            sessionId: claim['attestedSessionId'] as String?,
            detector: claim['attestedDetector'] as String?,
          ));
        }

        var step = 1;
        for (final item in plan) {
          step++;
          switch (item) {
            case _DocumentStep():
              yield SyncUploading(step: step, totalSteps: totalSteps, label: 'Uploading ${item.stageId}');
              switch (item.target.owner) {
                case DocumentOwner.individual:
                  await apiClient.uploadDocument(
                      recordId: item.recordId, kind: item.target.kind, filePath: item.filePath);
                case DocumentOwner.business:
                  await apiClient.uploadBusinessDocument(
                    businessRecordId: item.recordId,
                    kind: item.target.kind,
                    filePath: item.filePath,
                  );
              }
            case _AttestationStep():
              yield SyncUploading(
                  step: step, totalSteps: totalSteps, label: 'Recording device-attested liveness (${item.stageId})');
              await apiClient.submitAttestedLiveness(
                recordId: item.recordId,
                attestedLivenessVerdict: item.verdict,
                attestedAntiSpoofingFlags: item.flags,
                attestedSessionId: item.sessionId,
                attestedDetector: item.detector,
              );
          }
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

sealed class _SyncStep {
  final String stageId;
  final String recordId;
  const _SyncStep({required this.stageId, required this.recordId});
}

class _DocumentStep extends _SyncStep {
  final String filePath;
  final DocumentTarget target;
  const _DocumentStep({required super.stageId, required super.recordId, required this.filePath, required this.target});
}

/// The device's own liveness claim, sent as-is (never re-derived here).
class _AttestationStep extends _SyncStep {
  final bool verdict;
  final Map<String, dynamic> flags;
  final String? sessionId;
  final String? detector;
  const _AttestationStep({
    required super.stageId,
    required super.recordId,
    required this.verdict,
    required this.flags,
    this.sessionId,
    this.detector,
  });
}
