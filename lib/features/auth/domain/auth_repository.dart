import 'auth_token.dart';

/// The auth feature's port: what the rest of the app can ask it to do
/// without knowing it's actually a Keycloak ROPC (resource-owner-password-
/// credentials) client underneath — confirmed as the right grant type by
/// reading the real realm export directly (`directAccessGrantsEnabled:
/// true`, `standardFlowEnabled: false`, `publicClient: true` — see
/// NOTES.md's Phase 1), not assumed from the backend's own test
/// description alone.
abstract class AuthRepository {
  /// Logs in via the password grant, persists the resulting tokens, and
  /// returns them.
  Future<AuthToken> login({required String username, required String password});

  /// Exchanges the persisted refresh token for a new token pair, persists
  /// the result, and returns it. Throws if there's no refresh token to use
  /// (never logged in, or [logout] already cleared it).
  Future<AuthToken> refresh();

  /// Clears whatever's persisted (memory and secure storage both).
  Future<void> logout();

  /// The full currently-persisted session, if any — loaded from secure
  /// storage once at startup (see [initialize]) and kept in memory from
  /// then on. Null if never logged in, or after [logout].
  ///
  /// Named `currentSession`, not `currentToken` — a real naming collision
  /// forced this, not a style choice: whatever implements this also
  /// implements `lib/services/auth_token_provider.dart`'s
  /// `AuthTokenProvider.currentToken()` (see
  /// `KeycloakAuthRepositoryImpl`'s own doc comment for why one class
  /// implements both), which already returns `String?` — the bare access
  /// token, for `ApiClientImpl`'s `Authorization` header. A single class
  /// can't have two methods named `currentToken` returning different
  /// types, so this one, the fuller [AuthToken] (access + refresh +
  /// expiry), needed a different name.
  AuthToken? currentSession();

  /// Loads whatever was persisted from a previous session into memory.
  /// Called once, at app startup, before anything else touches this
  /// repository — the same "cheap, local-only check before runApp" shape
  /// flow's own saved-case check already established.
  Future<void> initialize();
}
