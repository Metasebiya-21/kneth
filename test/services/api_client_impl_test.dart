// Contract tests for ApiClientImpl against the CONFIRMED backend shapes
// (see NOTES.md's "Building ApiClientImpl" section for what was actually
// read to confirm them). Mocked at the transport level (package:http's own
// MockClient), never by faking ApiHttpClient — this is what actually
// exercises request-building and response-parsing for real. No live
// backend is required or attempted; see NOTES.md's Part 1a for why.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sdui_demo/services/api_client_impl.dart';
import 'package:sdui_demo/services/api_http_client.dart';
import 'package:sdui_demo/services/app_exception.dart';
import 'package:sdui_demo/services/auth_token_provider.dart';

/// A real temp file on disk — http.MultipartFile.fromPath genuinely reads
/// from the filesystem, so this is a real file the same way
/// media_storage_repository_impl_test.dart uses a real temp directory
/// rather than faking dart:io.
Future<File> _writeTempFile(String contents) async {
  final dir = await Directory.systemTemp.createTemp('api_client_impl_test');
  final file = File('${dir.path}/upload.bin');
  await file.writeAsString(contents);
  return file;
}

void main() {
  ApiClientImpl clientWith(
    Future<http.Response> Function(http.Request) handler, {
    String? token = 'token-123',
    void Function()? onUnauthorized,
  }) {
    final httpClient = ApiHttpClient(
      baseUrl: 'https://example.test',
      client: MockClient(handler),
      baseBackoff: const Duration(milliseconds: 1),
    );
    return ApiClientImpl(
      httpClient: httpClient,
      authTokenProvider: DevAuthTokenProvider(token: token),
      onUnauthorized: onUnauthorized,
    );
  }

  group('fetchFlowManifestStac (POST /cases/flow-manifest/stac)', () {
    test('sends the same body as the legacy route, with the bearer token, and parses case_id/stages', () async {
      final client = clientWith((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/cases/flow-manifest/stac');
        expect(request.headers['Authorization'], 'Bearer token-123');
        expect(jsonDecode(request.body), {'client_id': 'client-1', 'workflow_id': 'wf-1', 'case_id': 'case-9'});
        return http.Response(
          jsonEncode({
            'case_id': 'case-9',
            'workflow_version': ['a', 'b'],
            'stages': [
              {
                'stageId': 'a',
                'title': 'a',
                'screenType': 'GENERIC_FORM',
                'nativeHandler': null,
                'widget': {'type': 'column', 'children': []},
              },
            ],
          }),
          200,
        );
      });

      final manifest = await client.fetchFlowManifestStac(flowId: 'wf-1', clientId: 'client-1', caseId: 'case-9');

      expect(manifest.caseId, 'case-9');
      expect(manifest.workflowVersion, ['a', 'b']);
      expect(manifest.stages.single['widget'], {'type': 'column', 'children': []});
    });

    test('with no case_id it sends case_id: null (create a case) and returns the real case_id the backend issued',
        () async {
      final client = clientWith((request) async {
        expect(jsonDecode(request.body), {'client_id': 'c', 'workflow_id': 'w', 'case_id': null});
        return http.Response(jsonEncode({'case_id': 'issued-1', 'workflow_version': [], 'stages': []}), 200);
      });
      expect((await client.fetchFlowManifestStac(flowId: 'w', clientId: 'c')).caseId, 'issued-1');
    });

    test('goes through ApiHttpClient: a 500 is retried', () async {
      var calls = 0;
      final client = clientWith((request) async {
        calls++;
        if (calls == 1) return http.Response('{}', 500);
        return http.Response(jsonEncode({'case_id': 'c', 'workflow_version': [], 'stages': []}), 200);
      });

      final manifest = await client.fetchFlowManifestStac(flowId: 'w', clientId: 'c');

      expect(calls, 2, reason: "ApiHttpClient's retry/backoff applies — Stac.fromNetwork would have bypassed it");
      expect(manifest.caseId, 'c');
    });

    test('with no token: UnauthorizedException locally (no HTTP call), and onUnauthorized fires once', () async {
      var called = false;
      var unauthorized = 0;
      final client = clientWith(
        (request) async {
          called = true;
          return http.Response('{}', 200);
        },
        token: null,
        onUnauthorized: () => unauthorized++,
      );

      await expectLater(client.fetchFlowManifestStac(flowId: 'w', clientId: 'c'), throwsA(isA<UnauthorizedException>()));
      expect(called, isFalse);
      expect(unauthorized, 1);
    });

    test('a real 401 fires onUnauthorized exactly once', () async {
      var unauthorized = 0;
      final client = clientWith((request) async => http.Response(jsonEncode({'message': 'expired'}), 401),
          onUnauthorized: () => unauthorized++);

      await expectLater(client.fetchFlowManifestStac(flowId: 'w', clientId: 'c'), throwsA(isA<UnauthorizedException>()));
      expect(unauthorized, 1);
    });
  });

  group('Unicode transport (Amharic, emoji, NFD) — STAC_MIGRATION_SCOPING.md section 14', () {
    const values = {
      'personal.full_name': 'አበበ በቀለ',
      'personal.note': 'ሰላም 😀 e\u0301cole',
    };

    test('the request body goes out as UTF-8 bytes, character for character', () async {
      late List<int> sentBytes;
      late String contentType;
      final client = clientWith((request) async {
        sentBytes = request.bodyBytes;
        contentType = request.headers['content-type'] ?? '';
        return http.Response(jsonEncode({'case_id': 'c', 'status': 'ok', 'record_id': null}), 200);
      });

      await client.submitCase(caseId: 'case-1', values: values);

      final decoded = jsonDecode(utf8.decode(sentBytes)) as Map<String, dynamic>;
      expect(decoded['values'], {
        'personal': {'full_name': 'አበበ በቀለ', 'note': 'ሰላም 😀 e\u0301cole'},
      });
      expect(utf8.decode(sentBytes), contains('አበበ በቀለ'), reason: 'raw UTF-8 on the wire, not \\u1220 escapes');
      // No charset is declared (plain application/json; JSON is UTF-8 by specification) and none
      // other than UTF-8 is used. The live test proves the real server accepts exactly this.
      expect(contentType.toLowerCase(), isNot(contains('latin')));
      expect(contentType.toLowerCase(), startsWith('application/json'));
    });

    test('a charset-less application/json response (what FastAPI sends) is decoded as UTF-8, not Latin-1', () async {
      final client = clientWith((request) async {
        final body = utf8.encode(jsonEncode({
          'case_id': 'አበበ', // not a real id; proves the decode path
          'workflow_version': ['ሰላም'],
          'stages': <dynamic>[],
        }));
        return http.Response.bytes(body, 200, headers: {'content-type': 'application/json'});
      });

      final manifest = await client.fetchFlowManifestStac(flowId: 'w', clientId: 'c');

      expect(manifest.caseId, 'አበበ');
      expect(manifest.workflowVersion, ['ሰላም']);
    });

    test('an Amharic error message from the server reaches the exception intact', () async {
      final client = clientWith((request) async {
        return http.Response.bytes(utf8.encode(jsonEncode({'message': 'ስህተት ተፈጥሯል'})), 422,
            headers: {'content-type': 'application/json'});
      });

      await expectLater(
        client.fetchClients(),
        throwsA(isA<ClientException>().having((e) => e.message, 'message', 'ስህተት ተፈጥሯል')),
      );
    });
  });

  group('submitCase', () {
    test('POSTs to /cases/{case_id}/submit with values nested by stage and empty mediaRefs, parses recordId back',
        () async {
      final client = clientWith((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/cases/case-1/submit');
        expect(request.headers['Authorization'], 'Bearer token-123');
        expect(jsonDecode(request.body), {
          'values': {
            'stage_a': {'name': 'Ada'},
          },
          'mediaRefs': <String, String>{},
        });
        return http.Response(
          jsonEncode({'case_id': 'case-1', 'status': 'pending', 'record_id': 'record-1'}),
          200,
        );
      });

      final result = await client.submitCase(caseId: 'case-1', values: {'stage_a.name': 'Ada'});

      expect(result.caseId, 'case-1');
      expect(result.status, 'pending');
      expect(result.recordId, 'record-1');
    });

    test('parses business_record_id back alongside record_id (combined KYC+KYB), and null when absent', () async {
      final client = clientWith((request) async {
        return http.Response(
          jsonEncode({
            'case_id': 'case-1',
            'status': 'pending',
            'record_id': 'record-1',
            'business_record_id': 'business-record-1',
          }),
          200,
        );
      });
      final combined = await client.submitCase(caseId: 'case-1', values: const {});
      expect(combined.recordId, 'record-1');
      expect(combined.businessRecordId, 'business-record-1');

      final businessOnly = await clientWith((request) async {
        return http.Response(
          jsonEncode({'case_id': 'case-1', 'status': 'pending', 'record_id': null, 'business_record_id': 'b-1'}),
          200,
        );
      }).submitCase(caseId: 'case-1', values: const {});
      expect(businessOnly.recordId, isNull);
      expect(businessOnly.businessRecordId, 'b-1');

      final individualOnly = await clientWith((request) async {
        return http.Response(jsonEncode({'case_id': 'case-1', 'status': 'pending', 'record_id': 'r-1'}), 200);
      }).submitCase(caseId: 'case-1', values: const {});
      expect(individualOnly.businessRecordId, isNull);
    });

    test('a null record_id (TENANT-only submission) parses as null, not a crash', () async {
      final client = clientWith((request) async {
        return http.Response(jsonEncode({'case_id': 'case-1', 'status': 'pending'}), 200);
      });

      final result = await client.submitCase(caseId: 'case-1', values: const {});

      expect(result.recordId, isNull);
    });

    test('a null caseId fails locally, without ever making an HTTP call', () async {
      var called = false;
      final client = clientWith((request) async {
        called = true;
        return http.Response('{}', 200);
      });

      await expectLater(
        client.submitCase(caseId: null, values: const {}),
        throwsA(isA<StateError>()),
      );
      expect(called, isFalse);
    });
  });

  group('uploadDocument', () {
    test('POSTs multipart/form-data to /identity/records/{record_id}/documents/{kind}', () async {
      final client = clientWith((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/identity/records/record-1/documents/identification_card');
        expect(request.headers['Authorization'], 'Bearer token-123');
        // MockClient always reconstructs a plain Request from the raw
        // byte stream (see package:http's own mock_client.dart) — the
        // original MultipartRequest object never reaches this handler,
        // only its wire bytes do. So the multipart shape is confirmed
        // from what's actually observable at this layer: the
        // content-type's boundary marker, and that marker delimiting a
        // 'name="file"' part whose body is the uploaded file's own bytes.
        expect(request.headers['content-type'], contains('multipart/form-data; boundary='));
        expect(request.body, contains('name="file"'));
        expect(request.body, contains('fake image bytes'));
        return http.Response(
          jsonEncode({'id': 'doc-1', 'kind': 'identification_card', 'file_reference': 'ref-1'}),
          201,
        );
      });

      final tmpFile = await _writeTempFile('fake image bytes');
      final result = await client.uploadDocument(
        recordId: 'record-1',
        kind: 'identification_card',
        filePath: tmpFile.path,
      );

      expect(result.id, 'doc-1');
      expect(result.kind, 'identification_card');
      expect(result.fileReference, 'ref-1');
    });

    test('a business kind rejected for an individual record maps to ClientException(422)', () async {
      final client = clientWith((request) async {
        return http.Response(jsonEncode({'message': 'business kind rejected'}), 422);
      });
      final tmpFile = await _writeTempFile('x');

      await expectLater(
        client.uploadDocument(recordId: 'record-1', kind: 'trade_license', filePath: tmpFile.path),
        throwsA(isA<ClientException>().having((e) => e.statusCode, 'statusCode', 422)),
      );
    });
  });

  group('uploadBusinessDocument', () {
    test('POSTs multipart to /identity/business-records/{id}/documents/{kind}, no uploaded_by, parses the response',
        () async {
      final client = clientWith((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/identity/business-records/business-1/documents/trade_license');
        expect(request.headers['Authorization'], 'Bearer token-123');
        expect(request.headers['content-type'], contains('multipart/form-data; boundary='));
        expect(request.body, contains('name="file"'));
        expect(request.body, contains('fake license bytes'));
        expect(request.body, isNot(contains('uploaded_by')));
        return http.Response(
          jsonEncode({'id': 'doc-2', 'kind': 'trade_license', 'file_reference': 'ref-2'}),
          201,
        );
      });

      final tmpFile = await _writeTempFile('fake license bytes');
      final result = await client.uploadBusinessDocument(
        businessRecordId: 'business-1',
        kind: 'trade_license',
        filePath: tmpFile.path,
      );

      expect(result.id, 'doc-2');
      expect(result.kind, 'trade_license');
      expect(result.fileReference, 'ref-2');
    });

    test('an individual kind rejected by the business route maps to ClientException(422)', () async {
      final client = clientWith((request) async {
        return http.Response(jsonEncode({'message': 'individual kind rejected'}), 422);
      });
      final tmpFile = await _writeTempFile('x');

      await expectLater(
        client.uploadBusinessDocument(businessRecordId: 'b-1', kind: 'identification_card', filePath: tmpFile.path),
        throwsA(isA<ClientException>().having((e) => e.statusCode, 'statusCode', 422)),
      );
    });

    test('an unknown business record maps to ClientException(404)', () async {
      final client = clientWith((request) async {
        return http.Response(jsonEncode({'message': 'business record not found'}), 404);
      });
      final tmpFile = await _writeTempFile('x');

      await expectLater(
        client.uploadBusinessDocument(businessRecordId: 'nope', kind: 'trade_license', filePath: tmpFile.path),
        throwsA(isA<ClientException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });

  group('liveness attempts (counted by the backend)', () {
    Map<String, dynamic> statusJson({
      String caseStatus = 'in_progress',
      int used = 1,
      int completed = 0,
      int remaining = 2,
      bool pass = false,
      String? open = 'attempt-1',
      Map<String, dynamic>? override,
    }) =>
        {
          'case_status': caseStatus,
          'attempts_used': used,
          'attempts_completed': completed,
          'max_attempts': 3,
          'attempts_remaining': remaining,
          'attested_pass_recorded': pass,
          'open_attempt_id': open,
          'override': override,
        };

    test('begin POSTs to /cases/{id}/liveness-attempts and parses the attempt and the backend\'s count', () async {
      final client = clientWith((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/cases/case-1/liveness-attempts');
        expect(request.headers['Authorization'], 'Bearer token-123');
        return http.Response(jsonEncode({...statusJson(), 'attempt_id': 'attempt-1', 'attempt_number': 1}), 201);
      });

      final begun = await client.beginLivenessAttempt('case-1');

      expect(begun.attemptId, 'attempt-1');
      expect(begun.attemptNumber, 1);
      expect(begun.status.attemptsUsed, 1);
      expect(begun.status.attemptsRemaining, 2);
      expect(begun.status.maxAttempts, 3);
      expect(begun.status.openAttemptId, 'attempt-1');
    });

    test('a fourth attempt is the backend\'s 409, surfaced as ClientException(409) with its message', () async {
      final client = clientWith((request) async {
        return http.Response(
          jsonEncode({
            'message': 'the liveness check has used all 3 attempts for this case; it needs manual review by a supervisor',
            'details': {'attempts_used': 3, 'max_attempts': 3, 'case_status': 'needs_manual_review'},
          }),
          409,
        );
      });
      await expectLater(
        client.beginLivenessAttempt('case-1'),
        throwsA(isA<ClientException>()
            .having((e) => e.statusCode, 'status', 409)
            .having((e) => e.message, 'message', contains('manual review'))),
      );
    });

    test('the outcome is sent as an attested claim (every body key attested_*) to the attempt\'s own route', () async {
      final client = clientWith((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/cases/case-1/liveness-attempts/attempt-3/outcome');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body, {
          'attested_liveness_verdict': false,
          'attested_anti_spoofing_flags': {'motionCorrelationCheckFailed': true},
          'attested_session_id': 'session-3',
        });
        for (final key in body.keys) {
          expect(key, startsWith('attested_'));
        }
        return http.Response(
          jsonEncode(statusJson(caseStatus: 'needs_manual_review', used: 3, completed: 3, remaining: 0, open: null)),
          200,
        );
      });

      final status = await client.recordLivenessAttemptOutcome(
        caseId: 'case-1',
        attemptId: 'attempt-3',
        attestedLivenessVerdict: false,
        attestedAntiSpoofingFlags: const {'motionCorrelationCheckFailed': true},
        attestedSessionId: 'session-3',
      );

      expect(status.caseStatus, 'needs_manual_review');
      expect(status.attemptsRemaining, 0);
      expect(status.attestedPassRecorded, isFalse);
      expect(status.openAttemptId, isNull);
    });

    test('status GETs /cases/{id}/liveness-status and parses a supervisor\'s override', () async {
      final client = clientWith((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/cases/case-1/liveness-status');
        return http.Response(
          jsonEncode(statusJson(
            used: 3,
            completed: 3,
            remaining: 0,
            open: null,
            override: {'method': 'physical_document_review', 'decision': 'accepted', 'decided_at': '2026-09-24T10:00:00+00:00'},
          )),
          200,
        );
      });

      final status = await client.fetchLivenessStatus('case-1');

      expect(status.override?.method, 'physical_document_review');
      expect(status.override?.decision, 'accepted');
    });

    test('all three fail locally, without an HTTP call, when there is no token', () async {
      var called = false;
      final client = clientWith((request) async {
        called = true;
        return http.Response('{}', 200);
      }, token: null);
      await expectLater(client.beginLivenessAttempt('c'), throwsA(isA<UnauthorizedException>()));
      await expectLater(client.fetchLivenessStatus('c'), throwsA(isA<UnauthorizedException>()));
      await expectLater(
        client.recordLivenessAttemptOutcome(
            caseId: 'c', attemptId: 'a', attestedLivenessVerdict: true, attestedAntiSpoofingFlags: const {}),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(called, isFalse);
    });
  });

  group('submitAttestedLiveness', () {
    const flags = {
      'screenGlareDetected': false,
      'lackOfFacialContoursDetected': false,
      'motionCorrelationCheckFailed': false,
      'screenFlashSpoofDetected': false,
      'depthSpoofDetected': false,
    };

    test('POSTs the device claim, every payload key named as attested, to the device_liveness provider', () async {
      final client = clientWith((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/identity/records/record-1/verifications/device_liveness');
        expect(request.headers['Authorization'], 'Bearer token-123');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['field_checked'], 'liveness');
        final payload = body['payload'] as Map<String, dynamic>;
        expect(payload, {
          'attested_liveness_verdict': true,
          'attested_anti_spoofing_flags': flags,
          'attested_session_id': 'session-1',
          'attested_detector': 'smart_liveliness_detection 0.3.9',
        });
        for (final key in payload.keys) {
          expect(key, startsWith('attested_'));
        }
        return http.Response(
          jsonEncode({'id': 'v-1', 'result': 'attested_passed', 'provider': 'device-attested-liveness'}),
          201,
        );
      });

      final result = await client.submitAttestedLiveness(
        recordId: 'record-1',
        attestedLivenessVerdict: true,
        attestedAntiSpoofingFlags: flags,
        attestedSessionId: 'session-1',
        attestedDetector: 'smart_liveliness_detection 0.3.9',
      );

      expect(result.id, 'v-1');
      expect(result.result, 'attested_passed');
      expect(result.provider, 'device-attested-liveness');
    });

    test('a failed verdict is sent as such and comes back attested_failed', () async {
      final client = clientWith((request) async {
        expect(((jsonDecode(request.body) as Map)['payload'] as Map)['attested_liveness_verdict'], false);
        return http.Response(
          jsonEncode({'id': 'v-2', 'result': 'attested_failed', 'provider': 'device-attested-liveness'}),
          201,
        );
      });
      final result = await client.submitAttestedLiveness(
        recordId: 'record-1',
        attestedLivenessVerdict: false,
        attestedAntiSpoofingFlags: flags,
      );
      expect(result.result, 'attested_failed');
    });

    test('optional session id and detector are left out when null', () async {
      final client = clientWith((request) async {
        final payload = (jsonDecode(request.body) as Map)['payload'] as Map;
        expect(payload.keys, unorderedEquals(['attested_liveness_verdict', 'attested_anti_spoofing_flags']));
        return http.Response(jsonEncode({'id': 'v', 'result': 'attested_passed', 'provider': 'p'}), 201);
      });
      await client.submitAttestedLiveness(
          recordId: 'r', attestedLivenessVerdict: true, attestedAntiSpoofingFlags: const {});
    });

    test('a response that is not an attested_* result is refused (a different provider answered)', () async {
      final client = clientWith((request) async {
        return http.Response(jsonEncode({'id': 'v', 'result': 'passed', 'provider': 'mock-liveness'}), 201);
      });
      await expectLater(
        client.submitAttestedLiveness(recordId: 'r', attestedLivenessVerdict: true, attestedAntiSpoofingFlags: flags),
        throwsA(isA<ParseException>()),
      );
    });

    test('an unknown provider maps to ClientException(404); a malformed claim to 422', () async {
      for (final status in [404, 422]) {
        final client = clientWith((request) async => http.Response(jsonEncode({'message': 'no'}), status));
        await expectLater(
          client.submitAttestedLiveness(recordId: 'r', attestedLivenessVerdict: true, attestedAntiSpoofingFlags: flags),
          throwsA(isA<ClientException>().having((e) => e.statusCode, 'status', status)),
        );
      }
    });

    test('with no token it fails locally, without an HTTP call', () async {
      var called = false;
      final client = clientWith((request) async {
        called = true;
        return http.Response('{}', 200);
      }, token: null);
      await expectLater(
        client.submitAttestedLiveness(recordId: 'r', attestedLivenessVerdict: true, attestedAntiSpoofingFlags: flags),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(called, isFalse);
    });
  });

  group('fetchOptions', () {
    test(
      'GETs /config/clients/{client_id}/workflows/{workflow_id}/fields/{field_key}/options '
      'with dependency values as query params',
      () async {
        final client = clientWith((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/config/clients/client-1/workflows/workflow-1/fields/district/options');
          expect(request.url.queryParameters, {'region': 'Addis Ababa'});
          expect(request.headers['Authorization'], 'Bearer token-123');
          return http.Response(
            jsonEncode([
              {'label': 'Bole', 'value': 'bole'},
              {'label': 'Yeka', 'value': 'yeka'},
            ]),
            200,
          );
        });

        final options = await client.fetchOptions(
          clientId: 'client-1',
          workflowId: 'workflow-1',
          fieldKey: 'district',
          dependencyValues: {'region': 'Addis Ababa'},
        );

        expect(options.map((o) => o.label), ['Bole', 'Yeka']);
        expect(options.map((o) => o.value), ['bole', 'yeka']);
      },
    );
  });

  group('fetchClients / fetchWorkflows (bare JSON array responses)', () {
    test('fetchClients GETs /clients and parses each entry', () async {
      final client = clientWith((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/clients');
        expect(request.headers['Authorization'], 'Bearer token-123');
        return http.Response(
          jsonEncode([
            {'id': 'client-1', 'name': 'Awash Bank'},
            {'id': 'client-2', 'name': 'Dashen Bank'},
          ]),
          200,
        );
      });

      final clients = await client.fetchClients();

      expect(clients.map((c) => c.id), ['client-1', 'client-2']);
      expect(clients.map((c) => c.name), ['Awash Bank', 'Dashen Bank']);
    });

    test('fetchWorkflows GETs /clients/{id}/workflows and parses each entry', () async {
      final client = clientWith((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/clients/client-1/workflows');
        return http.Response(
          jsonEncode([
            {'id': 'kyc_kyb_collection', 'name': 'KYC/KYB collection'},
          ]),
          200,
        );
      });

      final workflows = await client.fetchWorkflows('client-1');

      expect(workflows.single.id, 'kyc_kyb_collection');
      expect(workflows.single.name, 'KYC/KYB collection');
    });
  });

  group('missing token — UnauthorizedException raised locally, no HTTP call made', () {
    test('fetchFlowManifestStac', () async {
      var called = false;
      final client = clientWith((request) async {
        called = true;
        return http.Response('{}', 200);
      }, token: null);

      await expectLater(
        client.fetchFlowManifestStac(flowId: 'f', clientId: 'c'),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(called, isFalse);
    });

    test('submitCase', () async {
      var called = false;
      final client = clientWith((request) async {
        called = true;
        return http.Response('{}', 200);
      }, token: null);

      await expectLater(
        client.submitCase(caseId: 'case-1', values: const {}),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(called, isFalse);
    });

    test('uploadDocument', () async {
      var called = false;
      final client = clientWith((request) async {
        called = true;
        return http.Response('{}', 200);
      }, token: null);
      final tmpFile = await _writeTempFile('x');

      await expectLater(
        client.uploadDocument(recordId: 'record-1', kind: 'identification_card', filePath: tmpFile.path),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(called, isFalse);
    });

    test('uploadBusinessDocument', () async {
      var called = false;
      final client = clientWith((request) async {
        called = true;
        return http.Response('{}', 200);
      }, token: null);
      final tmpFile = await _writeTempFile('x');

      await expectLater(
        client.uploadBusinessDocument(businessRecordId: 'b-1', kind: 'trade_license', filePath: tmpFile.path),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(called, isFalse);
    });

    test('fetchOptions', () async {
      var called = false;
      final client = clientWith((request) async {
        called = true;
        return http.Response('{}', 200);
      }, token: null);

      await expectLater(
        client.fetchOptions(
          clientId: 'client-1',
          workflowId: 'workflow-1',
          fieldKey: 'district',
          dependencyValues: const {'region': 'Addis Ababa'},
        ),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(called, isFalse);
    });

    test('fetchClients', () async {
      var called = false;
      final client = clientWith((request) async {
        called = true;
        return http.Response('{}', 200);
      }, token: null);

      await expectLater(client.fetchClients(), throwsA(isA<UnauthorizedException>()));
      expect(called, isFalse);
    });

    test('fetchWorkflows', () async {
      var called = false;
      final client = clientWith((request) async {
        called = true;
        return http.Response('{}', 200);
      }, token: null);

      await expectLater(client.fetchWorkflows('client-1'), throwsA(isA<UnauthorizedException>()));
      expect(called, isFalse);
    });
  });

  group('status-code mapping (documented in http_errors.py\'s _STATUS_BY_EXC)', () {
    Future<void> expectStatus(int status, Object matcher) async {
      final client = clientWith((request) async => http.Response(jsonEncode({'message': 'x'}), status));
      await expectLater(client.fetchClients(), throwsA(matcher));
    }

    test('403 -> ForbiddenException (authenticated, not assigned to this client)', () async {
      await expectStatus(403, isA<ForbiddenException>());
    });

    test('404 -> ClientException(404)', () async {
      final client = clientWith((request) async => http.Response(jsonEncode({'message': 'x'}), 404));
      try {
        await client.fetchClients();
        fail('expected a ClientException');
      } on ClientException catch (e) {
        expect(e.statusCode, 404);
      }
    });

    test('422 -> ClientException(422), including the missing-Authorization-header case documented in Phase 11',
        () async {
      final client = clientWith((request) async => http.Response(jsonEncode({'message': 'x'}), 422));
      try {
        await client.fetchClients();
        fail('expected a ClientException');
      } on ClientException catch (e) {
        expect(e.statusCode, 422);
      }
    });
  });

  // NOTES.md's Phase 1 documents a real bug: the first version of
  // _authenticated fired onUnauthorized from both _authHeaders (the local
  // no-token check) AND its own catch clause, since _authHeaders' throw
  // happens inside the closure _authenticated wraps — double-firing for the
  // same failure. These are the regression tests for that fix, plus the
  // case that fix's own description didn't yet have a test for: a REAL 401
  // response from the server (a token that looked valid when the request
  // was built, but was rejected — e.g. it expired mid-flight, or was
  // revoked), as distinct from the local "no token at all" check above.
  group('onUnauthorized callback (NOTES.md\'s Phase 1 double-fire bug)', () {
    test('a real 401 from the server (token present, sent, rejected) fires onUnauthorized exactly once', () async {
      var callCount = 0;
      final client = clientWith(
        (request) async {
          // The token really was attached to the request — this is not the
          // local "no token" path, it's the server rejecting one that was
          // present, e.g. because it expired between request-build time and
          // the response arriving (see NOTES.md's Phase 1 — the exact race
          // AuthTokenProvider.currentToken() being synchronous can't rule
          // out on its own).
          expect(request.headers['Authorization'], 'Bearer token-123');
          return http.Response(jsonEncode({'message': 'token expired'}), 401);
        },
        onUnauthorized: () => callCount++,
      );

      await expectLater(client.fetchClients(), throwsA(isA<UnauthorizedException>()));

      expect(callCount, 1);
    });

    test('a locally-detected missing token fires onUnauthorized exactly once, with no HTTP call made', () async {
      var callCount = 0;
      var handlerCalled = false;
      final client = clientWith(
        (request) async {
          handlerCalled = true;
          return http.Response('{}', 200);
        },
        token: null,
        onUnauthorized: () => callCount++,
      );

      await expectLater(client.fetchClients(), throwsA(isA<UnauthorizedException>()));

      expect(handlerCalled, isFalse);
      expect(callCount, 1);
    });

    test('a non-401 failure does not fire onUnauthorized at all', () async {
      var callCount = 0;
      final client = clientWith(
        (request) async => http.Response(jsonEncode({'message': 'x'}), 500),
        onUnauthorized: () => callCount++,
      );

      await expectLater(client.fetchClients(), throwsA(isA<ServerException>()));

      expect(callCount, 0);
    });
  });
}
