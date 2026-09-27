import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/core/settings/locale_resolution.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'package:family_hub/core/settings/locale_resolution.dart';
export 'package:flutter/material.dart' show ThemeMode;

/// Device-level preferences (not synced to the server).
///
/// The account's `locale` on the server (used for push / email language) is
/// updated separately by the language screen via `PATCH /me`.
@immutable
class AppSettings {
  const AppSettings({
    this.localeCode,
    this.largeText = false,
    this.themeMode = ThemeMode.system,
  });

  static const defaults = AppSettings();

  /// A supported language code (see `AppLanguages`) or `null` = follow the
  /// device language.
  final String? localeCode;

  /// "Large text" mode for older family members (text scale >= 1.3).
  final bool largeText;
  final ThemeMode themeMode;

  bool get followsSystemLocale => localeCode == null;

  /// [localeCode] takes a [ValueGetter] so it can be reset to `null`:
  /// `settings.copyWith(localeCode: () => null)`.
  AppSettings copyWith({
    ValueGetter<String?>? localeCode,
    bool? largeText,
    ThemeMode? themeMode,
  }) {
    return AppSettings(
      localeCode: localeCode != null ? localeCode() : this.localeCode,
      largeText: largeText ?? this.largeText,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          other.localeCode == localeCode &&
          other.largeText == largeText &&
          other.themeMode == themeMode;

  @override
  int get hashCode => Object.hash(localeCode, largeText, themeMode);

  @override
  String toString() =>
      'AppSettings(localeCode: $localeCode, '
      'largeText: $largeText, themeMode: ${themeMode.name})';
}

/// SharedPreferences keys (namespaced so they never clash with other stores).
abstract final class SettingsKeys {
  static const localeCode = 'settings.localeCode';
  static const largeText = 'settings.largeText';
  static const themeMode = 'settings.themeMode';
}

/// Reads and persists [AppSettings]. Every setter updates the state first
/// (the UI reacts instantly), then persists; if persisting fails the change
/// is rolled back and the error rethrown so the caller can show it.
class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return AppSettings(
      localeCode: normalizeLocaleCode(
        _read<String>(prefs, SettingsKeys.localeCode),
      ),
      largeText: _read<bool>(prefs, SettingsKeys.largeText) ?? false,
      themeMode: _parseThemeMode(_read<String>(prefs, SettingsKeys.themeMode)),
    );
  }

  /// `null` (or `'system'`) follows the device language. Throws
  /// [ArgumentError] for a language the app does not support.
  Future<void> setLocale(String? code) {
    final normalized = normalizeLocaleCode(code);
    if (normalized == null && !_isSystemCode(code)) {
      throw ArgumentError.value(code, 'code', 'Unsupported language');
    }
    return _update(
      state.copyWith(localeCode: () => normalized),
      (prefs) => normalized == null
          ? prefs.remove(SettingsKeys.localeCode)
          : prefs.setString(SettingsKeys.localeCode, normalized),
    );
  }

  Future<void> setLargeText(bool enabled) => _update(
    state.copyWith(largeText: enabled),
    (prefs) => prefs.setBool(SettingsKeys.largeText, enabled),
  );

  Future<void> setThemeMode(ThemeMode mode) => _update(
    state.copyWith(themeMode: mode),
    (prefs) => prefs.setString(SettingsKeys.themeMode, mode.name),
  );

  Future<void> _update(
    AppSettings next,
    Future<bool> Function(SharedPreferences prefs) persist,
  ) async {
    final previous = state;
    if (next == previous) return;
    state = next;
    try {
      final ok = await persist(ref.read(sharedPreferencesProvider));
      if (!ok) throw StateError('Could not save the setting on this device.');
    } catch (_) {
      // Roll back unless another change happened in the meantime.
      if (ref.mounted && state == next) state = previous;
      rethrow;
    }
  }

  static bool _isSystemCode(String? code) {
    final c = code?.trim().toLowerCase();
    return c == null || c.isEmpty || c == 'system';
  }

  static T? _read<T>(SharedPreferences prefs, String key) {
    try {
      final value = prefs.get(key);
      return value is T ? value : null;
    } on Object {
      return null;
    }
  }

  static ThemeMode _parseThemeMode(String? raw) {
    for (final mode in ThemeMode.values) {
      if (mode.name == raw) return mode;
    }
    return ThemeMode.system;
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// The device's preferred locales, kept up to date when the user changes the
/// system language while the app is running.
class DeviceLocalesNotifier extends Notifier<List<Locale>>
    with WidgetsBindingObserver {
  @override
  List<Locale> build() {
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    ref.onDispose(() => binding.removeObserver(this));
    return binding.platformDispatcher.locales;
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    state = locales ?? WidgetsBinding.instance.platformDispatcher.locales;
  }
}

final deviceLocalesProvider =
    NotifierProvider<DeviceLocalesNotifier, List<Locale>>(
      DeviceLocalesNotifier.new,
    );

/// The effective app locale (see [resolveAppLocale]). Watched by
/// `MaterialApp.locale`, `Fmt` and the `Accept-Language` interceptor.
final resolvedLocaleProvider = Provider<Locale>((ref) {
  final chosen = ref.watch(
    settingsControllerProvider.select((s) => s.localeCode),
  );
  return resolveAppLocale(
    chosenCode: chosen,
    deviceLocales: ref.watch(deviceLocalesProvider),
  );
});
