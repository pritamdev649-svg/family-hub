import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:family_hub/core/config/app_languages.dart';
import 'package:family_hub/core/config/countries.dart';
import 'package:family_hub/core/config/timezones.dart';
import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/settings/settings_controller.dart';
import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/auth/application/auth_errors.dart';
import 'package:family_hub/features/auth/domain/family_draft.dart';
import 'package:family_hub/features/auth/domain/register_args.dart';
import 'package:family_hub/features/auth/presentation/auth_labels.dart';
import 'package:family_hub/features/auth/presentation/auth_validators.dart';
import 'package:family_hub/features/auth/presentation/widgets/auth_code_fields.dart';
import 'package:family_hub/features/auth/presentation/widgets/auth_form.dart';
import 'package:family_hub/features/auth/presentation/widgets/auth_layout.dart';
import 'package:family_hub/features/auth/presentation/widgets/country_picker.dart';
import 'package:family_hub/features/auth/presentation/widgets/language_picker.dart';
import 'package:family_hub/shared/data/family_repository.dart'
    show CreateFamilyRequest;

/// State of a [FamilyForm]: the name field plus the [FamilyDraft]
/// (country / currency / time zone). Owned and disposed by the screen.
class FamilyFormController extends ChangeNotifier {
  FamilyFormController({FamilyDraft? draft, String name = ''})
    : name = TextEditingController(text: name),
      _draft = draft ?? FamilyDraft.forCountry(null);

  final TextEditingController name;
  FamilyDraft _draft;

  FamilyDraft get draft => _draft;

  set draft(FamilyDraft value) {
    if (value == _draft) return;
    _draft = value;
    notifyListeners();
  }

  /// Picks a country and pre-fills its currency and time zone.
  void selectCountry(String code) => draft = _draft.withCountry(code);

  void selectCurrency(String currency) =>
      draft = _draft.copyWith(currency: currency);

  void selectTimezone(String timezone) =>
      draft = _draft.copyWith(timezone: timezone);

  CreateFamilyRequest toRequest() => _draft.toRequest(name.text);

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }
}

/// The "create a family" fields, shared by sign-up (create mode) and family
/// setup: name, country (searchable), currency and time zone. Picking a
/// country pre-fills currency + time zone and offers to switch the app to
/// the country's main language.
///
/// Server errors are read from [serverErrors] under the [AuthField.family*]
/// ids; [onFieldChanged] is called with the id when the user edits a field.
class FamilyForm extends ConsumerWidget {
  const FamilyForm({
    super.key,
    required this.controller,
    required this.serverErrors,
    this.onFieldChanged,
    this.enabled = true,
  });

  final FamilyFormController controller;
  final ServerFieldErrors serverErrors;
  final ValueChanged<String>? onFieldChanged;
  final bool enabled;

  void _changed(String field) => onFieldChanged?.call(field);

  void _pickCountry(BuildContext context, WidgetRef ref, String code) {
    controller.selectCountry(code);
    _changed(AuthField.familyCountry);
    _suggestLanguage(context, ref, Countries.byCode(code));
  }

