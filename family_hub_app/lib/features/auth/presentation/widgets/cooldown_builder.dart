import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/features/auth/application/auth_cooldown.dart';
import 'package:family_hub/features/auth/presentation/auth_labels.dart';
import 'package:family_hub/features/auth/presentation/widgets/auth_layout.dart';

/// Rebuilds once per second while the cooldown [cooldownKey] runs and hands
/// [builder] the seconds left (0 = over).
class CooldownBuilder extends ConsumerStatefulWidget {
  const CooldownBuilder({
    super.key,
    required this.cooldownKey,
    required this.builder,
  });

  final AuthCooldownKey cooldownKey;
  final Widget Function(BuildContext context, int secondsLeft) builder;

  @override
  ConsumerState<CooldownBuilder> createState() => _CooldownBuilderState();
}

class _CooldownBuilderState extends ConsumerState<CooldownBuilder> {
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final until = ref.watch(authCooldownProvider(widget.cooldownKey));
    final now = ref.watch(authClockProvider)();
    final left = cooldownSecondsLeft(until, now);
    _tick?.cancel();
    _tick = null;
    if (until != null && left > 0) {
      // Wake up exactly when the displayed second changes.
      final ms = until.difference(now).inMilliseconds % 1000;
      _tick = Timer(Duration(milliseconds: ms == 0 ? 1000 : ms), () {
        if (mounted) setState(() {});
      });
    }
    return widget.builder(context, left);
  }
}

/// "Resend code" as a centred pill: brand-tinted and tappable when a new
/// code may be sent, a neutral disabled pill with a clock showing the
/// remaining time ("Resend code in 42 seconds") while the cooldown runs.
class ResendCodeButton extends StatelessWidget {
  const ResendCodeButton({
    super.key,
    required this.cooldownKey,
    required this.onPressed,
    this.isLoading = false,
  });

  final AuthCooldownKey cooldownKey;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brand = context.accent(AuthAccents.brand);
    return CooldownBuilder(
      cooldownKey: cooldownKey,
      builder: (context, left) {
        final waiting = left > 0;
        final Widget leading = isLoading
            ? SizedBox.square(
                dimension: AppSizes.iconXs,
                child: CircularProgressIndicator(
                  strokeWidth: AppSizes.spinnerStroke,
                  color: scheme.onSurfaceVariant,
                ),
              )
            : Icon(waiting ? AppIcons.time : AppIcons.retry);
        return Center(
          child: Semantics(
            value: isLoading ? l10n.commonLoading : null,
            child: TextButton(
              onPressed: waiting || isLoading ? null : onPressed,
              style: TextButton.styleFrom(
                shape: const StadiumBorder(),
                backgroundColor: brand.container,
                foregroundColor: brand.onContainer,
                disabledBackgroundColor: authSoftFill(context),
                disabledForegroundColor: scheme.onSurfaceVariant,
                iconSize: AppSizes.iconXs,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  leading,
                  AppGap.hSm,
                  Flexible(
                    child: Text(
                      waiting
                          ? l10n.authResendCodeIn(formatWait(l10n, left))
                          : l10n.authResendCode,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
