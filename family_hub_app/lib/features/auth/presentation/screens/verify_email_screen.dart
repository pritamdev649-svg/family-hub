import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/config/app_config.dart';
import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/network/mock/mock_seed.dart';
import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/auth/application/auth_actions.dart';
import 'package:family_hub/features/auth/application/auth_cooldown.dart';
import 'package:family_hub/features/auth/application/auth_errors.dart';
import 'package:family_hub/features/auth/presentation/auth_labels.dart';
import 'package:family_hub/features/auth/presentation/widgets/auth_code_fields.dart';
import 'package:family_hub/features/auth/presentation/widgets/auth_form.dart';
import 'package:family_hub/features/auth/presentation/widgets/auth_layout.dart';
import 'package:family_hub/features/auth/presentation/widgets/cooldown_builder.dart';
import 'package:family_hub/features/auth/presentation/widgets/onboarding_session_watch.dart';
import 'package:family_hub/shared/session/session_controller.dart';

/// Email verification with the 6-digit code (`POST /auth/verify-email`),
/// shown by the router while the signed-in user's email is unverified.
///
/// The code is submitted automatically once 6 digits are entered (typed,
/// pasted or autofilled). "Resend code" honours the 60 s cooldown and the
/// server's `retryAfterSeconds`; "Use another account" signs out. When the
/// email was verified on another device, resend (or returning to the app)
/// reloads the session and the router moves on.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen>
    with AuthFormState, OnboardingSessionWatch {
  final _otp = TextEditingController();
  bool _resending = false;
  bool _signingOut = false;

  @override
  Set<String> get formFields => const {AuthField.otp};

  @override
  void dispose() {
    _otp.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final actions = ref.read(authActionsProvider);
    final ok = await submit(() => actions.verifyEmail(_otp.text));
    if (ok && mounted) context.showSuccess(context.l10n.authEmailVerified);
  }

  void _otpChanged(String value) {
    fieldChanged(AuthField.otp);
    if (value.length == Validators.otpLength && !isSubmitting) _verify();
  }

  Future<void> _resend() async {
    if (_resending) return;
    setState(() => _resending = true);
    try {
      final sent = await ref.read(authActionsProvider).resendVerification();
      if (!mounted) return;
      _otp.clear();
      serverErrors.clearAll();
      // Not sent = already verified (e.g. on another device): the session
      // was reloaded and the router is moving on.
      context.showSuccess(
        sent ? context.l10n.authCodeSent : context.l10n.authEmailVerified,
      );
    } catch (e) {
      // On 429 the button additionally counts down the server's wait.
      if (mounted) context.showAuthError(e);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _useAnotherAccount() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    // Never throws; the router then shows the welcome screen.
    await ref.read(authActionsProvider).logout();
    if (mounted) setState(() => _signingOut = false);
  }

  @override
  Widget build(BuildContext context) {
    watchOnboardingSession();
    final l10n = context.l10n;
    final user = ref.watch(currentUserProvider);
    final busy = isSubmitting || _signingOut;

    return AuthScaffold(
      children: [
        AuthHeader(
          icon: AuthIcons.verifyEmail,
          title: l10n.authVerifyTitle,
          message: l10n.authVerifyMessage(user?.email ?? ''),
        ),
        AppGap.xl,
        if (AppConfig.useMockApi) ...[
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
            child: AuthSectionCard(
              children: [
                OtpCodeField(
                  controller: _otp,
                  enabled: !busy,
                  validator: serverErrors.guard(
                    AuthField.otp,
                    Validators.otp(l10n),
                  ),
                  onChanged: _otpChanged,
                  onSubmitted: (_) => _verify(),
                ),
                if (user != null) ...[
                  AppGap.lg,
                  ResendCodeButton(
                    cooldownKey: AuthCooldownKeys.verifyEmail(user.id),
                    isLoading: _resending,
                    onPressed: busy ? null : _resend,
                  ),
                ],
              ],
            ),
          ),
        ),
        AppGap.xl,
        AppButton(
          label: l10n.authVerifyButton,
          icon: AppIcons.check,
          isLoading: isSubmitting,
          onPressed: busy ? null : _verify,
        ),
        AppGap.md,
        AppButton(
          label: l10n.authUseAnotherAccount,
          icon: AppIcons.logout,
          variant: AppButtonVariant.secondary,
          isLoading: _signingOut,
          onPressed: busy ? null : _useAnotherAccount,
        ),
      ],
    );
  }
}
