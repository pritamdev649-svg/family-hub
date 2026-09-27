import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/config/app_config.dart';
import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/network/mock/mock_seed.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/auth/application/auth_cooldown.dart';
import 'package:family_hub/features/auth/application/auth_errors.dart';
import 'package:family_hub/features/auth/application/forgot_password_controller.dart';
import 'package:family_hub/features/auth/presentation/auth_labels.dart';
import 'package:family_hub/features/auth/presentation/auth_validators.dart';
import 'package:family_hub/features/auth/presentation/widgets/auth_code_fields.dart';
import 'package:family_hub/features/auth/presentation/widgets/auth_form.dart';
import 'package:family_hub/features/auth/presentation/widgets/auth_layout.dart';
import 'package:family_hub/features/auth/presentation/widgets/cooldown_builder.dart';

/// Forgot password in two steps: email → `POST /auth/forgot-password`, then
/// code + new password → `POST /auth/reset-password`. On success it returns
/// to the log-in screen (handing back the email) with a confirmation.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});

  /// Email typed on the log-in screen, if any.
  final String? initialEmail;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen>
    with AuthFormState {
  late final _email = TextEditingController(text: widget.initialEmail ?? '');
  final _otp = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  ForgotPasswordController get _controller =>
      ref.read(forgotPasswordControllerProvider.notifier);

  @override
  Set<String> get formFields =>
      ref.read(forgotPasswordControllerProvider).step ==
          ForgotPasswordStep.email
      ? const {AuthField.email}
      : const {AuthField.otp, AuthField.newPassword};

  @override
  void dispose() {
    _email.dispose();
    _otp.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final controller = _controller;
    final sent = await submit(() => controller.requestCode(_email.text));
    if (sent && mounted) {
      _otp.clear();
      setState(() => autovalidateMode = AutovalidateMode.disabled);
    }
  }

  Future<void> _resend() async {
    try {
      await _controller.resendCode();
      if (!mounted) return;
      _otp.clear();
      serverErrors.clear(AuthField.otp);
      context.showSuccess(context.l10n.authCodeSent);
    } catch (e) {
      if (mounted) context.showAuthError(e);
    }
  }

  Future<void> _reset() async {
    final controller = _controller;
    final email = ref.read(forgotPasswordControllerProvider).email;
    final ok = await submit(
      () =>
          controller.resetPassword(otp: _otp.text, newPassword: _password.text),
    );
    if (!ok || !mounted) return;
    TextInput.finishAutofillContext();
    context.showSuccess(context.l10n.authPasswordResetSuccess);
    if (context.canPop()) {
      context.pop(email);
    } else {
      // Opened directly (link / restored route): log-in with the email.
      context.go(AppRoutes.login, extra: email);
    }
  }

  void _changeEmail() {
    serverErrors.clearAll();
    setState(() => autovalidateMode = AutovalidateMode.disabled);
    _controller.changeEmail();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(forgotPasswordControllerProvider);
    final isEmailStep = state.step == ForgotPasswordStep.email;

    return AuthScaffold(
      children: [
        AuthHeader(
          icon: AuthIcons.resetPassword,
          title: l10n.authForgotTitle,
          message: isEmailStep
              ? l10n.authForgotEmailMessage
              : l10n.authForgotCodeMessage(state.email),
        ),
        AppGap.xl,
        if (!isEmailStep && AppConfig.useMockApi) ...[
          AuthMessageBanner(
            kind: AuthBannerKind.info,
            accent: AuthAccents.demo,
            icon: AuthIcons.demo,
            message: l10n.authDemoOtpHint(MockSeed.otp),
          ),
          AppGap.lg,
        ],
        Form(
          key: formKey,
          autovalidateMode: autovalidateMode,
          child: AutofillGroup(
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : AppDurations.normal,
              child: isEmailStep
                  ? _EmailStep(
                      key: const ValueKey(ForgotPasswordStep.email),
                      email: _email,
                      busy: state.isBusy,
                      validator: serverErrors.guard(
                        AuthField.email,
                        Validators.email(l10n),
                      ),
                      onChanged: () => fieldChanged(AuthField.email),
                      onSubmit: _sendCode,
                    )
                  : _ResetStep(
                      key: const ValueKey(ForgotPasswordStep.reset),
                      otp: _otp,
                      password: _password,
                      confirm: _confirm,
                      busy: state.isBusy,
                      serverErrors: serverErrors,
                      onFieldChanged: fieldChanged,
                      onSubmit: _reset,
                      resend: ResendCodeButton(
                        cooldownKey: AuthCooldownKeys.passwordReset(
                          state.email,
                        ),
                        isLoading: state.isSending,
                        onPressed: state.isBusy ? null : _resend,
                      ),
                    ),
            ),
          ),
        ),
        AppGap.xl,
        if (isEmailStep)
          AppButton(
            label: l10n.authSendCode,
            icon: AppIcons.email,
            isLoading: state.isSending,
            onPressed: state.isBusy ? null : _sendCode,
          )
        else ...[
          AppButton(
            label: l10n.authResetButton,
            icon: AppIcons.check,
            isLoading: state.isResetting,
            onPressed: state.isBusy ? null : _reset,
          ),
          AppGap.sm,
          AppButton(
            label: l10n.authChangeEmail,
            icon: AppIcons.edit,
            variant: AppButtonVariant.text,
            onPressed: state.isBusy ? null : _changeEmail,
          ),
        ],
      ],
    );
  }
}

