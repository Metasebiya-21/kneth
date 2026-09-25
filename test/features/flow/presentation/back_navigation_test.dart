// Phase 3 (section 14.4): what happens to a conditional field's value when the
// agent types it, the field is hidden, the agent moves on and then goes BACK
// and re-shows the field. Written before the fix (against both renderers, while
// both existed); the previous renderer has since been removed.
//
// Note: FlowNotifier.back() is the only way back, and nothing in the UI calls
// it today (no Back button in either renderer), so these tests drive it
// directly. The behavior still matters: it is the domain contract any future
// Back control will hit.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/flow/domain/flow_case_state.dart';
import 'package:sdui_demo/features/flow/presentation/flow_notifier.dart';
import 'package:sdui_demo/features/flow/presentation/flow_screen.dart';

import '../../../support/fake_api_client.dart';
import '../../../support/stac_flow_harness.dart';
import '../../../support/stac_fixtures.dart';

FlowNotifier _notifier(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(FlowScreen))).read(flowNotifierProvider.notifier);

FlowCaseState _state(WidgetTester tester) =>
    (ProviderScope.containerOf(tester.element(find.byType(FlowScreen))).read(flowNotifierProvider) as FlowViewReady)
        .caseState;

Future<void> _pump(WidgetTester tester) async {
  final api = FakeApiClient()..stacStages = (recordedStacManifest()['stages'] as List).cast<Map<String, dynamic>>();
  await tester.pumpWidget(stacFlowApp(
    apiClient: api,
    stacStages: recordedStacStages(['association_details', 'personal_info']),
    workflowId: 'w',
    clientId: 'c',
    caseId: 'case-1',
  ));
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  _notifier(tester).back();
  await tester.pumpAndSettle();
}

void main() {
  {
    group('back-navigation', () {
      testWidgets('typed, hidden, moved on, back, re-shown: the agent\'s answer is still there', (tester) async {
        await _pump(tester);
        await choose(tester, 'Group', dropdown: 0);
        await tester.enterText(textFieldWith('company_name'), 'Acme');
        await choose(tester, 'Individual', dropdown: 0);
        expect(isShown('company_name'), isFalse);
        await pressContinue(tester); // -> personal_info

        expect(_state(tester).allValues.containsKey('association_details.company_name'), isFalse,
            reason: 'hidden at submit: excluded from what would be sent');

        await _back(tester); // -> association_details again
        expect(isShown('company_name'), isFalse, reason: 'still Individual, so still hidden');

        await choose(tester, 'Group', dropdown: 0); // re-show
        expect(isShown('company_name'), isTrue);
        expect(find.widgetWithText(TextField, 'Acme'), findsOneWidget,
            reason: 'the displayed value comes back although it was (correctly) not submitted while hidden');
      });

      testWidgets('a field that was never answered is still empty on re-show (nothing invented)', (tester) async {
        await _pump(tester);
        await choose(tester, 'Individual', dropdown: 0);
        await pressContinue(tester);
        await _back(tester);

        await choose(tester, 'Group', dropdown: 0);
        expect(isShown('company_name'), isTrue);
        expect(find.widgetWithText(TextField, 'Acme'), findsNothing);
        expect(tester.widget<TextField>(textFieldWith('company_name')).controller?.text ?? '', isEmpty);
      });

      testWidgets('remembering never leaks into the payload: still hidden after coming back -> still excluded',
          (tester) async {
        await _pump(tester);
        await choose(tester, 'Group', dropdown: 0);
        await tester.enterText(textFieldWith('company_name'), 'Acme');
        await choose(tester, 'Individual', dropdown: 0);
        await pressContinue(tester);
        await _back(tester);
        await pressContinue(tester); // hidden the whole time on this visit

        final values = _state(tester).allValues;
        expect(values.containsKey('association_details.company_name'), isFalse);
        expect(values['association_details.association_type'], 'Individual');
      });

      testWidgets('re-shown, and submitted while visible: the remembered value IS sent', (tester) async {
        await _pump(tester);
        await choose(tester, 'Group', dropdown: 0);
        await tester.enterText(textFieldWith('company_name'), 'Acme');
        await choose(tester, 'Individual', dropdown: 0);
        await pressContinue(tester);
        await _back(tester);
        await choose(tester, 'Group', dropdown: 0);
        await pressContinue(tester);

        expect(_state(tester).allValues['association_details.company_name'], 'Acme');
      });
    });
  }
}
