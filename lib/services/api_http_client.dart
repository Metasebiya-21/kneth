import 'dart:async' as async;
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'app_exception.dart';

/// A generic HTTP execution layer — timeout, retry-with-backoff, and
/// failure-mapping, all in one place — for a future real `ApiClient`
/// implementation to build on. Not itself an `ApiClient`: it knows
/// nothing about manifests, options, or cases, only "run this request,
/// hand back parsed JSON or a categorized [AppException]." This is
/// infrastructure built ahead of a confirmed backend contract, on
/// purpose — see NOTES.md for what's still missing before it's wired to
/// anything real (a base URL, actual endpoint paths, an `ApiClient`
/// implementation that calls it).
///
/// `MockApiClient` — today's only `ApiClient` — does **not** use this. It
/// has no real transport to retry against; see api_client.dart's own
/// notes on why its simulated failures are thrown directly instead.
class ApiHttpClient {
  final String baseUrl;
  final http.Client _client;
  final Duration timeout;
  final int maxAttempts;
  final Duration baseBackoff;
  final Random _random;

  ApiHttpClient({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
    this.maxAttempts = 3,
    this.baseBackoff = const Duration(milliseconds: 500),
    Random? random,
  })  : _client = client ?? http.Client(),
        _random = random ?? Random();

  /// Runs one logical request, retrying retryable failures (see
  /// [AppException.isRetryable]) up to [maxAttempts] times with
  /// exponential backoff and jitter — `base * 2^(attempt-1)` plus a
  /// random 0-30% jitter fraction, the same formula this stack's backend
  /// already uses for its own webhook delivery retries (see
  /// onboarding-platform's NOTES.md), kept consistent here rather than
  /// inventing a different one. A non-retryable failure, or exhausting
  /// every attempt, throws the [AppException] straight through.
  Future<Map<String, dynamic>> request({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
    Map<String, String>? headers,
  }) async {
    final decoded = await _requestRaw(method: method, path: path, body: body, queryParams: queryParams, headers: headers);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const ParseException();
  }

  /// Same as [request], for an endpoint whose successful response body is
  /// a bare JSON array rather than an object — confirmed against the real
  /// backend's `GET /clients`/`GET /clients/{id}/workflows`
  /// (`response_model=list[...]`, not wrapped in `{"items": [...]}` or
  /// similar). [request] can't be reused as-is for these: its own
  /// decode step specifically requires a JSON object and throws
  /// [ParseException] on anything else, a list included.
  Future<List<dynamic>> requestList({
    required String method,
    required String path,
    Map<String, String>? queryParams,
    Map<String, String>? headers,
  }) async {
    final decoded = await _requestRaw(method: method, path: path, body: null, queryParams: queryParams, headers: headers);
    if (decoded is List<dynamic>) return decoded;
    throw const ParseException();
  }

