import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';

import 'package:family_hub/core/widgets/app_button.dart';
import 'package:family_hub/core/widgets/widget_errors.dart';

/// Full-area loading indicator with an optional message.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Not scrollable (no LayoutBuilder), so it is also safe inside widgets that
    // measure intrinsic sizes, such as dialogs.
    return _StateLayout(
      scrollable: false,
      child: Semantics(
        liveRegion: true,
        label: message ?? context.l10n.commonLoading,
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(
                dimension: AppSizes.spinnerLg,
                child: CircularProgressIndicator(
                  strokeWidth: AppSizes.spinnerStroke,
                ),
              ),
              if (message != null) ...[
                AppGap.lg,
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-area error state: icon, localised message and an optional retry
/// button. Network errors get an "offline" icon.
///
/// Fills and scrolls within the available height; inside widgets that measure
/// intrinsic sizes (e.g. `AlertDialog` content) give it a fixed width.
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.error,
    this.onRetry,
    this.isRetrying = false,
  });

  final Object error;
  final VoidCallback? onRetry;

  /// Shows the retry button in its busy state (e.g. while an automatic or
  /// manual retry is in flight) instead of swapping the whole view.
  final bool isRetrying;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final offline = isNetworkError(error);

    return _StateLayout(
      child: _StateContent(
        icon: offline ? AppIcons.offline : AppIcons.error,
        iconColor: offline ? scheme.onSurfaceVariant : scheme.onErrorContainer,
        iconBackground: offline
            ? scheme.surfaceContainerHighest
            : scheme.errorContainer,
        title: l10n.commonSomethingWentWrong,
        message: errorText(error, l10n),
        action: onRetry == null
            ? null
            : AppButton(
                label: l10n.commonRetry,
                icon: AppIcons.retry,
                onPressed: onRetry,
                isLoading: isRetrying,
                variant: AppButtonVariant.secondary,
                expand: false,
              ),
      ),
    );
  }
}

/// Friendly empty state: icon, title, optional message and call to action.
///
/// Fills and scrolls within the available height; inside widgets that measure
/// intrinsic sizes (e.g. `AlertDialog` content) give it a fixed width.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _StateLayout(
      child: _StateContent(
        icon: icon,
        iconColor: scheme.onPrimaryContainer,
        iconBackground: scheme.primaryContainer,
        title: title,
        message: message,
        action: action,
      ),
    );
  }
}

class _StateContent extends StatelessWidget {
  const _StateContent({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.message,
    required this.action,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: iconBackground,
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Icon(icon, size: AppSizes.iconLg, color: iconColor),
            ),
          ),
        ),
        AppGap.lg,
        Semantics(
          header: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        ),
        if (message != null && message!.isNotEmpty) ...[
          AppGap.sm,
          Text(
            message!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (action != null) ...[AppGap.xl, action!],
      ],
    );
  }
}

/// Centres a state view in the available space. When [scrollable] and the
/// height is bounded, the whole area scrolls (so large text never overflows and
/// pull-to-refresh keeps working on empty / error states); inside unbounded
/// parents it simply pads.
class _StateLayout extends StatelessWidget {
  const _StateLayout({required this.child, this.scrollable = true});

  final Widget child;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final padded = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxl,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizes.maxDialogWidth),
        child: child,
      ),
    );

    if (!scrollable) return Center(child: padded);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) return Center(child: padded);
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
              minWidth: constraints.hasBoundedWidth ? constraints.maxWidth : 0,
            ),
            child: Center(child: padded),
          ),
        );
      },
    );
  }
}
