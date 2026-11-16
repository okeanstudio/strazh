import 'package:flutter/material.dart';
import 'package:strazh/features/gifts/data/services/gift_service.dart';
import 'package:strazh/features/gifts/presentation/widgets/animated_gift_card.dart';
import 'package:strazh/features/gifts/presentation/widgets/gift_details_dialog.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

class GiftNftCard extends StatelessWidget {
  const GiftNftCard({
    super.key,
    required this.gift,
    this.width = 140,
    this.canUpgrade = false,
    this.onUpgraded,
    this.canPin = false,
    this.onPinned,
    this.ownerId,
    this.ownerName,
    this.ownerTag,
    this.ownerAvatarUrl,
    this.profileGrid = false,
  });

  final Map<String, dynamic> gift;
  final double width;
  final bool canUpgrade;
  final ValueChanged<Map<String, dynamic>>? onUpgraded;
  final bool canPin;
  final ValueChanged<Map<String, dynamic>>? onPinned;
  final String? ownerId;
  final String? ownerName;
  final String? ownerTag;
  final String? ownerAvatarUrl;
  final bool profileGrid;

  @override
  Widget build(BuildContext context) {
    final name = (gift['gift_name'] ?? 'Подарок').toString();
    final giftId = gift['gift_id']?.toString();
    final serial = _serialNumber(gift['nft_serial']);
    final backgroundColor = _readColor(gift['nft_background_color']);
    final pattern = (gift['nft_pattern'] ?? 'stars').toString();
    final skinName = (gift['nft_skin_name'] ?? '').toString();
    final skinEmoji = (gift['nft_skin_emoji'] ?? '').toString();
    final animationUrl = (gift['nft_animation_url'] ?? '').toString();
    final isNft = serial != null;
    final isPinned = gift['is_pinned'] == true;

    if (profileGrid) {
      return _buildProfileGridCard(
        context,
        name: name,
        giftId: giftId,
        serial: serial,
        backgroundColor: backgroundColor,
        pattern: pattern,
        animationUrl: animationUrl,
        isNft: isNft,
        isPinned: isPinned,
      );
    }

    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showGiftDetails(
          context: context,
          gift: {
            ...gift,
            if (ownerId != null) 'recipient_id': ownerId,
            if (ownerName != null) 'owner_name': ownerName,
            if (ownerTag != null) 'owner_tag': ownerTag,
            if (ownerAvatarUrl != null) 'owner_avatar_url': ownerAvatarUrl,
          },
          messageId: gift['message_id']?.toString(),
          canManageVisibility: canPin,
          onGiftChanged: onPinned,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: width * 0.84,
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isNft
                      ? [
                          backgroundColor,
                          backgroundColor.withValues(alpha: 0.6),
                        ]
                      : const [Color(0xFF26323A), Color(0xFF182129)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isNft
                      ? backgroundColor.withValues(alpha: 0.9)
                      : const Color(0xFF344754),
                ),
                boxShadow: isNft
                    ? [
                        BoxShadow(
                          color: backgroundColor.withValues(alpha: 0.3),
                          blurRadius: 16,
                        ),
                      ]
                    : null,
              ),
              child: Stack(
                children: [
                  if (isNft)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _NftPatternPainter(
                          pattern: pattern,
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                    ),
                  Center(
                    child: GiftAnimation(
                      name: name,
                      giftId: giftId,
                      animationUrl: isNft && animationUrl.isNotEmpty
                          ? animationUrl
                          : null,
                      size: width * 0.68,
                    ),
                  ),
                  if (serial != null)
                    Positioned(
                      top: 7,
                      right: 7,
                      child: _NftNumberBadge(serial: serial),
                    ),
                  if (canPin)
                    Positioned(
                      top: 5,
                      left: 5,
                      child: _GiftPinButton(
                        inventoryId: (gift['id'] ?? '').toString(),
                        isPinned: isPinned,
                        onPinned: onPinned,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (isNft) ...[
              const SizedBox(height: 2),
              Text(
                skinName.isNotEmpty ? skinName : 'NFT #$serial',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: backgroundColor.withValues(alpha: 0.95),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (skinEmoji.isNotEmpty)
                Text(
                  skinEmoji,
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
            ] else if ((gift['sender_name'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'от ${gift['sender_name']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ],
            if (!isNft && canUpgrade) ...[
              const SizedBox(height: 5),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _showUpgradeDialog(context, name, giftId),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFD477),
                    side: const BorderSide(color: Color(0xFF8A6734)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 6,
                    ),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text(
                    'Улучшить · 25 ENC',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProfileGridCard(
    BuildContext context, {
    required String name,
    required String? giftId,
    required int? serial,
    required Color backgroundColor,
    required String pattern,
    required String animationUrl,
    required bool isNft,
    required bool isPinned,
  }) {
    return SizedBox(
      width: width,
      height: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showGiftDetails(
          context: context,
          gift: {
            ...gift,
            if (ownerId != null) 'recipient_id': ownerId,
            if (ownerName != null) 'owner_name': ownerName,
            if (ownerTag != null) 'owner_tag': ownerTag,
            if (ownerAvatarUrl != null) 'owner_avatar_url': ownerAvatarUrl,
          },
          messageId: gift['message_id']?.toString(),
          canManageVisibility: canPin,
          onGiftChanged: onPinned,
        ),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isNft
                  ? [
                      backgroundColor,
                      Color.lerp(backgroundColor, Colors.black, 0.35)!,
                    ]
                  : const [Color(0xFF252525), Color(0xFF191919)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isNft
                  ? backgroundColor.withValues(alpha: 0.9)
                  : const Color(0xFF303030),
            ),
          ),
          child: Stack(
            children: [
              if (isNft)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _NftPatternPainter(
                      pattern: pattern,
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: GiftAnimation(
                    name: name,
                    giftId: giftId,
                    animationUrl: isNft && animationUrl.isNotEmpty
                        ? animationUrl
                        : null,
                    size: width * 0.72,
                    playDuration: const Duration(seconds: 2),
                  ),
                ),
              ),
              if (canPin)
                Positioned(
                  top: 6,
                  left: 6,
                  child: _GiftPinButton(
                    inventoryId: (gift['id'] ?? '').toString(),
                    isPinned: isPinned,
                    onPinned: onPinned,
                  ),
                ),
              if (serial != null)
                Positioned(
                  top: 7,
                  right: 7,
                  child: _NftNumberBadge(serial: serial),
                ),
              if (canUpgrade && !isNft)
                Positioned(
                  right: 7,
                  bottom: 7,
                  child: Material(
                    color: const Color(0xCC171717),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Улучшить · 25 ENC',
                      onPressed: () =>
                          _showUpgradeDialog(context, name, giftId),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.auto_awesome,
                        color: Color(0xFFFFD477),
                        size: 19,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showUpgradeDialog(
    BuildContext context,
    String name,
    String? giftId,
  ) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _NftUpgradeDialog(
        inventoryId: (gift['id'] ?? '').toString(),
        name: name,
        giftId: giftId,
        emoji: (gift['gift_emoji'] ?? '').toString(),
        onUpgraded: onUpgraded,
      ),
    );
  }

  static int? _serialNumber(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static Color _readColor(dynamic value) {
    final hex = value?.toString().replaceFirst('#', '');
    final parsed = hex == null ? null : int.tryParse(hex, radix: 16);
    return parsed == null
        ? const Color(0xFF6A4C93)
        : Color(0xFF000000 | parsed);
  }
}

class _GiftPinButton extends StatefulWidget {
  const _GiftPinButton({
    required this.inventoryId,
    required this.isPinned,
    required this.onPinned,
  });

  final String inventoryId;
  final bool isPinned;
  final ValueChanged<Map<String, dynamic>>? onPinned;

  @override
  State<_GiftPinButton> createState() => _GiftPinButtonState();
}

class _GiftPinButtonState extends State<_GiftPinButton> {
  bool _isUpdating = false;

  Future<void> _togglePin() async {
    if (_isUpdating || widget.inventoryId.isEmpty) return;
    setState(() => _isUpdating = true);
    try {
      final result = await GiftService.setGiftPinned(
        inventoryId: widget.inventoryId,
        isPinned: !widget.isPinned,
      );
      if (!mounted) return;
      widget.onPinned?.call(result);
      Toast.success(
        context,
        widget.isPinned ? 'Подарок откреплён' : 'Подарок закреплён в профиле',
      );
    } catch (error) {
      debugPrint('Не удалось изменить закрепление подарка: $error');
      if (!mounted) return;
      Toast.error(
        context,
        error.toString().contains('A maximum of 6 gifts can be pinned')
            ? 'Можно закрепить не больше 6 подарков'
            : 'Не удалось изменить закрепление подарка',
      );
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: widget.isPinned ? 'Открепить подарок' : 'Закрепить в профиле',
      onPressed: _isUpdating ? null : _togglePin,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.55),
        foregroundColor: widget.isPinned
            ? const Color(0xFFFFD477)
            : Colors.white,
        minimumSize: const Size(34, 34),
        maximumSize: const Size(34, 34),
        padding: EdgeInsets.zero,
      ),
      icon: _isUpdating
          ? const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(
              widget.isPinned
                  ? Icons.push_pin_rounded
                  : Icons.push_pin_outlined,
              size: 17,
            ),
    );
  }
}

class _NftUpgradeDialog extends StatefulWidget {
  const _NftUpgradeDialog({
    required this.inventoryId,
    required this.name,
    required this.giftId,
    required this.emoji,
    required this.onUpgraded,
  });

  final String inventoryId;
  final String name;
  final String? giftId;
  final String emoji;
  final ValueChanged<Map<String, dynamic>>? onUpgraded;

  @override
  State<_NftUpgradeDialog> createState() => _NftUpgradeDialogState();
}

class _NftUpgradeDialogState extends State<_NftUpgradeDialog>
    with TickerProviderStateMixin {
  static const _previewVariants = [
    (
      name: 'Северное сияние',
      emoji: '🌌',
      color: Color(0xFF315C91),
      pattern: 'stars',
    ),
    (
      name: 'Золотой узор',
      emoji: '✨',
      color: Color(0xFF8A5A24),
      pattern: 'diamonds',
    ),
    (
      name: 'Туманность',
      emoji: '🔮',
      color: Color(0xFF653A87),
      pattern: 'rings',
    ),
    (
      name: 'Мятный блеск',
      emoji: '❄️',
      color: Color(0xFF28756B),
      pattern: 'dots',
    ),
  ];

  late final AnimationController _spinController;
  late final AnimationController _settleController;
  Map<String, dynamic>? _result;
  bool _isUpgrading = false;
  bool _isSettling = false;
  bool _isRevealed = false;
  double _settleTarget = 4;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      duration: const Duration(milliseconds: 3200),
      vsync: this,
    );
    _settleController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _spinController.dispose();
    _settleController.dispose();
    super.dispose();
  }

  Future<void> _upgrade() async {
    setState(() {
      _isUpgrading = true;
      _isSettling = false;
      _errorMessage = null;
    });
    _settleController.reset();
    _spinController.repeat();

    try {
      final result = await GiftService.upgradeGiftToNft(widget.inventoryId);
      if (!mounted) return;
      _result = result;
      final winningIndex = _previewVariants.indexWhere(
        (variant) => variant.name == result['nft_skin_name'],
      );
      _settleTarget = 4 + (winningIndex < 0 ? 0 : winningIndex) / 4;
      widget.onUpgraded?.call(result);
      _spinController.stop();
      setState(() => _isSettling = true);
      await _settleController.forward();
      if (mounted) setState(() => _isRevealed = true);
    } catch (error) {
      debugPrint('Не удалось улучшить подарок до NFT: $error');
      _spinController.stop();
      _settleController.stop();
      if (mounted) {
        setState(() {
          _isSettling = false;
          _errorMessage = error.toString().contains('Insufficient Encoins')
              ? 'Недостаточно энкоинов для улучшения.'
              : 'Не удалось улучшить подарок. Попробуйте ещё раз.';
        });
      }
    } finally {
      if (mounted) setState(() => _isUpgrading = false);
    }
  }

  double get _roulettePosition {
    if (!_isSettling) return _spinController.value;
    return _spinController.value +
        (_settleTarget - _spinController.value) *
            Curves.easeOutQuart.transform(_settleController.value);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final finalColor = _NftColor.read(result?['nft_background_color']);
    final preview =
        _previewVariants[(_spinController.value * 24).floor() %
            _previewVariants.length];
    final color = _isRevealed ? finalColor : preview.color;
    final pattern = _isRevealed
        ? (result?['nft_pattern'] ?? 'stars').toString()
        : preview.pattern;
    final skinName = _isRevealed
        ? (result?['nft_skin_name'] ?? 'Коллекционный скин').toString()
        : preview.name;
    final skinEmoji = _isRevealed
        ? (result?['nft_skin_emoji'] ?? widget.emoji).toString()
        : preview.emoji;

    return Dialog(
      backgroundColor: const Color(0xFF121A21),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: const BorderSide(color: Color(0xFF40515D)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          child: AnimatedBuilder(
            animation: Listenable.merge([_spinController, _settleController]),
            builder: (context, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isRevealed ? 'Коллекционный NFT' : 'Улучшение подарка',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    _isRevealed
                        ? 'Ваш подарок получил уникальный номер'
                        : 'Откройте уникальный скин за ${GiftService.nftUpgradeCost} ENC',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFB2C0C9),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_isUpgrading)
                    GiftCaseRoulette(
                      progress: _roulettePosition,
                      winningSkinName: result?['nft_skin_name']?.toString(),
                    )
                  else
                    _NftRevealArtwork(
                      name: widget.name,
                      giftId: widget.giftId,
                      emoji: skinEmoji,
                      color: color,
                      pattern: pattern,
                      animationUrl: _isRevealed && result != null
                          ? result['nft_animation_url']?.toString()
                          : null,
                      serial: _isRevealed && result != null
                          ? result['nft_serial']?.toString()
                          : null,
                    ),
                  if (_isRevealed) ...[
                    const SizedBox(height: 12),
                    Text(
                      skinName,
                      style: TextStyle(
                        color: color.withValues(alpha: 0.95),
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ],
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFFF8A80),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isUpgrading
                          ? null
                          : _isRevealed
                          ? () => Navigator.pop(context)
                          : _upgrade,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFB98237),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: Text(
                        _isUpgrading
                            ? 'Открываем кейс…'
                            : _isRevealed
                            ? 'Отлично'
                            : _errorMessage == null
                            ? 'Улучшить за ${GiftService.nftUpgradeCost} ENC'
                            : 'Попробовать снова',
                      ),
                    ),
                  ),
                  if (!_isUpgrading && !_isRevealed) ...[
                    const SizedBox(height: 5),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Не сейчас',
                        style: TextStyle(color: Colors.white60),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class GiftCaseRoulette extends StatelessWidget {
  const GiftCaseRoulette({
    super.key,
    required this.progress,
    this.winningSkinName,
  });

  final double progress;
  final String? winningSkinName;

  static const _variants = [
    (name: 'Северное сияние', emoji: '🌌', color: Color(0xFF315C91)),
    (name: 'Золотой узор', emoji: '✨', color: Color(0xFF8A5A24)),
    (name: 'Туманность', emoji: '🔮', color: Color(0xFF653A87)),
    (name: 'Мятный блеск', emoji: '❄️', color: Color(0xFF28756B)),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final cardWidth = (constraints.maxWidth * 0.27)
            .clamp(72.0, 94.0)
            .toDouble();
        final pitch = cardWidth + spacing;
        final cycleWidth = _variants.length * pitch;
        final leadingInset = (constraints.maxWidth - cardWidth) / 2;
        final winningIndex = _variants.indexWhere(
          (variant) => variant.name == winningSkinName,
        );

        return Container(
          height: 230,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFF090F15),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF40515D)),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Transform.translate(
                    key: const ValueKey('profile-gift-roulette-track'),
                    offset: Offset(-progress * cycleWidth, 0),
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      maxWidth: double.infinity,
                      child: SizedBox(
                        width: cycleWidth * 12 + leadingInset,
                        child: Row(
                          children: [
                            SizedBox(width: leadingInset),
                            ...List.generate(48, (index) {
                              final variant =
                                  _variants[index % _variants.length];
                              return Padding(
                                padding: const EdgeInsets.only(right: spacing),
                                child: Container(
                                  key: index == 16 + winningIndex
                                      ? const ValueKey(
                                          'profile-gift-roulette-winning-item',
                                        )
                                      : null,
                                  width: cardWidth,
                                  height: 146,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        variant.color,
                                        variant.color.withValues(alpha: 0.45),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(15),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        variant.emoji,
                                        style: const TextStyle(fontSize: 33),
                                      ),
                                      const SizedBox(height: 8),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                        ),
                                        child: Text(
                                          variant.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: Center(
                  child: Container(
                    width: 3,
                    height: 192,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD56A),
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFB52E).withValues(alpha: 0.8),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 17,
                child: Text(
                  'ВЫПАДАЕТ СЛУЧАЙНЫЙ СКИН',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NftRevealArtwork extends StatelessWidget {
  const _NftRevealArtwork({
    required this.name,
    required this.giftId,
    required this.emoji,
    required this.color,
    required this.pattern,
    required this.animationUrl,
    required this.serial,
  });

  final String name;
  final String? giftId;
  final String emoji;
  final Color color;
  final String pattern;
  final String? animationUrl;
  final String? serial;

  @override
  Widget build(BuildContext context) {
    final artworkWidth = (MediaQuery.sizeOf(context).width - 84)
        .clamp(160.0, 260.0)
        .toDouble();
    return Container(
      width: artworkWidth,
      height: artworkWidth * 0.885,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: 0.6)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 24),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _NftPatternPainter(
                pattern: pattern,
                color: Colors.white.withValues(alpha: 0.18),
              ),
            ),
          ),
          Center(
            child: GiftAnimation(
              name: name,
              giftId: giftId,
              animationUrl: animationUrl,
              size: artworkWidth * 0.58,
            ),
          ),
          if (serial != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Text(
                '№ $serial',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  shadows: [Shadow(blurRadius: 5, color: Colors.black54)],
                ),
              ),
            ),
          if (emoji.isNotEmpty)
            Positioned(
              top: 10,
              right: 12,
              child: Text(emoji, style: const TextStyle(fontSize: 22)),
            ),
        ],
      ),
    );
  }
}

class _NftNumberBadge extends StatelessWidget {
  const _NftNumberBadge({required this.serial});

  final int serial;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Text(
        '#$serial',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _NftPatternPainter extends CustomPainter {
  const _NftPatternPainter({required this.pattern, required this.color});

  final String pattern;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = pattern == 'rings' ? PaintingStyle.stroke : PaintingStyle.fill
      ..strokeWidth = 1.2;
    const spacing = 30.0;

    for (var x = 0.0; x < size.width + spacing; x += spacing) {
      for (var y = 0.0; y < size.height + spacing; y += spacing) {
        switch (pattern) {
          case 'diamonds':
            final path = Path()
              ..moveTo(x, y - 5)
              ..lineTo(x + 4, y)
              ..lineTo(x, y + 5)
              ..lineTo(x - 4, y)
              ..close();
            canvas.drawPath(path, paint);
          case 'rings':
            canvas.drawCircle(Offset(x, y), 5, paint);
          case 'dots':
            canvas.drawCircle(Offset(x, y), 1.8, paint);
          default:
            final path = Path()
              ..moveTo(x, y - 6)
              ..lineTo(x + 1.5, y - 1.5)
              ..lineTo(x + 6, y)
              ..lineTo(x + 1.5, y + 1.5)
              ..lineTo(x, y + 6)
              ..lineTo(x - 1.5, y + 1.5)
              ..lineTo(x - 6, y)
              ..lineTo(x - 1.5, y - 1.5)
              ..close();
            canvas.drawPath(path, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NftPatternPainter oldDelegate) {
    return oldDelegate.pattern != pattern || oldDelegate.color != color;
  }
}

class _NftColor {
  static Color read(dynamic value) {
    final hex = value?.toString().replaceFirst('#', '');
    final parsed = hex == null ? null : int.tryParse(hex, radix: 16);
    return parsed == null
        ? const Color(0xFF6A4C93)
        : Color(0xFF000000 | parsed);
  }
}
