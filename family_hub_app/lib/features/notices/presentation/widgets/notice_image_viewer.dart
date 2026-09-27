import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/notices/presentation/widgets/notice_route_guard.dart';

/// Opens a notice photo full screen (pinch to zoom, pan, close button).
/// A repeated tap while the viewer is opening is ignored.
Future<void> showNoticeImage(
  BuildContext context, {
  required String url,
  required String title,
}) async {
  if (!isNoticeRouteCurrent(context)) return;
  await showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (_) => NoticeImageViewer(url: url, title: title),
  );
}

/// Full-screen photo viewer. Always dark, like the platform photo viewers,
/// using the app's dark theme tokens.
class NoticeImageViewer extends StatelessWidget {
  const NoticeImageViewer({super.key, required this.url, required this.title});

  final String url;
  final String title;

  static const double _maxZoom = 5;

  static final ThemeData _theme = AppTheme.dark();

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _theme,
      child: Builder(
        builder: (context) {
          final l10n = context.l10n;
          final scheme = Theme.of(context).colorScheme;
          return Dialog.fullscreen(
            backgroundColor: scheme.surface,
            child: Scaffold(
              backgroundColor: scheme.surface,
              appBar: AppBar(
                backgroundColor: scheme.surface,
                leading: IconButton(
                  tooltip: l10n.commonClose,
                  icon: const Icon(AppIcons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                title: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              body: SafeArea(
                child: InteractiveViewer(
                  maxScale: _maxZoom,
                  child: SizedBox.expand(
                    child: Semantics(
                      image: true,
                      label: l10n.noticesImageLabel(title),
                      excludeSemantics: true,
                      child: AppNetworkImage(url: url, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
