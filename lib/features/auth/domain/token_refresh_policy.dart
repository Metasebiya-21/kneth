import 'auth_token.dart';

/// Whether [token] is close enough to expiring that it should be
/// proactively refreshed now, rather than waiting for it to actually
/// expire and surface as a real 401. Pure computation, no I/O — the same
/// shape as flow's own `ResolvedFlowManifest.isStale`/
/// `LoadFlowCaseUseCase`'s staleness policy, and DYNAMIC options'
/// `resolveDynamicEndpoint`/`changedDynamicFieldKeys`: a small, genuine
/// "if this, then that instead" decision, not mechanical forwarding, but
/// not big enough to need its own use-case class either — see NOTES.md's
/// Phase 1 for why `AuthTokenProvider.currentToken()` stays synchronous
/// and this policy is what keeps that safe in practice: `AuthNotifier`
/// (presentation) calls this periodically and on app resume, and calls
/// [AuthRepository.refresh] when it returns true.
///
/// A token with no expiry information never needs refreshing here (there
/// isn't one to check against); [token] being null means "not logged in,"
/// also nothing to refresh.
bool shouldRefresh(AuthToken? token, {Duration buffer = const Duration(minutes: 2)}) {
  if (token == null) return false;
  return DateTime.now().isAfter(token.expiresAt.subtract(buffer));
}
