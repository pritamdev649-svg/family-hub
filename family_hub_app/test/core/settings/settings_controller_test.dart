import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/core/settings/settings_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences whose writes fail (e.g. disk full).
class _FailingPrefs implements SharedPreferences {
  @override
  Object? get(String key) => null;

  @override
  Future<bool> setBool(String key, bool value) async =>
      throw Exception('disk full');

  @override
  Future<bool> setString(String key, String value) async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ProviderContainer, SharedPreferences)> create([
    Map<String, Object> initial = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    return (container, prefs);
  }

  setUp(() {
    binding.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
  });
  tearDown(binding.platformDispatcher.clearLocalesTestValue);

  test('defaults when nothing is stored', () async {
    final (container, _) = await create();
    expect(container.read(settingsControllerProvider), AppSettings.defaults);
    expect(container.read(resolvedLocaleProvider), const Locale('en'));
  });

  test('reads stored values and tolerates corrupt ones', () async {
    final (container, _) = await create({
      SettingsKeys.localeCode: 'HI',
      SettingsKeys.largeText: true,
      SettingsKeys.themeMode: 'dark',
    });
    expect(
      container.read(settingsControllerProvider),
      const AppSettings(
        localeCode: 'hi',
        largeText: true,
        themeMode: ThemeMode.dark,
      ),
    );

    final (other, _) = await create({
      SettingsKeys.localeCode: 'klingon',
      SettingsKeys.largeText: 'yes', // wrong type
      SettingsKeys.themeMode: 'sepia',
    });
    expect(other.read(settingsControllerProvider), AppSettings.defaults);
  });

  test(
    'setLocale persists, drives resolvedLocale and can reset to system',
    () async {
      final (container, prefs) = await create();
      final controller = container.read(settingsControllerProvider.notifier);

      await controller.setLocale('ar');
      expect(container.read(settingsControllerProvider).localeCode, 'ar');
      expect(prefs.getString(SettingsKeys.localeCode), 'ar');
      expect(container.read(resolvedLocaleProvider), const Locale('ar'));

      await controller.setLocale(null);
      expect(
        container.read(settingsControllerProvider).followsSystemLocale,
        isTrue,
      );
      expect(prefs.containsKey(SettingsKeys.localeCode), isFalse);
      expect(container.read(resolvedLocaleProvider), const Locale('en'));
    },
  );

  test(
    'setLocale rejects unsupported languages without changing state',
    () async {
      final (container, _) = await create();
      final controller = container.read(settingsControllerProvider.notifier);
      expect(() => controller.setLocale('xx'), throwsArgumentError);
      expect(container.read(settingsControllerProvider), AppSettings.defaults);
    },
  );

  test('setLargeText and setThemeMode persist', () async {
    final (container, prefs) = await create();
    final controller = container.read(settingsControllerProvider.notifier);

    await controller.setLargeText(true);
    await controller.setThemeMode(ThemeMode.light);

    expect(
      container.read(settingsControllerProvider),
      const AppSettings(largeText: true, themeMode: ThemeMode.light),
    );
    expect(prefs.getBool(SettingsKeys.largeText), isTrue);
    expect(prefs.getString(SettingsKeys.themeMode), 'light');
  });

  test('a failed write is rolled back and rethrown', () async {
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(_FailingPrefs())],
    );
    addTearDown(container.dispose);
    final controller = container.read(settingsControllerProvider.notifier);

    await expectLater(controller.setLargeText(true), throwsException);
    expect(container.read(settingsControllerProvider).largeText, isFalse);

    await expectLater(
      controller.setThemeMode(ThemeMode.dark),
      throwsStateError,
    );
    expect(
      container.read(settingsControllerProvider).themeMode,
      ThemeMode.system,
    );
  });

  test(
    'resolvedLocale follows device language changes while running',
    () async {
      final (container, _) = await create();
      final sub = container.listen(resolvedLocaleProvider, (_, _) {});
      addTearDown(sub.close);
      expect(sub.read(), const Locale('en'));

      binding.platformDispatcher.localesTestValue = const [
        Locale('ja'),
        Locale('ta', 'IN'),
      ];
      expect(container.read(resolvedLocaleProvider), const Locale('ta'));

      // An explicit choice overrides the device language.
      await container.read(settingsControllerProvider.notifier).setLocale('de');
      expect(container.read(resolvedLocaleProvider), const Locale('de'));
    },
  );
}