  /// Same retry/status-mapping contract as [request], for a
  /// `multipart/form-data` upload — confirmed against the real backend's
  /// `POST /identity/records/{record_id}/documents/{kind}`, which is the
  /// only multipart endpoint this app talks to. Rebuilds the
  /// `MultipartRequest` fresh on every retry attempt: a `MultipartRequest`
  /// consumes its file stream once sent, so the same instance can't be
  /// reused across attempts the way a JSON body can.
  Future<Map<String, dynamic>> requestMultipart({
    required String method,
    required String path,
    required String fileFieldName,
    required String filePath,
    Map<String, String>? fields,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await _sendMultipart(method, uri, fileFieldName, filePath, fields, headers);
        final decoded = _parse(response);
        if (decoded is Map<String, dynamic>) return decoded;
        throw const ParseException();
      } on AppException catch (e) {
        if (!e.isRetryable || attempt == maxAttempts) rethrow;
        await Future<void>.delayed(_backoff(attempt));
      }
    }
    throw const UnknownException();
  }

  Future<http.Response> _sendMultipart(
    String method,
    Uri uri,
    String fileFieldName,
    String filePath,
    Map<String, String>? fields,
    Map<String, String>? extraHeaders,
  ) async {
    try {
      final request = http.MultipartRequest(method, uri)
        ..headers.addAll({...?extraHeaders})
        ..fields.addAll({...?fields})
        ..files.add(await http.MultipartFile.fromPath(fileFieldName, filePath));
      final streamedResponse = await _client.send(request).timeout(timeout);
      return await http.Response.fromStream(streamedResponse);
    } on async.TimeoutException {
      throw const AppTimeoutException();
    } on http.ClientException {
      throw const NetworkException();
    }
    // A missing local file (http.MultipartFile.fromPath reading a path
    // that doesn't exist) deliberately isn't caught here — that's a local
    // precondition problem, not a network/server outcome this taxonomy
    // models, and callers already have a defensive fallback for a
    // genuinely unanticipated non-AppException throw (see
    // SyncRepositoryImpl's own catch-all).
  }

  Future<dynamic> _requestRaw({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: queryParams);

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await _send(method, uri, body, headers);
        return _parse(response);
      } on AppException catch (e) {
        if (!e.isRetryable || attempt == maxAttempts) rethrow;
        await Future<void>.delayed(_backoff(attempt));
      }
    }
    // Unreachable: the loop above always either returns or throws.
    throw const UnknownException();
  }

  Future<http.Response> _send(
    String method,
    Uri uri,
    Map<String, dynamic>? body,
    Map<String, String>? extraHeaders,
  ) async {
    final headers = {'Content-Type': 'application/json', ...?extraHeaders};
    final encodedBody = body != null ? jsonEncode(body) : null;

    Future<http.Response> sendRequest() {
      switch (method.toUpperCase()) {
        case 'GET':
          return _client.get(uri, headers: headers);
        case 'POST':
          return _client.post(uri, headers: headers, body: encodedBody);
        case 'PUT':
          return _client.put(uri, headers: headers, body: encodedBody);
        case 'DELETE':
          return _client.delete(uri, headers: headers, body: encodedBody);
        default:
          throw ArgumentError('Unsupported HTTP method: $method');
      }
    }

    try {
      // The timeout has to wrap the request *inside* this try/catch, not
      // around the call to _send() from request() — dart:async's own
      // TimeoutException (thrown by .timeout()) needs to be caught here
      // to be mapped onto AppTimeoutException; catching it one level up
      // would be too late, since by then it's already propagating as a
      // raw, unmapped exception. (Caught by a test that actually
      // configured a real timeout and confirmed the mapping — this
      // bug produced a real dart:async TimeoutException escaping
      // unmapped on the first attempt.)
      return await sendRequest().timeout(timeout);
    } on async.TimeoutException {
      throw const AppTimeoutException();
    } on http.ClientException {
      // package:http's own ClientException covers connection-level
      // failures (host unreachable, connection refused, DNS failure).
      throw const NetworkException();
    }
  }

  /// Returns whatever `jsonDecode` produces — a `Map<String, dynamic>` for
  /// most endpoints, a `List<dynamic>` for the handful that return a bare
  /// JSON array (see [requestList]). [request] and [requestList] each
  /// check the shape they actually expect; this only handles transport/
  /// status-code concerns, the same for both.
  dynamic _parse(http.Response response) {
    final status = response.statusCode;
    if (status == 401) throw UnauthorizedException(_extractMessage(response) ?? 'Not authorized. Please sign in again.');
    if (status == 403) throw ForbiddenException(_extractMessage(response) ?? "You don't have access to this client.");
    if (status >= 500) {
      throw ServerException(status, _extractMessage(response));
    }
    if (status >= 400) {
      throw ClientException(status, _extractMessage(response));
    }

    // A 2xx with no body at all (the backend's `POST /auth/logout` is a 204)
    // is a success with nothing to say, not an unparseable response.
    if (response.body.isEmpty) return <String, dynamic>{};

    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw const ParseException();
    }
  }

  String? _extractMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['message'] is String) return decoded['message'] as String;
      // FastAPI's own request-validation 422 (a schema check that fails before
      // any route code runs, e.g. `/auth/password/reset`'s 8-character minimum)
      // is `{"detail": [{"loc": [..., "field"], "msg": "..."}]}`, not this
      // backend's `{"message": ...}` convention. Only `loc`/`msg` are read —
      // never `input`, which echoes the rejected value (a password, here).
      final detail = decoded is Map ? decoded['detail'] : null;
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        final messages = [
          for (final item in detail)
            if (item is Map && item['msg'] is String)
              item['loc'] is List && (item['loc'] as List).isNotEmpty
                  ? '${(item['loc'] as List).last}: ${item['msg']}'
                  : item['msg'] as String,
        ];
        if (messages.isNotEmpty) return messages.join('\n');
      }
    } on FormatException {
      // Body wasn't JSON at all — no message to extract, fall through.
    }
    return null;
  }

  Duration _backoff(int attempt) {
    final exponential = baseBackoff * pow(2, attempt - 1);
    final jitterFraction = _random.nextDouble() * 0.3;
    return exponential + exponential * jitterFraction;
  }
}
