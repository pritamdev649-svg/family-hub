import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/emergency_card/application/emergency_card_providers.dart';
import 'package:family_hub/features/emergency_card/presentation/emergency_card_actions.dart';
import 'package:family_hub/features/emergency_card/presentation/emergency_card_style.dart';
import 'package:family_hub/features/emergency_card/presentation/widgets/blood_group_badge.dart';
import 'package:family_hub/features/emergency_card/presentation/widgets/card_notice.dart';
import 'package:family_hub/features/emergency_card/presentation/widgets/emergency_card_view.dart';
import 'package:family_hub/features/emergency_card/presentation/widgets/emergency_chrome.dart';
import 'package:family_hub/shared/models/member.dart';

/// "Show to responder": the card full screen, in a maximum-contrast dark
/// scheme (near-black canvas, huge white type, solid emergency red for the
/// blood group and allergies), for handing the phone to a doctor or
/// paramedic. It looks the same whether the app is in light or dark mode, so
/// a responder always gets the same, predictable view; the status bar stays
/// transparent with light icons. Only the facts a responder needs, in the
/// order they need them; every contact is a full-width call button.
///
/// Opened as a full-screen dialog over the current route (it is a view mode
/// of the card screen, not a separate location).
///
/// [card] is the card at the moment the view was opened; with [followUpdates]
/// (default) the view switches to newer versions from
/// [emergencyCardProvider] — e.g. the fresh card replacing an offline copy a
/// few seconds later — and keeps [card] when the provider has nothing (yet).
class EmergencyCardResponderScreen extends ConsumerWidget {
  const EmergencyCardResponderScreen({
    super.key,
    required this.card,
    this.member,
    this.followUpdates = true,
  });

  final EmergencyCard card;
  final Member? member;
  final bool followUpdates;

  /// The open responder view, if any.
  static Route<void>? _route;

  /// Opens the view; a second tap while one is already open (or opening) is
  /// ignored, so rapid taps never stack copies. Tied to the route itself, so
  /// a navigator torn down with the view open (e.g. logout) never blocks it.
  static Future<void> open(
    BuildContext context, {
    required EmergencyCard card,
    Member? member,
  }) {
    if (_route?.isActive ?? false) return Future<void>.value();
    final route = MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => EmergencyCardResponderScreen(card: card, member: member),
    );
    _route = route;
    return Navigator.of(
      context,
      rootNavigator: true,
    ).push<void>(route).whenComplete(() {
      if (identical(_route, route)) _route = null;
    });
  }

  /// The responder theme: the app's dark theme with the highest-contrast
  /// scheme of its emergency red, on the app's near-black canvas and
  /// charcoal cards. Built once.
  static final ThemeData _theme = () {
    final base = AppTheme.dark();
    const semantic = AppSemanticColors.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: semantic.sos,
          brightness: Brightness.dark,
          contrastLevel: 1,
        ).copyWith(
          surface: semantic.canvas,
          surfaceContainer: semantic.card,
          surfaceContainerHigh: semantic.card,
          surfaceContainerHighest: semantic.card,
          surfaceTint: Colors.transparent,
        );
    return base.copyWith(
      colorScheme: scheme,
      // Same type scale / fonts as the app, recoloured for the new scheme.
      textTheme: base.textTheme.merge(AppTypography.textTheme(scheme)),
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      iconTheme: base.iconTheme.copyWith(color: scheme.onSurface),
    );
  }();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = followUpdates && card.memberId.isNotEmpty
        ? ref.watch(
                emergencyCardProvider(card.memberId).select((v) => v.value),
              ) ??
              card
        : card;
    return Theme(
      data: _theme,
      // Transparent status bar with light icons over the dark canvas.
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppSystemUi.forBackground(Brightness.dark),
        child: _ResponderBody(card: shown, member: member),
      ),
    );
  }
}

class _ResponderBody extends ConsumerWidget {
  const _ResponderBody({required this.card, required this.member});

  final EmergencyCard card;
  final Member? member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fmt = ref.watch(fmtProvider);
    final offlineSavedAt = card.offlineSavedAt;
    final updatedAt = card.updatedAt;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final m = member;

