/// Thrown by [AuthRepository.login] when the credentials were RIGHT but the
/// account must replace its password before it may sign in — a newly hired
/// agent's temporary password (backend NOTES.md, Phases 24/25). Not an
/// `AppException`: it isn't a failure to render, it's a different next step
/// (the change-password screen), which `AuthNotifier` branches on.
///
/// Carries the username so that step doesn't have to ask for it again.
class PasswordChangeRequiredException implements Exception {
  final String username;
  final String message;

  const PasswordChangeRequiredException({required this.username, required this.message});

  @override
  String toString() => message;
}
