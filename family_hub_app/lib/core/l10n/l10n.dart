import 'package:family_hub/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';

export 'package:family_hub/l10n/app_localizations.dart';

/// `context.l10n.someKey` — the only way widgets read user-visible text.
///
/// Strings come from `l10n_parts/<feature>.arb` (merged into
/// `lib/l10n/app_en.arb` by `dart run tool/l10n.dart`).
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
