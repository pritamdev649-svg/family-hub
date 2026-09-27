import 'package:flutter/material.dart';

import 'package:family_hub/core/design/app_colors.dart';
import 'package:family_hub/core/design/app_radius.dart';
import 'package:family_hub/core/design/app_sizes.dart';
import 'package:family_hub/core/design/app_spacing.dart';
import 'package:family_hub/core/design/app_typography.dart';

/// Light and dark Material 3 themes.
///
/// Look & feel: modern and colourful — vivid indigo brand, white cards with
/// thin 1 px borders on a soft canvas ([AppRadius.card]), thin Phosphor
/// outline icons, outlined inputs, tall rounded buttons and a colourful
/// accent per module ([AppAccents]). Always-visible navigation labels keep
/// it easy to use for every generation.
abstract final class AppTheme {
  static ThemeData light() => _build(
    _scheme(Brightness.light, AppSemanticColors.light),
    AppSemanticColors.light,
  );

  static ThemeData dark() => _build(
    _scheme(Brightness.dark, AppSemanticColors.dark),
    AppSemanticColors.dark,
  );

  /// Seeded scheme whose neutral surfaces are replaced by the app's canvas /
  /// card / border tokens so cards read as crisp white (or deep slate) tiles.
  static ColorScheme _scheme(Brightness brightness, AppSemanticColors s) {
    final seeded = ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    final isDark = brightness == Brightness.dark;
    Color tint(AppAccent a) => Color.alphaBlend(
      a.base.withValues(alpha: isDark ? 0.22 : 0.13),
      s.card,
    );
    Color onTint(AppAccent a) => isDark ? a.light : a.dark;
    return seeded.copyWith(
      // Soft, colourful containers (the fidelity variant would make them as
      // saturated as the seed): brand indigo, violet and pink tints.
      primaryContainer: tint(AppAccent.indigo),
      onPrimaryContainer: onTint(AppAccent.indigo),
      secondaryContainer: tint(AppAccent.violet),
      onSecondaryContainer: onTint(AppAccent.violet),
      tertiaryContainer: tint(AppAccent.pink),
      onTertiaryContainer: onTint(AppAccent.pink),
      surface: s.card,
      surfaceContainerLowest: s.card,
      surfaceContainerLow: s.card,
      surfaceContainer: Color.alphaBlend(
        seeded.primary.withValues(alpha: 0.04),
        s.card,
      ),
      outlineVariant: s.border,
      surfaceTint: Colors.transparent,
    );
  }

