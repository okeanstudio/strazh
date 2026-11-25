import 'package:flutter/material.dart';

class VoltBadge extends StatelessWidget {
  final bool extendedToday;
  final bool compact;

  const VoltBadge({
    super.key,
    required this.extendedToday,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = extendedToday
        ? const Color(0xFFFFD54F)
        : const Color(0xFF88858F);

    return Tooltip(
      message: extendedToday
          ? 'Вольт: общаетесь минимум 3 дня подряд. Сегодня серия продлена.'
          : 'Вольт: общаетесь минимум 3 дня подряд. Напишите сегодня, чтобы продлить серию.',
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_rounded, color: color, size: compact ? 14 : 16),
            if (!compact) ...[
              const SizedBox(width: 2),
              Text(
                'Вольт',
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
