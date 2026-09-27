import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/app_exception.dart';
import '../../../widgets/password_field.dart';
import '../domain/password_rules.dart';
import 'auth_error_banner.dart';
import 'auth_notifier.dart';

/// What the agent is told after asking for a code — always this, whatever
/// the username. The backend answers an unknown username with the same 200
/// as a real one on purpose (no account enumeration, backend NOTES.md
/// Phase 23), and this screen must not undo that by, say, echoing a phone
/// number or saying "sent" only for real accounts. It never reads the
/// response body at all.
const resetCodeSentMessage =
    'If an account with that username exists, a code has been sent to its registered phone.';

/// How long "Resend code" stays disabled after each send. A client-side
/// choice, not a backend signal: the backend gives none (no Retry-After, no
/// cooldown field), and it silently drops sends past its per-account limit
/// (3 an hour by default) with the same 200 — so without this, an impatient
/// agent could burn the hour's quota in seconds and never know. The only
/// 429 it ever shows is its per-IP limit.
const resendCooldown = Duration(seconds: 60);

/// "Forgot password?": ask for a code by SMS, then enter it with a new
/// password. Both steps live on this one screen so the whole thing can
/// `pop` with the username once the reset succeeds, and the login screen
/// fills it in.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  final String initialUsername;

  const ForgotPasswordScreen({super.key, this.initialUsername = ''});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  late final _usernameController = TextEditingController(text: widget.initialUsername);
  final _codeController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _codeRequested = false;
  bool _busy = false;
  AppException? _error;
  String? _usernameError;
  String? _codeError;
  String? _newError;
  String? _confirmError;

  /// Seconds until "Resend code" is enabled again; counted down by
  /// [_ticker] rather than compared against the wall clock, so it can't be
  /// skipped by changing the device time.
  int _resendSecondsLeft = 0;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    _usernameController.dispose();
    _codeController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String get _username => _usernameController.text.trim();

  void _startCooldown() {
    _resendSecondsLeft = resendCooldown.inSeconds;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _resendSecondsLeft--);
      if (_resendSecondsLeft <= 0) timer.cancel();
    });
  }

  void _endCooldown() {
    _ticker?.cancel();
    _resendSecondsLeft = 0;
  }

  Future<void> _run(
    Future<void> Function() action, {
    required void Function() onSuccess,
    void Function(AppException error)? onError,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          onError?.call(e);
        });
      }
      return;
    } catch (e) {
      if (mounted) setState(() => _error = UnknownException(e.toString()));
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) setState(onSuccess);
  }

  void _sendCode() {
    setState(() => _usernameError = _username.isEmpty ? 'Enter your username.' : null);
    if (_usernameError != null) return;
    final repository = ref.read(authRepositoryProvider);
    _run(
      () => repository.sendPasswordResetCode(username: _username),
      onSuccess: () {
        _codeRequested = true;
        _startCooldown();
      },
    );
  }

  void _resendCode() {
    final repository = ref.read(authRepositoryProvider);
    _codeController.clear();
    _run(
      () => repository.resendPasswordResetCode(username: _username),
      onSuccess: _startCooldown,
    );
  }

  void _useDifferentUsername() {
    setState(() {
      _codeRequested = false;
      _error = null;
      _endCooldown();
    });
  }

  void _reset() {
    final code = _codeController.text.trim();
    final next = _newController.text;
    setState(() {
      _codeError = code.isEmpty ? 'Enter the code from the SMS.' : null;
      _newError = newPasswordProblem(next);
      _confirmError = _newError == null ? confirmationProblem(next, _confirmController.text) : null;
    });
    if (_codeError != null || _newError != null || _confirmError != null) return;
    final repository = ref.read(authRepositoryProvider);
    _run(
      () => repository.resetPassword(username: _username, code: code, newPassword: next),
      onSuccess: () => Navigator.of(context).pop(_username),
      // A 429 here means the backend has thrown the code away ("Too many
      // attempts. Request a new OTP.") — the one case where waiting out the
      // resend cooldown would only be in the agent's way.
      onError: (e) {
        if (e is ClientException && e.statusCode == 429) _endCooldown();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;

    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (error != null) ...[
                  AuthErrorBanner(error: error, unauthorizedTitle: 'Not accepted'),
                  const SizedBox(height: 16),
                ],
                ...(_codeRequested ? _codeStep() : _requestStep()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _requestStep() => [
        const Text('Enter your username and we’ll send a reset code to the phone registered for your account.'),
        const SizedBox(height: 16),
        TextField(
          controller: _usernameController,
          enabled: !_busy,
          decoration: InputDecoration(labelText: 'Username', errorText: _usernameError),
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _sendCode(),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _busy ? null : _sendCode,
          child: Text(_busy ? 'Sending...' : 'Send code'),
        ),
      ];

  List<Widget> _codeStep() {
    final wait = _resendSecondsLeft;
    return [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(resetCodeSentMessage),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _codeController,
        enabled: !_busy,
        decoration: InputDecoration(labelText: 'Code', errorText: _codeError),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        autofillHints: const [AutofillHints.oneTimeCode],
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 12),
      PasswordField(
        controller: _newController,
        labelText: 'New password',
        enabled: !_busy,
        errorText: _newError,
        helperText: 'At least $minPasswordLength characters.',
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.newPassword],
      ),
      const SizedBox(height: 12),
      PasswordField(
        controller: _confirmController,
        labelText: 'Confirm new password',
        enabled: !_busy,
        errorText: _confirmError,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.newPassword],
        onSubmitted: (_) => _busy ? null : _reset(),
      ),
      const SizedBox(height: 24),
      ElevatedButton(
        onPressed: _busy ? null : _reset,
        child: Text(_busy ? 'Please wait...' : 'Reset password'),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _busy || wait > 0 ? null : _resendCode,
        child: Text(wait > 0 ? 'Resend code in ${wait}s' : 'Resend code'),
      ),
      TextButton(
        onPressed: _busy ? null : _useDifferentUsername,
        child: const Text('Use a different username'),
      ),
    ];
  }
}
