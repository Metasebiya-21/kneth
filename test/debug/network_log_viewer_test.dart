import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sdui_demo/debug/network_log.dart';
import 'package:sdui_demo/debug/network_log_viewer.dart';
import 'package:sdui_demo/debug/shake_detector.dart';

void main() {
  testWidgets('a shake opens the log over the app; entries newest first; detail view; close returns', (tester) async {
    final log = NetworkLog();
    final client = NetworkLogClient(
      MockClient((r) async => http.Response('{"password":"hunter2","ok":true}', r.url.path == '/b' ? 429 : 200,
          headers: {'content-type': 'application/json'})),
      log,
    );
    await tester.runAsync(() async {
      await client.post(Uri.parse('https://h.test/a'));
      await client.post(Uri.parse('https://h.test/b'));
    });

    final readings = StreamController<Acceleration>();
    addTearDown(readings.close);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => NetworkLogShakeListener(log: log, readings: readings.stream, child: child!),
      home: const Scaffold(body: Text('the app')),
    ));
    expect(find.text('Network log (debug build)'), findsNothing);

    for (var i = 0; i < 3; i++) {
      readings.add((x: 25, y: 0, z: 0));
    }
    await tester.pumpAndSettle();
    expect(find.text('Network log (debug build)'), findsOneWidget);

    final titles = tester.widgetList<ListTile>(find.byType(ListTile)).map((t) => (t.title as Text).data).toList();
    expect(titles, ['POST /b', 'POST /a']);
    expect(find.text('429'), findsOneWidget);

    await tester.tap(find.text('POST /b'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Status: 429'), findsOneWidget);
    expect(find.textContaining('hunter2'), findsNothing);
    expect(find.textContaining(redactedValue), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Network log (debug build)'), findsNothing);
    expect(find.text('the app'), findsOneWidget);
  });
}
