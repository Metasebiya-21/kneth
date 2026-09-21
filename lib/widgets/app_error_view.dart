import 'package:flutter/material.dart';

import '../services/app_exception.dart';

/// A reusable, feature-agnostic way to show an [AppException] — every
/// screen in this app that can fail a network call renders its error the
/// same way through this, instead of each screen inventing its own
/// message text and retry button. Lives in `lib/widgets/` (not any
/// feature, not `lib/services/`): it's pure presentation with nothing
/// feature-specific in it, the same reason a shared UI component belongs
/// outside `lib/features/` entirely.
///
/// Never shows a raw `exception.toString()` or stack trace — each
/// [AppException] variant gets its own plain-language message.
/// [NetworkException] specifically gets offline-appropriate wording
/// ("this will retry once you're back online") rather than being treated
/// like a hard server failure, since this app is already built
/// offline-first (see the flow-manifest and flow-migration NOTES.md
/// entries). [onRetry] is only ever shown for
/// [AppException.isRetryable] exceptions — retrying a malformed request
/// or an unauthorized call wouldn't do anything.
class AppErrorView extends StatelessWidget {
  final AppException error;
  final VoidCallback? onRetry;

  const AppErrorView({super.key, required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final presentation = _presentationFor(error);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(presentation.icon, size: 48, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 16),
          Text(presentation.message, textAlign: TextAlign.center),
          if (error.isRetryable && onRetry != null) ...[
            const SizedBox(height: 24),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ],
      ),
    );
  }

  _ErrorPresentation _presentationFor(AppException error) {
    return switch (error) {
      NetworkException() => const _ErrorPresentation(
          Icons.cloud_off,
          "You appear to be offline. This will retry automatically once you're back online.",
        ),
      AppTimeoutException() => const _ErrorPresentation(
          Icons.timer_off_outlined,
          'That took too long to respond. Please try again.',
        ),
      ServerException() => const _ErrorPresentation(
          Icons.dns_outlined,
          'Something went wrong on our end. Please try again shortly.',
        ),
      // Uses error.message, same as every other variant below — not a
      // hardcoded string, unlike this one used to be. A real, found-not-
      // guessed inconsistency: this was the only variant ignoring its own
      // carried message, which silently broke reusing UnauthorizedException
      // for a login failure's own specific reason (e.g. "Incorrect
      // username or password.") — see NOTES.md's Phase 1. The default
      // constructor message ('Not authorized. Please sign in again.')
      // still covers the plain "not signed in" case this was originally
      // written for.
      UnauthorizedException() => _ErrorPresentation(Icons.lock_outline, error.message),
      ForbiddenException() => _ErrorPresentation(Icons.block_outlined, error.message),
      ClientException() => _ErrorPresentation(Icons.error_outline, error.message),
      ParseException() => const _ErrorPresentation(
          Icons.warning_amber_outlined,
          'We received an unexpected response. Please try again.',
        ),
      UnknownException() => const _ErrorPresentation(
          Icons.error_outline,
          'Something unexpected happened. Please try again.',
        ),
    };
  }
}

class _ErrorPresentation {
  final IconData icon;
  final String message;
  const _ErrorPresentation(this.icon, this.message);
}
