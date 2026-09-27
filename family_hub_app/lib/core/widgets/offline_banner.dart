import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/providers/core_providers.dart';

/// Slim banner shown while the last API request failed with a network error
/// (reads [connectivityStatusProvider]). Collapses to nothing when online.
///
/// Place it above the screen content, e.g. at the top of the home shell body.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(connectivityStatusProvider).isOffline;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AnimatedSize(
      duration: AppDurations.normal,
      curve: Curves.easeOutCubic,
      alignment: AlignmentDirectional.topCenter,
      child: !offline
          ? const SizedBox(width: double.infinity)
          : Semantics(
              liveRegion: true,
              container: true,
              child: Material(
                color: scheme.inverseSurface,
                child: SafeArea(
                  top: false,
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          AppIcons.offline,
                          size: AppSizes.iconSm,
                          color: scheme.onInverseSurface,
                        ),
                        AppGap.hMd,
                        Expanded(
                          child: Text(
                            context.l10n.commonOffline,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onInverseSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
