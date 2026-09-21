/// A Keycloak token pair, plus when the access token stops being valid.
/// Pure data — parsing the token endpoint's JSON response into this shape
/// happens in data/, not here.
class AuthToken {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  const AuthToken({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  /// True once [expiresAt] has passed. [KeycloakAuthRepositoryImpl]'s
  /// background refresh checks a buffered version of this (see its own
  /// doc comment) so a call rarely has to discover expiry the hard way,
  /// via a real 401 — but a 401 is still handled correctly if one slips
  /// through (see AuthTokenProvider's own doc comment on why
  /// currentToken() stays synchronous).
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
