import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:flutter/material.dart';

/// Shown while the saved session is restored (`RouteGate.loading`). The
/// router leaves this screen automatically; it has no actions of its own.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: ResponsiveCenter(
          child: Center(
            child: SingleChildScrollView(
              padding: AppSpacing.screen,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Icon(
                          AppIcons.family,
                          size: AppSizes.iconHero,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                  AppGap.xl,
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.appName,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  AppGap.sm,
                  Text(
                    l10n.appTagline,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  LoadingView(message: l10n.homeSplashLoading),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
