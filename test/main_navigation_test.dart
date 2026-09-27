// SduiDemoApp itself, not a screen in isolation: picking a workflow on the
// client screen must open the flow. Regression test for a real device crash
// ("Navigator operation requested with a context that does not include a
// Navigator"): _startFlow was handed SduiDemoApp's own build context, which
// sits ABOVE MaterialApp and so has no Navigator. No earlier test pumped
// SduiDemoApp, so nothing exercised that tap -> push.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/auth/domain/auth_token.dart';
import 'package:sdui_demo/features/auth/presentation/auth_notifier.dart';
import 'package:sdui_demo/features/flow/presentation/flow_notifier.dart';
import 'package:sdui_demo/main.dart';
import 'package:sdui_demo/services/api_dtos.dart';

import 'support/fake_api_client.dart';
import 'support/fake_auth_repository.dart';
import 'support/fake_flow_repository.dart';

void main() {
  testWidgets('tapping a workflow on the client screen navigates (no "context without a Navigator" crash)',
      (tester) async {
    final apiClient = FakeApiClient(
      clients: const [ClientSummaryDto(id: 'client-1', name: 'Awash Bank')],
      workflowsByClientId: const {
        'client-1': [WorkflowSummaryDto(id: 'wf-1', name: 'KYC/KYB collection')],
      },
    );
    final flowRepository = FakeFlowRepository();
    final authRepository = FakeAuthRepository(
      initialSession: AuthToken(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    final authNotifier = AuthNotifier(authRepository);
    await authNotifier.initialize();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(apiClient),
        flowRepositoryProvider.overrideWithValue(flowRepository),
        authRepositoryProvider.overrideWithValue(authRepository),
        authNotifierProvider.overrideWith((ref) => authNotifier),
      ],
      child: SduiDemoApp(flowRepository: flowRepository),
    ));
    await tester.pump();

    await tester.tap(find.text('Awash Bank'));
    await tester.pump();
    await tester.tap(find.text('KYC/KYB collection'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.text('KYC/KYB collection'), findsNothing, reason: 'a new route should cover the client screen');
  });
}
