/// Wire-shaped types [ApiClient] returns — owned by `lib/services/`, not by
/// any feature, exactly because `ApiClient` itself is shared infrastructure
/// every feature can depend on, but nothing should depend the other way
/// around. Before this file existed, [ApiClient] returned flow's own
/// `ResolvedFlowManifest`/`FieldOption` domain types directly from its
/// method signatures — meaning shared code reached *into* one feature's
/// domain/, backwards from the dependency direction the boundary script
/// enforces everywhere else. See NOTES.md.
///
/// These deliberately don't mirror `StageConfig`/`FieldConfig` themselves —
/// only the flat/simple shapes ([FlowManifestDto], [FieldOptionDto],
/// [ClientSummaryDto], [WorkflowSummaryDto]) that [ApiClient]'s own methods
/// actually hand back. A flow stage's field descriptors are deeply nested
/// and already have a correct parser (`StageConfig.fromJson`/
/// `FieldConfig.fromJson`, in flow's own domain/); duplicating that as a
/// second, parallel DTO layer would just be two copies of the same parsing
/// logic to keep in sync for no benefit. So [FlowManifestDto] carries
/// stage data as the same raw `List<Map<String, dynamic>>` shape
/// `ResolvedFlowManifest` already keeps around for persistence
/// round-tripping — flow's own data layer (`FlowRepositoryImpl`) is what
/// turns that raw JSON into `StageConfig`s, by constructing a
/// `ResolvedFlowManifest` from it, exactly the mapping step this file's
/// doc comment promises lives in data/, not here.
///
/// [caseId]/[workflowVersion] were confirmed against the real backend's
/// `FlowManifestResponse` (`app/case/adapters/inbound/schemas.py`) rather
/// than guessed — see NOTES.md's "Building ApiClientImpl" section for what
/// changed here and why (this DTO used to have `flowId`/`clientId`/
/// `fetchedAt` fields that don't correspond to anything the server
/// actually returns).
class FlowManifestDto {
  final String caseId;
  final List<String> workflowVersion;
  final List<Map<String, dynamic>> stagesJson;

  const FlowManifestDto({
    required this.caseId,
    required this.workflowVersion,
    required this.stagesJson,
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
/// record_id, business_record_id}`. `businessRecordId` isn't carried here:
/// this app has no business-flow UI at all (see NOTES.md's Phase 4 on
/// `CreateBusinessRecordUseCase`/individual-only document upload), so
/// there's nothing that would ever read it. `recordId` null means this
/// submission was TENANT-only — no GLOBAL fields, so no identity record
/// was created, so there's nothing to upload a document against (see
/// NOTES.md's Phase 2).
class SubmitCaseResultDto {
  final String caseId;
  final String status;
  final String? recordId;

  const SubmitCaseResultDto({required this.caseId, required this.status, this.recordId});
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
