import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/emergency_card/domain/emergency_card.dart';
import 'package:family_hub/features/emergency_card/presentation/emergency_card_actions.dart';
import 'package:family_hub/features/emergency_card/presentation/emergency_card_style.dart';
import 'package:family_hub/features/emergency_card/presentation/widgets/blood_group_badge.dart';
import 'package:family_hub/features/emergency_card/presentation/widgets/card_notice.dart';
import 'package:family_hub/features/emergency_card/presentation/widgets/emergency_section.dart';
import 'package:family_hub/shared/models/member.dart';

/// Read-only emergency card (public API, docs/05-FLUTTER_GUIDE.md §10).
///
/// A non-scrolling column: place it in a `ListView` / scroll view. Every
/// section is a borderless card led by a solid icon badge in its own colour
/// (allergies amber, medications violet, conditions rose, contacts sky,
/// doctor blue, insurance emerald): allergies as warning chips, medications
/// and conditions as chips, emergency contacts and the doctor with round
/// one-tap call buttons, insurance with a copy button for the policy number,
/// notes, and when the card was last updated. Offline copies get an
/// "offline copy" hint.
///
/// With [showHeader] (default) the column starts with a member card (avatar,
/// name, solid blood group badge); screens that show the member and blood
/// group in their own gradient header pass `false`. [member] is optional
/// (e.g. while offline without a member directory); the header then shows
/// only the blood group. [onEdit] adds a "Fill in card" button to an empty
/// card — pass it only when the viewer may edit.
class EmergencyCardView extends ConsumerWidget {
  const EmergencyCardView({
    super.key,
    required this.card,
    required this.member,
    this.onEdit,
    this.showHeader = true,
  });

  final EmergencyCard card;
  final Member? member;
  final VoidCallback? onEdit;
  final bool showHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final fmt = ref.watch(fmtProvider);
    final offlineSavedAt = card.offlineSavedAt;
    final updatedAt = card.updatedAt;

    final sections = <Widget>[
      if (offlineSavedAt != null)
        CardNotice(
          icon: AppIcons.offline,
          accent: AppAccents.warning,
          text: l10n.emergencyCardOfflineCopy(
            fmt.relative(offlineSavedAt, l10n),
          ),
          liveRegion: true,
        ),
      if (showHeader) _Header(card: card, member: member),
      if (card.isEmpty)
        _EmptyCard(onEdit: onEdit)
      else ...[
        EmergencySectionCard(
          icon: AppIcons.allergy,
          accent: EmergencyCardAccents.allergies,
          title: l10n.emergencyCardAllergies,
          child: _Chips(
            items: card.allergies,
            accent: EmergencyCardAccents.allergies,
            icon: AppIcons.warning,
            semanticsLabel: l10n.emergencyCardAllergySemantics,
          ),
        ),
        EmergencySectionCard(
          icon: AppIcons.medication,
          accent: EmergencyCardAccents.medications,
          title: l10n.emergencyCardMedications,
          child: _Chips(
            items: card.medications,
            accent: EmergencyCardAccents.medications,
          ),
        ),
        EmergencySectionCard(
          icon: AppIcons.condition,
          accent: EmergencyCardAccents.conditions,
          title: l10n.emergencyCardConditions,
          child: _Chips(
            items: card.conditions,
            accent: EmergencyCardAccents.conditions,
          ),
        ),
        EmergencySectionCard(
          icon: AppIcons.emergencyContact,
          accent: EmergencyCardAccents.contacts,
          title: l10n.emergencyCardContacts,
          child: card.emergencyContacts.isEmpty
              ? const _NotRecorded()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < card.emergencyContacts.length; i++) ...[
                      // Hairlines are allowed as dividers inside a card.
                      if (i > 0) const Divider(height: AppSpacing.xl),
                      _PersonRow(
                        name: contactDisplayName(
                          l10n,
                          card.emergencyContacts[i],
                          i,
                        ),
                        detail: card.emergencyContacts[i].relation,
                        phone: card.emergencyContacts[i].phone,
                        callAccent: EmergencyCardAccents.callContact,
                      ),
                    ],
                  ],
                ),
        ),
        if (card.hasDoctor)
          EmergencySectionCard(
            icon: AppIcons.doctor,
            accent: EmergencyCardAccents.doctor,
            title: l10n.emergencyCardDoctor,
            child: _PersonRow(
              name: card.doctorName ?? l10n.emergencyCardDoctor,
              phone: card.doctorPhone,
              callAccent: EmergencyCardAccents.callDoctor,
            ),
          ),
        if (card.hasInsurance)
          EmergencySectionCard(
            icon: AppIcons.insurance,
            accent: EmergencyCardAccents.insurance,
            title: l10n.emergencyCardInsurance,
            child: _Insurance(card: card),
          ),
        if (card.notes != null)
          EmergencySectionCard(
            icon: AppIcons.notes,
            accent: EmergencyCardAccents.notes,
            title: l10n.emergencyCardNotes,
            child: Text(card.notes!, style: theme.textTheme.bodyLarge),
          ),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) AppGap.md,
          sections[i],
        ],
        AppGap.xl,
        Text(
          updatedAt != null
              ? l10n.emergencyCardLastUpdated(fmt.dateTime(updatedAt))
              : l10n.emergencyCardNotStarted,
          textAlign: TextAlign.center,
          style: muted,
        ),
        AppGap.sm,
        Text(
          l10n.emergencyCardDisclaimer,
          textAlign: TextAlign.center,
          style: muted,
        ),
      ],
    );
  }
}

