/// Maps a captured-media stage's id onto the confirmed backend's
/// `DocumentKind` enum value it should be uploaded as
/// (`POST /identity/records/{record_id}/documents/{kind}` — see
/// NOTES.md's Phase 2). Investigated, not guessed: `MockApiClient`'s own
/// two native-capture stages are `identification_card` (photo) and
/// `consent_signature` (signature). The first already *is* a real
/// `DocumentKind` value — a stage id can serve as its own kind when it
/// happens to match one exactly. The second isn't (the confirmed kind is
/// just `signature`, not `consent_signature`), so a stage id can't
/// *always* serve as its own kind, only sometimes — hence this small,
/// explicit, honestly-incomplete mapping rather than a blanket rule.
///
/// A stage id with no entry here has no known `DocumentKind` to upload
/// as — [documentKindForStageId] returns null, and callers (see
/// `SyncRepositoryImpl`) must not silently drop the file in that case:
/// an agent's captured document disappearing without a trace is a worse
/// failure than a loud one.
///
/// Which upload route a kind goes to is a property of the kind itself, not
/// of the stage or its `nativeHandler` (both business and individual
/// capture stages are `photo_capture`/`signature_capture` — the same
/// mechanism): the backend's `DocumentKind` splits into three individual
/// values and five business values, disjoint, and each route rejects the
/// other's kinds (`_INDIVIDUAL_DOCUMENT_KINDS`/`_BUSINESS_DOCUMENT_KINDS`,
/// `app/identity/adapters/inbound/router.py`). [documentTargetForStageId]
/// therefore returns both the kind and its [DocumentOwner].
const _individualDocumentKinds = {
  'identification_card',
  'signature',
  'profile_picture',
};

const _businessDocumentKinds = {
  'corporate_governance_document',
  'business_image',
  'trade_license',
  'memorandum_of_association',
  'article_of_association',
};

/// Whose record a document is uploaded against.
enum DocumentOwner {
  /// `POST /identity/records/{record_id}/documents/{kind}` (submitCase's `record_id`).
  individual,

  /// `POST /identity/business-records/{business_record_id}/documents/{kind}`
  /// (submitCase's `business_record_id`).
  business,
}

class DocumentTarget {
  final String kind;
  final DocumentOwner owner;

  const DocumentTarget(this.kind, this.owner);

  @override
  bool operator ==(Object other) => other is DocumentTarget && other.kind == kind && other.owner == owner;

  @override
  int get hashCode => Object.hash(kind, owner);

  @override
  String toString() => 'DocumentTarget($kind, ${owner.name})';
}

/// Stage ids whose own value isn't a `DocumentKind` by itself.
const _stageIdOverrides = {
  'consent_signature': 'signature',
  // The liveness stage's captured final image is uploaded as the customer's
  // profile picture (an individual kind), through the ordinary document path.
  'selfie_liveness': 'profile_picture',
};

String? documentKindForStageId(String stageId) {
  if (_individualDocumentKinds.contains(stageId) || _businessDocumentKinds.contains(stageId)) return stageId;
  return _stageIdOverrides[stageId];
}

/// The kind and owner for [stageId], or null if the stage has no confirmed
/// `DocumentKind` (callers must fail loudly, never drop the file).
DocumentTarget? documentTargetForStageId(String stageId) {
  final kind = documentKindForStageId(stageId);
  if (kind == null) return null;
  return DocumentTarget(
    kind,
    _businessDocumentKinds.contains(kind) ? DocumentOwner.business : DocumentOwner.individual,
  );
}
