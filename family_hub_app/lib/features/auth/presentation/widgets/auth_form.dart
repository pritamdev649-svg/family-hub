import 'package:flutter/material.dart';

import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/auth/application/auth_errors.dart';
import 'package:family_hub/features/auth/presentation/auth_labels.dart';

/// Snackbar for errors of the auth screens.
extension AuthSnackX on BuildContext {
  /// Like `showError`, but with the auth-specific texts of
  /// [authErrorText] (server waits in minutes, the sign-up age gate). Those
  /// explain a state rather than a failure, so they use the info style.
  void showAuthError(Object error) {
    final text = authErrorText(error, l10n);
    if (text != null) {
      showInfo(text);
    } else {
      showError(error);
    }
  }
}

/// Server-side field errors of one form (field id → message), shown by the
/// fields' validators until the user edits the field.
class ServerFieldErrors {
  final Map<String, String> _errors = {};

  String? operator [](String field) => _errors[field];

  bool get isEmpty => _errors.isEmpty;

  /// Validator that reports the server error of [field] first, then
  /// [local] (the client-side rules).
  FormFieldValidator<String> guard(
    String field, [
    FormFieldValidator<String>? local,
  ]) =>
      (value) => _errors[field] ?? local?.call(value);

  /// Replaces the errors with the entries of [errors] whose field is one of
  /// [fields]; returns whether any was kept (i.e. can be shown inline).
  bool show(Map<String, String> errors, Set<String> fields) {
    _errors
      ..clear()
      ..addEntries(errors.entries.where((e) => fields.contains(e.key)));
    return _errors.isNotEmpty;
  }

  void clear(String field) => _errors.remove(field);

  void clearAll() => _errors.clear();
}

/// Submit plumbing shared by the auth forms: validation, busy state (no
/// double submit), keyboard dismissal, and error display — field errors
/// inline (see [ServerFieldErrors]), everything else as a snackbar.
mixin AuthFormState<T extends StatefulWidget> on State<T> {
  final formKey = GlobalKey<FormState>();
  final serverErrors = ServerFieldErrors();

  /// Validation starts after the first submit attempt, then follows edits.
  AutovalidateMode autovalidateMode = AutovalidateMode.disabled;

  bool isSubmitting = false;

  /// Field ids ([AuthField]) of the fields currently in the form.
  Set<String> get formFields;

  /// Clears the server error of [field] (call from the field's onChanged).
  void fieldChanged(String field) => serverErrors.clear(field);

  /// Validates the form, runs [action] with the busy state and shows its
  /// errors. Returns `true` when [action] completed.
  Future<bool> submit(
    Future<void> Function() action, {
    Map<String, String> aliases = const {},
  }) async {
    if (isSubmitting) return false;
    serverErrors.clearAll();
    final form = formKey.currentState;
    if (form != null && !form.validate()) {
      setState(() => autovalidateMode = AutovalidateMode.onUserInteraction);
      return false;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => isSubmitting = true);
    try {
      await action();
      return true;
    } catch (e) {
      if (mounted) showSubmitError(e, aliases: aliases);
      return false;
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  /// Shows [error] under the matching fields when possible, else as a
  /// snackbar ([AuthSnackX.showAuthError]). Screens may override it for
  /// special codes.
  void showSubmitError(Object error, {Map<String, String> aliases = const {}}) {
    final fieldErrors = authFieldErrors(error, context.l10n, aliases: aliases);
    if (serverErrors.show(fieldErrors, formFields)) {
      setState(() => autovalidateMode = AutovalidateMode.onUserInteraction);
      formKey.currentState?.validate();
    } else {
      context.showAuthError(error);
    }
  }
}
