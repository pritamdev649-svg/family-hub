import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/auth/application/session_expired_notice.dart';
import 'package:family_hub/features/auth/presentation/auth_labels.dart';
import 'package:family_hub/features/auth/presentation/widgets/auth_layout.dart';
import 'package:family_hub/features/auth/presentation/widgets/language_picker.dart';

/// First screen for signed-out users.
///
/// A full-bleed brand gradient hero starts behind the **transparent**
/// status bar and fills the top of the screen: the language pill, a large
/// frosted app mark, the app name and tagline and three glass pills with
/// what FamilyHub does. Below it, the three ways in — create a family
/// (gradient), join with an invite code (tonal) and log in (text).
///
/// The hero grows to fill whatever the actions leave free (about the top
/// 55–70 % on phones); on short screens or with large text the page
/// scrolls, and the status-bar icons turn dark again (light theme) once
/// the hero has scrolled away.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _scroll = ScrollController();
  final _heroKey = GlobalKey();
  bool _heroUnderStatusBar = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    final box = _heroKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final topInset = MediaQuery.paddingOf(context).top;
    final under = _scroll.offset < box.size.height - topInset;
    if (under != _heroUnderStatusBar) {
      setState(() => _heroUnderStatusBar = under);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sessionExpired = ref.watch(sessionExpiredNoticeProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: authSystemUiStyle(context, onGradient: _heroUnderStatusBar),
      child: Scaffold(
        body: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _WelcomeHero(key: _heroKey)),
                  ResponsiveCenter(
                    child: Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(
                        AppSpacing.lg,
                        AppSpacing.xl,
                        AppSpacing.lg,
                        AppSpacing.lg + bottomInset,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (sessionExpired) ...[
                            AuthMessageBanner(
                              kind: AuthBannerKind.info,
                              message: l10n.authSessionExpiredNotice,
                            ),
                            AppGap.lg,
                          ],
                          AppButton(
                            label: l10n.authWelcomeCreateFamily,
                            icon: AuthIcons.createFamily,
                            onPressed: () => context.push(
                              AppRoutes.register(
                                mode: AppRoutes.registerModeCreate,
                              ),
                            ),
                          ),
                          AppGap.md,
                          AppButton(
                            label: l10n.authWelcomeJoinFamily,
                            icon: AuthIcons.inviteCode,
                            variant: AppButtonVariant.tonal,
                            onPressed: () => context.push(
                              AppRoutes.register(
                                mode: AppRoutes.registerModeJoin,
                              ),
                            ),
                          ),
                          AppGap.sm,
                          AppButton(
                            label: l10n.authWelcomeHaveAccount,
                            icon: AuthIcons.login,
                            variant: AppButtonVariant.text,
                            onPressed: () => context.push(AppRoutes.login),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The brand gradient hero: language pill (top end), frosted app mark,
/// name and tagline (centred) and the feature pills (bottom).
class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final secondary = Colors.white.withValues(alpha: AuthGlass.secondaryText);

    return GradientHeader(
      gradient: AppGradients.brand,
      bottomSpace: 0,
      child: Column(
        children: [
          const Align(
            alignment: AlignmentDirectional.centerEnd,
            child: LanguagePickerButton(),
          ),
          AppGap.xl,
          const Spacer(),
          const _AppMark(),
          AppGap.xl,
          Semantics(
            header: true,
            child: Text(
              l10n.appName,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineLarge?.copyWith(
                color: Colors.white,
              ),
            ),
          ),
          AppGap.sm,
          Text(
            l10n.appTagline,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(color: secondary),
          ),
          const Spacer(),
          AppGap.xl,
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _GlassPill(
                icon: AppIcons.tasks,
                text: l10n.authWelcomeFeatureTasks,
              ),
              _GlassPill(
                icon: AppIcons.money,
                text: l10n.authWelcomeFeatureMoney,
              ),
              _GlassPill(
                icon: AppIcons.sos,
                text: l10n.authWelcomeFeatureSafety,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Large frosted square with the family icon — the app mark on the hero
/// (an [IconBadge] made of white glass).
class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: AuthGlass.fill),
          borderRadius: const BorderRadius.all(Radius.circular(AppRadius.hero)),
          boxShadow: [
            BoxShadow(
              color: AuthAccents.brand.base.withValues(
                alpha: AppColors.glowOpacity,
              ),
              blurRadius: AppSizes.glowBlur,
              offset: const Offset(0, AppSpacing.sm),
            ),
          ],
        ),
        child: const Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Icon(
            AppIcons.family,
            size: AppSizes.iconHero,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Small frosted pill with a thin white icon and a short benefit line.
class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: AuthGlass.fill),
        borderRadius: AppRadius.brPill,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(icon, size: AppSizes.iconXs, color: Colors.white),
            ),
            AppGap.hSm,
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
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
