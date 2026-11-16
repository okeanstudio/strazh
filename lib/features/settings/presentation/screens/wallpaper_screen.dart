import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:strazh/features/settings/data/services/wallpaper_service.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

class WallpaperScreen extends StatefulWidget {
  final String userId;
  final String currentWallpaper;

  const WallpaperScreen({
    super.key,
    required this.userId,
    required this.currentWallpaper,
  });

  @override
  State<WallpaperScreen> createState() => _WallpaperScreenState();
}

class _WallpaperScreenState extends State<WallpaperScreen> {
  late String _selected;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentWallpaper;
  }

  Future<void> _pickCustom() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1440,
      maxHeight: 2560,
      imageQuality: 85,
    );
    if (file == null) return;

    setState(() => _isUploading = true);

    try {
      final bytes = await file.readAsBytes();
      final ext = file.name.split('.').last.toLowerCase();
      final safeExt = ext.isEmpty ? 'jpg' : ext;

      final url = await WallpaperService.uploadCustomWallpaper(
        userId: widget.userId,
        bytes: bytes,
        extension: safeExt,
      );

      setState(() {
        _selected = url;
        _isUploading = false;
      });
    } catch (e) {
      debugPrint('Ошибка загрузки обоев: $e');
      if (mounted) {
        Toast.error(context, 'Не удалось загрузить обои');
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _save() async {
    await WallpaperService.setWallpaper(widget.userId, _selected);
    if (mounted) {
      Toast.success(context, 'Обои сохранены');
      Navigator.pop(context, _selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0A0A),
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        title: const Text(
          'Обои чата',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text(
              'Сохранить',
              style: TextStyle(
                color: Color(0xFF1A73E8),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ===== СВОИ ОБОИ =====
            _buildSectionTitle('СВОИ ОБОИ'),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _isUploading ? null : _pickCustom,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF333333),
                    width: 1,
                  ),
                ),
                child: _isUploading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF1A73E8),
                        ),
                      )
                    : const Column(
                        children: [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            color: Colors.white,
                            size: 32,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Загрузить из галереи',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 24),

            // ===== ПРЕСЕТЫ =====
            _buildSectionTitle('ВСТРОЕННЫЕ'),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: WallpaperService.presets.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.6,
              ),
              itemBuilder: (context, index) {
                final preset = WallpaperService.presets[index];
                final isSelected = _selected == preset.id;

                return GestureDetector(
                  onTap: () => setState(() => _selected = preset.id),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? Colors.white
                            : const Color(0xFF333333),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: preset.imageAsset == null
                                ? CustomPaint(
                                    painter: _PreviewPainter(preset),
                                  )
                                : Image.asset(
                                    preset.imageAsset!,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                          if (isSelected)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  color: Colors.black,
                                  size: 14,
                                ),
                              ),
                            ),
                          Positioned(
                            bottom: 6,
                            left: 0,
                            right: 0,
                            child: Text(
                              preset.name,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF6E6E6E),
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ===== ПРЕВЬЮ ПРЕСЕТА =====

class _PreviewPainter extends CustomPainter {
  final WallpaperPreset preset;

  _PreviewPainter(this.preset);

  @override
  void paint(Canvas canvas, Size size) {
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

    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;

    switch (preset.pattern) {
      case WallpaperPattern.none:
        break;

      case WallpaperPattern.dots:
        const spacing = 16.0;
        for (double y = 0; y < size.height; y += spacing) {
          for (double x = 0; x < size.width; x += spacing) {
            canvas.drawCircle(Offset(x, y), 1, paint);
          }
        }
        break;

      case WallpaperPattern.diagonalStripes:
        final linePaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.05)
          ..strokeWidth = 1;
        for (double i = -size.height; i < size.width; i += 14) {
          canvas.drawLine(
            Offset(i, 0),
            Offset(i + size.height, size.height),
            linePaint,
          );
        }
        break;

      case WallpaperPattern.grid:
        final gridPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.05)
          ..strokeWidth = 0.6;
        for (double x = 0; x < size.width; x += 20) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
        }
        for (double y = 0; y < size.height; y += 20) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
        }
        break;

      case WallpaperPattern.waves:
        final wavePaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.05)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        const waveHeight = 18.0;
        for (double y = 0; y < size.height; y += waveHeight) {
          final path = Path();
          path.moveTo(0, y);
          for (double x = 0; x < size.width; x += 12) {
            path.quadraticBezierTo(x + 6, y - 4, x + 12, y);
          }
          canvas.drawPath(path, wavePaint);
        }
        break;

      case WallpaperPattern.icons:
        _drawIconPreview(canvas, size);
        break;
    }
  }

  void _drawIconPreview(Canvas canvas, Size size) {
    const icons = <IconData>[
      Icons.lock_outline,
      Icons.shield_outlined,
      Icons.vpn_key_outlined,
      Icons.mail_outline,
      Icons.visibility_outlined,
      Icons.fingerprint,
      Icons.security_outlined,
      Icons.star_outline,
    ];

    const double cell = 22;
    const double iconSize = 8;

    final random = _SeededRandom(42);

    final iconPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

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
  bool shouldRepaint(covariant _PreviewPainter oldDelegate) =>
      oldDelegate.preset.id != preset.id;
}

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