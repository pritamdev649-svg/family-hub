import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:family_hub/core/config/countries.dart';
import 'package:family_hub/core/config/timezones.dart';
import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/core/widgets/widgets.dart';
// Same picker as registration (f-auth owns it).
import 'package:family_hub/features/auth/presentation/widgets/country_picker.dart';
import 'package:family_hub/features/family/application/family_providers.dart';
import 'package:family_hub/features/family/application/family_session_sync.dart';
import 'package:family_hub/features/family/application/family_settings_controller.dart';
import 'package:family_hub/features/family/domain/family_limits.dart';
import 'package:family_hub/features/family/presentation/family_navigation.dart';
import 'package:family_hub/features/family/presentation/family_style.dart';
import 'package:family_hub/features/family/presentation/widgets/family_info_row.dart';
import 'package:family_hub/features/family/presentation/widgets/field_help_text.dart';
import 'package:family_hub/features/family/presentation/widgets/invite_code_card.dart';
import 'package:family_hub/shared/models/family.dart';
import 'package:family_hub/shared/session/session_controller.dart';

/// Family settings: admins edit name, country, currency and time zone and
/// manage the invite code; members see a read-only summary.
///
/// A fresher family (e.g. changed on another device) updates the session,
/// so money formatting, consent age etc. follow it everywhere; the view
/// switches between admin and read-only as the role changes (the family is
/// refetched then, since only admins get the invite code).
class FamilySettingsScreen extends ConsumerWidget {
  const FamilySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final family = ref.watch(familyProvider);
    final isAdmin = ref.watch(isAdminProvider);
    ref.syncFamilySession(members: false, family: true);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.familySettingsTitle)),
      body: ResponsiveCenter(
        child: AppRefreshIndicator(
          onRefresh: () => ref.refresh(familyProvider.future),
          child: AsyncValueView<Family?>(
            value: family,
            onRetry: () => ref.invalidate(familyProvider),
            isEmpty: (f) => f == null,
            empty: EmptyState(
              icon: AppIcons.family,
              title: l10n.familyNotFoundTitle,
              message: l10n.errorNoFamily,
            ),
            data: (f) => switch (f) {
              null => const SizedBox.shrink(), // handled by `empty`
              _ when isAdmin => _AdminSettings(family: f),
              _ => _ReadOnlySettings(family: f),
            },
          ),
        ),
      ),
    );
  }
}

// ── Admin ───────────────────────────────────────────────────────────────────

class _AdminSettings extends ConsumerStatefulWidget {
  const _AdminSettings({required this.family});

  final Family family;

  @override
  ConsumerState<_AdminSettings> createState() => _AdminSettingsState();
}

