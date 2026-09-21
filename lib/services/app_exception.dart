/// The shared error taxonomy for every network call this app makes.
/// `ApiHttpClient` (a real HTTP call, once one exists) and `MockApiClient`
/// (today's only `ApiClient`) both throw exactly these — never a raw
/// `http` exception, a raw `FormatException`, or a bare `String` — so
/// every caller, all the way up to a screen, handles one small, closed
/// set of outcomes instead of guessing at what a given `ApiClient` method
/// might throw.
///
/// Pure Dart, nothing else — no `package:http`, no Flutter. That's what
/// lets a feature's own domain/ depend on it directly (see
/// `tool/check_layer_boundaries.sh`'s narrow, named allowance for this one
/// file — NOTES.md explains why) without pulling in anything the
/// domain-purity check is actually meant to keep out.
sealed class AppException implements Exception {
  final String message;

  const AppException(this.message);

  /// Whether retrying the same call again might succeed — true for
  /// transient/transport failures, false for anything where the request
  /// itself was the problem (retrying won't fix a malformed request, an
  /// unauthorized token, or a response this app doesn't understand).
  bool get isRetryable;

  @override
  String toString() => message;
}

/// No connectivity, or the host couldn't be reached at all.
class NetworkException extends AppException {
  const NetworkException([super.message = 'No network connection.']);

  @override
  bool get isRetryable => true;
}

/// The request took too long to get a response.
///
/// Named `AppTimeoutException`, not `TimeoutException` — `dart:async`
/// already defines a `TimeoutException` (thrown by `Future.timeout()`),
/// and `ApiHttpClient` needs to catch *that* one and map it onto *this*
/// one; giving both the same name would mean every file that does that
/// mapping has to juggle an import prefix just to tell them apart.
class AppTimeoutException extends AppException {
  const AppTimeoutException([super.message = 'The request timed out.']);

  @override
  bool get isRetryable => true;
}

/// A 5xx response.
class ServerException extends AppException {
  final int statusCode;

  const ServerException(this.statusCode, [String? message]) : super(message ?? 'Server error ($statusCode).');

  @override
  bool get isRetryable => true;
}

/// A 4xx response other than 401 (see [UnauthorizedException]).
class ClientException extends AppException {
  final int statusCode;

  const ClientException(this.statusCode, [String? message]) : super(message ?? 'Request error ($statusCode).');

  @override
  bool get isRetryable => false;
}

/// A 401 response — split out from [ClientException] because real
/// authentication is coming later and will want to react to this one
/// specifically (e.g. prompt a re-login), not just show a generic
/// "request error" message.
class UnauthorizedException extends AppException {
  const UnauthorizedException([super.message = 'Not authorized. Please sign in again.']);

  @override
  bool get isRetryable => false;
}

/// A 403 response — the caller is authenticated, but not authorized for
/// this specific resource (confirmed against the real backend: an agent
/// whose token is valid but isn't assigned to the client a request is
/// scoped to). Split out from [ClientException] for the same reason
/// [UnauthorizedException] was: presentation will plausibly want to react
/// differently (e.g. route back to a client picker) than it would to a
/// generic 4xx, the same way a 401 will eventually prompt a re-login
/// rather than a generic error message.
class ForbiddenException extends AppException {
  const ForbiddenException([super.message = "You don't have access to this client."]);

  @override
  bool get isRetryable => false;
}

/// The response came back, but this app couldn't make sense of it
/// (invalid JSON, or valid JSON in an unexpected shape).
class ParseException extends AppException {
  const ParseException([super.message = 'Received an unexpected response.']);

  @override
  bool get isRetryable => false;
}

/// A defensive fallback — something was thrown that wasn't already one of
/// the variants above. Exists so that code which is only ever supposed to
/// see an [AppException] (see NOTES.md's Part 4) has somewhere to put a
/// genuinely-unanticipated error instead of letting a raw exception type
/// leak through, or silently discarding it.
class UnknownException extends AppException {
  const UnknownException([super.message = 'Something unexpected happened.']);

  @override
  bool get isRetryable => false;
}
