import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/url_actions.dart';
import 'package:family_hub/core/widgets/widgets.dart';

/// Opens the dialer for [phone]. When the device cannot place calls (tablet,
/// no SIM, no dialer) the number is shown so it can be dialled by hand.
Future<void> callFromEmergencyCard(BuildContext context, String phone) async {
  final ok = await UrlActions.call(phone);
  if (!ok && context.mounted) {
    context.showInfo(context.l10n.emergencyCardCallFailed(phone));
  }
}

/// Copies an insurance policy number to the clipboard.
Future<void> copyPolicyNumber(BuildContext context, String number) async {
  await Clipboard.setData(ClipboardData(text: number));
  if (context.mounted) {
    context.showSuccess(context.l10n.emergencyCardPolicyNumberCopied);
  }
}

/// Pushes [location] unless another route is already above this screen: a
/// double tap (or an impatient tap during the transition) would otherwise
/// open the same card / form twice.
// TODO(f-core): replace with the shared helper once `pushIfTop` moves from
// features/family/presentation/family_navigation.dart into core/router.
void pushFromEmergencyCard(BuildContext context, String location) {
  if (ModalRoute.of(context)?.isCurrent ?? true) {
    context.push<void>(location);
  }
}