/// Member card on top of the embedded view (e.g. inside an SOS alert).
class _Header extends StatelessWidget {
  const _Header({required this.card, required this.member});

  final EmergencyCard card;
  final Member? member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = member;
    final designation = m?.designation;
    return AppCard(
      child: Row(
        children: [
          if (m != null) ...[
            MemberAvatar(
              name: m.name,
              avatarUrl: m.avatarUrl,
              radius: AppSizes.avatarLg,
            ),
            AppGap.hMd,
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    m?.name ?? context.l10n.emergencyCardTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (designation != null)
                  Text(
                    designation,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          AppGap.hMd,
          BloodGroupBadge(
            group: card.bloodGroup,
            size: BloodGroupBadgeSize.large,
          ),
        ],
      ),
    );
  }
}

/// A card with nothing filled in: invitation to fill it in (or read-only
/// notice for everyone else).
class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.onEdit});

  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return EmergencyStateCard(
      icon: AppIcons.emergencyCardOutlined,
      accent: EmergencyCardAccents.module,
      title: l10n.emergencyCardEmptyTitle,
      message: onEdit != null
          ? l10n.emergencyCardEmptyMessage
          : l10n.emergencyCardEmptyReadOnly,
      action: onEdit == null
          ? null
          : AppButton(
              label: l10n.emergencyCardFillIn,
              icon: AppIcons.edit,
              expand: false,
              onPressed: onEdit,
            ),
    );
  }
}

/// Wrapping soft chips in the section's [accent] (never truncated — every
/// character matters here).
class _Chips extends StatelessWidget {
  const _Chips({
    required this.items,
    required this.accent,
    this.icon,
    this.semanticsLabel,
  });

