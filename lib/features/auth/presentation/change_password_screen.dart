import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/password_field.dart';
import '../domain/password_rules.dart';
import 'auth_error_banner.dart';
import 'auth_notifier.dart';

/// Shown by `main.dart` while the auth state is [AuthPasswordChangeRequired]
/// — a sign-in with a temporary password the backend won't accept until
/// it's replaced. Submitting calls [AuthNotifier.completePasswordChange],
/// which changes the password and then signs in with the new one, so on
/// success the app moves straight on; this screen never shows a "success"
/// state of its own.
///
/// The current (temporary) password is asked for again rather than carried
/// over from the login screen: the backend needs it, and holding a typed
/// password in app state between screens isn't worth saving one field.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _currentError;
  String? _newError;
  String? _confirmError;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final current = _currentController.text;
    final next = _newController.text;
    setState(() {
      _currentError = current.isEmpty ? 'Enter your temporary password.' : null;
      _newError = newPasswordProblem(next, currentPassword: current);
      _confirmError = _newError == null ? confirmationProblem(next, _confirmController.text) : null;
    });
    if (_currentError != null || _newError != null || _confirmError != null) return;
    ref.read(authNotifierProvider.notifier).completePasswordChange(currentPassword: current, newPassword: next);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authNotifierProvider);
    if (state is! AuthPasswordChangeRequired) return const SizedBox.shrink();
    final submitting = state.submitting;
    final error = state.error;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Set a new password'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Back to sign in',
          onPressed: submitting ? null : () => ref.read(authNotifierProvider.notifier).cancelPasswordChange(),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'You signed in with a temporary password. Choose a new password to continue.',
                ),
                const SizedBox(height: 16),
                if (error != null) ...[
                  AuthErrorBanner(error: error, unauthorizedTitle: 'Current password is incorrect'),
                  const SizedBox(height: 16),
                ],
                PasswordField(
                  controller: _currentController,
                  labelText: 'Temporary password',
                  enabled: !submitting,
                  errorText: _currentError,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.password],
                ),
                const SizedBox(height: 12),
                PasswordField(
                  controller: _newController,
                  labelText: 'New password',
                  enabled: !submitting,
                  errorText: _newError,
                  helperText: 'At least $minPasswordLength characters.',
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                ),
                const SizedBox(height: 12),
                PasswordField(
                  controller: _confirmController,
                  labelText: 'Confirm new password',
                  enabled: !submitting,
                  errorText: _confirmError,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  onSubmitted: (_) => submitting ? null : _submit(),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: submitting ? null : _submit,
                  child: Text(submitting ? 'Saving...' : 'Save and sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
