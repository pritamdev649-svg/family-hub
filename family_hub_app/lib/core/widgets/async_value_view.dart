import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';

import 'package:family_hub/core/widgets/state_views.dart';
import 'package:family_hub/core/widgets/widget_errors.dart';

/// The **only** way screens render an [AsyncValue].
///
/// | state                          | renders                                                   |
/// |--------------------------------|-----------------------------------------------------------|
/// | first load                     | [loading] or [LoadingView]                                 |
/// | error, no previous data        | [ErrorView] with [onRetry] (kept on screen while a retry runs) |
/// | data, [isEmpty] returns true   | [empty] or a generic [EmptyState]                         |
/// | data                           | [data]                                                    |
/// | data + refreshing / reloading  | previous data + thin progress bar on top                  |
/// | data + refresh failed          | previous data + dismissible "couldn't refresh" notice with retry |
///
/// Previous data stays on screen while refreshing, so lists never flash a
/// spinner after a mutation (`markChanged`) or pull-to-refresh, and the widget
/// tree around [data] stays stable (scroll positions are kept).
///
/// ```dart
/// AsyncValueView(
///   value: ref.watch(tasksProvider),
///   onRetry: () => ref.invalidate(tasksProvider),
///   isEmpty: (tasks) => tasks.isEmpty,
///   empty: EmptyState(icon: AppIcons.task, title: context.l10n.tasksEmpty),
///   data: (tasks) => ListView.builder(...),
/// )
/// ```
///
/// Note: the error / empty states fill and scroll within the available
/// height. Inside widgets that measure intrinsic sizes (e.g. `AlertDialog`
/// content) give the view a fixed width with a `SizedBox`.
class AsyncValueView<T> extends StatefulWidget {
  const AsyncValueView({
    super.key,
    required this.value,
    required this.data,
    this.onRetry,
    this.isEmpty,
    this.empty,
    this.loading,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;
  final bool Function(T data)? isEmpty;
  final Widget? empty;
  final Widget? loading;

  @override
  State<AsyncValueView<T>> createState() => _AsyncValueViewState<T>();
}

class _AsyncValueViewState<T> extends State<AsyncValueView<T>> {
  /// Message of the stale-data notice the user dismissed. The notice comes
  /// back only for a different error or after a successful refresh.
  String? _dismissedMessage;

  @override
  void didUpdateWidget(AsyncValueView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final v = widget.value;
    if (!v.hasError && !v.isLoading) _dismissedMessage = null;
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value;

    if (!v.hasValue) {
      final error = v.error;
      if (error != null) {
        return ErrorView(
          error: error,
          onRetry: widget.onRetry,
          isRetrying: v.isLoading,
        );
      }
      return widget.loading ?? const LoadingView();
    }

    final current = v.requireValue;
    final showEmpty = widget.isEmpty?.call(current) ?? false;
    final content = showEmpty
        ? (widget.empty ??
              EmptyState(
                icon: AppIcons.empty,
                title: context.l10n.commonNothingHere,
              ))
        : widget.data(current);

    final error = v.error;
    String? notice;
    if (!v.isLoading && error != null) {
      final message = isNetworkError(error)
          ? context.l10n.commonOffline
          : context.l10n.widgetStaleDataNotice;
      if (message != _dismissedMessage) notice = message;
    }

    // Always the same Stack so the [content] element (and e.g. its scroll
    // position) survives refresh / error transitions.
    return Stack(
      alignment: AlignmentDirectional.topStart,
      children: [
        content,
        if (v.isLoading)
          const PositionedDirectional(
            top: 0,
            start: 0,
            end: 0,
            child: LinearProgressIndicator(minHeight: AppSizes.refreshBar),
          ),
        // Non-positioned on purpose: the Stack grows to fit the notice even
        // when [content] is small, so its buttons always receive taps.
        if (notice != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: _StaleDataNotice(
              message: notice,
              offline: error != null && isNetworkError(error),
              onRetry: widget.onRetry,
              onDismiss: () => setState(() => _dismissedMessage = notice),
            ),
          ),
      ],
    );
  }
}

class _StaleDataNotice extends StatelessWidget {
  const _StaleDataNotice({
    required this.message,
    required this.offline,
    required this.onRetry,
    required this.onDismiss,
  });

  final String message;
  final bool offline;
  final VoidCallback? onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      liveRegion: true,
      container: true,
      child: Material(
        color: scheme.inverseSurface,
        elevation: 2,
        borderRadius: AppRadius.brMd,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AppSpacing.md,
            top: AppSpacing.xs,
            bottom: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Icon(
                offline ? AppIcons.offline : AppIcons.warning,
                size: AppSizes.iconSm,
                color: scheme.onInverseSurface,
              ),
              AppGap.hMd,
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onInverseSurface,
                  ),
                ),
              ),
              if (onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.inversePrimary,
                  ),
                  child: Text(l10n.commonRetry),
                ),
              IconButton(
                tooltip: l10n.commonClose,
                onPressed: onDismiss,
                color: scheme.onInverseSurface,
                icon: const Icon(AppIcons.close, size: AppSizes.iconSm),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
