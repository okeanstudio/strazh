import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  static const _legacyAccentMigrationKey = 'legacy_ocean_accent_migrated';

  // Текущая тема (акцентный цвет)
  ValueNotifier<AccentThemeData> currentTheme = ValueNotifier(_defaultTheme);

  // Режим: 'Тёмная', 'Светлая', 'Системная'
  ValueNotifier<String> themeMode = ValueNotifier('Тёмная');

  // Пустое значение использует стандартный шрифт платформы.
  ValueNotifier<String> fontFamily = ValueNotifier('');
  ValueNotifier<bool> fontItalic = ValueNotifier(false);

  static const _defaultTheme = AccentThemeData(
    name: 'Фиолетовый',
    myBubble: Color(0xFF7442F5),
    otherBubble: Color(0xFF211735),
    myText: Colors.white,
    otherText: Color(0xFFD1C2EF),
  );

  void setTheme(AccentThemeData theme) {
    currentTheme.value = theme;
  }

  void setThemeMode(String mode) {
    themeMode.value = mode;
  }

  // Сохранение в SharedPreferences
  Future<void> saveTheme() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('accent', currentTheme.value.name);
    await prefs.setString('themeMode', themeMode.value);
    await prefs.setString('fontFamily', fontFamily.value);
    await prefs.setBool('fontItalic', fontItalic.value);
  }

  // Загрузка из SharedPreferences
  Future<void> loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAccent = prefs.getString('accent');
      final savedMode = prefs.getString('themeMode');
      final savedFontFamily = prefs.getString('fontFamily');
      final savedFontItalic = prefs.getBool('fontItalic');
      final legacyAccentMigrated =
          prefs.getBool(_legacyAccentMigrationKey) ?? false;

      if (savedMode != null) {
        themeMode.value = savedMode;
      }

      if (savedFontFamily != null) {
        fontFamily.value = savedFontFamily;
      }

      if (savedFontItalic != null) {
        fontItalic.value = savedFontItalic;
      }

      if (savedAccent == 'Океанский синий' && !legacyAccentMigrated) {
        await prefs.setString('accent', _defaultTheme.name);
        currentTheme.value = _defaultTheme;
      } else if (savedAccent != null) {
        final theme = allThemes.firstWhere(
          (t) => t.name == savedAccent,
          orElse: () => _defaultTheme,
        );
        currentTheme.value = theme;
      }

      if (!legacyAccentMigrated) {
        await prefs.setBool(_legacyAccentMigrationKey, true);
      }
    } catch (e) {
      // Если ошибка — оставляем дефолтную тему
    }
  }
}

class AccentThemeData {
  final String name;
  final Color myBubble;
  final Color otherBubble;
  final Color myText;
  final Color otherText;

  const AccentThemeData({
    required this.name,
    required this.myBubble,
    required this.otherBubble,
    required this.myText,
    required this.otherText,
  });
}

// Все доступные темы
final List<AccentThemeData> allThemes = [
  const AccentThemeData(
    name: 'Красно-оранжевый',
    myBubble: Color(0xFFE85D3A),
    otherBubble: Color(0xFF2A1A14),
    myText: Colors.white,
    otherText: Color(0xFFFFC8B8),
  ),
  const AccentThemeData(
    name: 'Изумрудный',
    myBubble: Color(0xFF2D9B6E),
    otherBubble: Color(0xFF142A1E),
    myText: Colors.white,
    otherText: Color(0xFF88CCA8),
  ),
  const AccentThemeData(
    name: 'Океанский синий',
    myBubble: Color(0xFF2B7DB8),
    otherBubble: Color(0xFF142A3E),
    myText: Colors.white,
    otherText: Color(0xFF88B8D8),
  ),
  const AccentThemeData(
    name: 'Золотистый янтарь',
    myBubble: Color(0xFFD4A02B),
    otherBubble: Color(0xFF2A2214),
    myText: Colors.white,
    otherText: Color(0xFFD4C088),
  ),
  const AccentThemeData(
    name: 'Розовый закат',
    myBubble: Color(0xFFD45A8A),
    otherBubble: Color(0xFF2A1422),
    myText: Colors.white,
    otherText: Color(0xFFD488B0),
  ),
  const AccentThemeData(
    name: 'Лавандовый',
    myBubble: Color(0xFF8B7AC8),
    otherBubble: Color(0xFF1E1A2E),
    myText: Colors.white,
    otherText: Color(0xFFB8A8D8),
  ),
  const AccentThemeData(
    name: 'Мятный',
    myBubble: Color(0xFF3AA68A),
    otherBubble: Color(0xFF142A22),
    myText: Colors.white,
    otherText: Color(0xFF88D4BE),
  ),
  const AccentThemeData(
    name: 'Терракотовый',
    myBubble: Color(0xFFC47A4A),
    otherBubble: Color(0xFF2A1E14),
    myText: Colors.white,
    otherText: Color(0xFFD4B098),
  ),
  const AccentThemeData(
    name: 'Фиолетовый',
    myBubble: Color(0xFF7442F5),
    otherBubble: Color(0xFF211735),
    myText: Colors.white,
    otherText: Color(0xFFD1C2EF),
  ),
  const AccentThemeData(
    name: 'Небесно-голубой',
    myBubble: Color(0xFF4A9BD9),
    otherBubble: Color(0xFF142A3E),
    myText: Colors.white,
    otherText: Color(0xFF88C8E8),
  ),
  const AccentThemeData(
    name: 'Коралловый',
    myBubble: Color(0xFFE87060),
    otherBubble: Color(0xFF2A1A14),
    myText: Colors.white,
    otherText: Color(0xFFFFC8B8),
  ),
  const AccentThemeData(
    name: 'Лаймовый',
    myBubble: Color(0xFF6BBF4A),
    otherBubble: Color(0xFF142A1A),
    myText: Colors.white,
    otherText: Color(0xFFA8D888),
  ),
];
