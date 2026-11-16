import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strazh/features/chat/data/services/storage_upload_service.dart';

class WallpaperPreset {
  final String id;
  final String name;
  final List<Color> colors;
  final WallpaperPattern pattern;
  final String? imageAsset;

  const WallpaperPreset({
    required this.id,
    required this.name,
    required this.colors,
    this.pattern = WallpaperPattern.none,
    this.imageAsset,
  });
}

enum WallpaperPattern { none, dots, diagonalStripes, grid, waves, icons }

class WallpaperService {
  static const String _prefsKeyPrefix = 'chat_wallpaper_';
  static const String defaultWallpaper = 'standart';

  // ===== ПРЕСЕТЫ =====
  static const List<WallpaperPreset> presets = [
    WallpaperPreset(
      id: 'alt',
      name: 'Alt',
      colors: [Color(0xFF000000), Color(0xFF000000)],
      imageAsset: 'assets/wallpaper/alt.JPG',
    ),
    WallpaperPreset(
      id: 'red',
      name: 'Красные',
      colors: [Color(0xFF000000), Color(0xFF000000)],
      imageAsset: 'assets/wallpaper/red.JPG',
    ),
    WallpaperPreset(
      id: 'standart_light',
      name: 'Светлые',
      colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
      imageAsset: 'assets/wallpaper/standart_light.JPG',
    ),
    WallpaperPreset(
      id: 'standart',
      name: 'Стандарт',
      colors: [Color(0xFF000000), Color(0xFF000000)],
      imageAsset: 'assets/wallpaper/standart.JPG',
    ),
    WallpaperPreset(
      id: 'icons',
      name: 'Strazh',
      colors: [Color(0xFF000000), Color(0xFF000000)],
      pattern: WallpaperPattern.icons,
    ),
    WallpaperPreset(
      id: 'none',
      name: 'Без обоев',
      colors: [Color(0xFF0D0A0A), Color(0xFF0D0A0A)],
    ),
    WallpaperPreset(
      id: 'charcoal',
      name: 'Уголь',
      colors: [Color(0xFF1A1A1A), Color(0xFF0D0A0A)],
    ),
    WallpaperPreset(
      id: 'graphite',
      name: 'Графит',
      colors: [Color(0xFF2A2A2A), Color(0xFF141414)],
      pattern: WallpaperPattern.dots,
    ),
    WallpaperPreset(
      id: 'silver',
      name: 'Серебро',
      colors: [Color(0xFF3A3A3A), Color(0xFF1A1A1A)],
      pattern: WallpaperPattern.diagonalStripes,
    ),
    WallpaperPreset(
      id: 'smoke',
      name: 'Дым',
      colors: [Color(0xFF1F1F1F), Color(0xFF000000)],
      pattern: WallpaperPattern.waves,
    ),
    WallpaperPreset(
      id: 'steel',
      name: 'Сталь',
      colors: [Color(0xFF252525), Color(0xFF0D0D0D)],
      pattern: WallpaperPattern.grid,
    ),
    WallpaperPreset(
      id: 'obsidian',
      name: 'Обсидиан',
      colors: [Color(0xFF0A0A0A), Color(0xFF1F1F1F)],
    ),
    WallpaperPreset(
      id: 'ash',
      name: 'Пепел',
      colors: [Color(0xFF2E2E2E), Color(0xFF161616)],
      pattern: WallpaperPattern.dots,
    ),
  ];

  static WallpaperPreset getPreset(String id) {
    return presets.firstWhere(
      (p) => p.id == id,
      orElse: () =>
          presets.firstWhere((preset) => preset.id == defaultWallpaper),
    );
  }

  // ===== ХРАНЕНИЕ ВЫБОРА =====

  static String _prefsKey(String userId) => '$_prefsKeyPrefix$userId';

  /// Возвращает либо ID пресета, либо URL кастомных обоев.
  static Future<String> getWallpaper(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _prefsKey(userId);
    final wallpaper = prefs.getString(key) ?? defaultWallpaper;
    if (!wallpaper.startsWith('http')) return wallpaper;

    final objectPath = StorageUploadService.objectPathFromStorageUrl(
      'chat_wallpapers',
      wallpaper,
    );
    if (objectPath == null) return wallpaper;
    if (presets.any((preset) => preset.id == objectPath)) {
      await prefs.setString(key, objectPath);
      return objectPath;
    }

    try {
      final migratedUrl = await StorageUploadService.getPublicUrl(
        bucket: 'chat_wallpapers',
        path: objectPath,
      );
      await prefs.setString(key, migratedUrl);
      return migratedUrl;
    } catch (error) {
      debugPrint(
        'Не удалось обновить ссылку на обои; используем сохранённую: $error',
      );
      return wallpaper;
    }
  }

  static Future<void> setWallpaper(String userId, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey(userId), value);
  }

  // ===== ЗАГРУЗКА СВОИХ ОБОЕВ =====

  static Future<String> uploadCustomWallpaper({
    required String userId,
    required List<int> bytes,
    required String extension,
  }) async {
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.$extension';
    await StorageUploadService.uploadBinary(
      bucket: 'chat_wallpapers',
      path: path,
      bytes: Uint8List.fromList(bytes),
      contentType: extension == 'png' ? 'image/png' : 'image/jpeg',
      onProgress: (_, _) {},
    );

    return StorageUploadService.getPublicUrl(
      bucket: 'chat_wallpapers',
      path: path,
    );
  }
}

