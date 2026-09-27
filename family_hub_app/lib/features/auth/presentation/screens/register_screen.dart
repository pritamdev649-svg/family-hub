import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/settings/settings_controller.dart';
import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/auth/application/auth_actions.dart';
import 'package:family_hub/features/auth/application/auth_errors.dart';
import 'package:family_hub/features/auth/domain/family_draft.dart';
import 'package:family_hub/features/auth/domain/register_args.dart';
import 'package:family_hub/features/auth/presentation/auth_labels.dart';
import 'package:family_hub/features/auth/presentation/auth_validators.dart';
import 'package:family_hub/features/auth/presentation/widgets/auth_form.dart';
import 'package:family_hub/features/auth/presentation/widgets/auth_layout.dart';
import 'package:family_hub/features/auth/presentation/widgets/consent_checkbox.dart';
import 'package:family_hub/features/auth/presentation/widgets/family_form.dart';
import 'package:family_hub/shared/data/auth_repository.dart'
    show RegisterRequest;

/// Sign-up (`POST /auth/register`) in two modes — `/register?mode=create`
/// starts a new family (the user becomes its admin), `?mode=join&code=…`
/// joins one with an invite code. The user can switch modes on the screen.
///
/// Submit stays disabled until the privacy policy / terms are accepted. The
/// account's language is the app's current language. After sign-up the
/// router moves on to email verification.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.args = const RegisterArgs()});

  final RegisterArgs args;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen>
    with AuthFormState {
  late RegisterMode _mode = widget.args.mode;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late final _inviteCode = TextEditingController(text: widget.args.inviteCode);
  late final FamilyFormController _family;
  DateTime? _dateOfBirth;
  bool _consent = false;

  bool get _isCreate => _mode == RegisterMode.create;

  @override
  Set<String> get formFields => {
    AuthField.name,
    AuthField.email,
    AuthField.password,
    AuthField.dateOfBirth,
    if (_isCreate) ...AuthField.familyFields else AuthField.inviteCode,
  };

  @override
  void initState() {
    super.initState();
    // First guess from the device locales (e.g. en_IN → India).
    _family = FamilyFormController(
      draft: FamilyDraft.fromLocales(ref.read(deviceLocalesProvider)),
    );
  }

  @override
  void didUpdateWidget(RegisterScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new link (e.g. another invite code) while the screen is open.
    if (widget.args != oldWidget.args) {
      serverErrors.clearAll(); // they were about the previous input
      _mode = widget.args.mode;
      if (widget.args.inviteCode.isNotEmpty) {
        _inviteCode.text = widget.args.inviteCode;
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _inviteCode.dispose();
    _family.dispose();
    super.dispose();
  }

  void _setMode(RegisterMode mode) {
    if (mode == _mode) return;
    serverErrors.clearAll();
    setState(() => _mode = mode);
  }

  /// Create mode knows the country, so the age gate can be checked before
  /// the round trip (join mode: the server checks the family's country).
  String? _ageError(DateTime? dateOfBirth) {
    if (!_isCreate) return null;
    final age = signupConsentAgeIfTooYoung(dateOfBirth, _family.draft.country);
    return age == null ? null : context.l10n.authSignupTooYoung(age);
  }

  RegisterRequest _request() {
    final locale = ref.read(resolvedLocaleProvider).languageCode;
    return _isCreate
        ? RegisterRequest.create(
            name: _name.text,
            email: _email.text,
            password: _password.text,
            locale: locale,
            consentAccepted: _consent,
            dateOfBirth: _dateOfBirth,
            family: _family.toRequest(),
          )
        : RegisterRequest.join(
            name: _name.text,
            email: _email.text,
            password: _password.text,
            locale: locale,
            consentAccepted: _consent,
            dateOfBirth: _dateOfBirth,
            inviteCode: _inviteCode.text,
          );
  }

  Future<void> _submit() async {
    if (!_consent) return;
    final actions = ref.read(authActionsProvider);
    await submit(() async {
      await actions.register(_request());
      TextInput.finishAutofillContext();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final busy = isSubmitting;
    final now = DateTime.now();

    return AuthScaffold(
      children: [
        AuthHeader(
          icon: _isCreate ? AuthIcons.createFamily : AuthIcons.joinFamily,
          accent: _isCreate ? AuthAccents.create : AuthAccents.join,
          title: _isCreate
              ? l10n.authRegisterCreateTitle
              : l10n.authRegisterJoinTitle,
          message: _isCreate
              ? l10n.authRegisterCreateSubtitle
              : l10n.authRegisterJoinSubtitle,
        ),
        AppGap.xl,
        FamilyModeSelector(value: _mode, onChanged: _setMode, enabled: !busy),
        AppGap.xl,
        Form(
          key: formKey,
          autovalidateMode: autovalidateMode,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthSectionCard(
                  title: l10n.authSectionAboutYou,
                  icon: AuthIcons.name,
                  accent: AuthAccents.aboutYou,
                  children: [
                    AppTextField(
                      controller: _name,
                      label: l10n.authNameLabel,
                      prefixIcon: AuthIcons.name,
                      autofillHints: const [AutofillHints.name],
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      enabled: !busy,
                      validator: serverErrors.guard(
                        AuthField.name,
                        AuthValidators.displayName(l10n),
                      ),
                      onChanged: (_) => fieldChanged(AuthField.name),
                    ),
                    AppGap.md,
                    AppTextField(
                      controller: _email,
                      label: l10n.authEmailLabel,
                      prefixIcon: AppIcons.email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      enabled: !busy,
                      validator: serverErrors.guard(
                        AuthField.email,
                        Validators.email(l10n),
                      ),
                      onChanged: (_) => fieldChanged(AuthField.email),
                    ),
                    AppGap.md,
                    AppTextField(
                      controller: _password,
                      label: l10n.authPasswordLabel,
                      hint: l10n.authPasswordHint,
                      prefixIcon: AppIcons.password,
                      obscure: true,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      enabled: !busy,
                      validator: serverErrors.guard(
                        AuthField.password,
                        AuthValidators.newPassword(l10n),
                      ),
                      onChanged: (_) => fieldChanged(AuthField.password),
                    ),
                    AppGap.md,
                    AppTextField(
                      controller: _confirm,
                      label: l10n.authConfirmPasswordLabel,
                      prefixIcon: AppIcons.password,
                      obscure: true,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      enabled: !busy,
                      validator: Validators.confirmPassword(l10n, _password),
                    ),
                    AppGap.md,
                    DatePickerField(
                      label: l10n.authDateOfBirthLabel,
                      value: _dateOfBirth,
                      firstDate: DatePickerField.defaultFirstDate,
                      lastDate: DateTime(now.year, now.month, now.day),
                      validator: (d) =>
                          serverErrors[AuthField.dateOfBirth] ?? _ageError(d),
                      onChanged: (d) {
                        fieldChanged(AuthField.dateOfBirth);
                        setState(() => _dateOfBirth = d);
                      },
                    ),
                  ],
                ),
                AppGap.lg,
                FamilyModeFields(
                  mode: _mode,
                  family: _family,
                  inviteCode: _inviteCode,
                  serverErrors: serverErrors,
                  onFieldChanged: fieldChanged,
                  enabled: !busy,
                ),
              ],
            ),
          ),
        ),
        AppGap.lg,
        ConsentCheckbox(
          value: _consent,
          onChanged: busy ? null : (v) => setState(() => _consent = v),
          helperText: _consent ? null : l10n.authConsentRequired,
        ),
        AppGap.xl,
        AppButton(
          label: l10n.authRegisterButton,
          icon: _isCreate ? AuthIcons.createFamily : AuthIcons.joinFamily,
          isLoading: busy,
          onPressed: _consent ? _submit : null,
        ),
        AppGap.md,
        AuthLinkRow(
          text: l10n.authHaveAccount,
          linkLabel: l10n.authLoginLink,
          // Carries the email over (e.g. right after "already exists").
          onPressed: busy
              ? null
              : () => context.pushReplacement(
                  AppRoutes.login,
                  extra: _email.text.trim(),
                ),
        ),
      ],
    );
  }
}
