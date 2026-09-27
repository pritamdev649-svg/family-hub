import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';

import 'package:family_hub/core/widgets/widget_errors.dart';

enum _SnackKind { success, error, info }

/// App-wide snackbars. A new snackbar replaces the one currently visible.
///
/// ```dart
/// try {
///   await repo.save(...);
///   if (!context.mounted) return;
///   context.showSuccess(context.l10n.commonSaved);
/// } catch (e) {
///   if (context.mounted) context.showError(e);
/// }
/// ```
extension SnackX on BuildContext {
  void showSuccess(String message) =>
      _showSnack(this, message, _SnackKind.success);

  /// Shows the localised message for [error] (`localizedErrorMessage`).
  /// User-cancelled requests are ignored.
  void showError(Object error) {
    if (isCancellation(error)) return;
    if (kDebugMode) debugPrint('showError: ${unwrapError(error)}');
    _showSnack(this, errorText(error, l10n), _SnackKind.error);
  }

  void showInfo(String message) => _showSnack(this, message, _SnackKind.info);
}

void _showSnack(BuildContext context, String message, _SnackKind kind) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null || message.trim().isEmpty) return;

  final scheme = Theme.of(context).colorScheme;
  final semantic = context.semanticColors;

  final (Color background, Color foreground, IconData icon) = switch (kind) {
    _SnackKind.success => (
      semantic.success,
      semantic.onSuccess,
      AppIcons.success,
    ),
    _SnackKind.error => (scheme.error, scheme.onError, AppIcons.error),
    _SnackKind.info => (
      scheme.inverseSurface,
      scheme.onInverseSurface,
      AppIcons.info,
    ),
  };

  final textStyle = Theme.of(
    context,
  ).textTheme.bodyMedium?.copyWith(color: foreground);

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: background,
        // Errors stay a little longer so there is time to read them.
        duration: kind == _SnackKind.error
            ? AppDurations.snackbar * 1.5
            : AppDurations.snackbar,
        showCloseIcon: kind == _SnackKind.error,
        closeIconColor: foreground,
        content: Row(
          children: [
            Icon(icon, color: foreground, size: AppSizes.iconSm),
            AppGap.hMd,
            Expanded(child: Text(message, style: textStyle)),
          ],
        ),
      ),
    );
}
