import 'package:flutter/widgets.dart';

import 'package:family_hub/core/l10n/error_messages.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/widgets/widgets.dart';

/// What a failed ledger call was about, for "no longer exists" messages.
enum LedgerSubject { entry, goal, other }

/// The [ApiException] behind [error] (Riverpod wrappers unwrapped), or null.
ApiException? ledgerApiError(Object? error) {
  if (error == null) return null;
  final e = unwrapProviderError(error);
  return e is ApiException ? e : null;
}

/// Whether [error] is a `404 NOT_FOUND` (deleted, or never visible).
bool isLedgerNotFound(Object? error) =>
    ledgerApiError(error)?.isNotFound ?? false;

/// Text for ledger failures that the generic `localizedErrorMessage` cannot
/// explain well (a generic "check the highlighted fields" when nothing is
/// highlighted, a bare "not found"…), or null to use the generic message.
///
/// * `404` → the [subject] no longer exists;
/// * `403` → the role changed (the UI only offers allowed actions);
/// * `TIMEOUT` → the write may have gone through — check before retrying;
/// * `409 / 422` → mapped from `details` (archived goal, member left the
///   family, date outside the family's window, amount, category).
String? ledgerSpecificErrorMessage(
  Object error,
  AppLocalizations l10n, {
  LedgerSubject subject = LedgerSubject.other,
}) {
  final e = ledgerApiError(error);
  if (e == null) return null;
  if (e.isNotFound) {
    return switch (subject) {
      LedgerSubject.entry => l10n.ledgerErrorEntryGone,
      LedgerSubject.goal => l10n.ledgerErrorGoalGone,
      LedgerSubject.other => null,
    };
  }
  if (e.isForbidden) return l10n.ledgerErrorForbidden;
  if (e.code == ApiErrorCode.timeout) return l10n.ledgerErrorTimeout;
  if (!e.isValidation && e.statusCode != 409) return null;

  final fields = e.fieldErrors.keys.toSet();
  // Contract: contributions to archived goals → 409 VALIDATION_ERROR
  // (`details.goalId`).
  if (fields.contains('goalId') ||
      (e.statusCode == 409 && subject == LedgerSubject.goal)) {
    return l10n.ledgerGoalArchivedError;
  }
  if (fields.contains('memberId')) return l10n.ledgerErrorMemberGone;
  if (fields.contains('date')) return l10n.ledgerErrorDate;
  if (fields.contains('amount') || fields.contains('targetAmount')) {
    return l10n.ledgerErrorAmount;
  }
  if (fields.contains('type') || fields.contains('category')) {
    return l10n.ledgerErrorCategory;
  }
  return null;
}

/// [ledgerSpecificErrorMessage], falling back to `localizedErrorMessage`.
String ledgerErrorMessage(
  Object error,
  AppLocalizations l10n, {
  LedgerSubject subject = LedgerSubject.other,
}) =>
    ledgerSpecificErrorMessage(error, l10n, subject: subject) ??
    localizedErrorMessage(error, l10n);

extension LedgerErrorSnackX on BuildContext {
  /// `showError` with the ledger-specific text when there is one.
  void showLedgerError(
    Object error, {
    LedgerSubject subject = LedgerSubject.other,
  }) {
    final specific = ledgerSpecificErrorMessage(error, l10n, subject: subject);
    showError(specific == null ? error : _LocalizedLedgerError(specific));
  }
}

/// Carries an already localised text through `showError`, which shows the
/// message of codes it does not know. (`SnackX` has no "error text" variant;
/// see docs/progress/f-ledger-harden.md handoffs.)
class _LocalizedLedgerError extends ApiException {
  const _LocalizedLedgerError(String message)
    : super(code: 'LEDGER_LOCALIZED', message: message, statusCode: 0);
}
