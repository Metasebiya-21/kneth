import 'package:flutter/material.dart';
import 'package:stac/stac.dart';

import '../../../../services/api_dtos.dart';
import '../../../../services/app_exception.dart';
import '../../../../widgets/app_error_view.dart';
import '../../../liveness/domain/device_liveness_assessment.dart';
import '../../../liveness/domain/liveness_capture_result.dart';
import '../../../liveness/domain/liveness_progress.dart';
import '../../../native_capture/domain/captured_media.dart';
import '../knet_stac_scope.dart';
import '../stac_form_values.dart';
import 'kneth_photo_capture_parser.dart' show kCapturedFilePathKey;

/// `kneth_liveness_capture` — `{type, id, label}` where `id` is the stage id.
///
/// The BACKEND counts the attempts (per case): each attempt is started with the
/// backend before the camera opens and its outcome is reported back, the backend
/// refuses a further attempt once the limit is used, and a case that runs out
/// moves to manual review where only a supervisor can move it on. So an app
/// restart cannot buy more tries: on mount this asks the backend where the case
/// stands. The device's verdict (from [assessDeviceLiveness]) is still only a
/// claim: it is recorded as attested, never verified.
///
/// A pass stores the final image at [kCapturedFilePathKey] (uploaded at sync as a
/// `profile_picture`) and the claim at [kAttestedLivenessKey]. A stage completed
/// by a supervisor's acceptance stores [kLivenessManualOverrideKey] instead and
/// has nothing to upload. This screen only asks the backend and shows the answer:
/// the supervisor's own review interface does not exist yet.
///
/// The camera, sensors and anti-spoofing behind it cannot be tested without a
/// real device; the tests use a fake launcher and a scripted backend, so they
/// prove this widget's own handling only.
class KnethLivenessCaptureParser extends StacParser<Map<String, dynamic>> {
  const KnethLivenessCaptureParser();

  @override
  String get type => 'kneth_liveness_capture';

  @override
  Map<String, dynamic> getModel(Map<String, dynamic> json) => json;

  @override
  Widget parse(BuildContext context, Map<String, dynamic> model) =>
      _KnethLivenessCapture(model, key: ValueKey('kneth_liveness_capture:${model['id']}'));
}

class _KnethLivenessCapture extends StatefulWidget {
  final Map<String, dynamic> model;

  const _KnethLivenessCapture(this.model, {super.key});

  @override
  State<_KnethLivenessCapture> createState() => _KnethLivenessCaptureState();
}

/// A finished camera session whose outcome the backend has not yet acknowledged
/// (kept so a dropped connection can be retried without redoing the check).
class _PendingOutcome {
  final String attemptId;
  final LivenessCaptureResult result;
  final DeviceLivenessAssessment assessment;
  final String? persistedImagePath;

  const _PendingOutcome(this.attemptId, this.result, this.assessment, this.persistedImagePath);
}

class _KnethLivenessCaptureState extends State<_KnethLivenessCapture> {
  late final KnethStacScope _scope;
  late final StacFieldRegistration _registration;
  LivenessProgress? _progress;
  bool _completed = false;
  bool _byManualReview = false;
  bool _busy = false;
  String? _guidance;
  List<String> _tips = const [];
  AppException? _error;
  _PendingOutcome? _pending;

  StacFormValues get _values => _scope.values;
  String get _stageId => widget.model['id'] as String;

  @override
  void initState() {
    super.initState();
    _scope = KnethStacScope.of(context);
    // A resumed case that already holds a finished check (or a supervisor's acceptance) keeps it.
    final saved = _values[kAttestedLivenessKey];
    _completed = saved is Map && saved['attestedLivenessVerdict'] == true && _values[kCapturedFilePathKey] != null;
    _byManualReview = _values[kLivenessManualOverrideKey] is Map;
    _registration = StacFieldRegistration(
      id: _stageId,
      validate: () {
        if (_completed || _byManualReview) return null;
        final progress = _progress;
        if (progress != null && (progress.awaitingManualReview || progress.declined)) {
          return 'The selfie check is waiting for a supervisor';
        }
        return 'Complete the selfie check to continue';
      },
    );
    _values.register(_registration);
    if (!_completed && !_byManualReview) _refreshStatus(quiet: true);
  }

  @override
  void dispose() {
    _values.unregister(_registration);
    super.dispose();
  }

  LivenessProgress _progressFrom(LivenessStatusDto s) => LivenessProgress(
        caseStatus: s.caseStatus,
        attemptsUsed: s.attemptsUsed,
        attemptsCompleted: s.attemptsCompleted,
        maxAttempts: s.maxAttempts,
        attemptsRemaining: s.attemptsRemaining,
        attestedPassRecorded: s.attestedPassRecorded,
        overrideMethod: s.override?.method,
        overrideDecision: s.override?.decision,
      );

  /// Asks the backend where the case stands. [quiet]: on mount, a failure just leaves the start
  /// button (the backend still refuses a further attempt when it is pressed).
  Future<void> _refreshStatus({bool quiet = false}) async {
    if (!quiet) setState(() => _busy = true);
    try {
      final status = await _scope.apiClient.fetchLivenessStatus(_scope.caseId);
      if (!mounted) return;
      _adopt(_progressFrom(status));
    } on AppException catch (e) {
      if (mounted && !quiet) setState(() => _error = e);
    } finally {
      if (mounted && !quiet) setState(() => _busy = false);
    }
  }

