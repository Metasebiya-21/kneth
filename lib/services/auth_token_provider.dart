/// Shared infra, same tier as [ApiClient]/`ApiHttpClient` — not owned by
/// any feature. Supplies the bearer token [ApiClientImpl] attaches to
/// every authenticated call (`Authorization: Bearer <token>`, confirmed
/// against the real backend's `get_auth_context` — plain Keycloak-issued
/// JWT, nothing Keycloak-specific needed on the mobile side beyond
/// providing this string). Returns null when there's no token to send,
/// which [ApiClientImpl] treats as "not authenticated" *before* making any
/// network call — see its own doc comment for why that check happens
/// locally rather than relying on the server's behavior for a missing
/// header.
abstract class AuthTokenProvider {
  String? currentToken();
}

/// A manual stub, kept even now that real login exists
/// (`lib/features/auth/`'s `KeycloakAuthRepositoryImpl`) — investigated,
/// not left over by accident (see NOTES.md's Phase 1). `MockApiClient`
/// remains this app's default `ApiClient` (see main.dart), and this class
/// is still useful specifically for exercising `ApiClientImpl` directly
/// (e.g. from a test or a REPL) without going through the real login
/// flow at all — a plain settable field a developer can populate by hand
/// (e.g. paste in a token obtained from Keycloak directly). A genuinely
/// different use case from real login, not a redundant one: real login
/// is how the app is actually used; this is a developer convenience for
/// exercising the network layer in isolation. Starts with no token
/// (`currentToken()` returns null) — nothing is ever authenticated by
/// default.
class DevAuthTokenProvider implements AuthTokenProvider {
  String? token;

  DevAuthTokenProvider({this.token});

  @override
  String? currentToken() => token;
}
