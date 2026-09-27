import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/services/services_l10n.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/sos/application/sos_controller.dart';

/// Tells the member how their SOS went (snackbar + haptic confirmation).
void showSosSendOutcome(BuildContext context, SosSendOutcome outcome) {
  final l10n = context.l10n;
  switch (outcome.result) {
    case SosSendResult.cancelled:
      context.showInfo(l10n.sosCancelled);
    case SosSendResult.ignored:
      break;
    case SosSendResult.failed:
      HapticFeedback.vibrate();
      context.showError(outcome.error ?? const Object());
    case SosSendResult.sent:
      HapticFeedback.heavyImpact();
      switch (outcome.note) {
        case SosLocationNote.none:
          context.showSuccess(l10n.sosSent);
        case SosLocationNote.sharingOff:
          context.showInfo(l10n.sosSentWithoutLocation);
        case SosLocationNote.sharingUpdateFailed:
          context.showInfo(l10n.sosSentSharingUpdateFailed);
        case SosLocationNote.permissionMissing:
          final reason = outcome.permission?.message(l10n) ?? '';
          context.showInfo(
            reason.isEmpty
                ? l10n.sosSentWithoutLocation
                : l10n.sosSentPermissionMissing(reason),
          );
      }
  }
}

/// Snackbar after a resolve ("I am okay", "False alarm", "Mark as helped").
///
/// The server keeps the **first** resolution (a repeat is idempotent), so
/// when [result] was ended differently meanwhile — e.g. the owner said "I am
/// okay" while an admin tapped "Mark as helped" — the member is told that
/// the alert had already ended instead of a confirmation of [resolution].
void showSosResolved(
  BuildContext context,
  SosResolution resolution, {
  SosAlert? result,
}) {
  final l10n = context.l10n;
  if (result != null && result.resolution != resolution) {
    context.showInfo(l10n.errorSosNotActive);
    return;
  }
  switch (resolution) {
    case SosResolution.safe:
      context.showSuccess(l10n.sosResolvedSafe);
    case SosResolution.falseAlarm:
      context.showSuccess(l10n.sosResolvedFalseAlarm);
    case SosResolution.helped:
      context.showSuccess(l10n.sosMarkedHelped);
  }
}