  /// Takes the backend's word for the state; a supervisor's acceptance completes the stage.
  void _adopt(LivenessProgress progress) {
    setState(() {
      _progress = progress;
      if (progress.overrideAccepted && !_completed) {
        _byManualReview = true;
        _values.update(kLivenessManualOverrideKey, {
          'method': progress.overrideMethod,
          'decision': progress.overrideDecision,
        });
      }
    });
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pending = _pending;
      if (pending != null) {
        await _reportOutcome(pending);
        return;
      }
      final LivenessAttemptDto begun;
      try {
        begun = await _scope.apiClient.beginLivenessAttempt(_scope.caseId);
      } on ClientException catch (e) {
        if (e.statusCode == 409) {
          // The backend refuses: attempts used up, already decided, or a pass already recorded.
          await _refreshStatus();
          return;
        }
        rethrow;
      }
      if (!mounted) return;
      setState(() => _progress = _progressFrom(begun.status));

      final result = await _scope.captureLiveness(context);
      if (result == null || !mounted) return; // backed out: the backend keeps the attempt open, reused next time

      final assessment = assessDeviceLiveness(
        packageReportedSuccess: result.packageReportedSuccess,
        antiSpoofingFlags: result.antiSpoofingFlags,
      );
      // The image is stored locally first; a pass is only ever acknowledged with a photo to upload.
      String? persisted;
      final imagePath = result.imagePath;
      final verdict = assessment.verdict && imagePath != null;
      if (verdict) {
        final media = await _scope.mediaRepository.persistCopy(
          sourcePath: imagePath,
          prefix: _stageId,
          type: CaptureType.photo,
        );
        persisted = media.filePath;
      }
      await _reportOutcome(_PendingOutcome(begun.attemptId, result, assessment, persisted));
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e);
    } catch (_) {
      if (mounted) setState(() => _error = const UnknownException());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Reports the device's verdict to the backend, which counts it. If the connection drops the
  /// result is kept and the next press retries the report (no new camera session).
  Future<void> _reportOutcome(_PendingOutcome pending) async {
    final passed = pending.persistedImagePath != null;
    final LivenessStatusDto status;
    try {
      status = await _scope.apiClient.recordLivenessAttemptOutcome(
        caseId: _scope.caseId,
        attemptId: pending.attemptId,
        // A pass with no photo cannot be used, so it is reported as a failed attempt.
        attestedLivenessVerdict: passed,
        attestedAntiSpoofingFlags: pending.result.antiSpoofingFlags ?? const {},
        attestedSessionId: pending.result.sessionId,
      );
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _pending = pending;
          _error = e;
        });
      }
      return;
    }
    if (!mounted) return;
    _pending = null;
    final progress = _progressFrom(status);

    if (passed) {
      _values.update(kCapturedFilePathKey, pending.persistedImagePath);
      _values.update(
        kAttestedLivenessKey,
        attestedLivenessValue(
          attestedLivenessVerdict: true,
          attestedAntiSpoofingFlags: pending.result.antiSpoofingFlags ?? const {},
          attestedSessionId: pending.result.sessionId,
          attestedAttemptsUsed: progress.attemptsUsed,
        ),
      );
      setState(() {
        _progress = progress;
        _completed = true;
        _guidance = null;
        _tips = livenessTips(pending.assessment);
      });
      return;
    }

    setState(() {
      _progress = progress;
      _guidance = pending.assessment.verdict
          ? 'The selfie photo was not captured. Please try again.'
          : livenessFailureGuidance(pending.assessment);
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_completed) ...[
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.check_circle_outline),
              title: Text('Selfie check complete'),
              // Deliberately not "verified": the device reports it, nobody re-checks it.
              subtitle: Text('Recorded as reported by this device.'),
            ),
            for (final tip in _tips) Text(tip, style: const TextStyle(color: Colors.grey)),
          ] else if (_byManualReview)
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.check_circle_outline),
              title: Text('Approved by manual review'),
              subtitle: Text('A supervisor reviewed this case in person, so the selfie check is not needed.'),
            )
          else if (progress != null && progress.declined)
            const AppErrorView(
              error: ForbiddenException('This case was declined after manual review, so it cannot continue.'),
            )
          else if (progress != null && progress.awaitingManualReview) ...[
            const AppErrorView(
              error: ForbiddenException(
                'The selfie check could not be completed, so this case has been sent to a supervisor for '
                'manual review. You can continue once they have decided.',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : () => _refreshStatus(),
              child: const Text('Check review status'),
            ),
            if (_error != null) AppErrorView(error: _error!),
          ] else ...[
            const Text(
              'Take a quick selfie check: the camera will ask you to make a few simple movements.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            if (_guidance != null) ...[
              Text(_guidance!),
              const SizedBox(height: 12),
            ],
            if (progress != null && progress.attemptsUsed > 0)
              Text(
                'Tries left: ${progress.attemptsRemaining}',
                style: const TextStyle(color: Colors.grey),
              ),
            if (_error != null) AppErrorView(error: _error!, onRetry: _busy ? null : _start),
            ElevatedButton(
              onPressed: _busy ? null : _start,
              child: Text(_pending != null
                  ? 'Send result again'
                  : (progress == null || progress.attemptsCompleted == 0 ? 'Start selfie check' : 'Try again')),
            ),
          ],
          ValueListenableBuilder<Map<String, String>>(
            valueListenable: _values.errors,
            builder: (context, errors, _) {
              final message = errors[_stageId];
              if (message == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              );
            },
          ),
        ],
      ),
    );
  }
}
