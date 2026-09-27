import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/auth/domain/register_args.dart';
import 'package:family_hub/features/auth/presentation/auth_labels.dart';
import 'package:family_hub/features/auth/presentation/widgets/auth_layout.dart';

/// Keeps a text field's value sanitised by [sanitize] (the cursor goes to
/// the end, which is where typing / pasting a code happens).
class _SanitizingFormatter extends TextInputFormatter {
  _SanitizingFormatter(this.sanitize);

  final String Function(String input) sanitize;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = sanitize(newValue.text);
    if (text == newValue.text) return newValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Digits only (native digits converted), at most 6 — also for pasted
/// "123 456" or SMS / email autofill.
TextInputFormatter otpInputFormatter() =>
    _SanitizingFormatter(AuthInputs.sanitizeOtp);

/// Upper-case letters and digits only, at most 8 (`k7q2-m9xd` → `K7Q2M9XD`).
TextInputFormatter inviteCodeInputFormatter() =>
    _SanitizingFormatter(AuthInputs.sanitizeInviteCode);

/// The 6-digit one-time code (email verification, password reset), shown
/// as six rounded boxes with large digits.
///
/// One invisible text field spans the boxes, so typing, pasting a whole
/// code ("123 456"), SMS / email one-time-code autofill and screen readers
/// all work as with a normal field; the boxes only draw its text. The box
/// being typed into gets the focus ring, filled boxes a soft brand tint and
/// all boxes turn red with the error message below while the code is
/// invalid. Digits always run left to right (also in Arabic).
class OtpCodeField extends StatefulWidget {
  const OtpCodeField({
    super.key,
    required this.controller,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.textInputAction = TextInputAction.done,
  });

  final TextEditingController controller;

  /// Defaults to [Validators.otp].
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final TextInputAction textInputAction;

  @override
  State<OtpCodeField> createState() => _OtpCodeFieldState();
}

class _OtpCodeFieldState extends State<OtpCodeField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final validator = widget.validator ?? Validators.otp(l10n);

    return FormField<String>(
      initialValue: widget.controller.text,
      enabled: widget.enabled,
      // The controller is the source of truth (screens clear it after a
      // resend), not the field's last reported value.
      validator: (_) => validator(widget.controller.text),
      builder: (field) {
        final errorText = field.errorText;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Text(
                l10n.authOtpLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            AppGap.sm,
            Directionality(
              textDirection: TextDirection.ltr,
              child: Stack(
                children: [
                  ExcludeSemantics(
                    child: ListenableBuilder(
                      listenable: Listenable.merge([widget.controller, _focus]),
                      builder: (context, _) => _OtpBoxes(
                        code: widget.controller.text,
                        focused: _focus.hasFocus,
                        hasError: errorText != null,
                        enabled: widget.enabled,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: MergeSemantics(
                      child: Semantics(
                        label: l10n.authOtpLabel,
                        child: _HiddenCodeInput(
                          controller: widget.controller,
                          focusNode: _focus,
                          enabled: widget.enabled,
                          textInputAction: widget.textInputAction,
                          onChanged: (value) {
                            field.didChange(value);
                            widget.onChanged?.call(value);
                          },
                          onSubmitted: widget.onSubmitted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (errorText != null) ...[
              AppGap.xs,
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: AppSpacing.md,
                ),
                child: Text(
                  errorText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The real (invisible) input under the boxes: no text, cursor, fill or
/// outline of its own; it only receives keys, pastes and autofill.
class _HiddenCodeInput extends StatelessWidget {
  const _HiddenCodeInput({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.textInputAction,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final TextInputAction textInputAction;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    const none = InputBorder.none;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      keyboardType: TextInputType.number,
      textInputAction: textInputAction,
      autofillHints: enabled ? const [AutofillHints.oneTimeCode] : null,
      inputFormatters: [otpInputFormatter()],
      autocorrect: false,
      enableSuggestions: false,
      showCursor: false,
      textDirection: TextDirection.ltr,
      style: const TextStyle(color: Colors.transparent),
      decoration: const InputDecoration(
        filled: false,
        isCollapsed: true,
        contentPadding: EdgeInsets.zero,
        border: none,
        enabledBorder: none,
        disabledBorder: none,
        focusedBorder: none,
        errorBorder: none,
        focusedErrorBorder: none,
        counterText: '',
      ),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onTapOutside: (_) => focusNode.unfocus(),
    );
  }
}

/// Six rounded boxes drawing [code].
class _OtpBoxes extends StatelessWidget {
  const _OtpBoxes({
    required this.code,
    required this.focused,
    required this.hasError,
    required this.enabled,
  });

  final String code;
  final bool focused;
  final bool hasError;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brand = context.accent(AuthAccents.brand);
    const length = Validators.otpLength;
    // The box the next digit goes into (the last one once complete).
    final active = code.length < length ? code.length : length - 1;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppDurations.fast;
    final digitStyle = theme.textTheme.headlineMedium?.merge(
      AppTypography.tabularFigures,
    );
    // Same soft fill as the app's (borderless) text fields.
    final emptyFill = authSoftFill(context, enabled: enabled);

    return Row(
      children: [
        for (var i = 0; i < length; i++) ...[
          if (i > 0) AppGap.hSm,
          Expanded(
            child: Builder(
              builder: (context) {
                final digit = i < code.length ? code[i] : null;
                final isActive = focused && enabled && i == active;
                final Color fill;
                final Color textColor;
                if (hasError) {
                  fill = scheme.errorContainer;
                  textColor = scheme.onErrorContainer;
                } else if (digit != null) {
                  fill = brand.container;
                  textColor = brand.onContainer;
                } else {
                  fill = emptyFill;
                  textColor = scheme.onSurface;
                }
                return AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.md,
                    horizontal: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: AppRadius.brLg,
                    // Always present (transparent when inactive) so the
                    // focus ring never shifts the digit.
                    border: Border.all(
                      color: isActive
                          ? (hasError ? scheme.error : scheme.primary)
                          : Colors.transparent,
                      width: AppSizes.borderFocused,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    // An invisible "0" keeps empty boxes as tall as filled
                    // ones at every text size.
                    child: Text(
                      digit ?? '0',
                      style: digitStyle?.copyWith(
                        color: digit == null ? Colors.transparent : textColor,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// The family invite code field with its help text.
class InviteCodeField extends StatelessWidget {
  const InviteCodeField({
    super.key,
    required this.controller,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.textInputAction = TextInputAction.next,
  });

  final TextEditingController controller;

  /// Defaults to [Validators.inviteCode].
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: controller,
          label: l10n.authInviteCodeLabel,
          hint: l10n.authInviteCodeHint,
          prefixIcon: AuthIcons.inviteCode,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [inviteCodeInputFormatter()],
          validator: validator ?? Validators.inviteCode(l10n),
          textInputAction: textInputAction,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          enabled: enabled,
        ),
        AppGap.sm,
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.md,
          ),
          child: Text(
            l10n.authInviteCodeHelp,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
