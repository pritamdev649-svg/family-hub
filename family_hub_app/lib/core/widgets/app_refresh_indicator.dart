import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Pull-to-refresh wrapper.
///
/// The [child] must be scrollable (a `ListView`, `CustomScrollView`, or the
/// state views from [AsyncValueView], which are always scrollable). Errors
/// thrown by [onRefresh] are swallowed here because the refreshed provider
/// already exposes them to its [AsyncValueView].
///
/// ```dart
/// AppRefreshIndicator(
///   onRefresh: () => ref.refresh(tasksProvider.future),
///   child: AsyncValueView(...),
/// )
/// ```
class AppRefreshIndicator extends StatelessWidget {
  const AppRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.edgeOffset = 0,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  /// Distance from the top at which the spinner appears (e.g. the status-bar
  /// height when the content starts behind it).
  final double edgeOffset;

  Future<void> _handleRefresh() async {
    try {
      await onRefresh();
    } catch (error, stack) {
      debugPrint('AppRefreshIndicator: refresh failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stack, maxFrames: 5);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _handleRefresh,
      edgeOffset: edgeOffset,
      color: scheme.primary,
      backgroundColor: scheme.surfaceContainerHigh,
      child: child,
    );
  }
}