  static ThemeData _build(ColorScheme scheme, AppSemanticColors semantic) {
    final text = AppTypography.textTheme(scheme);

    const buttonPadding = EdgeInsets.symmetric(
      horizontal: AppSpacing.xl,
      vertical: AppSpacing.md,
    );
    const buttonMinSize = Size(AppSizes.minTapTarget, AppSizes.buttonHeight);
    const buttonShape = RoundedRectangleBorder(borderRadius: AppRadius.brLg);

    OutlineInputBorder inputBorder(Color color, double width) =>
        OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: width == 0
              ? BorderSide.none
              : BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: scheme.brightness,
      textTheme: text,
      primaryTextTheme: text.apply(
        bodyColor: scheme.onPrimary,
        displayColor: scheme.onPrimary,
      ),
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      scaffoldBackgroundColor: semantic.canvas,
      canvasColor: semantic.canvas,
      dividerColor: scheme.outlineVariant,
      extensions: <ThemeExtension<dynamic>>[semantic],
      iconTheme: IconThemeData(
        color: scheme.onSurfaceVariant,
        size: AppSizes.iconMd,
      ),

      appBarTheme: AppBarThemeData(
        backgroundColor: semantic.canvas,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(
          color: scheme.onSurface,
          size: AppSizes.iconMd,
        ),
        actionsIconTheme: IconThemeData(
          color: scheme.onSurfaceVariant,
          size: AppSizes.iconMd,
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: semantic.card,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brCard),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonMinSize,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: text.labelLarge,
          iconSize: AppSizes.iconSm,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: buttonMinSize,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: text.labelLarge,
          iconSize: AppSizes.iconSm,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonMinSize,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: text.labelLarge,
          iconSize: AppSizes.iconSm,
          foregroundColor: scheme.onSurface,
          backgroundColor: scheme.onSurface.withValues(alpha: 0.06),
          side: BorderSide.none,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(AppSizes.minTapTarget, AppSizes.minTapTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          shape: buttonShape,
          textStyle: text.labelLarge,
          iconSize: AppSizes.iconSm,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(AppSizes.minTapTarget),
          iconSize: AppSizes.iconMd,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 3,
        focusElevation: 4,
        hoverElevation: 4,
        highlightElevation: 2,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brLg),
        extendedTextStyle: text.labelLarge,
        extendedPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        iconSize: AppSizes.iconMd,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          side: const WidgetStatePropertyAll(BorderSide.none),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.primaryContainer
                : semantic.card,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
          minimumSize: const WidgetStatePropertyAll(
            Size(AppSizes.minTapTarget, AppSizes.minTapTarget),
          ),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          visualDensity: VisualDensity.standard,
          tapTargetSize: MaterialTapTargetSize.padded,
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.md),
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? scheme.onSurface.withValues(alpha: 0.03)
              : scheme.onSurface.withValues(alpha: 0.055),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        border: inputBorder(semantic.border, 0),
        enabledBorder: inputBorder(semantic.border, 0),
        disabledBorder: inputBorder(semantic.border, 0),
        focusedBorder: inputBorder(scheme.primary, AppSizes.borderFocused),
        errorBorder: inputBorder(scheme.error, AppSizes.hairline),
        focusedErrorBorder: inputBorder(scheme.error, AppSizes.borderFocused),
        labelStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
          final color = states.contains(WidgetState.error)
              ? scheme.error
              : states.contains(WidgetState.focused)
              ? scheme.primary
              : scheme.onSurfaceVariant;
          return (text.bodyLarge ?? const TextStyle()).copyWith(color: color);
        }),
        hintStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        helperStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        errorStyle: text.bodySmall?.copyWith(color: scheme.error),
        counterStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        prefixIconColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
        suffixIconColor: scheme.onSurfaceVariant,
        errorMaxLines: 3,
        helperMaxLines: 3,
        alignLabelWithHint: true,
      ),

      chipTheme: ChipThemeData(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brPill),
        backgroundColor: semantic.card,
        side: BorderSide.none,
        labelStyle: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
        secondaryLabelStyle: text.labelLarge?.copyWith(
          color: scheme.onSecondaryContainer,
        ),
        selectedColor: scheme.primaryContainer,
        checkmarkColor: scheme.onPrimaryContainer,
        iconTheme: IconThemeData(
          color: scheme.onSurfaceVariant,
          size: AppSizes.iconSm,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        showCheckmark: true,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: semantic.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: AppSizes.navBarHeight,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: AppRadius.brPill,
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return text.labelMedium?.copyWith(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            fontWeight: selected ? AppTypography.bold : AppTypography.medium,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: AppSizes.iconMd,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        minVerticalPadding: AppSpacing.sm,
        minTileHeight: AppSizes.minTapTarget + AppSpacing.sm,
        horizontalTitleGap: AppSpacing.md,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        titleTextStyle: text.bodyLarge?.copyWith(color: scheme.onSurface),
        subtitleTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        leadingAndTrailingTextStyle: text.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.inversePrimary,
        closeIconColor: scheme.onInverseSurface,
        elevation: 3,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        dismissDirection: DismissDirection.horizontal,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: semantic.card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brXl),
        titleTextStyle: text.headlineSmall?.copyWith(color: scheme.onSurface),
        contentTextStyle: text.bodyLarge?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xl,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        constraints: const BoxConstraints(
          minWidth: AppSizes.minDialogWidth,
          maxWidth: AppSizes.maxDialogWidth,
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: semantic.card,
        modalBackgroundColor: semantic.card,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brTopXl),
        clipBehavior: Clip.antiAlias,
        constraints: const BoxConstraints(maxWidth: AppSizes.maxContentWidth),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primary.withValues(alpha: 0.12),
        circularTrackColor: Colors.transparent,
        refreshBackgroundColor: scheme.surfaceContainerHigh,
        borderRadius: AppRadius.brPill,
      ),

      dividerTheme: DividerThemeData(
        color: semantic.border,
        thickness: AppSizes.hairline,
        space: AppSpacing.lg,
      ),

      tabBarTheme: TabBarThemeData(
        labelStyle: text.titleSmall,
        unselectedLabelStyle: text.titleSmall?.copyWith(
          fontWeight: AppTypography.medium,
        ),
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        dividerColor: scheme.outlineVariant,
        indicatorSize: TabBarIndicatorSize.tab,
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: semantic.card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
        textStyle: text.bodyLarge,
      ),

      datePickerTheme: DatePickerThemeData(
        backgroundColor: semantic.card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brXl),
      ),

      timePickerTheme: TimePickerThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brXl),
      ),

      tooltipTheme: TooltipThemeData(
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: AppRadius.brSm,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
      ),

      badgeTheme: BadgeThemeData(
        backgroundColor: scheme.error,
        textColor: scheme.onError,
        textStyle: text.labelSmall,
      ),

      expansionTileTheme: ExpansionTileThemeData(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
        collapsedShape: const RoundedRectangleBorder(
          borderRadius: AppRadius.brMd,
        ),
        iconColor: scheme.onSurfaceVariant,
        collapsedIconColor: scheme.onSurfaceVariant,
        tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      ),

      switchTheme: const SwitchThemeData(
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
      checkboxTheme: CheckboxThemeData(
        materialTapTargetSize: MaterialTapTargetSize.padded,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brSm),
        side: BorderSide(color: scheme.outline, width: AppSizes.checkboxBorder),
      ),
      radioTheme: const RadioThemeData(
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
    );
  }
}