/// Виджет обоев: рисует либо градиент+паттерн, либо картинку.
class WallpaperBackground extends StatelessWidget {
  final String wallpaper;
  final Widget child;

  const WallpaperBackground({
    super.key,
    required this.wallpaper,
    required this.child,
  });

  bool get _isUrl => wallpaper.startsWith('http');

  @override
  Widget build(BuildContext context) {
    if (wallpaper == 'none') return child;

    if (_isUrl) {
      const fallback = DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF211735), Color(0xFF100D1E)],
          ),
        ),
      );
      return Stack(
        children: [
          Positioned.fill(
            child: Image.network(
              wallpaper,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return fallback;
              },
            ),
          ),
          Positioned.fill(
            child: Container(
              color: const Color(0xFF0D0A0A).withValues(alpha: 0.35),
            ),
          ),
          child,
        ],
      );
    }

    final preset = WallpaperService.getPreset(wallpaper);
    return Stack(
      children: [
        Positioned.fill(
          child: preset.imageAsset == null
              ? CustomPaint(painter: _WallpaperPainter(preset))
              : Image.asset(preset.imageAsset!, fit: BoxFit.cover),
        ),
        child,
      ],
    );
  }
}

// ================= ХУДОЖНИК =================

class _WallpaperPainter extends CustomPainter {
  final WallpaperPreset preset;

  _WallpaperPainter(this.preset);

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Фон
    final gradientPaint = Paint()
      ..shader = LinearGradient(
        colors: preset.colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      gradientPaint,
    );

    // 2. Паттерн
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;

    switch (preset.pattern) {
      case WallpaperPattern.none:
        break;

      case WallpaperPattern.dots:
        const spacing = 40.0;
        for (double y = 0; y < size.height; y += spacing) {
          for (double x = 0; x < size.width; x += spacing) {
            canvas.drawCircle(Offset(x, y), 1.5, paint);
          }
        }
        break;

      case WallpaperPattern.diagonalStripes:
        const stripeWidth = 30.0;
        final linePaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.03)
          ..strokeWidth = 1.5;

        for (double i = -size.height; i < size.width; i += stripeWidth) {
          canvas.drawLine(
            Offset(i, 0),
            Offset(i + size.height, size.height),
            linePaint,
          );
        }
        break;

      case WallpaperPattern.grid:
        const cellSize = 50.0;
        final gridPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.04)
          ..strokeWidth = 0.8;

        for (double x = 0; x < size.width; x += cellSize) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
        }
        for (double y = 0; y < size.height; y += cellSize) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
        }
        break;

      case WallpaperPattern.waves:
        final wavePaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.03)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;

        const waveHeight = 40.0;
        for (double y = 0; y < size.height; y += waveHeight) {
          final path = Path();
          path.moveTo(0, y);
          for (double x = 0; x < size.width; x += 20) {
            path.quadraticBezierTo(x + 10, y - 6, x + 20, y);
          }
          canvas.drawPath(path, wavePaint);
        }
        break;

      case WallpaperPattern.icons:
        _drawIconPattern(canvas, size);
        break;
    }
  }

  // ================= ПАТТЕРН ИЗ ИКОНОК =================

  void _drawIconPattern(Canvas canvas, Size size) {
    const icons = <IconData>[
      Icons.lock_outline,
      Icons.shield_outlined,
      Icons.vpn_key_outlined,
      Icons.mail_outline,
      Icons.visibility_outlined,
      Icons.fingerprint,
      Icons.wifi_tethering,
      Icons.check_circle_outline,
      Icons.star_outline,
      Icons.cloud_outlined,
      Icons.security_outlined,
      Icons.enhanced_encryption_outlined,
      Icons.password_outlined,
      Icons.phonelink_lock_outlined,
      Icons.admin_panel_settings_outlined,
      Icons.verified_user_outlined,
      Icons.privacy_tip_outlined,
      Icons.key_outlined,
      Icons.qr_code_2_outlined,
      Icons.notifications_none_outlined,
    ];

    const double cell = 72;
    const double iconSize = 26;

    final random = _SeededRandom(42);

    final iconPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final cols = (size.width / cell).ceil() + 1;
    final rows = (size.height / cell).ceil() + 1;

    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final dx = col * cell + (row.isOdd ? cell / 2 : 0);
        final dy = row * cell;

        final iconData = icons[random.nextInt(icons.length)];
        final angle = (random.nextDouble() - 0.5) * 1.05;

        canvas.save();
        canvas.translate(dx, dy);
        canvas.rotate(angle);
        _drawIcon(canvas, iconData, iconSize, iconPaint);
        canvas.restore();
      }
    }
  }

  void _drawIcon(Canvas canvas, IconData icon, double size, Paint paint) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: paint.color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _WallpaperPainter oldDelegate) {
    return oldDelegate.preset.id != preset.id;
  }
}

// ===== Детерминированный рандом, чтобы узор не «прыгал» =====
class _SeededRandom {
  int _state;
  _SeededRandom(int seed) : _state = seed;

  double nextDouble() {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return _state / 0x7fffffff;
  }

  int nextInt(int max) {
    return (nextDouble() * max).floor();
  }
}