class _AdminSettingsState extends ConsumerState<_AdminSettings> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;

  /// Last saved state; the patch is computed against it.
  late Family _base;
  late String _country;
  late String _currency;
  late String _timezone;

  /// Latest family (invite code, member count) incl. mutation results.
  late Family _latest;

  bool _leaving = false;
  bool _resetting = false;

  @override
  void initState() {
    super.initState();
    _latest = widget.family;
    _name = TextEditingController()..addListener(_onChanged);
    _reset(widget.family);
  }

  @override
  void didUpdateWidget(_AdminSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.family != oldWidget.family) {
      _latest = widget.family;
      // Never overwrite the admin's unsaved edits with a background refresh.
      if (!_isDirty) _reset(widget.family);
    }
  }

  @override
  void dispose() {
    _name
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!_resetting) setState(() {});
  }

  void _reset(Family family) {
    _base = family;
    _resetting = true;
    _name.text = family.name;
    _resetting = false;
    _country = family.country;
    _currency = family.currency;
    _timezone = family.timezone;
  }

  bool get _isDirty =>
      _name.text.trim() != _base.name ||
      _country != _base.country ||
      _currency != _base.currency ||
      _timezone != _base.timezone;

  void _onCountry(String code) {
    final country = Countries.byCode(code);
    setState(() {
      // Follow the new country's currency unless a different one was chosen
      // on purpose (e.g. an expat family).
      if (_currency == Countries.byCode(_country).currency) {
        _currency = country.currency;
      }
      _timezone = Timezones.normalizeFor(country.code, _timezone);
      _country = country.code;
    });
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    try {
      final saved = await ref
          .read(familySettingsControllerProvider.notifier)
          .save(
            _base,
            name: _name.text,
            country: _country,
            currency: _currency,
            timezone: _timezone,
          );
      if (saved == null || !mounted) return;
      setState(() {
        _latest = saved;
        _reset(saved);
      });
      context.showSuccess(l10n.familySettingsSaved);
    } catch (e) {
      if (mounted) context.showError(e);
    }
  }

  Future<void> _regenerate() async {
    // A second tap while the dialog opens must not open another one.
    if (!context.isTopRoute) return;
    final l10n = context.l10n;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.familyNewInviteCodeConfirmTitle,
      message: l10n.familyNewInviteCodeConfirmMessage,
      confirmLabel: l10n.familyNewInviteCodeConfirm,
    );
    if (!confirmed || !mounted) return;
    try {
      final family = await ref
          .read(familySettingsControllerProvider.notifier)
          .regenerateInviteCode();
      if (family == null || !mounted) return;
      setState(() => _latest = family);
      context.showSuccess(l10n.familyNewInviteCodeCreated);
    } catch (e) {
      if (mounted) context.showError(e);
    }
  }

  Future<void> _confirmDiscard() async {
    final l10n = context.l10n;
    final discard = await showConfirmDialog(
      context,
      title: l10n.commonDiscardChangesTitle,
      message: l10n.commonDiscardChangesMessage,
      confirmLabel: l10n.commonDiscard,
      destructive: true,
    );
    if (!discard || !mounted) return;
    setState(() => _leaving = true);
    context.popOrGo(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final action = ref.watch(familySettingsControllerProvider);
    final busy = action != null;
    final country = Countries.byCode(_country);
    final inviteCode = _latest.inviteCode;

    return PopScope(
      canPop: _leaving || !_isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Form(
        key: _formKey,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: _screenPadding(context),
          children: [
            // Admins always receive the code; while a just-promoted admin's
            // family is refetched it may still be missing.
            if (inviteCode != null) ...[
              InviteCodeCard(
                familyName: _latest.name,
                code: inviteCode,
                enabled: !busy,
                regenerating:
                    action == FamilySettingsAction.regenerateInviteCode,
                onRegenerate: _regenerate,
              ),
              AppGap.xl,
            ],
            const _ProfileSectionHeader(),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTextField(
                    controller: _name,
                    label: l10n.familyNameFieldLabel,
                    prefixIcon: AppIcons.family,
                    maxLength: FamilyLimits.name,
                    enabled: !busy,
                    textCapitalization: TextCapitalization.words,
                    validator: Validators.compose([
                      Validators.required(l10n),
                      Validators.maxLength(l10n, FamilyLimits.name),
                    ]),
                  ),
                  AppGap.md,
                  CountryPickerField(
                    value: _country,
                    enabled: !busy,
                    onChanged: _onCountry,
                  ),
                  FieldHelpText(
                    l10n.familyCountryDetails(
                      country.emergencyNumber,
                      country.consentAge,
                    ),
                  ),
                  AppGap.lg,
                  _CurrencyField(
                    value: _currency,
                    enabled: !busy,
                    onChanged: (c) => setState(() => _currency = c),
                  ),
                  AppGap.lg,
                  _TimezoneField(
                    country: _country,
                    value: _timezone,
                    enabled: !busy,
                    onChanged: (z) => setState(() => _timezone = z),
                  ),
                ],
              ),
            ),
            AppGap.lg,
            AppButton(
              label: l10n.commonSave,
              icon: AppIcons.save,
              isLoading: action == FamilySettingsAction.save,
              onPressed: _isDirty && !busy ? _save : null,
            ),
            AppGap.xl,
            _MembersCard(count: _latest.memberCount),
          ],
        ),
      ),
    );
  }
}

