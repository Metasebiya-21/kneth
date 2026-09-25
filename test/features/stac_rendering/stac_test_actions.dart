import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens the [index]th dropdown and picks [optionLabel].
Future<void> pickOption(WidgetTester tester, String optionLabel, {int index = 0}) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>).at(index));
  await tester.pumpAndSettle();
  await tester.tap(find.text(optionLabel).last);
  await tester.pumpAndSettle();
}

Future<void> tapContinue(WidgetTester tester) async {
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}

/// The text field labelled [label] (its decoration's labelText).
Finder textFieldLabelled(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );
