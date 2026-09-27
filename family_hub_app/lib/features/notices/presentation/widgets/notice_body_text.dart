import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/features/notices/presentation/widgets/notice_style.dart';

/// Notice text that collapses to [collapsedMaxLines] lines with a
/// "Read more" / "Show less" toggle — shown only when the text really
/// overflows at the current width, text scale, font and direction.
///
/// Screen readers always get the whole text (a truncated [Text] still
/// exposes its full string to accessibility services).
class NoticeBodyText extends StatefulWidget {
  const NoticeBodyText({
    super.key,
    required this.text,
    this.collapsedMaxLines = 6,
    this.style,
  });

  final String text;
  final int collapsedMaxLines;

  /// Defaults to `textTheme.bodyMedium`.
  final TextStyle? style;

  @override
  State<NoticeBodyText> createState() => _NoticeBodyTextState();
}

class _NoticeBodyTextState extends State<NoticeBodyText> {
  bool _expanded = false;

  @override
  void didUpdateWidget(NoticeBodyText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Edited text starts collapsed again.
    if (oldWidget.text != widget.text) _expanded = false;
  }

  bool _overflows(BuildContext context, TextStyle style, double maxWidth) {
    if (!maxWidth.isFinite) return false;
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: style),
      maxLines: widget.collapsedMaxLines,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      textHeightBehavior: DefaultTextHeightBehavior.maybeOf(context),
    )..layout(maxWidth: maxWidth);
    final exceeded = painter.didExceedMaxLines;
    painter.dispose();
    return exceeded;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final style = DefaultTextStyle.of(
      context,
    ).style.merge(widget.style ?? Theme.of(context).textTheme.bodyMedium);

    return LayoutBuilder(
      builder: (context, constraints) {
        final overflows = _overflows(context, style, constraints.maxWidth);
        final collapsed = overflows && !_expanded;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: AppDurations.normal,
              curve: Curves.easeInOut,
              alignment: AlignmentDirectional.topStart,
              child: Text(
                widget.text,
                style: style,
                maxLines: collapsed ? widget.collapsedMaxLines : null,
                overflow: collapsed ? TextOverflow.ellipsis : null,
              ),
            ),
            if (overflows)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  style: TextButton.styleFrom(
                    foregroundColor: context
                        .accent(NoticeStyle.accent)
                        .foreground,
                    // Aligned with the text above; the button keeps its
                    // 48 dp tap target.
                    padding: EdgeInsets.zero,
                  ),
                  child: Text(
                    _expanded ? l10n.noticesShowLess : l10n.noticesReadMore,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
