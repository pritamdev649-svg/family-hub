import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/auth/presentation/auth_labels.dart';

/// System bar style of the auth screens: a **transparent** status bar (the
/// canvas or the welcome gradient shows through, no grey scrim) with icons
/// that contrast with what is behind them, and a navigation bar in the
/// canvas colour (older Android versions; edge-to-edge ones ignore it).
///
/// [onGradient] = the status bar sits over a gradient (welcome hero), so
/// its icons are white in both themes.
SystemUiOverlayStyle authSystemUiStyle(
  BuildContext context, {
  bool onGradient = false,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final lightIcons = onGradient || isDark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    // Android: icon colour. iOS: the brightness of what is *behind* them.
    statusBarIconBrightness: lightIcons ? Brightness.light : Brightness.dark,
    statusBarBrightness: lightIcons ? Brightness.dark : Brightness.light,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarColor: context.semanticColors.canvas,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: isDark
        ? Brightness.light
        : Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );
}

/// The soft neutral fill of the app's borderless text fields (theme), for
/// input-like elements drawn by hand (OTP boxes, the waiting resend pill).
Color authSoftFill(BuildContext context, {bool enabled = true}) {
  final theme = Theme.of(context);
  return WidgetStateProperty.resolveAs<Color?>(
        theme.inputDecorationTheme.fillColor,
        {if (!enabled) WidgetState.disabled},
      ) ??
      theme.colorScheme.surfaceContainerHighest;
}

/// Page frame of the canvas auth screens (log-in, sign-up, verify email,
/// reset password, family setup):
///
/// * soft canvas background under a transparent status bar,
/// * a slim canvas top bar with a round back button (only when the screen
///   was pushed) and optional [actions]; without either the bar is left out,
/// * a scrolling column, capped in width on tablets, that dismisses the
///   keyboard on drag and keeps its end clear of the home indicator.
///
/// The screen's big title belongs in the body ([AuthHeader]), so the top
/// bar carries no title.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, this.actions, required this.children});

  final List<Widget>? actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final style = authSystemUiStyle(context);
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    final hasBar = canPop || (actions?.isNotEmpty ?? false);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final body = SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: ResponsiveCenter(
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            AppSpacing.lg,
            hasBar ? AppSpacing.sm : AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl + bottomInset,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: style,
      child: Scaffold(
        appBar: hasBar
            ? AppBar(
                systemOverlayStyle: style,
                automaticallyImplyLeading: false,
                leadingWidth: AppSizes.minTapTarget + AppSpacing.md,
                leading: canPop
                    ? Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: AppSpacing.sm,
                        ),
                        child: AuthBarButton(
                          icon: AppIcons.back,
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).backButtonTooltip,
                          onPressed: () => Navigator.maybePop(context),
                        ),
                      )
                    : null,
                actions: [
                  ...?actions,
                  if (actions?.isNotEmpty ?? false) AppGap.hSm,
                ],
              )
            : null,
        // The bar (or the safe area) keeps content below the status bar;
        // the bottom inset is part of the scroll padding instead, so the
        // content can scroll behind the home indicator.
        body: SafeArea(top: !hasBar, bottom: false, child: body),
      ),
    );
  }
}

/// Round, borderless icon button of the auth top bar (back, log out): a
/// card-coloured circle on the canvas with a thin icon.
class AuthBarButton extends StatelessWidget {
  const AuthBarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: context.semanticColors.card,
          foregroundColor: scheme.onSurface,
          disabledBackgroundColor: context.semanticColors.card,
        ),
        icon: Icon(icon),
      ),
    );
  }
}

/// Big bold heading of an auth screen: a solid colour [IconBadge] with a
/// thin white icon, the title (a screen-reader header) and an explanation.
class AuthHeader extends StatelessWidget {
  const AuthHeader({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.accent = AuthAccents.brand,
  });

  final IconData icon;
  final String title;
  final String? message;
  final AppAccent accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ExcludeSemantics(
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : AppDurations.normal,
              child: IconBadge(
                key: ValueKey(accent),
                icon: icon,
                accent: accent,
                size: AppSizes.badgeLg,
              ),
            ),
          ),
        ),
        AppGap.lg,
        Semantics(
          header: true,
          child: Text(title, style: theme.textTheme.headlineMedium),
        ),
        if (message != null) ...[
          AppGap.sm,
          Text(
            message!,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// A group of form fields on a borderless [AppCard], optionally under a
/// [SectionHeader] with a coloured thin icon.
class AuthSectionCard extends StatelessWidget {
  const AuthSectionCard({
    super.key,
    this.title,
    this.icon,
    this.accent = AuthAccents.brand,
    required this.children,
  });

  final String? title;
  final IconData? icon;
  final AppAccent accent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            SectionHeader(title: title!, icon: icon, accent: accent),
            AppGap.xs,
          ],
          ...children,
        ],
      ),
    );
  }
}

/// Kind of an [AuthMessageBanner].
enum AuthBannerKind { error, info }

/// Inline message inside a form (wrong password, lockout countdown, demo
/// hints, "you were signed out"): a soft tinted card with a solid colour
/// icon badge. Announced to screen readers when it appears.
class AuthMessageBanner extends StatelessWidget {
  const AuthMessageBanner({
    super.key,
    required this.message,
    this.kind = AuthBannerKind.error,
    this.title,
    this.icon,
    this.accent,
    this.action,
  });

  final String message;
  final AuthBannerKind kind;
  final String? title;
  final IconData? icon;

  /// Overrides the kind's colour (red for errors, brand for info).
  final AppAccent? accent;

  /// Optional button under the message (e.g. "Fill in").
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (defaultAccent, defaultIcon) = switch (kind) {
      AuthBannerKind.error => (AuthAccents.error, AppIcons.error),
      AuthBannerKind.info => (AuthAccents.brand, AppIcons.info),
    };
    final a = accent ?? defaultAccent;
    final shades = context.accent(a);

    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: shades.container,
          borderRadius: AppRadius.brCard,
        ),
        child: Padding(
          padding: AppSpacing.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: IconBadge(
                      icon: icon ?? defaultIcon,
                      accent: a,
                      size: AppSizes.badgeSm,
                    ),
                  ),
                  AppGap.hMd,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title != null) ...[
                          Text(
                            title!,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: shades.onContainer,
                            ),
                          ),
                          AppGap.xxs,
                        ] else
                          // Centres a one-line message on the badge.
                          AppGap.xs,
                        Text(
                          message,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: shades.onContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (action != null)
                Align(alignment: AlignmentDirectional.centerEnd, child: action),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Question? [Link]" line under a form, wrapping on narrow / large-text
/// screens.
class AuthLinkRow extends StatelessWidget {
  const AuthLinkRow({
    super.key,
    required this.text,
    required this.linkLabel,
    required this.onPressed,
  });

  final String text;
  final String linkLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.xxs,
      children: [
        Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        AppButton(
          label: linkLabel,
          onPressed: onPressed,
          variant: AppButtonVariant.text,
          expand: false,
        ),
      ],
    );
  }
}
