import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/settings/settings_controller.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/auth/application/auth_actions.dart';
import 'package:family_hub/features/auth/application/auth_errors.dart';
import 'package:family_hub/features/auth/domain/family_draft.dart';
import 'package:family_hub/features/auth/domain/register_args.dart';
import 'package:family_hub/features/auth/presentation/auth_labels.dart';
import 'package:family_hub/features/auth/presentation/widgets/auth_form.dart';
import 'package:family_hub/features/auth/presentation/widgets/auth_layout.dart';
import 'package:family_hub/features/auth/presentation/widgets/family_form.dart';
import 'package:family_hub/features/auth/presentation/widgets/onboarding_session_watch.dart';
import 'package:family_hub/shared/session/session_controller.dart';

/// For a signed-in, verified user without a family (new account whose
/// family was deleted, or a member removed from their family): create a
/// family (`POST /family`) or join one with an invite code
/// (`POST /family/join`). The router opens the app once the session has a
/// family — also when that happened on another device (see
/// [OnboardingSessionWatch]).
///
/// `/family-setup?code=XXXX` (an invite link opened while signed in without
/// a family) starts in join mode with the code filled in.
class FamilySetupScreen extends ConsumerStatefulWidget {
  const FamilySetupScreen({super.key, this.args = const RegisterArgs()});

  /// Initial mode and invite code (same query as `/register`).
  final RegisterArgs args;

  @override
  ConsumerState<FamilySetupScreen> createState() => _FamilySetupScreenState();
}

class _FamilySetupScreenState extends ConsumerState<FamilySetupScreen>
    with AuthFormState, OnboardingSessionWatch {
  late RegisterMode _mode = widget.args.mode;
  late final _inviteCode = TextEditingController(text: widget.args.inviteCode);
  late final FamilyFormController _family;
  bool _signingOut = false;

  bool get _isCreate => _mode == RegisterMode.create;

  @override
  Set<String> get formFields =>
      _isCreate ? AuthField.familyFields : const {AuthField.inviteCode};

  @override
  void initState() {
    super.initState();
    // First guess from the device locales (e.g. en_IN → India).
    _family = FamilyFormController(
      draft: FamilyDraft.fromLocales(ref.read(deviceLocalesProvider)),
    );
  }

  @override
  void didUpdateWidget(FamilySetupScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Another invite link while the screen is open.
    if (widget.args != oldWidget.args && widget.args.inviteCode.isNotEmpty) {
      serverErrors.clearAll();
      _mode = widget.args.mode;
      _inviteCode.text = widget.args.inviteCode;
    }
  }

  @override
  void dispose() {
    _inviteCode.dispose();
    _family.dispose();
    super.dispose();
  }

  void _setMode(RegisterMode mode) {
    if (mode == _mode) return;
    serverErrors.clearAll();
    setState(() {
      _mode = mode;
      autovalidateMode = AutovalidateMode.disabled;
    });
  }

  Future<void> _submit() async {
    final actions = ref.read(authActionsProvider);
    final l10n = context.l10n;
    if (_isCreate) {
      final request = _family.toRequest();
      final ok = await submit(
        () => actions.createFamily(request),
        aliases: AuthField.createFamilyAliases,
      );
      if (ok && mounted) context.showSuccess(l10n.authFamilyCreated);
    } else {
      final code = _inviteCode.text;
      final ok = await submit(() => actions.joinFamily(code));
      if (!ok || !mounted) return;
      final family = ref.read(currentFamilyProvider)?.name ?? '';
      context.showSuccess(
        family.isEmpty ? l10n.authFamilyCreated : l10n.authFamilyJoined(family),
      );
    }
  }

  Future<void> _logout() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
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
      actions: [
        AuthBarButton(
          tooltip: l10n.authLogout,
          icon: AppIcons.logout,
          onPressed: busy ? null : _logout,
        ),
      ],
      children: [
        AuthHeader(
          icon: AppIcons.family,
          title: l10n.authFamilySetupTitle,
          message: l10n.authFamilySetupGreeting(user?.name ?? ''),
        ),
        if (user != null) ...[
          AppGap.md,
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _SignedInAsPill(email: user.email),
          ),
        ],
        AppGap.xl,
        FamilyModeSelector(value: _mode, onChanged: _setMode, enabled: !busy),
        AppGap.xl,
        Form(
          key: formKey,
          autovalidateMode: autovalidateMode,
          child: FamilyModeFields(
            mode: _mode,
            family: _family,
            inviteCode: _inviteCode,
            serverErrors: serverErrors,
            onFieldChanged: fieldChanged,
            enabled: !busy,
            onInviteSubmitted: (_) => _submit(),
          ),
        ),
        AppGap.xl,
        AppButton(
          label: _isCreate
              ? l10n.authCreateFamilyButton
              : l10n.authJoinFamilyButton,
          icon: _isCreate ? AuthIcons.createFamily : AuthIcons.joinFamily,
          isLoading: isSubmitting,
          onPressed: busy ? null : _submit,
        ),
        AppGap.md,
        AppButton(
          label: l10n.authLogout,
          icon: AppIcons.logout,
          variant: AppButtonVariant.text,
          isLoading: _signingOut,
          onPressed: busy ? null : _logout,
        ),
      ],
    );
  }
}

/// "Signed in as amit@example.com" on a soft pill, so the user knows which
/// account the new family will belong to.
class _SignedInAsPill extends StatelessWidget {
  const _SignedInAsPill({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shades = context.accent(AuthAccents.brand);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: shades.container,
        borderRadius: AppRadius.brPill,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(
                AppIcons.profile,
                size: AppSizes.iconXs,
                color: shades.onContainer,
              ),
            ),
            AppGap.hXs,
            Flexible(
              child: Text(
                context.l10n.authSignedInAs(email),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: shades.onContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
