import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/dashboard/application/dashboard_providers.dart';
import 'package:family_hub/features/dashboard/domain/dashboard_greeting.dart';
import 'package:family_hub/shared/l10n/shared_labels.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

/// Content of the full-bleed gradient header at the top of the dashboard
/// (rendered inside [GradientHeaderScrollView]): today's date, "Good
/// morning, Amit", "Sharma Family · Head of Family", the member's avatar and
/// three glass stat pills (my pending tasks, members, active goals).
///
/// Shown in every state of the screen, so the transparent status bar always
/// sits on the gradient: while [data] is `null` (first load, error) the
/// greeting comes from the signed-in session and the pills are frosted
/// placeholders of the same size (nothing moves when the numbers arrive).
///
/// The greeting and the date follow [dashboardNowProvider] (they update at
/// the period boundaries and at midnight, not only when data arrives).
class DashboardHeader extends ConsumerWidget {
  const DashboardHeader({super.key, this.data, this.sosAlerts = 0});

  /// The loaded dashboard, or `null` while there is none to show.
  final DashboardData? data;

  /// Number of active SOS alerts; when > 0 a "Needs help now" pill leads the
  /// header (the alert cards themselves follow right below it).
  final int sosAlerts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final fmt = ref.watch(fmtProvider);
    final now = ref.watch(dashboardNowProvider);
    final data = this.data;
    final me = data?.me ?? ref.watch(currentMemberProvider);
    final familyName =
        (data?.family ?? ref.watch(currentFamilyProvider))?.name.trim() ?? '';
    final period = GreetingPeriod.of(now);
    final firstName = firstNameOf(me?.name);
    final greeting = firstName.isEmpty
        ? l10n.dashboardGreetingNoName(period.name)
        : l10n.dashboardGreeting(period.name, firstName);
    final title = me?.titleOrRole(l10n);
    final subtitle = title == null
        ? familyName
        : familyName.isEmpty
        ? title
        : l10n.dashboardFamilyAndTitle(familyName, title);
    final onGradient = Colors.white.withValues(alpha: 0.85);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sosAlerts > 0) ...[
          _SosPill(label: l10n.dashboardSosTitle),
          AppGap.md,
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _periodIcon(period),
                        size: AppSizes.iconSm,
                        color: onGradient,
                      ),
                      AppGap.hXs,
                      Flexible(
                        child: Text(
                          fmt.weekdayDate(now),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: onGradient,
                          ),
                        ),
                      ),
                    ],
                  ),
                  AppGap.sm,
                  Semantics(
                    header: true,
                    child: Text(
                      greeting,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    AppGap.xs,
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: onGradient,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            AppGap.hMd,
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.7),
                  width: AppSizes.borderFocused,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxs),
                child: MemberAvatar(
                  name: me?.name,
                  avatarUrl: me?.avatarUrl,
                  radius: AppSizes.avatarLg,
                ),
              ),
            ),
          ],
        ),
        AppGap.xl,
        Row(
          children: [
            Expanded(
              child: _GlassStat(
                icon: AppIcons.task,
                value: data == null ? null : fmt.number(data.myPendingCount),
                label: l10n.dashboardHeroMyTasks,
              ),
            ),
            AppGap.hSm,
            Expanded(
              child: _GlassStat(
                icon: AppIcons.family,
                value: data == null ? null : fmt.number(_memberCount(data)),
                label: l10n.dashboardHeroMembers,
              ),
            ),
            AppGap.hSm,
            Expanded(
              child: _GlassStat(
                icon: AppIcons.goal,
                value: data == null ? null : _goalCount(data, fmt, l10n),
                label: l10n.dashboardHeroGoals,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The board lists every member; the family's own counter covers a
  /// server that left the board out.
  static int _memberCount(DashboardData data) => data.members.isNotEmpty
      ? data.members.length
      : data.family.memberCount;

  /// The server sends at most [DashboardData.goalsLimit] active goals, so a
  /// full list reads "3+" rather than claiming there are exactly three.
  static String _goalCount(
    DashboardData data,
    Fmt fmt,
    AppLocalizations l10n,
  ) {
    final count = data.goals.length;
    return count >= DashboardData.goalsLimit
        ? l10n.dashboardHeroAtLeast(fmt.number(DashboardData.goalsLimit))
        : fmt.number(count);
  }

  static IconData _periodIcon(GreetingPeriod period) => switch (period) {
    GreetingPeriod.morning => AppIcons.morning,
    GreetingPeriod.afternoon => AppIcons.afternoon,
    GreetingPeriod.evening || GreetingPeriod.night => AppIcons.evening,
  };
}

/// Frosted white pill with a number and a label, for use on gradients.
/// Without a [value] (still loading) a frosted bar of the value's line
/// height stands in for the number and the pill is hidden from screen
/// readers (the loading state announces itself).
class _GlassStat extends StatelessWidget {
  const _GlassStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String? value;
  final String label;

  /// Stand-in text that sizes the placeholder bar (never visible).
  static const _placeholderDigits = '00';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle = theme.textTheme.titleLarge
        ?.merge(AppTypography.tabularFigures)
        .copyWith(color: Colors.white);
    final value = this.value;
    final pill = MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: AppRadius.brLg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: AppSizes.iconXs, color: Colors.white),
                AppGap.hXs,
                Flexible(
                  child: value == null
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.24),
                            borderRadius: AppRadius.brSm,
                          ),
                          child: Opacity(
                            opacity: 0,
                            child: Text(
                              _placeholderDigits,
                              maxLines: 1,
                              style: valueStyle,
                            ),
                          ),
                        )
                      : Text(value, maxLines: 1, style: valueStyle),
                ),
              ],
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
    return value == null ? ExcludeSemantics(child: pill) : pill;
  }
}

/// Solid red pill shown on the header while a family member needs help.
class _SosPill extends StatelessWidget {
  const _SosPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final sos = context.semanticColors;
    return Semantics(
      header: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: sos.sos,
          borderRadius: AppRadius.brPill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.sosAlert, size: AppSizes.iconXs, color: sos.onSos),
            AppGap.hXs,
            Flexible(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: sos.onSos),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
