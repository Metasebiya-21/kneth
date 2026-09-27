import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// DEBUG BUILDS ONLY. Nothing in `lib/debug/` may be reachable from a
/// release build: `main.dart` constructs it only behind a `kDebugMode`
/// check, which is a compile-time constant, so the release compiler drops
/// these classes entirely (see NOTES.md, "Auth through the backend's /auth
/// proxy" -> "Release-build check" for the binary-level check and its status).
///
/// One captured request/response. Every field is stored ALREADY REDACTED
/// (see [redactJsonText]); nothing here ever held a password, OTP or token.
class NetworkLogEntry {
  final int id;
  final DateTime startedAt;
  final String method;
  final String url;
  final Map<String, String> requestHeaders;
  final String? requestBody;
  int? statusCode;
  Map<String, String> responseHeaders = const {};
  String? responseBody;
  Duration? duration;
  String? error;

  NetworkLogEntry({
    required this.id,
    required this.startedAt,
    required this.method,
    required this.url,
    required this.requestHeaders,
    required this.requestBody,
  });

  bool get isPending => statusCode == null && error == null;
}

/// The in-memory list the viewer shows, newest first, capped at
/// [maxEntries]. Never written to disk.
class NetworkLog extends ChangeNotifier {
  final int maxEntries;
  final List<NetworkLogEntry> _entries = [];
  int _nextId = 1;

  NetworkLog({this.maxEntries = 200});

  List<NetworkLogEntry> get entries => List.unmodifiable(_entries);

  NetworkLogEntry start({
    required String method,
    required Uri url,
    required Map<String, String> headers,
    required String? body,
  }) {
    final entry = NetworkLogEntry(
      id: _nextId++,
      startedAt: DateTime.now(),
      method: method,
      url: redactUrl(url),
      requestHeaders: redactHeaders(headers),
      requestBody: body,
    );
    _entries.insert(0, entry);
    if (_entries.length > maxEntries) _entries.removeLast();
    notifyListeners();
    return entry;
  }

  void finished(NetworkLogEntry entry) => notifyListeners();

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}

/// The app-wide log the debug tools share. Referenced only from
/// `kDebugMode`-guarded code, so it doesn't exist in a release build.
final debugNetworkLog = NetworkLog();

/// Wraps the real [http.Client] and records every request through it into
/// [log]. Sits under `ApiHttpClient` (and so under every auth call and,
/// once it's switched on, `ApiClientImpl`), so it sees exactly what goes on
/// the wire — after retries are split into separate attempts, each its own
/// entry.
class NetworkLogClient extends http.BaseClient {
  final http.Client _inner;
  final NetworkLog log;

  NetworkLogClient(this._inner, this.log);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final entry = log.start(
      method: request.method,
      url: request.url,
      headers: request.headers,
      body: _describeRequestBody(request),
    );
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _inner.send(request);
      // The body has to be read here to be recorded, so hand the caller a
      // fresh stream over the same bytes.
      final bytes = await response.stream.toBytes();
      entry
        ..statusCode = response.statusCode
        ..responseHeaders = redactHeaders(response.headers)
        ..responseBody = describeBody(bytes, response.headers['content-type'])
        ..duration = stopwatch.elapsed;
      log.finished(entry);
      return http.StreamedResponse(
        http.ByteStream.fromBytes(bytes),
        response.statusCode,
        contentLength: bytes.length,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (e) {
      entry
        ..error = e.runtimeType.toString()
        ..duration = stopwatch.elapsed;
      log.finished(entry);
      rethrow;
    }
  }

  @override
  void close() => _inner.close();

  String? _describeRequestBody(http.BaseRequest request) {
    if (request is http.MultipartRequest) {
      return '[multipart: fields ${request.fields.keys.toList()}, '
          'files ${request.files.map((f) => f.field).toList()} — not captured]';
    }
    if (request is http.Request) {
      return describeBody(request.bodyBytes, request.headers['content-type']);
    }
    return '[streamed body — not captured]';
  }
}

// ---------------------------------------------------------------------------
// Redaction — decided, not defaulted (NOTES.md, "Debug network log"):
// everything is redacted BEFORE it's stored, even in a debug build. This app
// sends real passwords, OTPs and bearer tokens, and the backend's own 422
// echoes a rejected password back in `detail[].input` (seen live). A log
// holding those in plain text would put them one screenshot or screen-share
// away from leaking. The cost is that a secret's actual value can't be read
// off the log — never needed to debug a request's shape or status.
// ---------------------------------------------------------------------------

const redactedValue = '«redacted»';
const maxCapturedBodyChars = 8000;

/// Keys whose values are never kept: anything password-, token-, OTP- or
/// secret-shaped, auth/cookie headers, and pydantic's `input` (the rejected
/// value, echoed).
final _sensitiveKey = RegExp(
  r'pass|token|otp|secret|authorization|cookie|api[-_]?key|^input$|^code$',
  caseSensitive: false,
);

bool isSensitiveKey(String key) => _sensitiveKey.hasMatch(key);

Map<String, String> redactHeaders(Map<String, String> headers) => {
      for (final e in headers.entries) e.key: isSensitiveKey(e.key) ? redactedValue : e.value,
    };

String redactUrl(Uri url) {
  if (url.queryParameters.isEmpty) return url.toString();
  return url.replace(queryParameters: {
    for (final e in url.queryParameters.entries) e.key: isSensitiveKey(e.key) ? redactedValue : e.value,
  }).toString();
}

/// Renders a body for the log. JSON and form bodies are kept with sensitive
/// values redacted; anything else is summarized, not stored — it can't be
/// redacted by key, so it can't be trusted not to hold a secret.
String? describeBody(List<int> bytes, String? contentType) {
  if (bytes.isEmpty) return null;
  final type = (contentType ?? '').toLowerCase();
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    return '[${bytes.length} bytes, binary — not captured]';
  }
  if (type.contains('x-www-form-urlencoded')) return _truncate(redactFormText(text));
  final redacted = redactJsonText(text);
  if (redacted != null) return _truncate(redacted);
  return '[${bytes.length} bytes, $type — not captured]';
}

/// [text] as pretty JSON with every sensitive key's value replaced, or null
/// if it isn't JSON.
String? redactJsonText(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return null;
  }
  return const JsonEncoder.withIndent('  ').convert(_redactJson(decoded));
}

Object? _redactJson(Object? value) {
  if (value is Map) {
    return {
      for (final e in value.entries)
        e.key.toString(): isSensitiveKey(e.key.toString()) ? redactedValue : _redactJson(e.value),
    };
  }
  if (value is List) return [for (final item in value) _redactJson(item)];
  return value;
}

String redactFormText(String text) {
  final Map<String, String> fields;
  try {
    fields = Uri.splitQueryString(text);
  } on Object {
    return '[form body — not captured]';
  }
  return fields.entries.map((e) => '${e.key}=${isSensitiveKey(e.key) ? redactedValue : e.value}').join('&');
}

String _truncate(String text) =>
    text.length <= maxCapturedBodyChars ? text : '${text.substring(0, maxCapturedBodyChars)}\n… [truncated]';
