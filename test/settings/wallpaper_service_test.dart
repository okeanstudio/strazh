import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strazh/features/settings/data/services/wallpaper_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('keeps the selected wallpaper after reloading preferences', () async {
    SharedPreferences.setMockInitialValues({});
    const userId = 'wallpaper-service-test-user';
    await WallpaperService.setWallpaper(userId, 'graphite');

    expect(await WallpaperService.getWallpaper(userId), 'graphite');
  });

  test('repairs preset IDs previously saved as storage URLs', () async {
    const userId = 'wallpaper-service-recovery-test';
    SharedPreferences.setMockInitialValues({
      'chat_wallpaper_$userId':
          'https://storage.example/storage/v1/object/public/'
          'chat_wallpapers/graphite',
    });

    expect(await WallpaperService.getWallpaper(userId), 'graphite');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('chat_wallpaper_$userId'), 'graphite');
  });
}
