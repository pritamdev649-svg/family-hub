import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/notices/application/notices_providers.dart';
import 'package:family_hub/features/notices/domain/notice.dart';
import 'package:family_hub/features/notices/presentation/widgets/notice_actions.dart';
import 'package:family_hub/features/notices/presentation/widgets/notice_body_text.dart';
import 'package:family_hub/features/notices/presentation/widgets/notice_image_viewer.dart';
import 'package:family_hub/features/notices/presentation/widgets/notice_style.dart';

/// One notice: author avatar + name, relative time, a solid amber "Pinned"
/// pill, bold title, text (with "Read more" for long notices) and the
/// optional rounded photo (tap → full screen).
///
/// Borderless [AppCard] (docs/12-DESIGN_LANGUAGE.md); a pinned notice sits on
/// the soft amber accent background so it stands out at the top of the board.
///
/// Public widget (docs/05-FLUTTER_GUIDE.md §10) — e.g. the dashboard shows
/// `NoticeCard(notice, compact: true, onTap: () => context.push(AppRoutes.notices))`.
///
/// * [showActions]: menu button + long-press sheet with the actions the
///   member may perform (edit, pin / unpin, copy, delete). While one of them
///   runs, the menu shows a spinner and further taps are ignored.
/// * [compact]: text clamped to a few lines without "Read more" and the
///   photo as a small thumbnail — for previews in other screens.
class NoticeCard extends ConsumerWidget {
  const NoticeCard(
    this.notice, {
    super.key,
    this.onTap,
    this.showActions = true,
    this.compact = false,
  });

  final Notice notice;
  final VoidCallback? onTap;
  final bool showActions;
  final bool compact;

  static const int _compactBodyLines = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final busy = ref.watch(
      noticesControllerProvider.select((ids) => ids.contains(notice.id)),
    );
    final canAct = showActions && !busy;
    void openActions() => showNoticeActions(context, ref, notice);

    final header = _NoticeHeader(
      notice: notice,
      trailing: !showActions
          ? null
          : busy
          ? const _BusyIndicator()
          : IconButton(
              tooltip: l10n.noticesActions,
              icon: const Icon(AppIcons.moreVert),
              onPressed: openActions,
            ),
    );

    final title = Semantics(
      header: true,
      child: Text(
        notice.title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: AppTypography.extraBold,
        ),
      ),
    );

    final Widget content;
    if (compact) {
      final image = notice.imageUrl;
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                if (notice.body.isNotEmpty) ...[
                  AppGap.xs,
                  Text(
                    notice.body,
                    maxLines: _compactBodyLines,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (image != null) ...[
            AppGap.hMd,
            _NoticeImage(
              url: image,
              title: notice.title,
              size: AppSizes.thumbnail,
            ),
          ],
        ],
      );
    } else {
      final image = notice.imageUrl;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          if (notice.body.isNotEmpty) ...[
            AppGap.xs,
            NoticeBodyText(text: notice.body),
          ],
          if (image != null) ...[
            AppGap.md,
            _NoticeImage(url: image, title: notice.title),
          ],
        ],
      );
    }

    return AppCard(
      padding: EdgeInsets.zero,
      accent: notice.pinned ? NoticeStyle.accent : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: canAct ? openActions : null,
        child: Padding(
          padding: AppSpacing.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [header, AppGap.md, content],
          ),
        ),
      ),
    );
  }
}

class _NoticeHeader extends ConsumerWidget {
  const _NoticeHeader({required this.notice, required this.trailing});

  final Notice notice;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fmt = ref.watch(fmtProvider);
    final known = notice.authorName.isNotEmpty;
    final author = known ? notice.authorName : l10n.noticesFormerMember;
    // A device clock behind the server's would show a just-posted notice as
    // posted "Today" (a future moment); it was posted just now.
    final now = DateTime.now();
    final posted = notice.createdAt.isAfter(now) ? now : notice.createdAt;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MemberAvatar(
          name: known ? notice.authorName : null,
          avatarUrl: notice.authorAvatarUrl,
        ),
        AppGap.hMd,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                label: l10n.noticesPostedBy(author),
                excludeSemantics: true,
                child: Text(
                  author,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              AppGap.xxs,
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Tooltip(
                    message: fmt.dateTime(posted),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          AppIcons.time,
                          size: AppSizes.iconXs,
                          color: scheme.onSurfaceVariant,
                        ),
                        AppGap.hXs,
                        Flexible(
                          child: Text(
                            fmt.relative(posted, l10n, now: now),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (notice.pinned) _PinnedPill(label: l10n.noticesPinned),
                ],
              ),
            ],
          ),
        ),
        if (trailing != null) ...[AppGap.hXs, trailing!],
      ],
    );
  }
}

/// Photo of a notice: 16:9 banner (or a square thumbnail when [size] is
/// given). Tapping opens it full screen.
class _NoticeImage extends StatelessWidget {
  const _NoticeImage({required this.url, required this.title, this.size});

  final String url;
  final String title;
  final double? size;

  static const double _bannerAspectRatio = 16 / 9;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    void open() => showNoticeImage(context, url: url, title: title);

    Widget framed(double? width) => ClipRRect(
      borderRadius: size != null ? AppRadius.brMd : AppRadius.brLg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AppNetworkImage(url: url, width: width, height: size),
          Material(
            type: MaterialType.transparency,
            child: InkWell(onTap: open),
          ),
        ],
      ),
    );

    final Widget image = size != null
        ? SizedBox.square(dimension: size, child: framed(size))
        : LayoutBuilder(
            builder: (context, constraints) => AspectRatio(
              aspectRatio: _bannerAspectRatio,
              child: framed(
                constraints.hasBoundedWidth ? constraints.maxWidth : null,
              ),
            ),
          );

    return Semantics(
      button: true,
      image: true,
      label: l10n.noticesImageLabel(title),
      hint: l10n.noticesOpenImage,
      onTap: open,
      excludeSemantics: true,
      child: image,
    );
  }
}

/// Solid amber pill with a white pin icon — "Pinned".
class _PinnedPill extends StatelessWidget {
  const _PinnedPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: NoticeStyle.solid,
        borderRadius: AppRadius.brPill,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              AppIcons.pin,
              size: AppSizes.iconXs,
              color: Colors.white,
            ),
            AppGap.hXs,
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BusyIndicator extends StatelessWidget {
  const _BusyIndicator();

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: AppSizes.minTapTarget,
      child: Center(
        child: Semantics(
          label: context.l10n.commonLoading,
          child: SizedBox.square(
            dimension: AppSizes.spinnerSm,
            child: CircularProgressIndicator(
              strokeWidth: AppSizes.spinnerStroke,
              color: context.accent(NoticeStyle.accent).base,
            ),
          ),
        ),
      ),
    );
  }
}
