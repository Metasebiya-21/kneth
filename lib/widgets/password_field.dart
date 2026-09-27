import 'package:flutter/material.dart';

/// The one password-entry field in this app: a [TextField] that starts
/// obscured, with an eye button to show or hide what's been typed. Every
/// password input (sign in, change password, reset password) uses this
/// rather than its own copy of the toggle, so they all behave the same.
///
/// Still a plain [TextField] underneath, labelled by [labelText] — so
/// `find.widgetWithText(TextField, 'Password')` in a test finds it exactly as
/// it found the bare field this replaced.
///
/// Autocorrect and suggestions are off whether or not the text is shown:
/// revealing a password must not also feed it to the keyboard's dictionary.
class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final bool enabled;
  final String? errorText;
  final String? helperText;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final Iterable<String>? autofillHints;

  const PasswordField({
    super.key,
    required this.controller,
    required this.labelText,
    this.enabled = true,
    this.errorText,
    this.helperText,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.autofillHints,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      enabled: widget.enabled,
      obscureText: _obscured,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      autofillHints: widget.autofillHints,
      decoration: InputDecoration(
        labelText: widget.labelText,
        errorText: widget.errorText,
        helperText: widget.helperText,
        helperMaxLines: 2,
        errorMaxLines: 3,
        suffixIcon: IconButton(
          icon: Icon(_obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          tooltip: _obscured ? 'Show password' : 'Hide password',
          onPressed: () => setState(() => _obscured = !_obscured),
        ),
      ),
    );
  }
}
