import 'package:flutter/material.dart';

import '../controllers/flow_controller.dart';
import '../models/flow_manifest.dart';
import 'flow_screen.dart';

/// Shown on startup when a saved in-progress case is found (offline-first
/// persistence, Phase 4) — lets the user pick up where they left off or
/// discard it and start a fresh case.
class ResumeChoiceScreen extends StatefulWidget {
  final FlowManifest manifest;
  final FlowController restoredController;

  const ResumeChoiceScreen({
    super.key,
    required this.manifest,
    required this.restoredController,
  });

  @override
  State<ResumeChoiceScreen> createState() => _ResumeChoiceScreenState();
}

class _ResumeChoiceScreenState extends State<ResumeChoiceScreen> {
  bool _startingOver = false;

  Future<void> _startOver() async {
    setState(() => _startingOver = true);
    await widget.restoredController.clearSaved();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => FlowScreen(controller: FlowController(manifest: widget.manifest)),
      ),
    );
  }

  void _resume() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => FlowScreen(controller: widget.restoredController)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.history, size: 64),
              const SizedBox(height: 16),
              Text(
                'Resume where you left off?',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'You have an in-progress case (stage ${widget.restoredController.progressLabel}).',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(onPressed: _resume, child: const Text('Resume')),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _startingOver ? null : _startOver,
                  child: Text(_startingOver ? 'Starting over...' : 'Start over'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