    final itemStyle = theme.textTheme.headlineSmall?.copyWith(
      color: scheme.onSurface,
    );

    final sections = <Widget>[
      _ResponderSection(
        icon: AppIcons.allergy,
        accent: EmergencyCardAccents.allergies,
        title: l10n.emergencyCardAllergies,
        highlight: card.allergies.isNotEmpty,
        children: [for (final a in card.allergies) _AllergyLine(allergy: a)],
      ),
      _ResponderSection(
        icon: AppIcons.medication,
        accent: EmergencyCardAccents.medications,
        title: l10n.emergencyCardMedications,
        children: [for (final m in card.medications) Text(m, style: itemStyle)],
      ),
      _ResponderSection(
        icon: AppIcons.condition,
        accent: EmergencyCardAccents.conditions,
        title: l10n.emergencyCardConditions,
        children: [for (final c in card.conditions) Text(c, style: itemStyle)],
      ),
      _ResponderSection(
        icon: AppIcons.emergencyContact,
        accent: EmergencyCardAccents.contacts,
        title: l10n.emergencyCardContacts,
        children: [
          for (var i = 0; i < card.emergencyContacts.length; i++)
            _ResponderPerson(
              name: contactDisplayName(l10n, card.emergencyContacts[i], i),
              detail: card.emergencyContacts[i].relation,
              phone: card.emergencyContacts[i].phone,
              callAccent: EmergencyCardAccents.callContact,
            ),
        ],
      ),
      if (card.hasDoctor)
        _ResponderSection(
          icon: AppIcons.doctor,
          accent: EmergencyCardAccents.doctor,
          title: l10n.emergencyCardDoctor,
          children: [
            _ResponderPerson(
              name: card.doctorName ?? l10n.emergencyCardDoctor,
              phone: card.doctorPhone,
              callAccent: EmergencyCardAccents.callDoctor,
            ),
          ],
        ),
      if (card.hasInsurance)
        _ResponderSection(
          icon: AppIcons.insurance,
          accent: EmergencyCardAccents.insurance,
          title: l10n.emergencyCardInsurance,
          children: [
            if (card.insuranceProvider != null)
              Text(card.insuranceProvider!, style: itemStyle),
            if (card.insurancePolicyNumber != null)
              _PolicyNumber(
                number: card.insurancePolicyNumber!,
                style: itemStyle,
              ),
          ],
        ),
      if (card.notes != null)
        _ResponderSection(
          icon: AppIcons.notes,
          accent: EmergencyCardAccents.notes,
          title: l10n.emergencyCardNotes,
          children: [
            Text(
              card.notes!,
              style: theme.textTheme.titleLarge?.copyWith(
                color: scheme.onSurface,
                fontWeight: AppTypography.regular,
              ),
            ),
          ],
        ),
    ];

