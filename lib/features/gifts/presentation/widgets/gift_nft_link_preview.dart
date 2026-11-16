import 'package:flutter/material.dart';
import 'package:strazh/features/gifts/data/services/gift_service.dart';
import 'package:strazh/features/gifts/presentation/widgets/animated_gift_card.dart';
import 'package:strazh/features/gifts/presentation/widgets/gift_details_dialog.dart';

class GiftNftLinkPreview extends StatelessWidget {
  const GiftNftLinkPreview({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: GiftService.getGiftDetailsBySlug(slug),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Не удалось создать превью NFT-ссылки: ${snapshot.error}');
          return const SizedBox.shrink();
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.only(top: 10),
            child: LinearProgressIndicator(
              minHeight: 2,
              color: Color(0xFF42B8FF),
              backgroundColor: Colors.white12,
            ),
          );
        }

        final gift = snapshot.data!;
        final name = (gift['gift_name'] ?? 'Подарок').toString();
        final serial = gift['nft_serial']?.toString();
        final skin = (gift['nft_skin_name'] ?? '').toString();
        final skinEmoji = (gift['nft_skin_emoji'] ?? '').toString();
        final title = serial == null ? name : '$name #$serial';
        final recipientId = gift['recipient_id']?.toString();
        final currentUserId = GiftService.currentUserId;

        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => showGiftDetails(
                context: context,
                gift: gift,
                canManageVisibility:
                    recipientId != null && recipientId == currentUserId,
              ),
              child: Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Strazh',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (skin.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '$skin $skinEmoji',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 220,
                        width: double.infinity,
                        color: _readColor(gift['nft_background_color']),
                        child: GiftAnimation(
                          name: name,
                          giftId: gift['gift_id']?.toString(),
                          animationUrl: gift['nft_animation_url']?.toString(),
                          size: 200,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => showGiftDetails(
                          context: context,
                          gift: gift,
                          canManageVisibility:
                              recipientId != null &&
                              recipientId == currentUserId,
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: const Text(
                          'ПОКАЗАТЬ ПОДАРОК',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Color _readColor(dynamic value) {
    final hex = value?.toString().replaceFirst('#', '');
    final parsed = hex == null ? null : int.tryParse(hex, radix: 16);
    return parsed == null ? const Color(0xFF426A7C) : Color(0xFF000000 | parsed);
  }
}
