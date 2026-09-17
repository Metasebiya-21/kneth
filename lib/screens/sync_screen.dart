import 'package:flutter/material.dart';

import '../controllers/flow_controller.dart';
import '../services/sync_engine.dart';
import '../services/sync_status.dart';

/// "Sync now" screen shown after a flow completes — uploads the collected
/// case through [SyncEngine] and shows live progress from its stream.
class SyncScreen extends StatefulWidget {
  final FlowController controller;

  const SyncScreen({super.key, required this.controller});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  late final SyncEngine _engine = SyncEngine(apiClient: widget.controller.apiClient);
  SyncStatus _status = const SyncIdle();

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    final values = widget.controller.allValues;
    final mediaFilePaths = values.entries
        .where((entry) => entry.key.endsWith('.filePath') && entry.value != null)
        .map((entry) => entry.value as String)
        .toList();

    _engine.sync(values: values, mediaFilePaths: mediaFilePaths).listen((status) async {
      if (!mounted) return;
      setState(() => _status = status);
      if (status is SyncSucceeded) {
        // The case has been handed off to the backend — no need to resume
        // it locally anymore.
        await widget.controller.clearSaved();
      }
    });
  }

  void _retry() {
    setState(() => _status = const SyncIdle());
    _start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sync case')),
      body: Center(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    final status = _status;
    return switch (status) {
      SyncIdle() => const Text('Preparing...'),
      SyncUploading(:final step, :final totalSteps, :final label) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 220,
                child: LinearProgressIndicator(value: step / totalSteps),
              ),
              const SizedBox(height: 16),
              Text('$label ($step/$totalSteps)'),
            ],
          ),
        ),
      SyncSucceeded() => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 64),
              const SizedBox(height: 16),
              const Text('Case synced successfully'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      SyncFailed(:final message) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 64),
              const SizedBox(height: 16),
              Text('Sync failed: $message', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: _retry, child: const Text('Retry')),
            ],
          ),
        ),
    };
  }
}
