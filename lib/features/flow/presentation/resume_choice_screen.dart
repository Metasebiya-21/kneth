import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/flow_case_state.dart';
import '../domain/flow_manifest.dart';
import 'flow_notifier.dart';
import 'flow_screen.dart';

/// Shown on startup when a saved in-progress case is found — lets the
/// agent pick up where they left off or discard it and start a fresh
/// case. [savedCaseState] is only used to display progress (how far the
/// agent got) — actually resuming re-runs the full
/// [FlowNotifier.resume] flow (including its stale-manifest check) once
/// [FlowScreen] mounts, rather than reusing this exact snapshot, so
/// there's only one place that logic lives.
class ResumeChoiceScreen extends ConsumerStatefulWidget {
  final FlowManifest manifest;
  final FlowCaseState savedCaseState;

  const ResumeChoiceScreen({
    super.key,
    required this.manifest,
    required this.savedCaseState,
  });

  @override
  ConsumerState<ResumeChoiceScreen> createState() => _ResumeChoiceScreenState();
}

class _ResumeChoiceScreenState extends ConsumerState<ResumeChoiceScreen> {
  bool _startingOver = false;

  Future<void> _startOver() async {
    setState(() => _startingOver = true);
    await ref.read(flowRepositoryProvider).clearSavedCaseState(widget.manifest.workflowId);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => FlowScreen(manifest: widget.manifest)),
    );
  }

  void _resume() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => FlowScreen(manifest: widget.manifest, resumeMode: true),
      ),
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
                'You have an in-progress case (stage ${widget.savedCaseState.progressLabel}).',
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
