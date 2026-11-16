import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:strazh/features/gifts/presentation/widgets/animated_gift_card.dart';
import 'package:strazh/features/gifts/presentation/widgets/gift_details_dialog.dart';
import 'package:strazh/features/profile/data/services/profile_nft_decoration_service.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

class ProfileNftAvatarOrbit extends StatelessWidget {
  const ProfileNftAvatarOrbit({
    super.key,
    required this.child,
    required this.gifts,
    this.size = 184,
  });

  final Widget child;
  final List<Map<String, dynamic>> gifts;
  final double size;

  @override
  Widget build(BuildContext context) {
    final visibleGifts = gifts.take(4).toList();
    if (visibleGifts.isEmpty) return child;

    return SizedBox(
      width: size,
      height: size * 0.94,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          child,
          for (var index = 0; index < visibleGifts.length; index++)
            Positioned(
              left: index.isEven ? size * 0.04 : null,
              right: index.isOdd ? size * 0.04 : null,
              top: index < 2 ? size * 0.05 : null,
              bottom: index >= 2 ? size * 0.05 : null,
              child: _SparklingNft(
                gift: visibleGifts[index],
                size: (size * 0.19).clamp(46.0, 62.0),
              ),
            ),
        ],
      ),
    );
  }
}

class ProfileNftNameDecoration extends StatelessWidget {
  const ProfileNftNameDecoration({
    super.key,
    required this.child,
    required this.gift,
  });

  final Widget child;
  final Map<String, dynamic>? gift;

  @override
  Widget build(BuildContext context) {
    if (gift == null) return child;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: child),
        const SizedBox(width: 5),
        _SparklingNft(gift: gift!, size: 30),
      ],
    );
  }
}

class ProfileNftDecorationPicker {
  static Future<void> show({
    required BuildContext context,
    required List<Map<String, dynamic>> gifts,
    required Map<String, Map<int, String>> decorations,
    required ValueChanged<Map<String, Map<int, String>>> onChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DecorationPickerSheet(
        gifts: gifts
            .where((gift) => gift['nft_serial'] != null)
            .toList(growable: false),
        decorations: decorations,
        onChanged: onChanged,
      ),
    );
  }
}

