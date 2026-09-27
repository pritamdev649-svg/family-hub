import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/config/app_config.dart';
import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/error_messages.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/network/mock/mock_seed.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/auth/application/auth_actions.dart';
import 'package:family_hub/features/auth/application/auth_cooldown.dart';
import 'package:family_hub/features/auth/application/auth_errors.dart';
import 'package:family_hub/features/auth/application/session_expired_notice.dart';
import 'package:family_hub/features/auth/presentation/auth_labels.dart';
import 'package:family_hub/features/auth/presentation/widgets/auth_form.dart';
import 'package:family_hub/features/auth/presentation/widgets/auth_layout.dart';
import 'package:family_hub/features/auth/presentation/widgets/cooldown_builder.dart';

/// Email + password log-in (`POST /auth/login`). The router leaves this
/// screen by itself once the session changes (to verify-email, family setup
/// or home).
///
/// A wrong password shows one generic message (the server never says which
/// part was wrong); after too many failures the lockout is shown with a live
/// countdown and the button stays disabled until it ends.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.initialEmail});

  /// Pre-filled email (e.g. passed back from the reset-password flow).
  final String? initialEmail;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> with AuthFormState {
  late final _email = TextEditingController(text: widget.initialEmail ?? '');
  final _password = TextEditingController();

  /// Last `INVALID_CREDENTIALS` error, shown as a banner until the user
  /// edits the form.
  Object? _credentialsError;

  @override
  Set<String> get formFields => const {AuthField.email, AuthField.password};

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _edited(String field) {
    fieldChanged(field);
    // Rebuild: the lockout banner is per email, and the credentials error
    // goes away once the user corrects something.
    setState(() => _credentialsError = null);
  }

  Future<void> _submit() async {
    final actions = ref.read(authActionsProvider);
    final email = _email.text.trim();
    if (actions.loginLockSeconds(email) > 0) return;
    setState(() => _credentialsError = null);
    await submit(() async {
      await actions.login(email: email, password: _password.text);
      TextInput.finishAutofillContext();
    });
  }

  @override
  void showSubmitError(Object error, {Map<String, String> aliases = const {}}) {
    switch (authErrorCode(error)) {
      case ApiErrorCode.invalidCredentials:
        setState(() => _credentialsError = error);
      case ApiErrorCode.tooManyRequests:
        // The lockout banner (cooldown) explains it with a live countdown.
        setState(() => _credentialsError = null);
      default:
        super.showSubmitError(error, aliases: aliases);
    }
  }

  void _fillDemo() {
    _email.text = MockSeed.demoEmail;
    _password.text = MockSeed.demoPassword;
    serverErrors.clearAll();
    setState(() => _credentialsError = null);
  }

  Future<void> _forgotPassword() async {
    final email = await context.push<String>(
      AppRoutes.forgotPassword,
      extra: _email.text.trim(),
    );
    if (!mounted || email == null || email.isEmpty) return;
    _email.text = email;
    _password.clear();
    setState(() => _credentialsError = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sessionExpired = ref.watch(sessionExpiredNoticeProvider);
    final lockKey = AuthCooldownKeys.login(_email.text);

    return AuthScaffold(
      children: [
        AuthHeader(
          icon: AuthIcons.login,
          title: l10n.authLoginTitle,
          message: l10n.authLoginSubtitle,
        ),
        AppGap.xl,
        if (sessionExpired) ...[
          AuthMessageBanner(
            kind: AuthBannerKind.info,
            message: l10n.authSessionExpiredNotice,
          ),
          AppGap.lg,
        ],
        if (AppConfig.useMockApi) ...[
          AuthMessageBanner(
            kind: AuthBannerKind.info,
            accent: AuthAccents.demo,
            icon: AuthIcons.demo,
            title: l10n.authDemoTitle,
            message: l10n.authDemoLoginHint(
              MockSeed.demoEmail,
              MockSeed.demoPassword,
            ),
            action: AppButton(
              label: l10n.authDemoFill,
              variant: AppButtonVariant.text,
              expand: false,
              onPressed: isSubmitting ? null : _fillDemo,
            ),
          ),
          AppGap.lg,
        ],
        Form(
          key: formKey,
          autovalidateMode: autovalidateMode,
          child: AutofillGroup(
            child: AuthSectionCard(
              children: [
                AppTextField(
                  controller: _email,
                  label: l10n.authEmailLabel,
                  prefixIcon: AppIcons.email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [
                    AutofillHints.email,
                    AutofillHints.username,
                  ],
                  textInputAction: TextInputAction.next,
                  enabled: !isSubmitting,
                  validator: serverErrors.guard(
                    AuthField.email,
                    Validators.email(l10n),
                  ),
                  onChanged: (_) => _edited(AuthField.email),
                ),
                AppGap.md,
                AppTextField(
                  controller: _password,
                  label: l10n.authPasswordLabel,
                  prefixIcon: AppIcons.password,
                  obscure: true,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  enabled: !isSubmitting,
                  // Only "required": older accounts may predate the rules.
                  validator: serverErrors.guard(
                    AuthField.password,
                    Validators.required(l10n),
                  ),
                  onChanged: (_) => _edited(AuthField.password),
                  onSubmitted: (_) => _submit(),
                ),
                AppGap.xs,
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: AppButton(
                    label: l10n.authForgotPasswordLink,
                    variant: AppButtonVariant.text,
                    expand: false,
                    onPressed: isSubmitting ? null : _forgotPassword,
                  ),
                ),
              ],
            ),
          ),
        ),
        AppGap.xl,
        CooldownBuilder(
          cooldownKey: lockKey,
          builder: (context, lockedFor) {
            final error = _credentialsError;
            final String? message = lockedFor > 0
                ? l10n.authLoginLockedOut(formatWait(l10n, lockedFor))
                : error == null
                ? null
                : localizedErrorMessage(error, l10n);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (message != null) ...[
                  AuthMessageBanner(
                    message: message,
                    icon: lockedFor > 0 ? AppIcons.time : null,
                  ),
                  AppGap.lg,
                ],
                AppButton(
                  label: l10n.authLoginButton,
                  icon: AuthIcons.login,
                  isLoading: isSubmitting,
                  onPressed: lockedFor > 0 ? null : _submit,
                ),
              ],
            );
          },
        ),
        AppGap.lg,
        AuthLinkRow(
          text: l10n.authLoginNoAccount,
          linkLabel: l10n.authCreateAccountLink,
          onPressed: isSubmitting
              ? null
              : () => context.pushReplacement(
                  AppRoutes.register(mode: AppRoutes.registerModeCreate),
                ),
        ),
      ],
    );
  }
}
