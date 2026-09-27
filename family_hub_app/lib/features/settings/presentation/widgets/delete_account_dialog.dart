import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/error_messages.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/settings/application/settings_actions.dart';
import 'package:family_hub/features/settings/presentation/settings_navigation.dart';

/// Outcome of [showDeleteAccountDialog] (`null` = cancelled).
enum DeleteAccountOutcome {
  /// The account was deleted and the session signed out.
  deleted,

  /// The server refused with `LAST_ADMIN`.
  lastAdmin,
}

/// Explains what deleting the account removes, asks for the password and
/// performs `DELETE /me`. A wrong password or a network error is shown inside
/// the dialog, so the member can correct it without starting over.
Future<DeleteAccountOutcome?> showDeleteAccountDialog(BuildContext context) =>
    showDialog<DeleteAccountOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const DeleteAccountDialog(),
    );

class DeleteAccountDialog extends ConsumerStatefulWidget {
  const DeleteAccountDialog({super.key});

  @override
  ConsumerState<DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<DeleteAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _busy = false;
  String? _passwordError;
  String? _error;

  /// After the first submit the field re-validates while typing, so a
  /// "wrong password" message disappears as soon as it is edited.
  bool _submitted = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _passwordError = null;
      _error = null;
      _submitted = true;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = context.l10n;
    // Stays mounted when the router replaces the pages after sign-out.
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    setState(() => _busy = true);
    try {
      await ref.read(settingsActionsProvider).deleteAccount(_password.text);
      if (rootContext.mounted) {
        rootContext.showSuccess(l10n.settingsDeleteAccountDone);
      }
      if (mounted) Navigator.of(context).pop(DeleteAccountOutcome.deleted);
    } catch (e) {
      if (!mounted) return;
      if (isLastAdminError(e)) {
        Navigator.of(context).pop(DeleteAccountOutcome.lastAdmin);
        return;
      }
      setState(() {
        _busy = false;
        if (isInvalidCredentialsError(e)) {
          _passwordError = l10n.settingsDeleteAccountWrongPassword;
        } else {
          _error = localizedErrorMessage(e, l10n);
        }
      });
      _formKey.currentState?.validate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        icon: Icon(AppIcons.warning, color: scheme.error),
        title: Text(l10n.settingsDeleteAccountTitle),
        content: Form(
          key: _formKey,
          autovalidateMode: _submitted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.settingsDeleteAccountMessage),
              AppGap.lg,
              AutofillGroup(
                child: AppTextField(
                  controller: _password,
                  label: l10n.settingsDeleteAccountPassword,
                  obscure: true,
                  enabled: !_busy,
                  prefixIcon: AppIcons.password,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  onChanged: (_) {
                    if (_passwordError != null || _error != null) {
                      setState(() {
                        _passwordError = null;
                        _error = null;
                      });
                    }
                  },
                  validator: Validators.compose([
                    Validators.required(l10n),
                    (_) => _passwordError,
                  ]),
                ),
              ),
              if (_error != null) ...[
                AppGap.md,
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          AppButton(
            label: l10n.settingsDeleteAccountConfirm,
            variant: AppButtonVariant.danger,
            expand: false,
            isLoading: _busy,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
