import 'package:flutter/widgets.dart';

/// Languages the UI is translated into. Adding a language = add
/// `lib/l10n/app_<code>.arb` and an entry here.
class AppLanguage {
  const AppLanguage(this.code, this.nativeName, this.englishName);

  final String code;
  final String nativeName;
  final String englishName;

  Locale get locale => Locale(code);
}

class AppLanguages {
  AppLanguages._();

  static const all = <AppLanguage>[
    AppLanguage('en', 'English', 'English'),
    AppLanguage('hi', 'हिन्दी', 'Hindi'),
    AppLanguage('bn', 'বাংলা', 'Bengali'),
    AppLanguage('ta', 'தமிழ்', 'Tamil'),
    AppLanguage('te', 'తెలుగు', 'Telugu'),
    AppLanguage('mr', 'मराठी', 'Marathi'),
    AppLanguage('gu', 'ગુજરાતી', 'Gujarati'),
    AppLanguage('kn', 'ಕನ್ನಡ', 'Kannada'),
    AppLanguage('ml', 'മലയാളം', 'Malayalam'),
    AppLanguage('pa', 'ਪੰਜਾਬੀ', 'Punjabi'),
    AppLanguage('ar', 'العربية', 'Arabic'),
    AppLanguage('es', 'Español', 'Spanish'),
    AppLanguage('fr', 'Français', 'French'),
    AppLanguage('pt', 'Português', 'Portuguese'),
    AppLanguage('de', 'Deutsch', 'German'),
  ];

  static AppLanguage? byCode(String? code) {
    for (final l in all) {
      if (l.code == code) return l;
    }
    return null;
  }
}