  final List<String> items;
  final AppAccent accent;
  final IconData? icon;
  final String Function(String item)? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const _NotRecorded();
    final theme = Theme.of(context);
    final shades = context.accent(accent);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final item in items)
          Semantics(
            container: true,
            label: semanticsLabel?.call(item),
            excludeSemantics: semanticsLabel != null,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: shades.container,
                borderRadius: AppRadius.brMd,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        size: AppSizes.iconXs,
                        color: shades.foreground,
                      ),
                      AppGap.hXs,
                    ],
                    Flexible(
                      child: Text(
                        item,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: shades.onContainer,
                          fontWeight: AppTypography.semiBold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _NotRecorded extends StatelessWidget {
  const _NotRecorded();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      context.l10n.emergencyCardNotRecorded,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}

/// A contact's name for display; "Contact 2" when the stored name is blank
/// (never sent by the contract, but the card must still be callable).
String contactDisplayName(
  AppLocalizations l10n,
  EmergencyContact contact,
  int index,
) {
  final name = contact.name.trim();
  return name.isEmpty ? l10n.emergencyCardContactNumber(index + 1) : name;
}

/// Avatar, name, optional relation and phone, with a round call button.
class _PersonRow extends StatelessWidget {
  const _PersonRow({
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
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final number = phone;
    return Row(
      children: [
        ExcludeSemantics(
          child: MemberAvatar(name: name, radius: AppSizes.avatarMd),
        ),
        AppGap.hMd,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, style: theme.textTheme.titleSmall),
              if (detail != null) Text(detail!, style: muted),
              AppGap.xxs,
              if (number != null)
                Text(
                  number,
                  textDirection: TextDirection.ltr,
                  style: theme.textTheme.bodyMedium?.merge(
                    AppTypography.tabularFigures,
                  ),
                )
              else
                Text(l10n.emergencyCardNoPhone, style: muted),
            ],
          ),
        ),
        if (number != null) ...[
          AppGap.hMd,
          CallButton(name: name, phone: number, accent: callAccent),
        ],
      ],
    );
  }
}

/// Call button (dialer), labelled "Call `name`" for screen readers.
///
/// By default a round solid [accent] button with a white phone icon (next
/// to a contact); with [expand] a full-width solid button that also shows
/// "Call `name`" as text (responder view).
class CallButton extends StatelessWidget {
  const CallButton({
    super.key,
    required this.name,
    required this.phone,
    this.expand = false,
    this.accent = EmergencyCardAccents.callContact,
  });

  final String name;
  final String phone;
  final bool expand;
  final AppAccent accent;

  @override
  Widget build(BuildContext context) {
    final label = context.l10n.emergencyCardCallPerson(name);
    void call() => callFromEmergencyCard(context, phone);

    final Widget button;
    if (expand) {
      button = SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: call,
          icon: const Icon(AppIcons.phone, size: AppSizes.iconSm),
          label: Text(label, textAlign: TextAlign.center),
          style: FilledButton.styleFrom(
            // The deep shade keeps white text at AA contrast.
            backgroundColor: accent.dark,
            foregroundColor: Colors.white,
            minimumSize: const Size(
              AppSizes.minTapTarget,
              AppSizes.buttonHeight,
            ),
          ),
        ),
      );
    } else {
      button = DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              // Same soft glow as core `ActionTile`.
              color: accent.base.withValues(alpha: AppColors.glowOpacity * 0.6),
              blurRadius: AppSizes.cardShadowBlur,
              offset: const Offset(0, AppSpacing.xxs),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Ink(
            decoration: BoxDecoration(
              gradient: AppGradients.of(accent),
              shape: BoxShape.circle,
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: call,
              child: const SizedBox.square(
                dimension: AppSizes.minTapTarget,
                child: Icon(
                  AppIcons.phone,
                  size: AppSizes.iconSm,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        label: label,
        button: true,
        excludeSemantics: true,
        onTap: call,
        child: button,
      ),
    );
  }
}

class _Insurance extends StatelessWidget {
  const _Insurance({required this.card});

  final EmergencyCard card;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final shades = context.accent(EmergencyCardAccents.insurance);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final provider = card.insuranceProvider;
    final policy = card.insurancePolicyNumber;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (provider != null) ...[
          Text(l10n.emergencyCardInsuranceProvider, style: muted),
          Text(provider, style: theme.textTheme.titleSmall),
        ],
        if (provider != null && policy != null) AppGap.md,
        if (policy != null)
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.emergencyCardPolicyNumber, style: muted),
                    SelectableText(
                      policy,
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.titleSmall?.merge(
                        AppTypography.tabularFigures,
                      ),
                    ),
                  ],
                ),
              ),
              AppGap.hSm,
              IconButton(
                tooltip: l10n.emergencyCardCopyPolicyNumber,
                onPressed: () => copyPolicyNumber(context, policy),
                icon: const Icon(AppIcons.copy),
                style: IconButton.styleFrom(
                  backgroundColor: shades.container,
                  foregroundColor: shades.foreground,
                  iconSize: AppSizes.iconSm,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
