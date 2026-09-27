import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/design/design.dart';

void main() {
  group('AppTheme', () {
    for (final (name, build, brightness) in [
      ('light', AppTheme.light, Brightness.light),
      ('dark', AppTheme.dark, Brightness.dark),
    ]) {
      test('$name theme is Material 3 with the expected brightness', () {
        final theme = build();
        expect(theme.useMaterial3, isTrue);
        expect(theme.brightness, brightness);
        expect(theme.colorScheme.brightness, brightness);
        expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
        expect(theme.visualDensity, VisualDensity.standard);
      });

      test('$name theme registers the matching semantic colours', () {
        final semantic = build().extension<AppSemanticColors>();
        expect(semantic, isNotNull);
        expect(semantic, AppSemanticColors.of(brightness));
        expect(semantic!.sos, AppColors.sos);
      });

      test('$name theme: rounded cards, filled inputs, floating snackbars', () {
        final theme = build();
        final cardShape = theme.cardTheme.shape as RoundedRectangleBorder?;
        expect(cardShape?.borderRadius, AppRadius.brCard);
        // Containers are borderless (docs/12-DESIGN_LANGUAGE.md).
        expect(cardShape?.side, BorderSide.none);
        expect(theme.cardTheme.margin, EdgeInsets.zero);
        expect(theme.inputDecorationTheme.filled, isTrue);
        final border = theme.inputDecorationTheme.border as OutlineInputBorder?;
        expect(border?.borderRadius, AppRadius.brMd);
        expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
        expect(theme.bottomSheetTheme.showDragHandle, isTrue);
        expect(
          theme.navigationBarTheme.labelBehavior,
          NavigationDestinationLabelBehavior.alwaysShow,
        );
      });

      test('$name theme uses the AppTypography scale', () {
        final theme = build();
        final expected = AppTypography.textTheme(theme.colorScheme);
        expect(
          theme.textTheme.bodyLarge?.fontSize,
          expected.bodyLarge?.fontSize,
        );
        expect(
          theme.textTheme.titleMedium?.fontWeight,
          expected.titleMedium?.fontWeight,
        );
        expect(theme.textTheme.bodyMedium?.color, theme.colorScheme.onSurface);
      });
    }
  });

  group('AppSemanticColors', () {
    test('lerp interpolates and copyWith replaces single fields', () {
      const light = AppSemanticColors.light;
      const dark = AppSemanticColors.dark;
      expect(light.lerp(dark, 0), light);
      expect(light.lerp(dark, 1), dark);
      expect(light.lerp(null, 0.5), light);
      final copy = light.copyWith(info: const Color(0xFF000000));
      expect(copy.info, const Color(0xFF000000));
      expect(copy.success, light.success);
    });

    testWidgets(
      'context.semanticColors falls back when the extension is missing',
      (tester) async {
        late AppSemanticColors resolved;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: Brightness.dark),
            home: Builder(
              builder: (context) {
                resolved = context.semanticColors;
                return const SizedBox();
              },
            ),
          ),
        );
        expect(resolved, AppSemanticColors.dark);
      },
    );
  });

  group('tokens', () {
    test('spacing scale is strictly increasing', () {
      const scale = [
        AppSpacing.xxs,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xxl,
        AppSpacing.xxxl,
      ];
      for (var i = 1; i < scale.length; i++) {
        expect(scale[i], greaterThan(scale[i - 1]));
      }
      expect(AppGap.md.height, AppSpacing.md);
      expect(AppGap.hMd.width, AppSpacing.md);
    });

    test('radius getters match the scale', () {
      expect(
        AppRadius.brLg,
        const BorderRadius.all(Radius.circular(AppRadius.lg)),
      );
      expect(
        AppRadius.brPill,
        const BorderRadius.all(Radius.circular(AppRadius.pill)),
      );
    });

    test('durations', () {
      expect(AppDurations.fast, lessThan(AppDurations.normal));
      expect(AppDurations.normal, lessThan(AppDurations.slow));
      expect(AppDurations.pollSos, const Duration(seconds: 5));
      expect(AppDurations.pollActiveSos, const Duration(seconds: 15));
      expect(AppDurations.snackbar, const Duration(seconds: 4));
    });
  });
}
