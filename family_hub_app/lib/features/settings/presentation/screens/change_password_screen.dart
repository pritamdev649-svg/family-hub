import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/settings/application/settings_actions.dart';
import 'package:family_hub/features/settings/presentation/settings_navigation.dart';
import 'package:family_hub/features/settings/presentation/widgets/settings_page.dart';

/// Current + new + confirm password → `POST /auth/change-password`.
/// A wrong current password is shown on that field.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  /// Accent of this screen (matches its row on the More tab).
  static const AppAccent accent = AppAccent.indigo;

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _currentError;

  /// After the first submit fields re-validate while the user edits them,
  /// so a fixed error (e.g. the wrong current password) disappears at once.
  bool _submitted = false;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _currentError = null;
      _submitted = true;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = context.l10n;
    setState(() => _saving = true);
    try {
      await ref
          .read(settingsActionsProvider)
          .changePassword(
            currentPassword: _current.text,
            newPassword: _new.text,
          );
      if (!mounted) return;
      TextInput.finishAutofillContext();
      context.showSuccess(l10n.settingsPasswordChanged);
      closeSettingsScreen(context);
    } catch (e) {
      if (!mounted) return;
      if (isInvalidCredentialsError(e)) {
        setState(() => _currentError = l10n.settingsPasswordWrongCurrent);
        _formKey.currentState?.validate();
      } else {
        context.showError(e);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    const accent = ChangePasswordScreen.accent;

    return SettingsPage(
      title: l10n.settingsChangePassword,
      child: Form(
        key: _formKey,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: AutofillGroup(
          child: SettingsListView(
            children: [
              SectionHeader(
                title: l10n.settingsPasswordSectionCurrent,
                icon: AppIcons.password,
                accent: accent,
              ),
              AppCard(
                child: AppTextField(
                  controller: _current,
                  label: l10n.settingsPasswordCurrent,
                  obscure: true,
                  prefixIcon: AppIcons.password,
                  enabled: !_saving,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.password],
                  onChanged: (_) {
                    if (_currentError != null) {
                      setState(() => _currentError = null);
                    }
                  },
                  validator: Validators.compose([
                    Validators.required(l10n),
                    (_) => _currentError,
                  ]),
                ),
              ),
              AppGap.xl,
              SectionHeader(
                title: l10n.settingsPasswordSectionNew,
                icon: AppIcons.security,
                accent: accent,
              ),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppTextField(
                      controller: _new,
                      label: l10n.settingsPasswordNew,
                      obscure: true,
                      prefixIcon: AppIcons.security,
                      enabled: !_saving,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                      validator: Validators.compose([
                        Validators.password(l10n),
                        (v) => v != null && v.isNotEmpty && v == _current.text
                            ? l10n.settingsPasswordSameAsCurrent
                            : null,
                      ]),
                    ),
                    AppGap.sm,
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          AppIcons.info,
                          size: AppSizes.iconXs,
                          color: context.accent(accent).foreground,
                        ),
                        AppGap.hXs,
                        Expanded(
                          child: Text(
                            l10n.settingsPasswordRules,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    AppGap.lg,
                    AppTextField(
                      controller: _confirm,
                      label: l10n.settingsPasswordConfirm,
                      obscure: true,
                      prefixIcon: AppIcons.security,
                      enabled: !_saving,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      onSubmitted: (_) => _submit(),
                      validator: Validators.confirmPassword(l10n, _new),
                    ),
                  ],
                ),
              ),
              AppGap.xl,
              AppButton(
                label: l10n.settingsChangePassword,
                icon: AppIcons.password,
                isLoading: _saving,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