class _EmailStep extends StatelessWidget {
  const _EmailStep({
    super.key,
    required this.email,
    required this.busy,
    required this.validator,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController email;
  final bool busy;
  final FormFieldValidator<String> validator;
  final VoidCallback onChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AuthSectionCard(
      children: [
        AppTextField(
          controller: email,
          label: l10n.authEmailLabel,
          prefixIcon: AppIcons.email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.done,
          enabled: !busy,
          validator: validator,
          onChanged: (_) => onChanged(),
          onSubmitted: (_) => onSubmit(),
        ),
      ],
    );
  }
}

class _ResetStep extends StatelessWidget {
  const _ResetStep({
    super.key,
    required this.otp,
    required this.password,
    required this.confirm,
    required this.busy,
    required this.serverErrors,
    required this.onFieldChanged,
    required this.onSubmit,
    required this.resend,
  });

  final TextEditingController otp;
  final TextEditingController password;
  final TextEditingController confirm;
  final bool busy;
  final ServerFieldErrors serverErrors;
  final ValueChanged<String> onFieldChanged;
  final VoidCallback onSubmit;

  /// The "resend code" pill under the code.
  final Widget resend;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AuthSectionCard(
      children: [
        OtpCodeField(
          controller: otp,
          enabled: !busy,
          textInputAction: TextInputAction.next,
          validator: serverErrors.guard(AuthField.otp, Validators.otp(l10n)),
          onChanged: (_) => onFieldChanged(AuthField.otp),
        ),
        AppGap.lg,
        resend,
        AppGap.lg,
        AppTextField(
          controller: password,
          label: l10n.authNewPasswordLabel,
          hint: l10n.authPasswordHint,
          prefixIcon: AppIcons.password,
          obscure: true,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.next,
          enabled: !busy,
          validator: serverErrors.guard(
            AuthField.newPassword,
            AuthValidators.newPassword(l10n),
          ),
          onChanged: (_) => onFieldChanged(AuthField.newPassword),
        ),
        AppGap.md,
        AppTextField(
          controller: confirm,
          label: l10n.authConfirmNewPasswordLabel,
          prefixIcon: AppIcons.password,
          obscure: true,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.done,
          enabled: !busy,
          validator: Validators.confirmPassword(l10n, password),
          onSubmitted: (_) => onSubmit(),
        ),
      ],
    );
  }
}
