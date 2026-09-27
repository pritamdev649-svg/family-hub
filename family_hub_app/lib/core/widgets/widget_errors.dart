import 'package:family_hub/core/l10n/error_messages.dart';
import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/l10n/app_localizations.dart';

/// Internal helpers shared by the error-displaying widgets
/// ([ErrorView], [AsyncValueView], `context.showError`). Not exported from the
/// widgets barrel — features use those widgets instead.

/// Riverpod 3 wraps errors of dependent providers in `ProviderException`;
/// unwrap them so error codes can be mapped to localised messages.
Object unwrapError(Object error) => unwrapProviderError(error);

/// Whether [error] means the device could not reach the server.
bool isNetworkError(Object error) {
  final e = unwrapError(error);
  return e is ApiException && e.isNetwork;
}

/// Whether [error] is a user-initiated cancellation that should stay silent.
bool isCancellation(Object error) {
  final e = unwrapError(error);
  return e is ApiException && e.isCancelled;
}

/// Localised, user-facing message for [error].
String errorText(Object error, AppLocalizations l10n) =>
    localizedErrorMessage(error, l10n);
