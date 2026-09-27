import 'auth_token.dart';

/// The auth feature's port: what the rest of the app can ask it to do
/// without knowing what's underneath — today the onboarding-platform
/// backend's own `/auth/*` routes, which proxy Keycloak's password grant
/// (see NOTES.md, "Auth through the backend's /auth proxy"). It used to be
/// a direct Keycloak client; nothing above this interface changed when that
/// was swapped.
abstract class AuthRepository {
  /// Logs in, persists the resulting tokens, and returns them. Throws
  /// `PasswordChangeRequiredException` (not an `AppException`) when the
  /// password was right but must be replaced first — see
  /// [changePassword].
  Future<AuthToken> login({required String username, required String password});

  /// Replaces [currentPassword] with [newPassword]. Also how a newly hired
  /// agent's temporary password is replaced. Persists nothing — call
  /// [login] afterwards.
  Future<void> changePassword({
    required String username,
    required String currentPassword,
    required String newPassword,
  });

  /// Asks for a password-reset code to be sent to the account's registered
  /// phone. Succeeds identically whether or not [username] exists.
  Future<void> sendPasswordResetCode({required String username});

  /// Issues a fresh code, invalidating the previous one. Same
  /// no-enumeration behavior as [sendPasswordResetCode].
  Future<void> resendPasswordResetCode({required String username});

  /// Sets [newPassword] if [code] is the account's current reset code.
  Future<void> resetPassword({required String username, required String code, required String newPassword});

  /// Exchanges the persisted refresh token for a new token pair, persists
  /// the result, and returns it. Throws if there's no refresh token to use
  /// (never logged in, or [logout] already cleared it).
  Future<AuthToken> refresh();

  /// Clears whatever's persisted (memory and secure storage both), then
  /// asks the server to end the session, best effort: a failure there is
  /// swallowed, since the local session is already gone either way.
  Future<void> logout();

  /// The full currently-persisted session, if any — loaded from secure
  /// storage once at startup (see [initialize]) and kept in memory from
  /// then on. Null if never logged in, or after [logout].
  ///
  /// Named `currentSession`, not `currentToken` — a real naming collision
  /// forced this, not a style choice: whatever implements this also
  /// implements `lib/services/auth_token_provider.dart`'s
  /// `AuthTokenProvider.currentToken()` (see
  /// `BackendAuthRepositoryImpl`'s own doc comment for why one class
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
