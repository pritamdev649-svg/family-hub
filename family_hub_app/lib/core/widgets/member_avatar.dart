import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';

import 'package:family_hub/core/widgets/app_network_image.dart';

/// Round member picture with an initials fallback.
///
/// * The background colour is derived deterministically from [name], so the
///   same person always gets the same colour on every device.
/// * Initials handle any script (grapheme clusters, e.g. Devanagari conjuncts).
/// * If the image fails to load, the initials stay visible.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    super.key,
    this.name,
    this.avatarUrl,
    this.radius = AppSizes.avatarMd,
  });

  final String? name;
  final String? avatarUrl;
  final double radius;

  static final Map<(int, Brightness), ColorScheme> _schemes = {};

  /// Accessible (container, on-container) pair for [name].
  static ({Color background, Color foreground}) colorsFor(
    String? name,
    Brightness brightness,
  ) {
    final index =
        _stableHash(name?.trim().toLowerCase() ?? '') %
        AppColors.avatarSeeds.length;
    final scheme = _schemes.putIfAbsent(
      (index, brightness),
      () => ColorScheme.fromSeed(
        seedColor: AppColors.avatarSeeds[index],
        brightness: brightness,
      ),
    );
    return (
      background: scheme.primaryContainer,
      foreground: scheme.onPrimaryContainer,
    );
  }

  /// Up to two initials: first letter of the first and last word.
  static String initialsOf(String? name) {
    final words = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '';
    final first = words.first.characters.first;
    if (words.length == 1) return first.toUpperCase();
    final last = words.last.characters.first;
    return '$first$last'.toUpperCase();
  }

  /// FNV-1a — stable across runs and platforms (unlike `String.hashCode`).
  static int _stableHash(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = colorsFor(name, theme.brightness);
    final initials = initialsOf(name);
    final image = appImageProvider(
      avatarUrl,
      cacheWidth: cacheWidthFor(context, radius * 2),
    );

    final TextStyle? style = switch (radius) {
      < AppSizes.avatarLg => theme.textTheme.labelLarge,
      < AppSizes.avatarXl => theme.textTheme.titleLarge,
      _ => theme.textTheme.headlineMedium,
    };

    final Widget fallback = initials.isEmpty
        ? Icon(AppIcons.member, size: radius, color: colors.foreground)
        : Padding(
            padding: EdgeInsets.all(radius / 4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                initials,
                maxLines: 1,
                textScaler: TextScaler.noScaling,
                style: style?.copyWith(
                  color: colors.foreground,
                  fontWeight: AppTypography.semiBold,
                ),
              ),
            ),
          );

    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: colors.background,
      foregroundImage: image,
      onForegroundImageError: image == null ? null : (_, _) {},
      child: fallback,
    );

    final label = name?.trim();
    if (label == null || label.isEmpty) return ExcludeSemantics(child: avatar);
    return Semantics(
      image: true,
      label: label,
      excludeSemantics: true,
      child: avatar,
    );
  }
}
