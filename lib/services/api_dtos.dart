/// Wire-shaped types [ApiClient] returns — owned by `lib/services/`, not by
/// any feature, exactly because `ApiClient` itself is shared infrastructure
/// every feature can depend on, but nothing should depend the other way
/// around. Before this file existed, [ApiClient] returned flow's own
/// `ResolvedFlowManifest`/`FieldOption` domain types directly from its
/// method signatures — meaning shared code reached *into* one feature's
/// domain/, backwards from the dependency direction the boundary script
/// enforces everywhere else. See NOTES.md.
///
/// These deliberately don't mirror `StageConfig`/`FieldConfig` themselves: only the flat/simple
/// shapes ([StacFlowManifestDto], [FieldOptionDto], [ClientSummaryDto], [WorkflowSummaryDto]) that
/// [ApiClient]'s own methods actually hand back. A stage is carried as the raw
/// `List<Map<String, dynamic>>` the wire sent; flow's own data layer (`FlowRepositoryImpl`, via
/// `stac_manifest_mapper.dart`) is what turns it into the domain's `StageConfig`s, exactly the mapping
/// step this file's doc comment promises lives in data/, not here.
///
/// What `POST /cases/flow-manifest/stac` returns (STAC_MIGRATION_SCOPING.md section 11), the app's only
/// manifest route: `case_id`/`workflow_version` plus the stages. Each stage is
/// `{stageId, title, screenType, nativeHandler, widget}` where `widget` is an open Stac JSON tree, kept
/// as raw maps: the mapper and the parsers under `features/stac_rendering/` are the only code that
/// interprets it. Confirmed against the real backend's `StacFlowManifestResponse`
/// (`app/case/adapters/inbound/schemas.py`).
class StacFlowManifestDto {
  final String caseId;
  final List<String> workflowVersion;
  final List<Map<String, dynamic>> stages;

  const StacFlowManifestDto({
    required this.caseId,
    required this.workflowVersion,
    required this.stages,
  });
}

class FieldOptionDto {
  final String label;
  final String value;

  const FieldOptionDto({required this.label, required this.value});
}

/// `{id, name}` — confirmed directly against `ClientSummaryResponse` in
/// `app/config/adapters/inbound/schemas.py`. Deliberately minimal, the
/// same reason that backend schema is: nothing mobile-facing should ever
/// see a client's `api_key`/webhook settings.
class ClientSummaryDto {
  final String id;
  final String name;

  const ClientSummaryDto({required this.id, required this.name});
}

/// `{id, name}` — confirmed directly against `WorkflowSummaryResponse`.
class WorkflowSummaryDto {
  final String id;
  final String name;

  const WorkflowSummaryDto({required this.id, required this.name});
}

/// Confirmed directly against `SubmitCaseResponse`
/// (`app/case/adapters/inbound/schemas.py`) — `{case_id, status,
/// record_id, business_record_id}`. Each id is non-null only if the
/// submission carried that side's GLOBAL fields: [recordId] null means no
/// individual identity fields were submitted (nothing to upload an
/// individual document against, NOTES.md's Phase 2); [businessRecordId]
/// null means no business fields were (nothing to upload a business
/// document against). A combined KYC+KYB submission returns both.
class SubmitCaseResultDto {
  final String caseId;
  final String status;
  final String? recordId;
  final String? businessRecordId;

  const SubmitCaseResultDto({required this.caseId, required this.status, this.recordId, this.businessRecordId});
}

/// A supervisor's decision on a case whose liveness check was exhausted (`GET
/// /cases/{id}/liveness-status`). A human decision, not an attested claim.
class LivenessOverrideDto {
  final String method;
  final String decision;

  const LivenessOverrideDto({required this.method, required this.decision});
}

/// The BACKEND's count of a case's device-liveness attempts (confirmed against
/// `LivenessStatusResponse`). The device never counts for itself: this is the
/// source of truth, and [attestedPassRecorded] is the device's own claim as
/// recorded, not a verification.
class LivenessStatusDto {
  final String caseStatus;
  final int attemptsUsed;
  final int attemptsCompleted;
  final int maxAttempts;
  final int attemptsRemaining;
  final bool attestedPassRecorded;
  final String? openAttemptId;
  final LivenessOverrideDto? override;

  const LivenessStatusDto({
    required this.caseStatus,
    required this.attemptsUsed,
    required this.attemptsCompleted,
    required this.maxAttempts,
    required this.attemptsRemaining,
    required this.attestedPassRecorded,
    this.openAttemptId,
    this.override,
  });
}

/// `POST /cases/{id}/liveness-attempts`: an attempt the backend has started (or
/// handed back because it was still open) plus the resulting status.
class LivenessAttemptDto {
  final String attemptId;
  final int attemptNumber;
  final LivenessStatusDto status;

  const LivenessAttemptDto({required this.attemptId, required this.attemptNumber, required this.status});
}

/// Confirmed against `VerificationResponse` (`{id, result, provider}`) for
/// `POST /identity/records/{record_id}/verifications/device_liveness`. [result]
/// is `attested_passed` or `attested_failed`: the backend recorded the device's
/// own claim and checked nothing. Nothing in this app may present it as
/// verified.
class AttestedLivenessResultDto {
  final String id;
  final String result;
  final String provider;

  const AttestedLivenessResultDto({required this.id, required this.result, required this.provider});
}

/// Confirmed directly against `UploadDocumentResponse`
/// (`app/identity/adapters/inbound/schemas.py`) — `{id, kind,
/// file_reference}`.
class UploadedDocumentDto {
  final String id;
  final String kind;
  final String fileReference;

  const UploadedDocumentDto({required this.id, required this.kind, required this.fileReference});
}
