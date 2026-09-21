import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/sync/data/sync_repository_impl.dart';
import 'package:sdui_demo/features/sync/domain/sync_status.dart';
import 'package:sdui_demo/services/api_client.dart';
import 'package:sdui_demo/services/api_dtos.dart';
import 'package:sdui_demo/services/app_exception.dart';

import '../../../support/fake_api_client.dart';

void main() {
  test('with no captured media, reports one step then succeeded, and forwards values as-is', () async {
    final apiClient = FakeApiClient();
    final repository = SyncRepositoryImpl(apiClient: apiClient);

    final values = {'stage_a.name': 'Ada'};

    final statuses = await repository.submitCase(caseId: 'case-1', values: values, mediaFilesByStage: const {}).toList();

    expect(statuses, [
      const SyncUploading(step: 1, totalSteps: 1, label: 'Submitting case'),
      const SyncSucceeded(),
    ]);
    expect(apiClient.submitCaseCallCount, 1);
    expect(apiClient.uploadDocumentCallCount, 0);
    expect(apiClient.lastSubmittedCaseId, 'case-1');
    expect(apiClient.lastSubmittedValues, values);
  });

  test('uploads each captured document against submitCase\'s recordId, one step per file', () async {
    final apiClient = FakeApiClient()..recordIdToReturn = 'record-1';
    final repository = SyncRepositoryImpl(apiClient: apiClient);

    final statuses = await repository
        .submitCase(
          caseId: 'case-1',
          values: const {},
          mediaFilesByStage: const {
            'identification_card': '/tmp/id.jpg',
            'consent_signature': '/tmp/sig.png',
          },
        )
        .toList();

    expect(statuses, [
      const SyncUploading(step: 1, totalSteps: 3, label: 'Submitting case'),
      const SyncUploading(step: 2, totalSteps: 3, label: 'Uploading identification_card'),
      const SyncUploading(step: 3, totalSteps: 3, label: 'Uploading consent_signature'),
      const SyncSucceeded(),
    ]);
    expect(apiClient.uploadDocumentCallCount, 2);
    // identification_card maps onto itself; consent_signature maps onto
    // the confirmed DocumentKind "signature" — see document_kind_mapping.dart.
    expect(apiClient.uploadDocumentCalls, [
      {'recordId': 'record-1', 'kind': 'identification_card', 'filePath': '/tmp/id.jpg'},
      {'recordId': 'record-1', 'kind': 'signature', 'filePath': '/tmp/sig.png'},
    ]);
  });

  test('a captured document with no recordId to upload against fails loudly, not silently dropped', () async {
    final apiClient = FakeApiClient()..recordIdToReturn = null;
    final repository = SyncRepositoryImpl(apiClient: apiClient);

    final statuses = await repository
        .submitCase(
          caseId: 'case-1',
          values: const {},
          mediaFilesByStage: const {'identification_card': '/tmp/id.jpg'},
        )
        .toList();

    expect(statuses.last, isA<SyncFailed>());
    expect(apiClient.uploadDocumentCallCount, 0);
  });

  test('a stage with no confirmed DocumentKind mapping fails loudly, not silently dropped', () async {
    final apiClient = FakeApiClient()..recordIdToReturn = 'record-1';
    final repository = SyncRepositoryImpl(apiClient: apiClient);

    final statuses = await repository
        .submitCase(
          caseId: 'case-1',
          values: const {},
          mediaFilesByStage: const {'some_unmapped_stage': '/tmp/x.jpg'},
        )
        .toList();

    expect(statuses.last, isA<SyncFailed>());
    expect(apiClient.uploadDocumentCallCount, 0);
  });

  test('a failed upload stops the sequence — later files are not attempted', () async {
    final apiClient = FakeApiClient()
      ..recordIdToReturn = 'record-1'
      ..uploadDocumentError = const ServerException(500);
    final repository = SyncRepositoryImpl(apiClient: apiClient);

    final statuses = await repository
        .submitCase(
          caseId: 'case-1',
          values: const {},
          mediaFilesByStage: const {
            'identification_card': '/tmp/id.jpg',
            'consent_signature': '/tmp/sig.png',
          },
        )
        .toList();

    expect(statuses.last, isA<SyncFailed>());
    expect((statuses.last as SyncFailed).exception, isA<ServerException>());
    // Stopped after the first failure — the second file was never attempted.
    expect(apiClient.uploadDocumentCallCount, 1);
  });

  test('a non-AppException throw is wrapped, not left as a raw exception type', () async {
    final apiClient = _FailingApiClient();
    final repository = SyncRepositoryImpl(apiClient: apiClient);

    final statuses = await repository.submitCase(caseId: 'case-1', values: const {}, mediaFilesByStage: const {}).toList();

    expect(statuses.last, isA<SyncFailed>());
    final exception = (statuses.last as SyncFailed).exception;
    expect(exception, isA<UnknownException>());
    expect(exception.message, contains('submit failed'));
  });

  group('AppException propagation (Part 4)', () {
    // Injected via MockApiClient's deterministic test-injection hook (see
    // api_client.dart) — never the random demo-failure path, which a test
    // must never assert against.
    for (final injected in [
      const NetworkException(),
      const AppTimeoutException(),
      const ServerException(503),
      const ClientException(422, 'Bad request'),
      const UnauthorizedException(),
      const ParseException(),
    ]) {
      test('${injected.runtimeType} surfaces unchanged through SyncRepositoryImpl', () async {
        final apiClient = MockApiClient()..injectedFailure = injected;
        final repository = SyncRepositoryImpl(apiClient: apiClient);

        final statuses =
            await repository.submitCase(caseId: 'case-1', values: const {}, mediaFilesByStage: const {}).toList();

        expect(statuses.last, isA<SyncFailed>());
        // Not wrapped, not re-stringified, not converted — the exact same
        // instance the mock threw.
        expect((statuses.last as SyncFailed).exception, same(injected));
      });
    }
  });
}

/// A minimal fake whose submitCase always throws a plain (non-AppException)
/// exception, to exercise the defensive-fallback path — not something
/// MockApiClient itself would ever do post-Part-3, but SyncRepositoryImpl
/// shouldn't assume every ApiClient implementation is equally careful.
class _FailingApiClient extends FakeApiClient {
  @override
  Future<SubmitCaseResultDto> submitCase({
    required String? caseId,
    required Map<String, dynamic> values,
  }) async {
    throw Exception('submit failed');
  }
}
