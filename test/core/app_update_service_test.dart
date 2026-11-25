import 'package:flutter_test/flutter_test.dart';
import 'package:strazh/core/services/app_update_service.dart';

void main() {
  test('detects a server version newer than the installed app', () {
    expect(AppUpdateService.isNewerVersion('1.1.0', '3.0.179'), isTrue);
    expect(AppUpdateService.isNewerVersion('3.0.178', '3.0.179'), isTrue);
  });

  test('does not report an update for the same or an older version', () {
    expect(AppUpdateService.isNewerVersion('3.0.179', '3.0.179'), isFalse);
    expect(AppUpdateService.isNewerVersion('3.1.0', '3.0.179'), isFalse);
  });

  test(
    'reads release notes and download URLs from the new manifest format',
    () {
      final manifest = AppUpdateService.parseManifest('''
      {
        "version": "1.1.5",
        "whats_new": ["Новая функция", "Исправления"],
        "android_url": "https://strazh.chat/app.apk",
        "windows_url": "https://strazh.chat/app.exe",
        "download_url": "https://strazh.chat/"
      }
    ''');

      expect(manifest.version, '1.1.5');
      expect(manifest.whatsNew, ['Новая функция', 'Исправления']);
      expect(manifest.androidUrl, 'https://strazh.chat/app.apk');
      expect(manifest.windowsUrl, 'https://strazh.chat/app.exe');
      expect(manifest.downloadUrl, 'https://strazh.chat/');
    },
  );

  test('continues to accept the current server manifest format', () {
    final manifest = AppUpdateService.parseManifest('''
      {
        "version": "1.1.0",
        "android_url": "https://strazh.chat/assets/files/strazh.apk",
        "windows_url": "https://strazh.chat/assets/files/StrazhSetup.exe",
        "download_url": "https://strazh.chat/"
      }
    ''');

    expect(manifest.version, '1.1.0');
    expect(manifest.whatsNew, isEmpty);
    expect(manifest.androidUrl, 'https://strazh.chat/assets/files/strazh.apk');
  });

  test('rejects invalid release notes and insecure download URLs', () {
    expect(
      () => AppUpdateService.parseManifest('''
        {"version": "1.1.5", "whats_new": [""]}
      '''),
      throwsFormatException,
    );
    expect(
      () => AppUpdateService.parseManifest('''
        {"version": "1.1.5", "download_url": "http://strazh.chat"}
      '''),
      throwsFormatException,
    );
  });
}
