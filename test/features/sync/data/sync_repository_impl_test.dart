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

  group('individual and business documents (combined KYC+KYB)', () {
    test('a combined submission uploads the individual document AND the business document to their own endpoints',
        () async {
      final apiClient = FakeApiClient()
        ..recordIdToReturn = 'record-1'
        ..businessRecordIdToReturn = 'business-1';
      final repository = SyncRepositoryImpl(apiClient: apiClient);

      final statuses = await repository
          .submitCase(
            caseId: 'case-1',
            values: const {},
            mediaFilesByStage: const {
              'identification_card': '/tmp/id.jpg',
              'trade_license': '/tmp/license.jpg',
            },
          )
          .toList();

      expect(statuses, [
        const SyncUploading(step: 1, totalSteps: 3, label: 'Submitting case'),
        const SyncUploading(step: 2, totalSteps: 3, label: 'Uploading identification_card'),
        const SyncUploading(step: 3, totalSteps: 3, label: 'Uploading trade_license'),
        const SyncSucceeded(),
      ]);
      expect(apiClient.uploadDocumentCalls, [
        {'recordId': 'record-1', 'kind': 'identification_card', 'filePath': '/tmp/id.jpg'},
      ]);
      expect(apiClient.uploadBusinessDocumentCalls, [
        {'businessRecordId': 'business-1', 'kind': 'trade_license', 'filePath': '/tmp/license.jpg'},
      ]);
    });

    test('business-only: uploads the business document and never calls uploadDocument with a null record id',
        () async {
      final apiClient = FakeApiClient()
        ..recordIdToReturn = null
        ..businessRecordIdToReturn = 'business-1';
      final repository = SyncRepositoryImpl(apiClient: apiClient);

      final statuses = await repository
          .submitCase(
            caseId: 'case-1',
            values: const {},
            mediaFilesByStage: const {'trade_license': '/tmp/license.jpg'},
          )
          .toList();

      expect(statuses.last, const SyncSucceeded());
      expect(apiClient.uploadDocumentCallCount, 0);
      expect(apiClient.uploadBusinessDocumentCalls, [
        {'businessRecordId': 'business-1', 'kind': 'trade_license', 'filePath': '/tmp/license.jpg'},
      ]);
    });

    test('a business document with no businessRecordId fails loudly, before anything is uploaded', () async {
      final apiClient = FakeApiClient()
        ..recordIdToReturn = 'record-1'
        ..businessRecordIdToReturn = null;
      final repository = SyncRepositoryImpl(apiClient: apiClient);

      final statuses = await repository
          .submitCase(
            caseId: 'case-1',
            values: const {},
            // The individual file comes first, and still must not go out.
            mediaFilesByStage: const {
              'identification_card': '/tmp/id.jpg',
              'trade_license': '/tmp/license.jpg',
            },
          )
          .toList();

      expect(statuses.last, isA<SyncFailed>());
      expect((statuses.last as SyncFailed).exception.message, contains('businessRecordId'));
      expect(apiClient.uploadDocumentCallCount, 0);
      expect(apiClient.uploadBusinessDocumentCallCount, 0);
    });

    test('an individual document with no recordId (business-only case) fails loudly, not routed to the business record',
        () async {
      final apiClient = FakeApiClient()
        ..recordIdToReturn = null
        ..businessRecordIdToReturn = 'business-1';
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
      expect(apiClient.uploadBusinessDocumentCallCount, 0);
    });

    test('a failed business upload stops the sequence — later files (either kind) are not attempted', () async {
      final apiClient = FakeApiClient()
        ..recordIdToReturn = 'record-1'
        ..businessRecordIdToReturn = 'business-1'
        ..uploadBusinessDocumentError = const ServerException(500);
      final repository = SyncRepositoryImpl(apiClient: apiClient);

      final statuses = await repository
          .submitCase(
            caseId: 'case-1',
            values: const {},
            mediaFilesByStage: const {
              'trade_license': '/tmp/license.jpg',
              'identification_card': '/tmp/id.jpg',
            },
          )
          .toList();

      expect((statuses.last as SyncFailed).exception, isA<ServerException>());
      expect(apiClient.uploadBusinessDocumentCallCount, 1);
      expect(apiClient.uploadDocumentCallCount, 0);
    });

    test('an unmapped stage among business documents still fails loudly, before anything is uploaded', () async {
      final apiClient = FakeApiClient()
        ..recordIdToReturn = 'record-1'
        ..businessRecordIdToReturn = 'business-1';
      final repository = SyncRepositoryImpl(apiClient: apiClient);

      final statuses = await repository
          .submitCase(
            caseId: 'case-1',
            values: const {},
            mediaFilesByStage: const {
              'trade_license': '/tmp/license.jpg',
              'business_permit': '/tmp/x.jpg', // not a DocumentKind
            },
          )
          .toList();

      expect(statuses.last, isA<SyncFailed>());
      expect(apiClient.uploadBusinessDocumentCallCount, 0);
    });
  });

  group('device-attested liveness', () {
    Map<String, dynamic> claim({bool verdict = true, String session = 's-1'}) => {
          'attestedLivenessVerdict': verdict,
          'attestedAntiSpoofingFlags': {'motionCorrelationCheckFailed': false},
          'attestedSessionId': session,
          'attestedDetector': 'smart_liveliness_detection 0.3.9',
          'attestedAttemptsUsed': 1,
        };

    test('the selfie image goes up as a profile_picture through the ordinary individual document path, then the claim is recorded',
        () async {
      final apiClient = FakeApiClient()..recordIdToReturn = 'record-1';
      final statuses = await SyncRepositoryImpl(apiClient: apiClient)
          .submitCase(
            caseId: 'case-1',
            values: const {},
            mediaFilesByStage: const {'selfie_liveness': '/tmp/selfie.jpg'},
            attestedLivenessByStage: {'selfie_liveness': claim()},
          )
          .toList();

      expect(statuses, [
        const SyncUploading(step: 1, totalSteps: 3, label: 'Submitting case'),
        const SyncUploading(step: 2, totalSteps: 3, label: 'Uploading selfie_liveness'),
        const SyncUploading(step: 3, totalSteps: 3, label: 'Recording device-attested liveness (selfie_liveness)'),
        const SyncSucceeded(),
      ]);
      expect(apiClient.uploadDocumentCalls, [
        {'recordId': 'record-1', 'kind': 'profile_picture', 'filePath': '/tmp/selfie.jpg'},
      ]);
      expect(apiClient.uploadBusinessDocumentCallCount, 0);
      expect(apiClient.submitAttestedLivenessCalls, [
        {
          'recordId': 'record-1',
          'attestedLivenessVerdict': true,
          'attestedAntiSpoofingFlags': {'motionCorrelationCheckFailed': false},
          'attestedSessionId': 's-1',
          'attestedDetector': 'smart_liveliness_detection 0.3.9',
        },
      ]);
    });

    test('the claim is sent exactly as the device made it (a false verdict is not turned into a pass)', () async {
      final apiClient = FakeApiClient()..recordIdToReturn = 'record-1';
      await SyncRepositoryImpl(apiClient: apiClient)
          .submitCase(
            caseId: 'case-1',
            values: const {},
            mediaFilesByStage: const {},
            attestedLivenessByStage: {'selfie_liveness': claim(verdict: false)},
          )
          .toList();
      expect(apiClient.submitAttestedLivenessCalls.single['attestedLivenessVerdict'], false);
    });

    test('a claim with no recordId to record it against fails loudly before anything is uploaded', () async {
      final apiClient = FakeApiClient()
        ..recordIdToReturn = null
        ..businessRecordIdToReturn = 'business-1';
      final statuses = await SyncRepositoryImpl(apiClient: apiClient)
          .submitCase(
            caseId: 'case-1',
            values: const {},
            mediaFilesByStage: const {'trade_license': '/tmp/license.jpg'},
            attestedLivenessByStage: {'selfie_liveness': claim()},
          )
          .toList();

      expect(statuses.last, isA<SyncFailed>());
      expect((statuses.last as SyncFailed).exception.message, contains('attested liveness'));
      expect(apiClient.uploadBusinessDocumentCallCount, 0, reason: 'resolved before the first upload');
      expect(apiClient.submitAttestedLivenessCallCount, 0);
    });

    test('a malformed claim fails loudly before anything is uploaded', () async {
      final apiClient = FakeApiClient()..recordIdToReturn = 'record-1';
      final statuses = await SyncRepositoryImpl(apiClient: apiClient)
          .submitCase(
            caseId: 'case-1',
            values: const {},
            mediaFilesByStage: const {'identification_card': '/tmp/id.jpg'},
            attestedLivenessByStage: {
              'selfie_liveness': {'attestedLivenessVerdict': 'yes'},
            },
          )
          .toList();

      expect(statuses.last, isA<SyncFailed>());
      expect(apiClient.uploadDocumentCallCount, 0);
      expect(apiClient.submitAttestedLivenessCallCount, 0);
    });

    test('a failed image upload stops the sequence: the claim is not recorded', () async {
      final apiClient = FakeApiClient()
        ..recordIdToReturn = 'record-1'
        ..uploadDocumentError = const ServerException(500);
      final statuses = await SyncRepositoryImpl(apiClient: apiClient)
          .submitCase(
            caseId: 'case-1',
            values: const {},
            mediaFilesByStage: const {'selfie_liveness': '/tmp/selfie.jpg'},
            attestedLivenessByStage: {'selfie_liveness': claim()},
          )
          .toList();

      expect((statuses.last as SyncFailed).exception, isA<ServerException>());
      expect(apiClient.submitAttestedLivenessCallCount, 0);
    });

    test('a failed claim call is a SyncFailed carrying the same exception', () async {
      final apiClient = FakeApiClient()
        ..recordIdToReturn = 'record-1'
        ..submitAttestedLivenessError = const ClientException(404, 'unknown provider');
      final statuses = await SyncRepositoryImpl(apiClient: apiClient)
          .submitCase(
            caseId: 'case-1',
            values: const {},
            mediaFilesByStage: const {},
            attestedLivenessByStage: {'selfie_liveness': claim()},
          )
          .toList();
      expect((statuses.last as SyncFailed).exception, isA<ClientException>());
    });
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
