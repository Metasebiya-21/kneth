// Widget-level coverage for FlowScreen, using the same ProviderScope-
// override seam established by sync/native_capture — except flow's own
// providers are overridden at the *root* ProviderScope (matching how
// main.dart does it for real), not a per-screen nested one, since flow's
// state is app-session-scoped rather than screen-scoped. See NOTES.md.
//
// Gotcha check (per NOTES.md's sync/native_capture sections — investigated,
// not assumed):
// - initState-time provider mutation: FlowScreen's _load() DOES mutate
//   flowNotifierProvider's state, and DOES run from initState — so this
//   gotcha applies here too, and flow_screen.dart already defers it via
//   addPostFrameCallback the same way sync_screen.dart does. Recurred, and
//   was already handled by following the established pattern up front.
// - Future.delayed vs tester.pump(): doesn't come up here — FakeFlowRepository
//   has no real delays, so ordinary tester.pump() calls are enough; no
//   polling helper was needed.
// - RenderRepaintBoundary under testWidgets: not applicable, flow renders
//   no canvas/image content itself.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/flow/data/stac_manifest_mapper.dart';
import 'package:sdui_demo/features/flow/domain/flow_manifest.dart';
import 'package:sdui_demo/features/flow/presentation/flow_notifier.dart';
import 'package:sdui_demo/features/flow/presentation/flow_screen.dart';
import 'package:sdui_demo/services/app_exception.dart';

import '../../../support/fake_api_client.dart';
import '../../../support/fake_flow_repository.dart';

/// Stac JSON for the two stages, produced by the backend's real serializer.
List<Map<String, dynamic>> _stacStages() {
  final ported = jsonDecode(File('test/fixtures/stac/ported_fixtures.json').readAsStringSync()) as Map<String, dynamic>;
  return [(ported['stage_a'] as Map).cast<String, dynamic>(), (ported['stage_b'] as Map).cast<String, dynamic>()];
}

Widget _app(FakeFlowRepository repository) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(FakeApiClient()),
      flowRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(
      home: FlowScreen(manifest: FlowManifest(workflowId: 'f', clientId: 'c')),
    ),
  );
}

void main() {
  // 'starts fresh, renders the first stage, advances through to completion' lives on as the
  // ported version in stac_rendering/ported_flow_tests_test.dart (Stac is the only renderer now).

  testWidgets('a failed load shows the error screen with a working retry', (tester) async {
    // A retryable AppException, not a bare Exception — AppErrorView (see
    // NOTES.md's Phase 4) only shows a Retry button when
    // error.isRetryable, and this test is specifically about confirming
    // retry works, so the fixture needs to be a failure that's actually
    // retryable, the same discipline every other AppErrorView-backed
    // test in this codebase already follows.
    final repository = FakeFlowRepository(stagesJson: stacStagesToStageJson(_stacStages()))..fetchManifestError = const NetworkException();

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    expect(find.textContaining('offline'), findsOneWidget);

    repository.fetchManifestError = null;
    await tester.tap(find.widgetWithText(ElevatedButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('stage_a'), findsOneWidget);
  });
}
