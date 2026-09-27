import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/core/widgets/widgets.dart';

/// Keeps a money input well-formed while typing:
///
/// * only digits (ASCII and the native digits [Validators] understands),
///   grouping marks and the locale's decimal separator are accepted;
/// * at most one decimal separator ([decimalSeparator], `.` or `,`);
/// * at most [maxDecimals] digits after it;
/// * at most [maxLength] characters.
///
/// The final value is still checked by `Validators.amount` (range, grouping)
/// and read with `Validators.amountValue`.
class DecimalAmountInputFormatter extends TextInputFormatter {
  DecimalAmountInputFormatter({
    this.decimalSeparator = '.',
    this.maxDecimals = 2,
    this.maxLength = 20,
  }) : assert(decimalSeparator == '.' || decimalSeparator == ',');

  final String decimalSeparator;
  final int maxDecimals;
  final int maxLength;

  /// Arabic decimal separator `٫` counts as the decimal separator too.
  static const _arabicDecimal = '٫';

  String get _groupingSeparator => decimalSeparator == '.' ? ',' : '.';

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    if (text.length > maxLength) return oldValue;

    var decimals = -1; // -1 = no decimal separator seen yet
    var separators = 0;
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final isDecimal = char == decimalSeparator || char == _arabicDecimal;
      if (isDecimal) {
        separators++;
        if (separators > 1) return oldValue;
        decimals = 0;
        continue;
      }
      if (_isDigit(rune)) {
        if (decimals >= 0) {
          decimals++;
          if (decimals > maxDecimals) return oldValue;
        }
        continue;
      }
      final grouping =
          char == _groupingSeparator ||
          char == ' ' ||
          char == ' ' ||
          char == ' ' ||
          char == "'" ||
          char == '٬';
      // Grouping marks are only valid in the integer part.
      if (grouping && decimals < 0) continue;
      return oldValue;
    }
    return newValue;
  }

  static bool _isDigit(int rune) {
    final ascii = Validators.normalizeDigits(String.fromCharCode(rune));
    if (ascii.length != 1) return false;
    final unit = ascii.codeUnitAt(0);
    return unit >= 0x30 && unit <= 0x39;
  }

  /// [amount] as editable text for [decimalSeparator]: `1250` / `1250.5`
  /// (or `1250,5`). No grouping, at most 2 decimals.
  static String textFor(double amount, {String decimalSeparator = '.'}) {
    if (!amount.isFinite || amount <= 0) return '';
    final rounded = (amount * 100).roundToDouble() / 100;
    var text = rounded == rounded.truncateToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(2);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      text = text.replaceFirst(RegExp(r'\.$'), '');
    }
    return decimalSeparator == ',' ? text.replaceAll('.', ',') : text;
  }
}

/// Money input used by every ledger form: label with the family currency
/// symbol (from [Fmt]), decimal keyboard, [DecimalAmountInputFormatter] and
/// `Validators.amount`. Read the value with [amountFieldValue].
///
/// [AmountField.hero] is the big centred variant for the entry form: a
/// small caption, then the currency symbol and the amount in large bold
/// digits (in [accent]) centred as a group — no fill, no borders.
class AmountField extends ConsumerWidget {
  const AmountField({
    super.key,
    required this.controller,
    this.label,
    this.enabled = true,
    this.textInputAction = TextInputAction.next,
    this.onChanged,
    this.onSubmitted,
  }) : hero = false,
       accent = AppAccents.money;

  const AmountField.hero({
    super.key,
    required this.controller,
    this.label,
    this.enabled = true,
    this.textInputAction = TextInputAction.next,
    this.onChanged,
    this.onSubmitted,
    this.accent = AppAccents.money,
  }) : hero = true;

  final TextEditingController controller;

  /// Builds the label from the currency symbol; defaults to
  /// `ledgerFieldAmount(symbol)`.
  final String Function(String currencySymbol)? label;
  final bool enabled;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Big centred variant ([AmountField.hero]).
  final bool hero;

