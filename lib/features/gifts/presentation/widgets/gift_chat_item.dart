import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:strazh/shared/domain/models/message.dart';
import 'package:strazh/features/gifts/presentation/widgets/animated_gift_card.dart';
import 'package:strazh/features/gifts/presentation/widgets/gift_details_dialog.dart';
import 'package:strazh/features/settings/data/services/theme_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GiftChatItem extends StatelessWidget {
  const GiftChatItem({super.key, required this.message, this.onLongPress});

  final Message message;
  final VoidCallback? onLongPress;

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _showDetails(BuildContext context) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    return showGiftDetails(
      context: context,
      messageId: message.id,
      canManageVisibility:
          currentUserId != null && currentUserId != message.senderId,
      gift: {
        'message_id': message.id,
        'gift_id': message.giftId,
        'gift_name': message.giftName ?? 'Подарок',
        'gift_emoji': message.giftEmoji,
        'sender_name': message.sender?.name ?? '',
        'price_enc': message.giftPriceEnc,
        'caption': message.giftCaption ?? '',
        'created_at': message.createdAt.toIso8601String(),
        'nft_serial': message.giftNftSerial,
        'nft_skin_name': message.giftNftSkinName,
        'nft_skin_emoji': message.giftNftSkinEmoji,
        'nft_background_color': message.giftNftBackgroundColor,
        'nft_pattern': message.giftNftPattern,
        'nft_animation_url': message.giftNftAnimationUrl,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = message.giftName ?? 'Подарок';
    final title = message.giftNftSerial == null
        ? name
        : '$name #${message.giftNftSerial}';
    final skinName = message.giftNftSkinName?.trim() ?? '';
    final skinEmoji = message.giftNftSkinEmoji?.trim() ?? '';
    final senderName = message.sender?.name.trim() ?? '';
    final senderLabel = senderName.isEmpty
        ? 'Подарок'
        : 'Подарок от $senderName';
    final accentColor = ThemeService().currentTheme.value.myBubble;
    final summary = message.giftPriceEnc == null
        ? message.isMe
              ? 'Вы отправили подарок'
              : 'Вы получили подарок'
        : message.isMe
        ? 'Вы отправили подарок стоимостью ${message.giftPriceEnc} ENC'
        : 'Вы получили подарок стоимостью ${message.giftPriceEnc} ENC';
    final backgroundColor = _readColor(message.giftNftBackgroundColor);

    return GestureDetector(
      onTap: () => _showDetails(context),
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = math.min(constraints.maxWidth * 0.82, 430.0);
            return Center(
              child: SizedBox(
                width: cardWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      summary,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final artworkHeight = constraints.maxWidth * 0.66;
                        return Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF171329),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: accentColor.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: SizedBox(
                                  height: artworkHeight,
                                  width: double.infinity,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          backgroundColor.withValues(
                                            alpha: 0.82,
                                          ),
                                          backgroundColor.withValues(
                                            alpha: 0.52,
                                          ),
                                          const Color(0xFF2A2140),
                                        ],
                                      ),
                                    ),
                                    child: Stack(
                                      children: [
                                        Positioned.fill(
                                          child: CustomPaint(
                                            painter: _GiftPatternPainter(
                                              color: Colors.black.withValues(
                                                alpha: 0.13,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Center(
                                          child: GiftAnimation(
                                            name: name,
                                            giftId: message.giftId,
                                            animationUrl:
                                                message.giftNftAnimationUrl,
                                            size: artworkHeight * 0.88,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (skinName.isNotEmpty ||
                                  skinEmoji.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  [
                                    skinName,
                                    skinEmoji,
                                  ].where((part) => part.isNotEmpty).join(' '),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFB8C5D0),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Text(
                                senderLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                              if ((message.giftCaption ?? '')
                                  .trim()
                                  .isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '«${message.giftCaption!.trim()}»',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFC1C8CE),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: TextButton.icon(
                                  onPressed: () => _showDetails(context),
                                  icon: const Icon(
                                    Icons.auto_awesome,
                                    size: 17,
                                  ),
                                  label: const Text('Посмотреть'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    backgroundColor: accentColor.withValues(
                                      alpha: 0.3,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    shape: const StadiumBorder(),
                                    textStyle: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 5, right: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            _formatTime(message.createdAt),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                          if (message.isMe) ...[
                            const SizedBox(width: 4),
                            Icon(
                              message.readByOthers
                                  ? Icons.done_all
                                  : Icons.done,
                              size: 14,
                              color: message.readByOthers
                                  ? const Color(0xFF64B5F6)
                                  : Colors.white54,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Color _readColor(String? value) {
    final hex = value?.replaceFirst('#', '');
    final colorValue = hex == null ? null : int.tryParse(hex, radix: 16);
    return colorValue == null
        ? const Color(0xFF5C3BA8)
        : Color(0xFF000000 | colorValue);
  }
}

class _GiftPatternPainter extends CustomPainter {
  const _GiftPatternPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const spacingX = 64.0;
    const spacingY = 58.0;
    for (var row = 0, y = 10.0; y < size.height; row++, y += spacingY) {
      final offset = row.isEven ? 0.0 : spacingX / 2;
      for (var x = -16.0 + offset; x < size.width; x += spacingX) {
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(-0.2);
        final path = Path()
          ..moveTo(-5, -9)
          ..quadraticBezierTo(1, -14, 7, -8)
          ..lineTo(4, -3)
          ..quadraticBezierTo(10, 1, 4, 6)
          ..lineTo(-4, 6)
          ..quadraticBezierTo(-10, 5, -7, 0)
          ..lineTo(-4, -2)
          ..close();
        canvas.drawPath(path, paint);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GiftPatternPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
