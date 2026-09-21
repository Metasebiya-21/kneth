import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/app_error_view.dart';
import 'auth_notifier.dart';

/// The app's entry screen whenever there's no valid stored session (see
/// `SduiDemoApp` in main.dart, which reactively swaps between this and
/// `ClientSelectionScreen` based on `authNotifierProvider`). Reads
/// `authNotifierProvider` directly — no nested `ProviderScope` of its
/// own, the same deliberate deviation flow's own screens and
/// `ClientSelectionScreen` already make (this screen's dependency doesn't
/// vary per instance).
///
/// Reuses the shared `AppErrorView` for a failed login, per this task's
/// own instruction — not a bespoke error widget.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    ref.read(authNotifierProvider.notifier).login(
          username: _usernameController.text,
          password: _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authNotifierProvider);
    final isLoggingIn = state is AuthLoggingIn;

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state is AuthFailed) ...[
                  AppErrorView(error: state.error),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: _usernameController,
                  enabled: !isLoggingIn,
                  decoration: const InputDecoration(labelText: 'Username'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  enabled: !isLoggingIn,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => isLoggingIn ? null : _submit(),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: isLoggingIn ? null : _submit,
                  child: Text(isLoggingIn ? 'Signing in...' : 'Sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