  /// Colour of the hero digits (income emerald / expense rose).
  final AppAccent accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final fmt = ref.watch(fmtProvider);
    final symbol = fmt.currencySymbol;
    final separator = Validators.decimalSeparatorFor(l10n.localeName);
    final labelText = label?.call(symbol) ?? l10n.ledgerFieldAmount(symbol);
    final formatters = [
      DecimalAmountInputFormatter(decimalSeparator: separator),
    ];
    const keyboard = TextInputType.numberWithOptions(decimal: true);

    if (!hero) {
      return AppTextField(
        controller: controller,
        label: labelText,
        enabled: enabled,
        keyboardType: keyboard,
        textInputAction: textInputAction,
        inputFormatters: formatters,
        validator: Validators.amount(l10n),
        onChanged: onChanged,
        onSubmitted: onSubmitted,
      );
    }

    return _HeroAmountInput(
      controller: controller,
      label: labelText,
      symbol: symbol,
      hint: fmt.number(0),
      enabled: enabled,
      accent: accent,
      keyboardType: keyboard,
      textInputAction: textInputAction,
      inputFormatters: formatters,
      validator: Validators.amount(l10n),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}

/// `Amount (₹)` caption, then `₹ 1,250.50` in big bold digits centred as a
/// group (the text field is exactly as wide as what was typed), then the
/// validation message. Tapping anywhere on the row focuses the input.
class _HeroAmountInput extends StatefulWidget {
  const _HeroAmountInput({
    required this.controller,
    required this.label,
    required this.symbol,
    required this.hint,
    required this.enabled,
    required this.accent,
    required this.keyboardType,
    required this.textInputAction,
    required this.inputFormatters,
    required this.validator,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String symbol;
  final String hint;
  final bool enabled;
  final AppAccent accent;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final List<TextInputFormatter> inputFormatters;
  final FormFieldValidator<String> validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_HeroAmountInput> createState() => _HeroAmountInputState();
}

class _HeroAmountInputState extends State<_HeroAmountInput> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // The caption takes the accent colour while the field is focused.
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shades = context.accent(widget.accent);
    final digits = theme.textTheme.displaySmall
        ?.merge(AppTypography.tabularFigures)
        .copyWith(fontWeight: AppTypography.extraBold);
    const none = InputBorder.none;

    return FormField<String>(
      // Validates what is typed (the controller), like a TextFormField.
      validator: (_) => widget.validator(widget.controller.text),
      builder: (field) {
        final error = field.errorText;
        final Color captionColor;
        if (error != null) {
          captionColor = scheme.error;
        } else if (_focus.hasFocus) {
          captionColor = shades.foreground;
        } else {
          captionColor = scheme.onSurfaceVariant;
        }
        return MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.label,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: captionColor,
                ),
              ),
              AppGap.xs,
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.enabled ? _focus.requestFocus : null,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AppSizes.minTapTarget,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      ExcludeSemantics(
                        child: Text(
                          widget.symbol,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      AppGap.hSm,
                      Flexible(
                        child: IntrinsicWidth(
                          child: TextField(
                            controller: widget.controller,
                            focusNode: _focus,
                            enabled: widget.enabled,
                            keyboardType: widget.keyboardType,
                            textInputAction: widget.textInputAction,
                            inputFormatters: widget.inputFormatters,
                            onChanged: (value) {
                              field.didChange(value);
                              widget.onChanged?.call(value);
                            },
                            onSubmitted: widget.onSubmitted,
                            onTapOutside: (_) => _focus.unfocus(),
                            style: digits?.copyWith(
                              color: widget.enabled
                                  ? shades.foreground
                                  : scheme.onSurfaceVariant,
                            ),
                            cursorColor: shades.base,
                            decoration: InputDecoration(
                              isCollapsed: true,
                              filled: false,
                              border: none,
                              enabledBorder: none,
                              disabledBorder: none,
                              focusedBorder: none,
                              errorBorder: none,
                              focusedErrorBorder: none,
                              hintText: widget.hint,
                              hintStyle: digits?.copyWith(
                                color: scheme.onSurfaceVariant.withValues(
                                  alpha: _hintOpacity,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (error != null) ...[
                AppGap.xs,
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Opacity of the "0" placeholder of [AmountField.hero].
const double _hintOpacity = 0.4;

/// Parsed value of an [AmountField] (null when invalid).
double? amountFieldValue(AppLocalizations l10n, String text) =>
    Validators.amountValue(l10n, text);