  /// Offers the country's default language when the app shows another one.
  void _suggestLanguage(
    BuildContext context,
    WidgetRef ref,
    CountryInfo country,
  ) {
    final suggested = AppLanguages.byCode(country.defaultLanguage);
    final current = ref.read(resolvedLocaleProvider).languageCode;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (suggested == null || suggested.code == current || messenger == null) {
      return;
    }
    final l10n = context.l10n;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.authSuggestLanguage(suggested.nativeName)),
          duration: AppDurations.snackbar * 2,
          action: SnackBarAction(
            label: l10n.authSuggestLanguageAction,
            onPressed: () {
              if (context.mounted) {
                switchAppLanguage(context, ref, suggested.code);
              }
            },
          ),
        ),
      );
  }

  static String _currencyLabel(String code) {
    String symbol;
    try {
      symbol = NumberFormat.simpleCurrency(name: code).currencySymbol;
    } catch (_) {
      symbol = code;
    }
    return symbol == code ? code : '$code · $symbol';
  }

  static String _timezoneLabel(String zone) {
    final city = Timezones.cityName(zone);
    return city == zone ? zone : '$city ($zone)';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final draft = controller.draft;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              controller: controller.name,
              label: l10n.authFamilyNameLabel,
              hint: l10n.authFamilyNameHint,
              prefixIcon: AppIcons.family,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              enabled: enabled,
              validator: serverErrors.guard(
                AuthField.familyName,
                AuthValidators.displayName(l10n),
              ),
              onChanged: (_) => _changed(AuthField.familyName),
            ),
            AppGap.md,
            CountryPickerField(
              value: draft.country,
              enabled: enabled,
              errorText: serverErrors[AuthField.familyCountry],
              onChanged: (code) => _pickCountry(context, ref, code),
            ),
            AppGap.md,
            AppDropdownField<String>(
              // Re-created when the country pre-fills a new value.
              key: ValueKey('currency-${draft.currency}'),
              label: l10n.authCurrencyLabel,
              value: draft.currency,
              items: draft.currencyOptions,
              itemLabel: _currencyLabel,
              validator: (_) => serverErrors[AuthField.familyCurrency],
              onChanged: enabled
                  ? (c) {
                      if (c == null) return;
                      controller.selectCurrency(c);
                      _changed(AuthField.familyCurrency);
                    }
                  : null,
            ),
            AppGap.md,
            AppDropdownField<String>(
              key: ValueKey('timezone-${draft.country}-${draft.timezone}'),
              label: l10n.authTimezoneLabel,
              value: draft.timezone,
              items: draft.timezoneOptions,
              itemLabel: _timezoneLabel,
              validator: (_) => serverErrors[AuthField.familyTimezone],
              onChanged: enabled
                  ? (tz) {
                      if (tz == null) return;
                      controller.selectTimezone(tz);
                      _changed(AuthField.familyTimezone);
                    }
                  : null,
            ),
            AppGap.sm,
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.md,
              ),
              child: Text(
                l10n.authFamilyFormHelp,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Create / join switch used by sign-up and family setup: two colourful
/// tiles side by side — "Create a family" (indigo) and "Join with invite
/// code" (teal). The chosen one is a solid gradient card with white text
/// and a check mark; the other a soft tint of its colour. Screen readers
/// hear them as a group of selectable buttons.
class FamilyModeSelector extends StatelessWidget {
  const FamilyModeSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final RegisterMode value;
  final ValueChanged<RegisterMode> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget tile(RegisterMode mode) {
      final create = mode == RegisterMode.create;
      return _ModeTile(
        icon: create ? AuthIcons.createFamily : AuthIcons.joinFamily,
        label: create
            ? l10n.authWelcomeCreateFamily
            : l10n.authWelcomeJoinFamily,
        accent: create ? AuthAccents.create : AuthAccents.join,
        selected: value == mode,
        onTap: enabled ? () => onChanged(mode) : null,
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: tile(RegisterMode.create)),
          AppGap.hMd,
          Expanded(child: tile(RegisterMode.join)),
        ],
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.icon,
    required this.label,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final AppAccent accent;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shades = context.accent(accent);
    final foreground = selected ? Colors.white : shades.onContainer;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppDurations.normal;

    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      enabled: onTap != null,
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: AppRadius.brCard,
          color: selected ? null : shades.container,
          gradient: selected ? AppGradients.of(accent) : null,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accent.base.withValues(alpha: AppColors.glowOpacity),
                    blurRadius: AppSizes.cardShadowBlur,
                    offset: const Offset(0, AppSpacing.xs),
                  ),
                ]
              : const [],
        ),
        child: Material(
          type: MaterialType.transparency,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.brCard),
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                // Large faint watermark of the icon, like [ActionTile].
                PositionedDirectional(
                  bottom: -AppSpacing.lg,
                  end: -AppSpacing.md,
                  child: ExcludeSemantics(
                    child: Icon(
                      icon,
                      size: AppSizes.iconHero,
                      color: foreground.withValues(alpha: AuthGlass.watermark),
                    ),
                  ),
                ),
                Padding(
                  padding: AppSpacing.card,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ExcludeSemantics(
                            child: selected
                                ? Container(
                                    width: AppSizes.badgeSm,
                                    height: AppSizes.badgeSm,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: AuthGlass.fill,
                                      ),
                                      borderRadius: AppRadius.brMd,
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      icon,
                                      size: AppSizes.iconSm,
                                      color: Colors.white,
                                    ),
                                  )
                                : IconBadge(
                                    icon: icon,
                                    accent: accent,
                                    size: AppSizes.badgeSm,
                                  ),
                          ),
                          const Spacer(),
                          if (selected)
                            ExcludeSemantics(
                              child: Container(
                                padding: const EdgeInsets.all(AppSpacing.xxs),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  AppIcons.check,
                                  size: AppSizes.iconXs,
                                  color: accent.dark,
                                ),
                              ),
                            ),
                        ],
                      ),
                      AppGap.lg,
                      Text(
                        label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: foreground,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The family part of sign-up and family setup on its own card: the
/// [FamilyForm] in create mode, the [InviteCodeField] in join mode (the
/// switch cross-fades). The card's header icon follows the mode colour.
class FamilyModeFields extends StatelessWidget {
  const FamilyModeFields({
    super.key,
    required this.mode,
    required this.family,
    required this.inviteCode,
    required this.serverErrors,
    required this.onFieldChanged,
    this.enabled = true,
    this.onInviteSubmitted,
  });

  final RegisterMode mode;
  final FamilyFormController family;
  final TextEditingController inviteCode;
  final ServerFieldErrors serverErrors;
  final ValueChanged<String> onFieldChanged;
  final bool enabled;

  /// Keyboard "done" in the invite code field.
  final ValueChanged<String>? onInviteSubmitted;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final create = mode == RegisterMode.create;
    return AuthSectionCard(
      title: l10n.authSectionFamily,
      icon: create ? AuthIcons.createFamily : AuthIcons.joinFamily,
      accent: create ? AuthAccents.create : AuthAccents.join,
      children: [
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppDurations.normal,
          child: create
              ? FamilyForm(
                  key: const ValueKey(RegisterMode.create),
                  controller: family,
                  serverErrors: serverErrors,
                  onFieldChanged: onFieldChanged,
                  enabled: enabled,
                )
              : InviteCodeField(
                  key: const ValueKey(RegisterMode.join),
                  controller: inviteCode,
                  enabled: enabled,
                  textInputAction: TextInputAction.done,
                  validator: serverErrors.guard(
                    AuthField.inviteCode,
                    Validators.inviteCode(l10n),
                  ),
                  onChanged: (_) => onFieldChanged(AuthField.inviteCode),
                  onSubmitted: onInviteSubmitted,
                ),
        ),
      ],
    );
  }
}
