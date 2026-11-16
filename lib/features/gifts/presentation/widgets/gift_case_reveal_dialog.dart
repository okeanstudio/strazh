import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:strazh/features/gifts/presentation/widgets/animated_gift_card.dart';

Future<bool?> showGiftCaseRevealDialog(
  BuildContext context, {
  required String name,
  required String giftId,
  required String emoji,
  required Future<Map<String, dynamic>> result,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => GiftCaseRevealDialog(
      name: name,
      giftId: giftId,
      emoji: emoji,
      result: result,
    ),
  );
}

class GiftCaseRevealDialog extends StatefulWidget {
  const GiftCaseRevealDialog({
    super.key,
    required this.name,
    required this.giftId,
    required this.emoji,
    required this.result,
  });

  final String name;
  final String giftId;
  final String emoji;
  final Future<Map<String, dynamic>> result;

  @override
  State<GiftCaseRevealDialog> createState() => _GiftCaseRevealDialogState();
}

class _GiftCaseRevealDialogState extends State<GiftCaseRevealDialog>
    with SingleTickerProviderStateMixin {
  static const _variants = [
    (name: 'Северное сияние', emoji: '🌌', color: Color(0xFF315C91)),
    (name: 'Золотой узор', emoji: '✨', color: Color(0xFF8A5A24)),
    (name: 'Туманность', emoji: '🔮', color: Color(0xFF653A87)),
    (name: 'Мятный блеск', emoji: '❄️', color: Color(0xFF28756B)),
  ];

  static const _cardWidth = 94.0;
  static const _cardSpacing = 8.0;
  static const _minimumSpinDuration = Duration(seconds: 3);

  late final AnimationController _controller;
  Map<String, dynamic>? _result;
  bool _isRevealed = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _revealGift();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _revealGift() async {
    final minimumSpin = Future<void>.delayed(_minimumSpinDuration);
    try {
      final result = await widget.result;
      await minimumSpin;
      if (!mounted) return;
      await _controller.animateTo(
        1,
        duration: const Duration(milliseconds: 1500),
        curve: Curves.easeOutQuart,
      );
      if (mounted) {
        setState(() {
          _result = result;
          _isRevealed = true;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Не удалось открыть улучшенный подарок: $error');
      debugPrint('$stackTrace');
      if (mounted) {
        _controller.stop();
        setState(() {
          _errorMessage = error.toString().contains('Insufficient Encoins')
              ? 'Недостаточно Encoins для улучшения.'
              : 'Не удалось отправить подарок. Проверьте подключение и миграции Supabase.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final result = _result;
    final skinName = (result?['nft_skin_name'] ?? 'Коллекционный скин')
        .toString();
    final skinEmoji = (result?['nft_skin_emoji'] ?? widget.emoji).toString();
    final serial = result?['nft_serial']?.toString() ?? '';
    final color = _readColor(result?['nft_background_color']);
    final animationUrl = result?['nft_animation_url']?.toString();

    return Dialog(
      backgroundColor: const Color(0xFF111923),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(color: color.withValues(alpha: 0.7)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: size.height * 0.9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage != null
                    ? 'НЕ УДАЛОСЬ ОТПРАВИТЬ'
                    : _isRevealed
                    ? 'ПОДАРОК УЛУЧШЕН!'
                    : 'ОТКРЫВАЕМ ПОДАРОК',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFFFD98A),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                _errorMessage ??
                    (_isRevealed
                        ? 'Ваш подарок стал уникальным NFT'
                        : 'Крутим кейс и выбираем ваш уникальный скин…'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 20),
              _buildRoulette(),
              const SizedBox(height: 20),
              if (_isRevealed)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutBack,
                  transform: Matrix4.identity()
                    ..scale(_isRevealed ? 1.0 : 0.94),
                  transformAlignment: Alignment.center,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color.withValues(alpha: 0.48),
                        color.withValues(alpha: 0.14),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: color.withValues(alpha: _isRevealed ? 0.9 : 0.35),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(
                          alpha: _isRevealed ? 0.42 : 0.12,
                        ),
                        blurRadius: _isRevealed ? 28 : 12,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 106,
                        height: 106,
                        child: GiftAnimation(
                          name: widget.name,
                          giftId: widget.giftId,
                          animationUrl: animationUrl,
                          size: 106,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              skinName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: color.withValues(alpha: 0.98),
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${widget.name} $skinEmoji',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            if (serial.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                '№ $serial',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (_isRevealed || _errorMessage != null)
                const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isRevealed || _errorMessage != null
                      ? () => Navigator.pop(context, _isRevealed)
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: color.withValues(alpha: 0.4),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: Text(
                    _errorMessage != null
                        ? 'Закрыть'
                        : _isRevealed
                        ? 'Забрать подарок'
                        : 'Кейс открывается…',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoulette() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = math.min(
          _cardWidth,
          math.max(70.0, constraints.maxWidth * 0.32),
        );
        final spacing = math.min(_cardSpacing, cardWidth * 0.09);
        final pitch = cardWidth + spacing;
        final cycleDistance = _variants.length * pitch;

        return Container(
          height: 112,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFF080D13),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      return Transform.translate(
                        key: const ValueKey('gift-case-roulette-track'),
                        offset: Offset(-_controller.value * cycleDistance, 0),
                        child: OverflowBox(
                          alignment: Alignment.centerLeft,
                          maxWidth: double.infinity,
                          child: SizedBox(
                            width: 16 * pitch,
                            child: Row(
                              children: List.generate(16, (index) {
                                final variant =
                                    _variants[index % _variants.length];
                                return Padding(
                                  padding: EdgeInsets.only(right: spacing),
                                  child: _rouletteCard(
                                    width: cardWidth,
                                    color: variant.color,
                                    emoji: variant.emoji,
                                    label: variant.name,
                                    highlighted: false,
                                  ),
                                );
                              }),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              IgnorePointer(
                child: Center(
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD56A),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFB52E).withValues(alpha: 0.9),
                          blurRadius: 14,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                width: 30,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF080D13),
                          const Color(0xFF080D13).withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: 30,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                        colors: [
                          const Color(0xFF080D13),
                          const Color(0xFF080D13).withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _rouletteCard({
    required double width,
    required Color color,
    required String emoji,
    required String label,
    required bool highlighted,
  }) {
    return Container(
      width: width,
      height: 86,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.92),
            color.withValues(alpha: 0.48),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlighted ? Colors.white : color.withValues(alpha: 0.8),
          width: highlighted ? 2 : 1,
        ),
        boxShadow: highlighted
            ? [BoxShadow(color: color.withValues(alpha: 0.8), blurRadius: 20)]
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Color _readColor(dynamic value) {
    final hex = value?.toString().replaceFirst('#', '');
    final parsed = hex == null ? null : int.tryParse(hex, radix: 16);
    return parsed == null
        ? const Color(0xFF6A4C93)
        : Color(0xFF000000 | parsed);
  }
}