class _DecorationPickerSheet extends StatefulWidget {
  const _DecorationPickerSheet({
    required this.gifts,
    required this.decorations,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> gifts;
  final Map<String, Map<int, String>> decorations;
  final ValueChanged<Map<String, Map<int, String>>> onChanged;

  @override
  State<_DecorationPickerSheet> createState() => _DecorationPickerSheetState();
}

class _DecorationPickerSheetState extends State<_DecorationPickerSheet> {
  late Map<String, Map<int, String>> _decorations;
  String _placement = 'avatar';
  int _slot = 0;
  String? _savingGiftId;
  bool _isClearing = false;

  @override
  void initState() {
    super.initState();
    _decorations = {
      'avatar': Map<int, String>.from(widget.decorations['avatar'] ?? {}),
      'name': Map<int, String>.from(widget.decorations['name'] ?? {}),
    };
  }

  String? get _equippedInventoryId => _decorations[_placement]?[_slot];

  Future<void> _equip(Map<String, dynamic> gift) async {
    final inventoryId = gift['id']?.toString();
    if (inventoryId == null || inventoryId.isEmpty) return;
    setState(() {
      _savingGiftId = inventoryId;
      _isClearing = false;
    });

    try {
      await ProfileNftDecorationService.setDecoration(
        placement: _placement,
        slot: _slot,
        inventoryId: inventoryId,
      );
      if (!mounted) return;
      for (final slots in _decorations.values) {
        slots.removeWhere((_, assignedId) => assignedId == inventoryId);
      }
      _decorations[_placement]![_slot] = inventoryId;
      widget.onChanged(_decorations);
      setState(() => _savingGiftId = null);
    } catch (error) {
      debugPrint('Не удалось установить NFT-украшение профиля: $error');
      if (!mounted) return;
      setState(() => _savingGiftId = null);
      Toast.error(context, 'Не удалось сохранить украшение');
    }
  }

  Future<void> _clearSlot() async {
    final inventoryId = _equippedInventoryId;
    if (inventoryId == null) return;
    setState(() => _isClearing = true);
    try {
      await ProfileNftDecorationService.setDecoration(
        placement: _placement,
        slot: _slot,
        inventoryId: null,
      );
      if (!mounted) return;
      _decorations[_placement]!.remove(_slot);
      widget.onChanged(_decorations);
      setState(() => _isClearing = false);
    } catch (error) {
      debugPrint('Не удалось снять NFT-украшение профиля: $error');
      if (!mounted) return;
      setState(() => _isClearing = false);
      Toast.error(context, 'Не удалось снять украшение');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.82,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF151923),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: Color(0xFF344052))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Text(
                  'Украшения профиля',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Text(
                  'Выбери NFT-подарки для аватарки и ника',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'avatar',
                      label: Text('Вокруг аватарки'),
                      icon: Icon(Icons.account_circle_outlined),
                    ),
                    ButtonSegment(
                      value: 'name',
                      label: Text('У ника'),
                      icon: Icon(Icons.auto_awesome),
                    ),
                  ],
                  selected: {_placement},
                  onSelectionChanged: (value) {
                    setState(() {
                      _placement = value.first;
                      _slot = 0;
                    });
                  },
                  style: SegmentedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    selectedForegroundColor: Colors.white,
                    selectedBackgroundColor: const Color(0xFF4055A8),
                  ),
                ),
              ),
              if (_placement == 'avatar')
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: List.generate(
                      4,
                      (index) => ChoiceChip(
                        label: Text('Слот ${index + 1}'),
                        selected: _slot == index,
                        onSelected: (_) => setState(() => _slot = index),
                        selectedColor: const Color(0xFF344A96),
                        labelStyle: TextStyle(
                          color: _slot == index ? Colors.white : Colors.white70,
                        ),
                        side: BorderSide(
                          color: _slot == index
                              ? const Color(0xFF7895FF)
                              : Colors.white12,
                        ),
                      ),
                    ),
                  ),
                )
              else
                const SizedBox(height: 16),
              if (_equippedInventoryId != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                  child: OutlinedButton.icon(
                    onPressed: _isClearing ? null : _clearSlot,
                    icon: _isClearing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.remove_circle_outline, size: 18),
                    label: const Text('Снять украшение с этого места'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                  ),
                ),
              Flexible(
                child: widget.gifts.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(28),
                        child: Text(
                          'Сначала получи NFT-подарок — он появится здесь.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white60),
                        ),
                      )
                    : GridView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 0.84,
                            ),
                        itemCount: widget.gifts.length,
                        itemBuilder: (context, index) {
                          final gift = widget.gifts[index];
                          final id = gift['id']?.toString() ?? '';
                          final isEquipped = _equippedInventoryId == id;
                          final isSaving = _savingGiftId == id;
                          final color = _giftColor(
                            gift['nft_background_color'],
                          );
                          return InkWell(
                            onTap: isSaving ? null : () => _equip(gift),
                            borderRadius: BorderRadius.circular(18),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: color.withValues(
                                  alpha: isEquipped ? 0.3 : 0.12,
                                ),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isEquipped
                                      ? color
                                      : Colors.white.withValues(alpha: 0.1),
                                  width: isEquipped ? 1.8 : 1,
                                ),
                                boxShadow: isEquipped
                                    ? [
                                        BoxShadow(
                                          color: color.withValues(alpha: 0.22),
                                          blurRadius: 16,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        SizedBox(
                                          width: 72,
                                          height: 72,
                                          child: GiftAnimation(
                                            name:
                                                gift['gift_name']?.toString() ??
                                                'Подарок',
                                            giftId: gift['gift_id']?.toString(),
                                            animationUrl:
                                                gift['nft_animation_url']
                                                    ?.toString(),
                                            size: 72,
                                            playDuration: const Duration(
                                              seconds: 2,
                                            ),
                                          ),
                                        ),
                                        if (isSaving)
                                          const CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        if (isEquipped && !isSaving)
                                          const Positioned(
                                            right: 0,
                                            top: 0,
                                            child: Icon(
                                              Icons.check_circle,
                                              color: Color(0xFF86F0B3),
                                              size: 20,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    (gift['nft_skin_name'] ??
                                            gift['gift_name'] ??
                                            'NFT')
                                        .toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '№${gift['nft_serial']}',
                                    style: TextStyle(
                                      color: color.withValues(alpha: 0.9),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SparklingNft extends StatefulWidget {
  const _SparklingNft({required this.gift, required this.size});

  final Map<String, dynamic> gift;
  final double size;

  @override
  State<_SparklingNft> createState() => _SparklingNftState();
}

class _SparklingNftState extends State<_SparklingNft>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _stopTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..forward();
    _stopTimer = Timer(const Duration(seconds: 2), _controller.stop);
  }

  @override
  void dispose() {
    _stopTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _giftColor(widget.gift['nft_background_color']);
    return GestureDetector(
      onTap: () => showGiftDetails(
        context: context,
        gift: widget.gift,
        messageId: widget.gift['message_id']?.toString(),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF141922).withValues(alpha: 0.94),
              border: Border.all(
                color: color.withValues(alpha: 0.85),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 15,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: GiftAnimation(
                name: widget.gift['gift_name']?.toString() ?? 'Подарок',
                giftId: widget.gift['gift_id']?.toString(),
                animationUrl: widget.gift['nft_animation_url']?.toString(),
                size: widget.size - 8,
                playDuration: const Duration(seconds: 2),
              ),
            ),
          ),
        ),
        builder: (context, child) {
          final pulse = 0.92 + math.sin(_controller.value * math.pi * 2) * 0.08;
          return Transform.scale(
            scale: pulse,
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  child!,
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _SparklePainter(
                          progress: _controller.value,
                          color: const Color(0xFFFFF2BE),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  const _SparklePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const points = [
      Offset(0.13, 0.22),
      Offset(0.82, 0.12),
      Offset(0.92, 0.74),
      Offset(0.22, 0.88),
    ];
    for (var index = 0; index < points.length; index++) {
      final phase = (progress + index * 0.23) % 1;
      final opacity = math.sin(phase * math.pi).clamp(0.12, 1.0);
      final radius = 1.3 + math.sin(phase * math.pi) * 1.5;
      final center = Offset(
        points[index].dx * size.width,
        points[index].dy * size.height,
      );
      final paint = Paint()..color = color.withValues(alpha: opacity);
      canvas.drawCircle(center, radius, paint);
      canvas.drawLine(
        center.translate(-radius * 1.8, 0),
        center.translate(radius * 1.8, 0),
        paint..strokeWidth = 0.8,
      );
      canvas.drawLine(
        center.translate(0, -radius * 1.8),
        center.translate(0, radius * 1.8),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SparklePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

Color _giftColor(Object? value) {
  final hex = value?.toString().replaceFirst('#', '');
  if (hex == null || !RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(hex)) {
    return const Color(0xFF6C8EFF);
  }
  return Color(int.parse('FF$hex', radix: 16));
}
