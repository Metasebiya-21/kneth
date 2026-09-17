import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'controllers/flow_controller.dart';
import 'models/flow_manifest.dart';
import 'screens/flow_screen.dart';
import 'screens/resume_choice_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final manifest = FlowManifest(flowId: 'kyc_kyb_collection');
  final restoredController = await FlowController.restore(manifest: manifest);
  runApp(
    ProviderScope(
      // Required by kifiya_rendering_engine's DynamicForm (a Riverpod
      // ConsumerWidget). Each GENERIC_FORM stage additionally nests its own
      // scoped override — see RenderingEngineStageScreen.
      child: SduiDemoApp(manifest: manifest, restoredController: restoredController),
    ),
  );
}

class SduiDemoApp extends StatelessWidget {
  final FlowManifest manifest;
  final FlowController? restoredController;

  const SduiDemoApp({super.key, required this.manifest, this.restoredController});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SDUI demo',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: restoredController != null
          ? ResumeChoiceScreen(manifest: manifest, restoredController: restoredController!)
          : FlowScreen(controller: FlowController(manifest: manifest)),
    );
  }
}