class _CurrencyField extends ConsumerWidget {
  const _CurrencyField({
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(fmtProvider.select((f) => f.intlLocale));
    final all = Countries.currencies;
    final options = all.contains(value) ? all : [value, ...all];
    return AppDropdownField<String>(
      // Rebuilt when the value changes programmatically (country switch).
      key: ValueKey<String>('currency-$value'),
      label: context.l10n.familyCurrencyLabel,
      value: value,
      items: options,
      itemLabel: (code) => currencyLabel(code, locale),
      onChanged: enabled
          ? (code) {
              if (code != null) onChanged(code);
            }
          : null,
    );
  }

  /// `INR (₹)`, or just the code when the locale has no distinct symbol.
  static String currencyLabel(String code, String locale) {
    try {
      final symbol = NumberFormat.simpleCurrency(
        locale: locale,
        name: code,
      ).currencySymbol;
      return symbol.isEmpty || symbol == code ? code : '$code ($symbol)';
    } catch (_) {
      return code;
    }
  }
}

class _TimezoneField extends StatelessWidget {
  const _TimezoneField({
    required this.country,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String country;
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final zones = Timezones.forCountry(country);
    final options = zones.contains(value) ? zones : [value, ...zones];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDropdownField<String>(
          key: ValueKey<String>('timezone-$country-$value'),
          label: l10n.familyTimezoneLabel,
          value: value,
          items: options,
          itemLabel: Timezones.cityName,
          onChanged: enabled
              ? (zone) {
                  if (zone != null) onChanged(zone);
                }
              : null,
        ),
        FieldHelpText(l10n.familyTimezoneHint),
      ],
    );
  }
}

// ── Read-only (members) ─────────────────────────────────────────────────────

class _ReadOnlySettings extends ConsumerWidget {
  const _ReadOnlySettings({required this.family});

  final Family family;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final locale = ref.watch(fmtProvider.select((f) => f.intlLocale));
    final country = family.countryInfo;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: _screenPadding(context),
      children: [
        // Members never receive the code: the card says to ask an admin.
        InviteCodeCard(familyName: family.name),
        AppGap.xl,
        const _ProfileSectionHeader(),
        AppCard(
          child: Column(
            children: [
              FamilyInfoRow(
                icon: AppIcons.country,
                accent: AppAccent.teal,
                label: l10n.familyCountryLabel,
                value: '${country.flag} ${country.name}',
                detail: l10n.familyCountryDetails(
                  country.emergencyNumber,
                  country.consentAge,
                ),
              ),
              FamilyInfoRow(
                icon: AppIcons.currency,
                accent: AppAccents.money,
                label: l10n.familyCurrencyLabel,
                value: _CurrencyField.currencyLabel(family.currency, locale),
              ),
              FamilyInfoRow(
                icon: AppIcons.time,
                accent: AppAccent.violet,
                label: l10n.familyTimezoneLabel,
                value: Timezones.cityName(family.timezone),
                detail: family.timezone,
              ),
            ],
          ),
        ),
        AppGap.md,
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.xs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(AppIcons.info, size: AppSizes.iconSm, color: muted),
              AppGap.hSm,
              Expanded(
                child: Text(
                  l10n.familySettingsReadOnly,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
            ],
          ),
        ),
        AppGap.xl,
        _MembersCard(count: family.memberCount),
      ],
    );
  }
}

/// Screen padding that keeps the last card clear of the bottom inset.
EdgeInsets _screenPadding(BuildContext context) => AppSpacing.screen.copyWith(
  bottom: AppSpacing.lg + MediaQuery.paddingOf(context).bottom,
);

class _ProfileSectionHeader extends StatelessWidget {
  const _ProfileSectionHeader();

  @override
  Widget build(BuildContext context) {
    return SectionHeader(
      title: context.l10n.familyProfileSection,
      icon: AppIcons.family,
      accent: FamilyStyle.accent,
    );
  }
}

/// "4 members · View members" row: a solid blue icon badge, like the
/// settings rows elsewhere in the app.
class _MembersCard extends StatelessWidget {
  const _MembersCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return AppCard(
      onTap: () => context.pushIfTop(AppRoutes.members),
      child: Row(
        children: [
          const IconBadge(icon: AppIcons.members, accent: FamilyStyle.accent),
          AppGap.hMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.familyMembersCount(count),
                  style: theme.textTheme.titleSmall,
                ),
                AppGap.xxs,
                Text(
                  l10n.familyViewMembers,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
          AppGap.hSm,
          Icon(AppIcons.chevron, size: AppSizes.iconSm, color: muted),
        ],
      ),
    );
  }
}
