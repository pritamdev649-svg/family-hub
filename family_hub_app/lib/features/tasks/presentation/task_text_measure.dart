import 'package:flutter/widgets.dart';

/// Width of the widest single word of [texts] in [style], at the current
/// text scale and direction.
///
/// Used by compact multi-column layouts (header counters, the view
/// switcher) to switch to a roomier arrangement before a word would have to
/// break in the middle — with large text or long words in some languages
/// (e.g. German).
double longestWordWidth(
  BuildContext context,
  Iterable<String> texts,
  TextStyle? style,
) {
  final painter = TextPainter(
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  );
  var widest = 0.0;
  for (final text in texts) {
    for (final word in text.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      painter
        ..text = TextSpan(text: word, style: style)
        ..layout();
      if (painter.width > widest) widest = painter.width;
    }
  }
  painter.dispose();
  return widest;
}
