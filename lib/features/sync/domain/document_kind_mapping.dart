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
const _knownDocumentKinds = {
  'identification_card',
  'signature',
  'profile_picture',
  'corporate_governance_document',
  'business_image',
  'trade_license',
  'memorandum_of_association',
  'article_of_association',
};

/// Stage ids whose own value isn't a `DocumentKind` by itself.
const _stageIdOverrides = {
  'consent_signature': 'signature',
};

String? documentKindForStageId(String stageId) {
  if (_knownDocumentKinds.contains(stageId)) return stageId;
  return _stageIdOverrides[stageId];
}
