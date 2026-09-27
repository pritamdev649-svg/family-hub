import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/url_actions.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

/// "Call emergency services 112" — dials the family country's emergency
/// number (works without mobile data). Shown next to every SOS action,
/// because FamilyHub itself never contacts emergency services.
class SosEmergencyCallButton extends ConsumerWidget {
  const SosEmergencyCallButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final number = ref.watch(
      currentCountryProvider.select((c) => c.emergencyNumber),
    );
    return AppButton(
      label: context.l10n.sosCallEmergency(number),
      icon: AppIcons.phone,
      variant: AppButtonVariant.danger,
      onPressed: () => sosDial(context, number),
    );
  }
}

/// Opens the dialer for [number]; tells the user to dial themselves when
/// no phone app can handle it (tablets, emulators).
Future<void> sosDial(BuildContext context, String number) async {
  final opened = await UrlActions.call(number);
  if (!opened && context.mounted) {
    context.showInfo(context.l10n.sosCallFailed(number));
  }
}
