import 'dart:async';

import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/features/sos/application/sos_controller.dart';

/// Asked while sending an SOS when the member's location sharing is
/// `never`: "Share location for SOS only" or "Send without location".
///
/// * Not dismissible by tapping outside (an accidental tap must not
///   decide); the system back button answers `null`, which the controller
///   treats as "send without location" — the SOS itself is always sent.
/// * Someone in danger may not be able to answer: after [autoAnswerAfter]
///   (a visible countdown) the dialog answers "send without location" by
///   itself — privacy by default, silence never means "share". The
///   controller applies the same limit ([SosController.locationChoiceTimeout]).
Future<SosLocationChoice?> showSosLocationChoiceDialog(
  BuildContext context, {
  Duration autoAnswerAfter = SosController.locationChoiceTimeout,
}) {
  return showDialog<SosLocationChoice>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SosLocationChoiceDialog(autoAnswerAfter: autoAnswerAfter),
  );
}

class _SosLocationChoiceDialog extends StatefulWidget {
  const _SosLocationChoiceDialog({required this.autoAnswerAfter});

  final Duration autoAnswerAfter;

  @override
  State<_SosLocationChoiceDialog> createState() =>
      _SosLocationChoiceDialogState();
}

class _SosLocationChoiceDialogState extends State<_SosLocationChoiceDialog> {
  static const _tick = Duration(seconds: 1);

  late int _secondsLeft = widget.autoAnswerAfter.inSeconds;
  Timer? _timer;
  bool _answered = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_tick, (_) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        _answer(SosLocationChoice.sendWithout);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _answer(SosLocationChoice choice) {
    // One answer only (a tap in the same frame as the automatic answer).
    if (_answered || !mounted) return;
    _answered = true;
    _timer?.cancel();
    Navigator.of(context).pop(choice);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return AlertDialog(
      scrollable: true,
      icon: Icon(AppIcons.location, color: context.semanticColors.sos),
      title: Text(l10n.sosLocationDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.sosLocationDialogMessage),
          AppGap.md,
          Semantics(
            liveRegion: true,
            child: Text(
              l10n.sosLocationDialogAutoSend(_secondsLeft),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      actionsOverflowButtonSpacing: AppSpacing.sm,
      actions: [
        TextButton(
          onPressed: () => _answer(SosLocationChoice.sendWithout),
          child: Text(l10n.sosLocationDialogWithout),
        ),
        FilledButton.icon(
          onPressed: () => _answer(SosLocationChoice.shareDuringSos),
          icon: const Icon(AppIcons.liveLocation, size: AppSizes.iconSm),
          label: Text(l10n.sosLocationDialogShare),
        ),
      ],
    );
  }
}
