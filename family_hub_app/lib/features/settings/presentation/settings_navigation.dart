import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/l10n/error_messages.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/utils/url_actions.dart';
import 'package:family_hub/core/widgets/snackbars.dart';

/// Leaves a settings screen: pops when there is a previous page, otherwise
/// (opened from a deep link) goes to the More tab.
void closeSettingsScreen(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(AppRoutes.more);
  }
}

/// Whether [error] is the contract's `409 LAST_ADMIN`.
bool isLastAdminError(Object error) {
  final e = unwrapProviderError(error);
  return e is ApiException && e.code == ApiErrorCode.lastAdmin;
}

/// Whether [error] is `401 INVALID_CREDENTIALS` (wrong password).
bool isInvalidCredentialsError(Object error) {
  final e = unwrapProviderError(error);
  return e is ApiException && e.code == ApiErrorCode.invalidCredentials;
}

/// Opens [url] (privacy policy, terms) externally; tells the user when that
/// is not possible.
Future<void> openSettingsLink(BuildContext context, String url) =>
    _launchOrExplain(context, () => UrlActions.openUrl(url));

/// Opens the mail app for [address].
Future<void> openSettingsEmail(BuildContext context, String address) =>
    _launchOrExplain(context, () => UrlActions.email(address));

/// Starts a phone call to [number].
Future<void> callFromSettings(BuildContext context, String number) =>
    _launchOrExplain(context, () => UrlActions.call(number));

Future<void> _launchOrExplain(
  BuildContext context,
  Future<bool> Function() launch,
) async {
  final opened = await launch();
  if (!opened && context.mounted) {
    context.showInfo(context.l10n.settingsLinkOpenFailed);
  }
}
