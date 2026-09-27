import 'package:family_hub/core/settings/text_scale.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

double _factor(TextScaler scaler, [double fontSize = 100]) =>
    scaler.scale(fontSize) / fontSize;

/// A non-linear scaler like Android 14's: small text grows more than big text.
class _NonLinear extends TextScaler {
  const _NonLinear();
  @override
  double scale(double fontSize) => fontSize <= 20 ? fontSize * 2 : fontSize * 1.2;
  @Deprecated('Use scale() instead.')
  @override
  double get textScaleFactor => 2;
}

void main() {
  group('AppTextScale.resolve', () {
    test('large text off keeps the system scale', () {
      expect(_factor(AppTextScale.resolve(TextScaler.noScaling, largeText: false)), 1.0);
      expect(
        _factor(AppTextScale.resolve(const TextScaler.linear(1.2), largeText: false)),
        closeTo(1.2, 1e-9),
      );
      expect(
        _factor(AppTextScale.resolve(const TextScaler.linear(0.85), largeText: false)),
        closeTo(0.85, 1e-9),
      );
    });

    test('large text on raises small system scales to 1.3', () {
      expect(_factor(AppTextScale.resolve(TextScaler.noScaling, largeText: true)), 1.3);
      expect(
        _factor(AppTextScale.resolve(const TextScaler.linear(0.85), largeText: true)),
        1.3,
      );
    });

    test('large text on keeps a larger system scale', () {
      expect(
        _factor(AppTextScale.resolve(const TextScaler.linear(1.45), largeText: true)),
        closeTo(1.45, 1e-9),
      );
    });

    test('both modes cap at 1.6', () {
      expect(_factor(AppTextScale.resolve(const TextScaler.linear(2.0), largeText: true)), 1.6);
      expect(_factor(AppTextScale.resolve(const TextScaler.linear(2.0), largeText: false)), 1.6);
    });

    test('bounds are applied per font size (non-linear scaling kept)', () {
      final scaler = AppTextScale.resolve(const _NonLinear(), largeText: true);
      expect(_factor(scaler, 14), 1.6); // 2.0 capped
      expect(_factor(scaler, 40), 1.3); // 1.2 raised
    });

    test('is a value (equal inputs -> equal scalers)', () {
      expect(
        AppTextScale.resolve(const TextScaler.linear(1.1), largeText: true),
        AppTextScale.resolve(const TextScaler.linear(1.1), largeText: true),
      );
    });
  });

  group('BoundedTextScaler.clamp', () {
    test('re-clamping to a collapsed range is allowed', () {
      final scaler = AppTextScale.resolve(TextScaler.noScaling, largeText: true)
          .clamp(maxScaleFactor: AppTextScale.largeTextMin);
      expect(_factor(scaler), 1.3);
    });

    test('a later maximum below the minimum wins', () {
      final scaler = AppTextScale.resolve(TextScaler.noScaling, largeText: true)
          .clamp(maxScaleFactor: 1.2);
      expect(_factor(scaler), closeTo(1.2, 1e-9));
    });

    test('a wider clamp returns the same scaler', () {
      final scaler = AppTextScale.resolve(TextScaler.noScaling, largeText: true);
      expect(identical(scaler.clamp(maxScaleFactor: 3), scaler), isTrue);
    });

    testWidgets('large text + a nested withClampedTextScaling builds (regression)', (tester) async {
      late double factor;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            textScaler: AppTextScale.resolve(TextScaler.noScaling, largeText: true),
          ),
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: AppTextScale.largeTextMin,
            child: Builder(builder: (context) {
              factor = _factor(MediaQuery.textScalerOf(context));
              return const SizedBox.shrink();
            }),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(factor, 1.3);
    });
  });
}
