import 'package:flutter_riverpod/legacy.dart';

import '../domain/field_config.dart';

/// Live DYNAMIC options that a stage screen has already fetched, kept for the
/// rest of the session so a later screen (the completion summary) can turn a
/// stored value back into its label without another network call. Keyed
/// `"<stageId>.<fieldKey>"`, the same shape as the flat payload's keys.
///
/// Needed because the fetching controllers are per stage and discarded when
/// the agent leaves it; static and eagerly-resolved options don't need this
/// (they're in the manifest). In memory only: after an app restart the cache
/// is empty and the summary re-fetches (see `SummaryValueText`).
final resolvedOptionsProvider =
    StateNotifierProvider<ResolvedOptionsCache, Map<String, List<FieldOption>>>((ref) => ResolvedOptionsCache());

class ResolvedOptionsCache extends StateNotifier<Map<String, List<FieldOption>>> {
  ResolvedOptionsCache() : super(const {});

  void record(String stageId, String fieldKey, List<FieldOption> options) {
    state = {...state, '$stageId.$fieldKey': options};
  }
}
