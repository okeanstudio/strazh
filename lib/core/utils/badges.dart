import 'package:flutter/material.dart';

class BadgeData {
  final String id;
  final String name;
  final IconData? icon;
  final String? asset;
  final Color color;

  const BadgeData({
    required this.id,
    required this.name,
    this.icon,
    this.asset,
    required this.color,
  });
}

class Badges {
  static const List<BadgeData> all = [
    BadgeData(
      id: 'pancake',
      name: '🥞 Сырник',
      asset: 'assets/icon/sirnik.png',
      color: Color(0xFFFFD700),
    ),
    BadgeData(
      id: 'crown',
      name: '👑 Корона',
      icon: Icons.workspace_premium,
      color: Color(0xFFFFD700),
    ),
    BadgeData(
      id: 'fire',
      name: '🔥 Огонь',
      icon: Icons.local_fire_department,
      color: Color(0xFFFF6B35),
    ),
    BadgeData(
      id: 'rocket',
      name: '🚀 Ракета',
      icon: Icons.rocket_launch,
      color: Color(0xFF4A9BD9),
    ),
    BadgeData(
      id: 'star',
      name: '⭐ Звезда',
      icon: Icons.star,
      color: Color(0xFFFFD700),
    ),
    BadgeData(
      id: 'skull',
      name: '💀 Череп',
      icon: Icons.dangerous,
      color: Color(0xFFE53935),
    ),
    BadgeData(
      id: 'verified',
      name: '✓ Галочка',
      icon: Icons.verified,
      color: Color(0xFF1A73E8),
    ),
    BadgeData(
      id: 'poop',
      name: '💩 Какашка',
      asset: 'assets/icon/poop.png',
      color: Color(0xFF8B5A2B),
    ),
  ];

  static BadgeData? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final badge in all) {
      if (badge.id == id) return badge;
    }
    return null;
  }
}

class BadgeIcon extends StatelessWidget {
  final String? badgeId;
  final double size;

  const BadgeIcon({super.key, required this.badgeId, this.size = 20});

  @override
  Widget build(BuildContext context) {
    final badge = Badges.byId(badgeId);
    if (badge == null) return const SizedBox.shrink();

    if (badge.asset != null) {
      return Image.asset(
        badge.asset!,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            Icon(badge.icon ?? Icons.verified, color: badge.color, size: size),
      );
    }

    return Icon(badge.icon ?? Icons.verified, color: badge.color, size: size);
  }
}
