import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLanguage {
  const AppLanguage({
    required this.code,
    required this.name,
    required this.nativeName,
    required this.flag,
  });

  final String code;
  final String name;
  final String nativeName;
  final String flag;

  Locale get locale => Locale(code);
}

class AppLanguageService {
  AppLanguageService._();

  static final AppLanguageService _instance = AppLanguageService._();
  factory AppLanguageService() => _instance;

  static const languages = [
    AppLanguage(
      code: 'ru',
      name: 'Русский',
      nativeName: 'Русский',
      flag: '🇷🇺',
    ),
    AppLanguage(
      code: 'en',
      name: 'English',
      nativeName: 'English',
      flag: '🇬🇧',
    ),
  ];

  static const _preferenceKey = 'app_language_code';

  final ValueNotifier<Locale> locale = ValueNotifier(const Locale('ru'));
  Map<String, String> _translations = const {};

  AppLanguage get currentLanguage => languages.firstWhere(
    (language) => language.code == locale.value.languageCode,
    orElse: () => languages.first,
  );

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final savedCode = preferences.getString(_preferenceKey) ?? 'ru';
    final language = languages.firstWhere(
      (candidate) => candidate.code == savedCode,
      orElse: () => languages.first,
    );
    final translations = await _loadTranslations(language.code);
    _translations = translations;
    locale.value = language.locale;
  }

  Future<void> setLanguage(String code) async {
    final language = languages.firstWhere(
      (candidate) => candidate.code == code,
      orElse: () => throw ArgumentError.value(code, 'code', 'Unknown language'),
    );

    final translations = await _loadTranslations(language.code);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferenceKey, language.code);
    _translations = translations;
    locale.value = language.locale;
  }

  Future<Map<String, String>> _loadTranslations(String languageCode) async {
    final contents = await rootBundle.loadString(
      'assets/locales/$languageCode.json',
    );
    final decoded = jsonDecode(contents);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException(
        'Translation file for "$languageCode" must contain a JSON object.',
      );
    }

    return decoded.map((key, value) {
      if (value is! String) {
        throw FormatException(
          'Translation "$key" in "$languageCode" must be a string.',
        );
      }
      return MapEntry(key, value);
    });
  }

  String translate(String source) {
    if (locale.value.languageCode == 'ru') return source;
    return _translations[source] ?? source;
  }
}

extension AppLanguageText on String {
  String get tr => AppLanguageService().translate(this);
}
