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

  group('fetchFlowManifest', () {
    test('POSTs client_id/workflow_id/case_id and the bearer token, and parses the response', () async {
      final client = clientWith((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/cases/flow-manifest');
        expect(request.headers['Authorization'], 'Bearer token-123');
        expect(
          jsonDecode(request.body),
          {'client_id': 'client-1', 'workflow_id': 'kyc_kyb_collection', 'case_id': null},
        );
        return http.Response(
          jsonEncode({
            'case_id': 'case-1',
            'workflow_version': ['1'],
            'stages': [
              {'stageId': 'a', 'title': 'A', 'screenType': 'GENERIC_FORM', 'fields': []},
            ],
          }),
          200,
        );
      });

      final manifest = await client.fetchFlowManifest(flowId: 'kyc_kyb_collection', clientId: 'client-1');

      expect(manifest.caseId, 'case-1');
      expect(manifest.workflowVersion, ['1']);
      expect(manifest.stagesJson, [
        {'stageId': 'a', 'title': 'A', 'screenType': 'GENERIC_FORM', 'fields': []},
      ]);
    });

    test('sends a non-null caseId through, e.g. resuming a case', () async {
      final client = clientWith((request) async {
        expect(jsonDecode(request.body)['case_id'], 'case-1');
        return http.Response(
          jsonEncode({'case_id': 'case-1', 'workflow_version': <String>['1'], 'stages': <dynamic>[]}),
          200,
        );
      });

      await client.fetchFlowManifest(flowId: 'kyc_kyb_collection', clientId: 'client-1', caseId: 'case-1');
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
    test('fetchFlowManifest', () async {
      var called = false;
      final client = clientWith((request) async {
        called = true;
        return http.Response('{}', 200);
      }, token: null);

      await expectLater(
        client.fetchFlowManifest(flowId: 'f', clientId: 'c'),
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
