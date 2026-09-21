import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/services/api_client.dart';
import 'package:sdui_demo/services/app_exception.dart';

void main() {
  group('MockApiClient.injectedFailure (deterministic test-injection path)', () {
    test('throws the injected failure on the next call, for every method', () async {
      final client = MockApiClient();

      client.injectedFailure = const NetworkException();
      await expectLater(
        client.fetchFlowManifest(flowId: 'kyc_kyb_collection', clientId: 'c'),
        throwsA(isA<NetworkException>()),
      );

      client.injectedFailure = const AppTimeoutException();
      await expectLater(
        client.fetchOptions(
          clientId: 'client-1',
          workflowId: 'kyc_kyb_collection',
          fieldKey: 'district',
          dependencyValues: const {'region': 'Addis Ababa'},
        ),
        throwsA(isA<AppTimeoutException>()),
      );

      client.injectedFailure = const ServerException(500);
      await expectLater(
        client.submitCase(caseId: null, values: const {}),
        throwsA(isA<ServerException>()),
      );

      client.injectedFailure = const UnauthorizedException();
      await expectLater(
        client.uploadDocument(recordId: 'record-1', kind: 'identification_card', filePath: '/tmp/x.jpg'),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('only fires once, then clears itself', () async {
      final client = MockApiClient()..injectedFailure = const NetworkException();

      await expectLater(
        client.fetchFlowManifest(flowId: 'kyc_kyb_collection', clientId: 'c'),
        throwsA(isA<NetworkException>()),
      );

      // Second call succeeds normally — the injected failure only applied
      // to the one call right after it was set.
      final manifest = await client.fetchFlowManifest(flowId: 'kyc_kyb_collection', clientId: 'c');
      expect(manifest.stagesJson, isNotEmpty);
      expect(client.injectedFailure, isNull);
    });
  });

  test('enableDemoFailures is off by default, so the random demo-failure path never runs', () async {
    // Not a statistical check: enableDemoFailures gates the whole demo
    // path behind a plain `if`, so "off" means the random path is
    // unreachable, not merely unlikely — one call is enough to prove it.
    final client = MockApiClient();

    final manifest = await client.fetchFlowManifest(flowId: 'kyc_kyb_collection', clientId: 'c');

    expect(manifest.stagesJson, isNotEmpty);
  });

  test('submitCase always returns a recordId, so demo/manual runs can exercise document upload', () async {
    final client = MockApiClient();

    final result = await client.submitCase(caseId: 'case-1', values: const {});

    expect(result.caseId, 'case-1');
    expect(result.recordId, isNotNull);
  });

  test('uploadDocument echoes the kind it was given', () async {
    final client = MockApiClient();

    final result = await client.uploadDocument(
      recordId: 'record-1',
      kind: 'identification_card',
      filePath: '/tmp/x.jpg',
    );

    expect(result.kind, 'identification_card');
  });

  test('enableDemoFailures, when explicitly enabled with a seeded Random, can simulate a failure', () async {
    // Seeded so this is deterministic despite exercising the "random" path
    // — this is testing that the demo mechanism *works*, not asserting
    // real randomness, which would be flaky by definition.
    // Seed 2's first nextDouble() is ~0.0008, comfortably inside the ~5%
    // demo-failure threshold — verified by hand, not guessed (a wrong seed
    // would just make this test pass for the wrong reason, waiting to time
    // out on `fetchFlowManifest`'s own delay instead of asserting anything).
    final client = MockApiClient(enableDemoFailures: true, demoRandom: Random(2));

    await expectLater(
      client.fetchFlowManifest(flowId: 'kyc_kyb_collection', clientId: 'c'),
      throwsA(isA<AppException>()),
    );
  });
}
