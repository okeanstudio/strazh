import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:strazh/features/gifts/data/services/gift_service.dart';
import 'package:strazh/features/gifts/presentation/widgets/animated_gift_card.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

Future<void> showGiftDetails({
  required BuildContext context,
  required Map<String, dynamic> gift,
  String? messageId,
  bool canManageVisibility = false,
  ValueChanged<Map<String, dynamic>>? onGiftChanged,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Закрыть подарок',
    barrierColor: Colors.black.withValues(alpha: 0.72),
    pageBuilder: (context, _, _) => GiftDetailsDialog(
      gift: gift,
      messageId: messageId,
      canManageVisibility: canManageVisibility,
      onGiftChanged: onGiftChanged,
    ),
    transitionDuration: const Duration(milliseconds: 260),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class GiftDetailsDialog extends StatefulWidget {
  const GiftDetailsDialog({
    super.key,
    required this.gift,
    this.messageId,
    this.canManageVisibility = false,
    this.onGiftChanged,
  });

  final Map<String, dynamic> gift;
  final String? messageId;
  final bool canManageVisibility;
  final ValueChanged<Map<String, dynamic>>? onGiftChanged;

  @override
  State<GiftDetailsDialog> createState() => _GiftDetailsDialogState();
}

class _GiftDetailsDialogState extends State<GiftDetailsDialog> {
  late Map<String, dynamic> _gift;
  bool _isLoading = false;
  bool _isPinning = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _gift = Map<String, dynamic>.from(widget.gift);
    final messageId = widget.messageId;
    if (messageId != null && messageId.isNotEmpty) {
      _loadFullDetails(messageId);
    }
  }

  Future<void> _loadFullDetails(String messageId) async {
    setState(() => _isLoading = true);
    try {
      final details = await GiftService.getGiftDetailsForMessage(messageId);
      if (!mounted) return;
      setState(() {
        _gift = {..._gift, ...details};
        _loadError = null;
      });
    } catch (error) {
      debugPrint('Не удалось загрузить подробности подарка: $error');
      if (mounted) {
        setState(() => _loadError = 'Не удалось загрузить все сведения');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _togglePinned() async {
    final inventoryId = _gift['id']?.toString();
    if (inventoryId == null || inventoryId.isEmpty || _isPinning) return;
    setState(() => _isPinning = true);
    try {
      final updated = await GiftService.setGiftPinned(
        inventoryId: inventoryId,
        isPinned: _gift['is_pinned'] != true,
      );
      if (!mounted) return;
      setState(() => _gift = {..._gift, ...updated});
      widget.onGiftChanged?.call(updated);
      Toast.success(
        context,
        updated['is_pinned'] == true
            ? 'Подарок закреплён в профиле'
            : 'Подарок скрыт из профиля',
      );
    } catch (error) {
      debugPrint('Не удалось изменить видимость подарка: $error');
      if (!mounted) return;
      Toast.error(
        context,
        error.toString().contains('A maximum of 6 gifts can be pinned')
            ? 'Можно закрепить не больше 6 подарков'
            : 'Не удалось изменить видимость подарка',
      );
    } finally {
      if (mounted) setState(() => _isPinning = false);
    }
  }

  Future<void> _copyGiftReference() async {
    var gift = _gift;
    if (gift['nft_serial'] == null) {
      final messageId = widget.messageId;
      if (messageId != null && messageId.isNotEmpty) {
        try {
          final details = await GiftService.getGiftDetailsForMessage(messageId);
          if (!mounted) return;
          gift = {...gift, ...details};
          setState(() {
            _gift = gift;
            _loadError = null;
          });
        } catch (error) {
          debugPrint('Не удалось загрузить NFT для ссылки: $error');
        }
      }

      if (gift['nft_serial'] == null) {
        final inventoryId = gift['id']?.toString();
        final recipientId = gift['recipient_id']?.toString();
        if (inventoryId != null &&
            inventoryId.isNotEmpty &&
            recipientId != null &&
            recipientId.isNotEmpty) {
          try {
            final receivedGifts = await GiftService.getReceivedGifts(
              recipientId,
            );
            for (final receivedGift in receivedGifts) {
              if (receivedGift['id']?.toString() == inventoryId) {
                gift = {...gift, ...receivedGift};
                if (mounted) {
                  setState(() {
                    _gift = gift;
                    _loadError = null;
                  });
                }
                break;
              }
            }
          } catch (error) {
            debugPrint('Не удалось загрузить подарок владельца: $error');
            if (mounted) {
              Toast.error(context, 'Не удалось загрузить данные подарка');
            }
            return;
          }
        }
      }
    }

    final serial = int.tryParse(gift['nft_serial']?.toString() ?? '');
    if (serial == null) {
      if (mounted) {
        Toast.error(context, 'Ссылка доступна только для NFT-подарков');
      }
      return;
    }

    final name = (gift['gift_name'] ?? 'Подарок').toString();
    final giftId = gift['gift_id']?.toString();
    final url = GiftService.giftNftUrl(
      name: name,
      serial: serial,
      giftId: giftId,
    );
    if (url == null) {
      if (mounted) {
        Toast.error(context, 'Не удалось создать ссылку на NFT');
      }
      return;
    }

    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      Toast.success(context, 'Ссылка на NFT скопирована');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final isWide = screenSize.width > 700;
    final giftName = (_gift['gift_name'] ?? 'Подарок').toString();
    final giftId = _gift['gift_id']?.toString();
    final serial = _gift['nft_serial']?.toString();
    final skinName = (_gift['nft_skin_name'] ?? '').toString();
    final skinEmoji = (_gift['nft_skin_emoji'] ?? '').toString();
    final pattern = (_gift['nft_pattern'] ?? '').toString();
    final backgroundHex = (_gift['nft_background_color'] ?? '').toString();
    final color = _readColor(backgroundHex);
    final senderName = (_gift['sender_name'] ?? '').toString();
    final senderTag = (_gift['sender_tag'] ?? '').toString();
    final ownerName = (_gift['owner_name'] ?? '').toString();
    final ownerTag = (_gift['owner_tag'] ?? '').toString();
    final caption = (_gift['caption'] ?? '').toString();
    final isPinned = _gift['is_pinned'] == true;
    final timestamp = DateTime.tryParse(
      (_gift['nft_upgraded_at'] ?? _gift['created_at'] ?? '').toString(),
    );
    final title = serial == null ? giftName : '$giftName #$serial';

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isWide ? 680 : double.infinity,
            maxHeight: screenSize.height,
          ),
          child: Material(
            color: const Color(0xFF17232E),
            child: Column(
              children: [
                SizedBox(
                  height: math.min(screenSize.height * 0.4, 560),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                color,
                                color.withValues(alpha: 0.78),
                                const Color(0xFF38596C),
                              ],
                            ),
                          ),
                          child: CustomPaint(
                            painter: _GiftBackgroundPainter(
                              color: Colors.black.withValues(alpha: 0.12),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 10,
                        left: 10,
                        child: _HeroIconButton(
                          tooltip: 'Закрыть',
                          icon: Icons.close_rounded,
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: _HeroIconButton(
                          tooltip: 'Скопировать ссылку',
                          icon: Icons.more_horiz_rounded,
                          onPressed: _copyGiftReference,
                        ),
                      ),
                      Positioned.fill(
                        top: 45,
                        bottom: 106,
                        child: Center(
                          child: SizedBox(
                            width: math.min(screenSize.width * 0.58, 310),
                            height: math.min(screenSize.width * 0.58, 310),
                            child: GiftAnimation(
                              name: giftName,
                              giftId: giftId,
                              animationUrl: (_gift['nft_animation_url'] ?? '')
                                  .toString(),
                              size: 260,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 104,
                        child: Column(
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (skinName.isNotEmpty ||
                                skinEmoji.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                [
                                  skinName,
                                  skinEmoji,
                                ].where((part) => part.isNotEmpty).join(' '),
                                style: const TextStyle(
                                  color: Color(0xFFD8E5ED),
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Positioned(
                        left: 14,
                        right: 14,
                        bottom: 14,
                        child: Row(
                          children: [
                            Expanded(
                              child: _HeroActionButton(
                                icon: Icons.ios_share_rounded,
                                label: 'Поделиться',
                                onPressed: _copyGiftReference,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _HeroActionButton(
                                icon: isPinned
                                    ? Icons.push_pin_rounded
                                    : Icons.push_pin_outlined,
                                label: isPinned ? 'В профиле' : 'В профиль',
                                onPressed: widget.canManageVisibility
                                    ? _togglePinned
                                    : null,
                                isActive: isPinned,
                                isLoading: _isPinning,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _HeroActionButton(
                                icon: Icons.check_rounded,
                                label: 'Готово',
                                onPressed: () => Navigator.pop(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                    children: [
                      Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: const Color(0xFF18242F),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: const Color(0xFF263746),
                            width: 1.2,
                          ),
                        ),
                        child: Column(
                          children: [
                            _DetailRow(
                              label: 'Владелец',
                              value: _personValue(
                                ownerName.isEmpty ? 'Вы' : ownerName,
                                ownerTag,
                              ),
                              valueLeading: _OwnerAvatar(
                                url: _gift['owner_avatar_url']?.toString(),
                              ),
                            ),
                            _DetailRow(
                              label: 'Модель',
                              value: serial == null
                                  ? giftName
                                  : '$giftName  #$serial',
                            ),
                            if (skinName.isNotEmpty)
                              _DetailRow(
                                label: 'Скин',
                                value: skinName,
                                pill: 'NFT',
                              ),
                            if (pattern.isNotEmpty)
                              _DetailRow(
                                label: 'Узор',
                                value: _patternLabel(pattern),
                              ),
                            if (backgroundHex.isNotEmpty)
                              _DetailRow(
                                label: 'Фон',
                                value: backgroundHex,
                                valueColor: color,
                              ),
                            if (serial != null)
                              _DetailRow(label: 'Номер', value: '#$serial'),
                            if (timestamp != null)
                              _DetailRow(
                                label: 'Получен',
                                value: _formatDate(timestamp),
                              ),
                            if (_gift['price_enc'] != null)
                              _DetailRow(
                                label: 'Стоимость',
                                value: '${_gift['price_enc']} ENC',
                              ),
                            if (caption.isNotEmpty)
                              _DetailRow(
                                label: 'Комментарий',
                                value: '«$caption»',
                                isLast: true,
                              )
                            else
                              _DetailRow(
                                label: 'Отправитель',
                                value: _personValue(
                                  senderName.isEmpty ? 'Подарок' : senderName,
                                  senderTag,
                                ),
                                isLast: true,
                              ),
                          ],
                        ),
                      ),
                      if (senderName.isNotEmpty && caption.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Подарок от ${_personValue(senderName, senderTag)}'
                          '${timestamp == null ? '' : ' · ${_formatDate(timestamp)}'}'
                          '\n«$caption»',
                          textAlign: TextAlign.start,
                          style: const TextStyle(
                            color: Color(0xFFB7C7D3),
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                      ],
                      if (_isLoading) ...[
                        const SizedBox(height: 14),
                        const Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ],
                      if (_loadError != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _loadError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFFFB4AB),
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 54,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF08A9F2),
                            foregroundColor: Colors.white,
                            shape: const StadiumBorder(),
                          ),
                          child: const Text(
                            'OK',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _personValue(String name, String tag) {
    if (tag.isEmpty) return name;
    return '$name  @$tag';
  }

  String _patternLabel(String pattern) {
    return switch (pattern) {
      'stars' => 'Звёзды',
      'diamonds' => 'Ромбы',
      'rings' => 'Кольца',
      'dots' => 'Точки',
      _ => pattern,
    };
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day.$month.${date.year}';
  }

  Color _readColor(String value) {
    final normalized = value.replaceFirst('#', '');
    final parsed = int.tryParse(normalized, radix: 16);
    return parsed == null
        ? const Color(0xFF426A7C)
        : Color(0xFF000000 | parsed);
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.pill,
    this.valueColor,
    this.valueLeading,
    this.isLast = false,
  });

  final String label;
  final String value;
  final String? pill;
  final Color? valueColor;
  final Widget? valueLeading;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFF263746))),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 132,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 15,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFFE5EDF2),
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
            Container(width: 1, color: const Color(0xFF263746)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 15,
                ),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (valueLeading != null) valueLeading!,
                    Text(
                      value,
                      style: TextStyle(
                        color: valueColor ?? Colors.white,
                        fontSize: 15,
                      ),
                    ),
                    if (pill != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF203D53),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          pill!,
                          style: const TextStyle(
                            color: Color(0xFF42B8FF),
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OwnerAvatar extends StatelessWidget {
  const _OwnerAvatar({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = url?.trim() ?? '';
    return ClipOval(
      child: SizedBox(
        width: 26,
        height: 26,
        child: avatarUrl.isEmpty
            ? const ColoredBox(
                color: Color(0xFF253746),
                child: Icon(
                  Icons.person_rounded,
                  size: 17,
                  color: Color(0xFFB4C7D5),
                ),
              )
            : Image.network(
                avatarUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: Color(0xFF253746),
                  child: Icon(
                    Icons.person_rounded,
                    size: 17,
                    color: Color(0xFFB4C7D5),
                  ),
                ),
              ),
      ),
    );
  }
}

class _HeroIconButton extends StatelessWidget {
  const _HeroIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        fixedSize: const Size(54, 54),
        foregroundColor: Colors.white,
        backgroundColor: Colors.black.withValues(alpha: 0.12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
        shape: const CircleBorder(),
      ),
      icon: Icon(icon, size: 28),
    );
  }
}

class _HeroActionButton extends StatelessWidget {
  const _HeroActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isActive = false,
    this.isLoading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool isActive;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: isActive
              ? const Color(0xFF245A78)
              : Colors.black.withValues(alpha: 0.1),
          disabledBackgroundColor: Colors.black.withValues(alpha: 0.08),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white38,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 22),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
      ),
    );
  }
}

class _GiftBackgroundPainter extends CustomPainter {
  const _GiftBackgroundPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const spacingX = 118.0;
    const spacingY = 108.0;
    for (var row = 0, y = 16.0; y < size.height; row++, y += spacingY) {
      final offset = row.isEven ? 0.0 : spacingX / 2;
      for (var x = -30.0 + offset; x < size.width; x += spacingX) {
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(-0.2);
        final path = Path()
          ..moveTo(-9, -17)
          ..quadraticBezierTo(1, -24, 11, -16)
          ..lineTo(6, -6)
          ..quadraticBezierTo(16, 1, 7, 10)
          ..lineTo(-7, 10)
          ..quadraticBezierTo(-19, 8, -14, 0)
          ..lineTo(-7, -4)
          ..close();
        canvas.drawPath(path, paint);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GiftBackgroundPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