    return Scaffold(
      body: Column(
        children: [
          // Pinned top bar: close is always within reach.
          SafeArea(
            bottom: false,
            child: ResponsiveCenter(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.sm,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: l10n.emergencyCardResponderClose,
                      icon: const Icon(AppIcons.close),
                      onPressed: () => Navigator.of(context).maybePop(),
                      style: IconButton.styleFrom(
                        backgroundColor: scheme.surfaceContainerHigh,
                        foregroundColor: scheme.onSurface,
                      ),
                    ),
                    AppGap.hMd,
                    const IconBadge(
                      icon: AppIcons.emergencyCard,
                      accent: AppAccents.sos,
                      size: AppSizes.badgeSm,
                    ),
                    AppGap.hSm,
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          l10n.emergencyCardResponderHint,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ResponsiveCenter(
              child: ListView(
                padding: EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.xl + bottomInset,
                ),
                children: [
                  if (offlineSavedAt != null) ...[
                    CardNotice(
                      icon: AppIcons.offline,
                      accent: AppAccents.warning,
                      text: l10n.emergencyCardOfflineCopy(
                        fmt.relative(offlineSavedAt, l10n),
                      ),
                    ),
                    AppGap.lg,
                  ],
                  if (m != null) ...[
                    Semantics(
                      header: true,
                      child: Text(
                        m.name,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: AppTypography.extraBold,
                        ),
                      ),
                    ),
                    AppGap.lg,
                  ],
                  Center(
                    child: BloodGroupBadge(
                      group: card.bloodGroup,
                      size: BloodGroupBadgeSize.hero,
                    ),
                  ),
                  AppGap.xl,
                  for (final section in sections) ...[section, AppGap.md],
                  AppGap.md,
                  Text(
                    updatedAt != null
                        ? l10n.emergencyCardLastUpdated(fmt.dateTime(updatedAt))
                        : l10n.emergencyCardNotStarted,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                  AppGap.sm,
                  Text(
                    l10n.emergencyCardDisclaimer,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  AppGap.xl,
                  AppButton(
                    label: l10n.commonClose,
                    icon: AppIcons.close,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One block of the responder view: a borderless charcoal card (solid red
/// with white text for known allergies) led by a solid icon badge. Empty
/// lists show "Not recorded".
class _ResponderSection extends StatelessWidget {
  const _ResponderSection({
    required this.icon,
    required this.accent,
    required this.title,
    required this.children,
    this.highlight = false,
  });

  final IconData icon;
  final AppAccent accent;
  final String title;
  final List<Widget> children;

  /// Solid emergency red (known allergies).
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semanticColors;
    final foreground = highlight ? semantic.onSos : scheme.onSurface;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: highlight ? semantic.sos : scheme.surfaceContainerHigh,
        borderRadius: AppRadius.brCard,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (highlight)
                  EmergencyGlassIcon(icon: icon, size: AppSizes.badgeMd)
                else
                  IconBadge(icon: icon, accent: accent),
                AppGap.hMd,
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: foreground,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            AppGap.md,
            if (children.isEmpty)
              Text(
                context.l10n.emergencyCardNotRecorded,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) AppGap.md,
                children[i],
              ],
          ],
        ),
      ),
    );
  }
}

/// A known allergy in big bold type on the red block.
class _AllergyLine extends StatelessWidget {
  const _AllergyLine({required this.allergy});

  final String allergy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSos = context.semanticColors.onSos;
    return Semantics(
      container: true,
      label: context.l10n.emergencyCardAllergySemantics(allergy),
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(top: AppSpacing.xs),
            child: Icon(AppIcons.warning, color: onSos, size: AppSizes.iconMd),
          ),
          AppGap.hSm,
          Expanded(
            child: Text(
              allergy,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: onSos,
                fontWeight: AppTypography.extraBold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicyNumber extends StatelessWidget {
  const _PolicyNumber({required this.number, required this.style});

  final String number;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: SelectableText(
              number,
              textDirection: TextDirection.ltr,
              style: style?.merge(AppTypography.tabularFigures),
            ),
          ),
        ),
        AppGap.hSm,
        IconButton(
          tooltip: l10n.emergencyCardCopyPolicyNumber,
          icon: const Icon(AppIcons.copy),
          onPressed: () => copyPolicyNumber(context, number),
          style: IconButton.styleFrom(
            backgroundColor: scheme.surface,
            foregroundColor: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _ResponderPerson extends StatelessWidget {
  const _ResponderPerson({
    required this.name,
    required this.callAccent,
    this.detail,
    this.phone,
  });

  final String name;
  final String? detail;
  final String? phone;
  final AppAccent callAccent;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final number = phone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          detail == null
              ? name
              : l10n.emergencyCardPersonWithRelation(name, detail!),
          style: theme.textTheme.headlineSmall?.copyWith(
            color: scheme.onSurface,
          ),
        ),
        // Numbers stay left-to-right but sit at the start edge (RTL-safe).
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            number ?? l10n.emergencyCardNoPhone,
            textDirection: number == null ? null : TextDirection.ltr,
            style: theme.textTheme.titleLarge
                ?.merge(AppTypography.tabularFigures)
                .copyWith(
                  color: number == null
                      ? scheme.onSurfaceVariant
                      : scheme.onSurface,
                  fontWeight: AppTypography.regular,
                ),
          ),
        ),
        if (number != null) ...[
          AppGap.sm,
          CallButton(
            name: name,
            phone: number,
            expand: true,
            accent: callAccent,
          ),
        ],
      ],
    );
  }
}
