import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:family_hub/core/config/app_config.dart';
import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/url_actions.dart';
import 'package:family_hub/core/widgets/widgets.dart';

/// Sign-up consent (docs/08-COMPLIANCE.md §3 row 1) on its own card: an
/// unticked checkbox whose text links to the privacy policy and the terms,
/// in body size with bold, underlined brand-coloured links. Tapping the
/// text (outside the links) toggles the box. The card turns a soft green
/// once accepted; [helperText] (e.g. "please accept…") shows under the text.
class ConsentCheckbox extends StatefulWidget {
  const ConsentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.helperText,
  });

  final bool value;

  /// `null` disables the checkbox (e.g. while submitting).
  final ValueChanged<bool>? onChanged;

  /// Hint under the consent text.
  final String? helperText;

  @override
  State<ConsentCheckbox> createState() => _ConsentCheckboxState();
}

class _ConsentCheckboxState extends State<ConsentCheckbox> {
  // Markers the placeholders are replaced with, so the links can sit
  // wherever each language puts them in the sentence.
  static const _privacyMarker = '\u0001';
  static const _termsMarker = '\u0002';

  late final TapGestureRecognizer _privacyTap = TapGestureRecognizer()
    ..onTap = () => _open(AppConfig.privacyPolicyUrl);
  late final TapGestureRecognizer _termsTap = TapGestureRecognizer()
    ..onTap = () => _open(AppConfig.termsUrl);

  @override
  void dispose() {
    _privacyTap.dispose();
    _termsTap.dispose();
    super.dispose();
  }

  Future<void> _open(String url) async {
    final opened = await UrlActions.openUrl(url);
    if (!opened && mounted) context.showInfo(context.l10n.authLinkOpenFailed);
  }

  void _toggle() => widget.onChanged?.call(!widget.value);

  List<InlineSpan> _spans(BuildContext context) {
    final l10n = context.l10n;
    final linkColor = context.accent(AppAccents.brand).foreground;
    final linkStyle = TextStyle(
      color: linkColor,
      fontWeight: AppTypography.bold,
      decoration: TextDecoration.underline,
      decorationColor: linkColor,
    );
    final text = l10n.authConsentAgree(_privacyMarker, _termsMarker);
    final spans = <InlineSpan>[];
    final buffer = StringBuffer();
    void flush() {
      if (buffer.isEmpty) return;
      spans.add(TextSpan(text: buffer.toString()));
      buffer.clear();
    }

    for (final char in text.characters) {
      if (char == _privacyMarker || char == _termsMarker) {
        flush();
        final privacy = char == _privacyMarker;
        spans.add(
          TextSpan(
            text: privacy ? l10n.authPrivacyPolicy : l10n.authTermsOfService,
            style: linkStyle,
            recognizer: privacy ? _privacyTap : _termsTap,
          ),
        );
      } else {
        buffer.write(char);
      }
    }
    flush();
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = widget.onChanged != null;
    final helper = widget.helperText;
    return AppCard(
      accent: widget.value ? AppAccents.success : null,
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: widget.value,
            // Screen readers announce what is being agreed to (the links
            // stay separately focusable in the text next to it).
            semanticLabel: context.l10n.authConsentAgree(
              context.l10n.authPrivacyPolicy,
              context.l10n.authTermsOfService,
            ),
            onChanged: enabled ? (v) => widget.onChanged!(v ?? false) : null,
          ),
          AppGap.hXs,
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: enabled ? _toggle : null,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(top: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(children: _spans(context)),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    if (helper != null) ...[
                      AppGap.xs,
                      Text(
                        helper,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
