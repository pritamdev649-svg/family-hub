import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';

/// Standard form text field (filled, rounded — styled by the theme).
///
/// * [obscure] fields get a show / hide toggle and disable autocorrect and
///   suggestions.
/// * Either pass a [controller] **or** an [initialValue]; when both are given
///   the controller wins.
/// * `maxLines > 1` fields default to a multiline keyboard and grow from one
///   line up to [maxLines].
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.controller,
    required this.label,
    this.hint,
    this.validator,
    this.keyboardType,
    this.obscure = false,
    this.prefixIcon,
    this.maxLines = 1,
    this.maxLength,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.autofillHints,
    this.enabled = true,
    this.initialValue,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController? controller;
  final String label;
  final String? hint;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final bool obscure;
  final IconData? prefixIcon;
  final int maxLines;
  final int? maxLength;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final Iterable<String>? autofillHints;
  final bool enabled;
  final String? initialValue;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _hidden = true;

  @override
  void didUpdateWidget(AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.obscure && oldWidget.obscure) _hidden = true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final obscure = widget.obscure;
    // Obscured text can never span multiple lines.
    final maxLines = obscure ? 1 : (widget.maxLines < 1 ? 1 : widget.maxLines);
    final multiline = maxLines > 1;

    final keyboardType =
        widget.keyboardType ??
        (multiline
            ? TextInputType.multiline
            : obscure
            ? TextInputType.visiblePassword
            : TextInputType.text);

    final textInputAction =
        widget.textInputAction ?? (multiline ? TextInputAction.newline : null);

    Widget? suffix;
    if (obscure) {
      final tooltip = _hidden
          ? l10n.commonShowPassword
          : l10n.commonHidePassword;
      suffix = IconButton(
        tooltip: tooltip,
        onPressed: widget.enabled
            ? () => setState(() => _hidden = !_hidden)
            : null,
        icon: AnimatedSwitcher(
          duration: AppDurations.fast,
          child: Icon(
            _hidden ? AppIcons.visibility : AppIcons.visibilityOff,
            key: ValueKey<bool>(_hidden),
          ),
        ),
      );
    }

    return TextFormField(
      controller: widget.controller,
      initialValue: widget.controller == null ? widget.initialValue : null,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        prefixIcon: widget.prefixIcon == null ? null : Icon(widget.prefixIcon),
        suffixIcon: suffix,
      ),
      validator: widget.validator,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscure && _hidden,
      autocorrect: !obscure,
      enableSuggestions: !obscure,
      minLines: 1,
      maxLines: maxLines,
      maxLength: widget.maxLength,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      onFieldSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      autofillHints: widget.enabled ? widget.autofillHints : null,
      enabled: widget.enabled,
      inputFormatters: widget.inputFormatters,
      textCapitalization: widget.textCapitalization,
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
    );
  }
}
