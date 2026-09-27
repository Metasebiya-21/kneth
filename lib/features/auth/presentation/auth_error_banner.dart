import 'package:flutter/material.dart';

import '../../../services/app_exception.dart';
import '../../../widgets/app_error_view.dart';

/// Shows a failed password change or reset, keeping the backend's distinct
/// outcomes distinct instead of one generic "something went wrong":
///
/// - 429 (rate limited): the backend's own message. It sends no
///   `Retry-After` header or wait time (checked in its source: its
///   `RateLimitedError` carries only a message), so none is shown — any
///   number here would be a guess.
/// - 422 (weak, unchanged, or policy-refused password; wrong/expired code):
///   the backend's own message, which says which.
/// - 401: [unauthorizedTitle] (the caller knows what was wrong — e.g. the
///   current password), plus the backend's message.
/// - Anything else (offline, timeout, 5xx): the shared [AppErrorView].
class AuthErrorBanner extends StatelessWidget {
  final AppException error;
  final String unauthorizedTitle;

  const AuthErrorBanner({super.key, required this.error, this.unauthorizedTitle = 'Not accepted'});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String title)? kind = switch (error) {
      ClientException(statusCode: 429) => (Icons.hourglass_top, 'Too many attempts'),
      ClientException(statusCode: 422) => (Icons.rule, 'Check what you entered'),
      UnauthorizedException() => (Icons.lock_outline, unauthorizedTitle),
      _ => null,
    };
    if (kind == null) return AppErrorView(error: error);
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('auth-error-banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(kind.$1, color: colors.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kind.$2,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(color: colors.onErrorContainer),
                ),
                const SizedBox(height: 4),
                Text(error.message, style: TextStyle(color: colors.onErrorContainer)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
