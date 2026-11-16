import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strazh/features/settings/data/services/theme_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('violet is the default accent theme', () {
    final theme = ThemeService().currentTheme.value;

    expect(theme.name, 'Фиолетовый');
    expect(theme.myBubble, const Color(0xFF7442F5));
    expect(theme.otherBubble, const Color(0xFF211735));
  });

  test('migrates the previous ocean default once', () async {
    SharedPreferences.setMockInitialValues({'accent': 'Океанский синий'});

    await ThemeService().loadTheme();
    expect(ThemeService().currentTheme.value.name, 'Фиолетовый');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('accent'), 'Фиолетовый');

    await prefs.setString('accent', 'Океанский синий');
    await ThemeService().loadTheme();
    expect(ThemeService().currentTheme.value.name, 'Океанский синий');
  });
}
