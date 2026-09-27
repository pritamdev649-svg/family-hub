import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/utils/fmt.dart';
import 'package:family_hub/features/sos/domain/sos_alert.dart';
import 'package:family_hub/l10n/app_localizations.dart';

// Localised labels, icons and formatting of the SOS domain
// (docs/05-FLUTTER_GUIDE.md §6).

extension SosStatusLabels on SosStatus {
  String label(AppLocalizations l10n) => switch (this) {
    SosStatus.active => l10n.sosStatusActive,
    SosStatus.resolved => l10n.sosStatusResolved,
    SosStatus.expired => l10n.sosStatusExpired,
  };

  IconData get icon => switch (this) {
    SosStatus.active => AppIcons.sosAlert,
    SosStatus.resolved => AppIcons.success,
    SosStatus.expired => AppIcons.time,
  };

  /// Theme colour of the status (chips, icons).
  Color color(BuildContext context) => switch (this) {
    SosStatus.active => context.semanticColors.sos,
    SosStatus.resolved => context.semanticColors.success,
    SosStatus.expired => Theme.of(context).colorScheme.onSurfaceVariant,
  };
}

extension SosResolutionLabels on SosResolution {
  String label(AppLocalizations l10n) => switch (this) {
    SosResolution.safe => l10n.sosResolutionSafe,
    SosResolution.falseAlarm => l10n.sosResolutionFalseAlarm,
    SosResolution.helped => l10n.sosResolutionHelped,
  };

  IconData get icon => switch (this) {
    SosResolution.safe => AppIcons.safe,
    SosResolution.falseAlarm => AppIcons.falseAlarm,
    SosResolution.helped => AppIcons.helped,
  };
}

extension SosAlertLabels on SosAlert {
  /// The member's name, or "Former member" once they left the family.
  String displayName(AppLocalizations l10n) =>
      memberName ?? l10n.sosFormerMember;

  /// Chip text: the resolution for resolved alerts ("Safe"), else the
  /// status ("Active", "Ended").
  String statusLabel(AppLocalizations l10n, DateTime now) {
    final status = effectiveStatusAt(now);
    final r = resolution;
    if (status == SosStatus.resolved && r != null) return r.label(l10n);
    return status.label(l10n);
  }

  IconData statusIcon(DateTime now) {
    final status = effectiveStatusAt(now);
    final r = resolution;
    if (status == SosStatus.resolved && r != null) return r.icon;
    return status.icon;
  }
}

/// Time left in the live window as `m:ss` (e.g. `14:05`).
String sosFormatRemaining(Duration d) {
  final total = d.isNegative ? 0 : d.inSeconds;
  final minutes = total ~/ 60;
  final seconds = total % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// Relative time with second precision under a minute ("5 seconds ago"),
/// for live location updates; older moments use [Fmt.relative]. Small
/// clock differences between phone and server never show a future time.
String sosAgo(DateTime at, DateTime now, Fmt fmt, AppLocalizations l10n) {
  final diff = now.difference(at);
  if (diff.inSeconds.abs() < 60) {
    return l10n.sosSecondsAgo(diff.isNegative ? 0 : diff.inSeconds);
  }
  if (diff.isNegative) return l10n.sosSecondsAgo(0);
  return fmt.relative(at, l10n, now: now);
}

/// GPS accuracy in whole metres, localised digits / grouping.
String sosFormatMeters(double meters, Fmt fmt) => fmt.number(meters.round());

/// Coordinate with six decimals (≈ 10 cm), as used in map links.
String sosFormatCoordinate(double value) => value.toStringAsFixed(6);
