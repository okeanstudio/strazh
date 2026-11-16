import 'dart:math' as math;

import 'package:flutter/material.dart';

class StrazhSLoader extends StatefulWidget {
  const StrazhSLoader({super.key, this.size = 96, this.label});

  final double size;
  final String? label;

  @override
  State<StrazhSLoader> createState() => _StrazhSLoaderState();
}

class _StrazhSLoaderState extends State<StrazhSLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      label: widget.label ?? 'Загрузка',
      liveRegion: true,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final progress = reduceMotion ? 0.22 : _controller.value;
            final wave = math.sin(progress * math.pi * 2);
            final rotationY = reduceMotion ? -0.08 : wave * 0.18;
            final scale = reduceMotion ? 1.0 : 1 + wave * 0.025;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: widget.size * 1.48,
                  height: widget.size * 1.35,
                  child: CustomPaint(
                    painter: _OrbitPainter(progress: progress),
                    child: Center(
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0018)
                          ..rotateY(rotationY)
                          ..rotateZ(reduceMotion ? 0 : wave * 0.018),
                        child: Transform.scale(
                          scale: scale,
                          child: _DimensionalS(size: widget.size),
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.label != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.label!,
                    style: const TextStyle(
                      color: Color(0xFFB8B1CA),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DimensionalS extends StatelessWidget {
  const _DimensionalS({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 0.92,
      height: size * 1.05,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (var layer = 8; layer > 0; layer--)
            Transform.translate(
              offset: Offset(layer * 0.85, layer * 1.15),
              child: Text(
                'S',
                style: TextStyle(
                  color: Color.lerp(
                    const Color(0xFF50535C),
                    const Color(0xFF858A96),
                    layer / 8,
                  ),
                  fontSize: size,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFF1F5FC), Color(0xFFC9D2E0)],
              stops: [0, 0.55, 1],
            ).createShader(bounds),
            child: Text(
              'S',
              style: TextStyle(
                color: Colors.white,
                fontSize: size,
                height: 1,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                shadows: const [
                  Shadow(
                    color: Color(0xB8399CFF),
                    blurRadius: 24,
                    offset: Offset(0, 7),
                  ),
                  Shadow(
                    color: Color(0x6681C7FF),
                    blurRadius: 34,
                    offset: Offset(-2, -3),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  const _OrbitPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final orbitWidth = size.width * 0.84;
    final orbitHeight = size.height * 0.34;
    final angle = progress * math.pi * 2;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.28);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: orbitWidth,
        height: orbitHeight,
      ),
      Paint()
        ..color = const Color(0x6652AFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    final dot = Offset(
      math.cos(angle) * orbitWidth / 2,
      math.sin(angle) * orbitHeight / 2,
    );
    canvas.drawCircle(
      dot,
      5,
      Paint()
        ..color = const Color(0x8872BFFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(dot, 2.8, Paint()..color = const Color(0xFF9BD5FF));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OrbitPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
