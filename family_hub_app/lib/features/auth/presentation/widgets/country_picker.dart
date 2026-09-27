import 'package:flutter/material.dart';

import 'package:family_hub/core/config/countries.dart';
import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/auth/presentation/auth_labels.dart';

/// A query made of a dial code only (`+49`, `91`, `٩١`).
final _dialQuery = RegExp(r'^\+?\d+$');

/// Countries matching [query] (name or ISO code, case-insensitive; a query
/// of digits matches dial codes, native digits included), in
/// [Countries.all] order.
List<CountryInfo> filterCountries(String query) {
  final q = Validators.normalizeDigits(query).trim().toLowerCase();
  if (q.isEmpty) return Countries.all;
  final compact = q.replaceAll(RegExp(r'[\s\-]'), '');
  final dial = _dialQuery.hasMatch(compact)
      ? compact.replaceAll('+', '')
      : null;
  return [
    for (final c in Countries.all)
      if (c.name.toLowerCase().contains(q) ||
          c.code.toLowerCase() == q ||
          (dial != null && c.dialCode.replaceAll('+', '').startsWith(dial)))
        c,
  ];
}

/// The dial code isolated as left-to-right text, so an RTL layout (Arabic)
/// shows `+91`, not `91+`.
String countryDialCode(CountryInfo country) =>
    '\u2066${country.dialCode}\u2069';

/// `+91 · INR` for a country (dial code isolated, see [countryDialCode]).
String countrySubtitle(CountryInfo country) =>
    '${countryDialCode(country)} · ${country.currency}';

/// Opens the searchable country list; returns the picked ISO code or `null`
/// when dismissed.
Future<String?> showCountryPicker(BuildContext context, {String? selected}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _CountryPickerSheet(selected: selected),
  );
}

/// Form field showing the selected country (flag + name) that opens
/// [showCountryPicker]. Controlled by [value].
class CountryPickerField extends StatelessWidget {
  const CountryPickerField({
    super.key,
    required this.value,
    required this.onChanged,
    this.errorText,
    this.enabled = true,
  });

  /// ISO 3166-1 alpha-2 code.
  final String value;
  final ValueChanged<String> onChanged;
  final String? errorText;
  final bool enabled;

  Future<void> _pick(BuildContext context) async {
    final picked = await showCountryPicker(context, selected: value);
    if (picked != null && picked != value) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final country = Countries.byCode(value);
    return Semantics(
      button: true,
      enabled: enabled,
      label: l10n.authCountryLabel,
      value: country.name,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: AppRadius.brMd,
        onTap: enabled ? () => _pick(context) : null,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: l10n.authCountryLabel,
            errorText: errorText,
            enabled: enabled,
            prefixIcon: const Icon(AuthIcons.country),
            suffixIcon: const Icon(AppIcons.expand),
          ),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Text(country.flag, style: theme.textTheme.titleMedium),
              ),
              AppGap.hSm,
              Expanded(
                child: Text(
                  country.name,
                  style: theme.textTheme.bodyLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet({this.selected});

  final String? selected;

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  /// Fractions of the screen height the sheet opens at / may grow to.
  static const _initialFraction = 0.85;
  static const _minFraction = 0.5;

  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final countries = filterCountries(_query);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: _initialFraction,
      minChildSize: _minFraction,
      maxChildSize: 1,
      builder: (context, scrollController) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const ExcludeSemantics(
                      child: IconBadge(
                        icon: AuthIcons.country,
                        accent: AppAccents.family,
                        size: AppSizes.badgeSm,
                      ),
                    ),
                    AppGap.hMd,
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          l10n.authCountryPickerTitle,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                    ),
                  ],
                ),
                AppGap.lg,
                AppTextField(
                  label: l10n.commonSearch,
                  hint: l10n.authCountrySearchHint,
                  prefixIcon: AppIcons.search,
                  textInputAction: TextInputAction.search,
                  onChanged: (v) => setState(() => _query = v),
                ),
                AppGap.sm,
              ],
            ),
          ),
          Expanded(
            child: countries.isEmpty
                ? EmptyState(
                    icon: AppIcons.search,
                    title: l10n.authCountryNoResults,
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.sm,
                      AppSpacing.xs,
                      AppSpacing.sm,
                      AppSpacing.lg + bottomInset,
                    ),
                    itemCount: countries.length,
                    itemBuilder: (context, i) {
                      final c = countries[i];
                      return _CountryRow(
                        country: c,
                        selected: c.code == widget.selected,
                        onTap: () => Navigator.of(context).pop(c.code),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Flag on a soft square, name, dial code and a currency pill; the
/// selected country is tinted and ticked.
class _CountryRow extends StatelessWidget {
  const _CountryRow({
    required this.country,
    required this.selected,
    required this.onTap,
  });

  final CountryInfo country;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.accent(AppAccents.brand);
    final money = context.accent(AppAccents.money);
    return ListTile(
      selected: selected,
      selectedTileColor: brand.container,
      selectedColor: brand.onContainer,
      leading: ExcludeSemantics(child: FlagBadge(flag: country.flag)),
      title: Text(
        country.name,
        style: theme.textTheme.titleSmall?.copyWith(
          color: selected ? brand.onContainer : theme.colorScheme.onSurface,
        ),
      ),
      subtitle: Text(countryDialCode(country)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusChip(label: country.currency, color: money.foreground),
          if (selected) ...[
            AppGap.hSm,
            Icon(AppIcons.check, color: brand.foreground),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}

/// A country's flag emoji on a soft rounded square (country lists).
class FlagBadge extends StatelessWidget {
  const FlagBadge({super.key, required this.flag});

  final String flag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: AppSizes.badgeMd,
      height: AppSizes.badgeMd,
      decoration: BoxDecoration(
        color: context.semanticColors.canvas,
        borderRadius: AppRadius.brMd,
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(flag, style: theme.textTheme.headlineSmall),
      ),
    );
  }
}
