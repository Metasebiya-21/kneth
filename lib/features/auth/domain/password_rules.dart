/// The backend's own limits on a new password (`ChangePasswordRequest` /
/// `ResetPasswordRequest` in onboarding-platform's `shared/auth/schemas.py`:
/// 8 to 128 characters; and for a change, not equal to the current one).
/// Checked here first so the obvious mistakes never cost the agent one of
/// the backend's limited attempts. The backend still checks everything
/// itself, and Keycloak's realm policy can refuse more; those come back as
/// a 422 and are shown as-is.
const minPasswordLength = 8;
const maxPasswordLength = 128;

/// Why [newPassword] can't be submitted, or null if it can.
String? newPasswordProblem(String newPassword, {String? currentPassword}) {
  if (newPassword.length < minPasswordLength) {
    return 'Use at least $minPasswordLength characters.';
  }
  if (newPassword.length > maxPasswordLength) {
    return 'Use at most $maxPasswordLength characters.';
  }
  if (currentPassword != null && newPassword == currentPassword) {
    return 'Choose a password different from your current one.';
  }
  return null;
}

/// Why [confirmation] doesn't confirm [newPassword], or null if it does.
String? confirmationProblem(String newPassword, String confirmation) =>
    newPassword == confirmation ? null : 'The passwords don’t match.';
