// Same outer-ProviderScope pattern flow_screen_test.dart uses: this screen
// reads apiClientProvider directly (no nested ProviderScope of its own —
// see client_selection_screen.dart's doc comment), so a test can just wrap
// it in its own ProviderScope(overrides: [...]) the same way main.dart does
// for real.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/client_selection/presentation/client_selection_screen.dart';
import 'package:sdui_demo/features/flow/presentation/flow_notifier.dart';
import 'package:sdui_demo/services/api_dtos.dart';
import 'package:sdui_demo/services/app_exception.dart';

import '../../../support/fake_api_client.dart';

Widget _wrap(FakeApiClient apiClient, {required void Function(String, String) onSelected}) {
  return ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(apiClient)],
    child: MaterialApp(home: ClientSelectionScreen(onSelected: onSelected)),
  );
}

void main() {
  testWidgets('lists clients, then workflows for the tapped client, then reports the pick', (tester) async {
    final apiClient = FakeApiClient(
      clients: const [
        ClientSummaryDto(id: 'client-1', name: 'Awash Bank'),
        ClientSummaryDto(id: 'client-2', name: 'Dashen Bank'),
      ],
      workflowsByClientId: const {
        'client-1': [WorkflowSummaryDto(id: 'wf-1', name: 'KYC/KYB collection')],
      },
    );
    String? pickedClientId;
    String? pickedWorkflowId;

    await tester.pumpWidget(_wrap(
      apiClient,
      onSelected: (clientId, workflowId) {
        pickedClientId = clientId;
        pickedWorkflowId = workflowId;
      },
    ));
    await tester.pump();

    expect(find.text('Awash Bank'), findsOneWidget);
    expect(find.text('Dashen Bank'), findsOneWidget);

    await tester.tap(find.text('Awash Bank'));
    await tester.pump();

    expect(apiClient.lastFetchWorkflowsClientId, 'client-1');
    expect(find.text('KYC/KYB collection'), findsOneWidget);

    await tester.tap(find.text('KYC/KYB collection'));
    await tester.pump();

    expect(pickedClientId, 'client-1');
    expect(pickedWorkflowId, 'wf-1');
  });

  testWidgets('the back button returns to the client list without re-fetching clients', (tester) async {
    final apiClient = FakeApiClient(
      clients: const [ClientSummaryDto(id: 'client-1', name: 'Awash Bank')],
      workflowsByClientId: const {
        'client-1': [WorkflowSummaryDto(id: 'wf-1', name: 'KYC/KYB collection')],
      },
    );

    await tester.pumpWidget(_wrap(apiClient, onSelected: (_, __) {}));
    await tester.pump();
    await tester.tap(find.text('Awash Bank'));
    await tester.pump();
    expect(apiClient.fetchClientsCallCount, 1);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();

    expect(find.text('Awash Bank'), findsOneWidget);
    expect(apiClient.fetchClientsCallCount, 1);
  });

  testWidgets('an empty client list shows a plain message, not a crash', (tester) async {
    await tester.pumpWidget(_wrap(FakeApiClient(), onSelected: (_, __) {}));
    await tester.pump();

    expect(find.textContaining('No clients'), findsOneWidget);
  });

  testWidgets('a fetchClients failure shows AppErrorView, and retry re-fetches', (tester) async {
    final apiClient = FakeApiClient(fetchClientsError: const NetworkException());

    await tester.pumpWidget(_wrap(apiClient, onSelected: (_, __) {}));
    await tester.pump();

    expect(find.textContaining('offline'), findsOneWidget);
    expect(apiClient.fetchClientsCallCount, 1);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Retry'));
    await tester.pump();

    expect(apiClient.fetchClientsCallCount, 2);
  });

  testWidgets('a fetchWorkflows failure shows AppErrorView scoped to the workflows step', (tester) async {
    final apiClient = FakeApiClient(
      clients: const [ClientSummaryDto(id: 'client-1', name: 'Awash Bank')],
      fetchWorkflowsError: const ForbiddenException(),
    );

    await tester.pumpWidget(_wrap(apiClient, onSelected: (_, __) {}));
    await tester.pump();
    await tester.tap(find.text('Awash Bank'));
    await tester.pump();

    expect(find.text(const ForbiddenException().message), findsOneWidget);
  });
}
