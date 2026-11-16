import 'package:flutter/material.dart';
import 'package:strazh/shared/domain/models/gift.dart';
import 'package:strazh/features/gifts/data/services/encoins_service.dart';
import 'package:strazh/features/gifts/data/services/gift_service.dart';
import 'package:strazh/features/settings/data/services/subscription_service.dart';
import 'package:strazh/features/gifts/presentation/widgets/animated_gift_card.dart';
import 'package:strazh/features/gifts/presentation/widgets/gift_case_reveal_dialog.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

class GiftShopScreen extends StatefulWidget {
  const GiftShopScreen({
    super.key,
    required this.roomId,
    required this.recipientId,
    required this.recipientName,
    this.recipientAvatarUrl,
  });

  final String roomId;
  final String recipientId;
  final String recipientName;
  final String? recipientAvatarUrl;

  @override
  State<GiftShopScreen> createState() => _GiftShopScreenState();
}

class _GiftShopScreenState extends State<GiftShopScreen> {
  final _captionController = TextEditingController();
  List<Gift> _gifts = [];
  Gift? _selectedGift;
  _GiftSubscriptionPlan? _selectedPlan;
  bool _upgradeToNft = false;
  int _balance = 0;
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;

  static const _plans = [
    _GiftSubscriptionPlan(
      id: '1m',
      title: '1 мес.',
      priceEnc: 200,
      badge: '',
      emoji: '🎁',
    ),
    _GiftSubscriptionPlan(
      id: '3m',
      title: '3 мес.',
      priceEnc: 500,
      badge: '−16%',
      emoji: '🎀',
    ),
    _GiftSubscriptionPlan(
      id: '1y',
      title: '1 год',
      priceEnc: 1500,
      badge: '−37%',
      emoji: '💎',
    ),
    _GiftSubscriptionPlan(
      id: '2y',
      title: '2 года',
      priceEnc: 2500,
      badge: '−48%',
      emoji: '🏆',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        GiftService.getCatalog(),
        EncoinsService.getBalance(),
      ]);
      if (!mounted) return;
      setState(() {
        _gifts = results[0] as List<Gift>;
        _balance = results[1] as int;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _sendSelectedGift() async {
    final gift = _selectedGift;
    if (gift == null || _isSending) return;
    final totalCost =
        gift.priceEnc + (_upgradeToNft ? GiftService.nftUpgradeCost : 0);
    if (_balance < totalCost) {
      Toast.error(context, 'Недостаточно Encoins. Нужно $totalCost ENC');
      return;
    }

    setState(() => _isSending = true);
    try {
      final result = GiftService.sendGift(
        roomId: widget.roomId,
        gift: gift,
        caption: _captionController.text.trim(),
        upgradeToNft: _upgradeToNft,
      );
      if (_upgradeToNft) {
        final wasSent = await showGiftCaseRevealDialog(
          context,
          name: gift.name,
          giftId: gift.id,
          emoji: gift.emoji,
          result: result,
        );
        if (!mounted || wasSent != true) return;
      } else {
        await result;
        if (!mounted) return;
      }
      Toast.success(context, 'Подарок отправлен!');
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      Toast.error(context, 'Не удалось отправить подарок: $error');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _sendSelectedPlan(_GiftSubscriptionPlan plan) async {
    if (_isSending) return;
    if (_balance < plan.priceEnc) {
      Toast.error(context, 'Недостаточно Encoins. Нужно ${plan.priceEnc} ENC');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A2530),
        title: const Text(
          'Подарить Strazh Infinity?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '${widget.recipientName} получит подписку на ${plan.title} за ${plan.priceEnc} ENC.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Подарить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSending = true);
    try {
      await SubscriptionService.giftSubscription(
        roomId: widget.roomId,
        recipientId: widget.recipientId,
        planId: plan.id,
      );
      if (!mounted) return;
      Toast.success(context, 'Strazh Infinity подарен!');
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      Toast.error(context, 'Не удалось подарить подписку: $error');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedGiftCost = _selectedGift == null
        ? 0
        : _selectedGift!.priceEnc +
              (_upgradeToNft ? GiftService.nftUpgradeCost : 0);
    final canAffordSelectedGift = _balance >= selectedGiftCost;
    return Scaffold(
      backgroundColor: const Color(0xFF101820),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101820),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded, color: Colors.white),
        ),
        title: const Text(
          'Подарки',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _balanceChip(),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF43B5F5)),
            )
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Не удалось загрузить подарки:\n$_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    children: [
                      _recipientHeader(),
                      const SizedBox(height: 18),
                      const Text(
                        'Подарить Strazh Infinity',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Подарите ${widget.recipientName} доступ к возможностям Infinity',
                        style: const TextStyle(
                          color: Color(0xFFB7C7D6),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _plansGrid(),
                      const SizedBox(height: 22),
                      const Text(
                        'Отправить подарок',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Выберите подарок для профиля собеседника',
                        style: TextStyle(
                          color: Color(0xFFB7C7D6),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _giftsGrid(),
                      if (_selectedGift != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF192630),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF344754)),
                          ),
                          child: CheckboxListTile(
                            value: _upgradeToNft,
                            onChanged: _isSending
                                ? null
                                : (value) => setState(
                                    () => _upgradeToNft = value ?? false,
                                  ),
                            activeColor: const Color(0xFF43B5F5),
                            checkColor: Colors.white,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text(
                              'Сразу улучшить до NFT',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: const Text(
                              'Уникальный скин и номер · +25 ENC',
                              style: TextStyle(
                                color: Color(0xFFB7C7D6),
                                fontSize: 12,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                            dense: true,
                          ),
                        ),
                        if (!canAffordSelectedGift)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Недостаточно Encoins: нужно $selectedGiftCost ENC',
                                style: const TextStyle(
                                  color: Color(0xFFFF8A80),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _captionController,
                          maxLength: 120,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Подпись к подарку (необязательно)',
                            hintStyle: const TextStyle(color: Colors.white38),
                            counterStyle: const TextStyle(
                              color: Colors.white38,
                            ),
                            filled: true,
                            fillColor: const Color(0xFF192630),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_selectedGift != null)
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _isSending || !canAffordSelectedGift
                              ? null
                              : _sendSelectedGift,
                          icon: _isSending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send_rounded),
                          label: Text('Подарить за $selectedGiftCost ENC'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF43B5F5),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _recipientHeader() {
    final avatar = widget.recipientAvatarUrl;
    return Row(
      children: [
        CircleAvatar(
          radius: 25,
          backgroundColor: const Color(0xFF263442),
          foregroundImage: avatar == null || avatar.isEmpty
              ? null
              : NetworkImage(avatar),
          child: Text(
            widget.recipientName.trim().isEmpty
                ? '?'
                : widget.recipientName.trim().characters.first.toUpperCase(),
            style: const TextStyle(color: Colors.white),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Для ${widget.recipientName}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _balanceChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF203D53),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bolt_rounded, size: 18, color: Color(0xFFFFC34D)),
          const SizedBox(width: 4),
          Text(
            '$_balance ENC',
            style: const TextStyle(
              color: Color(0xFF43B5F5),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _plansGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 640 ? 4 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _plans.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: columns == 2 ? 1.15 : 0.9,
          ),
          itemBuilder: (context, index) {
            final plan = _plans[index];
            final selected = plan.id == _selectedPlan?.id;
            final enoughBalance = _balance >= plan.priceEnc;
            return Material(
              color: const Color(0xFF192630),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: _isSending
                    ? null
                    : () {
                        setState(() {
                          _selectedPlan = plan;
                          _selectedGift = null;
                          _upgradeToNft = false;
                        });
                        _sendSelectedPlan(plan);
                      },
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: selected || plan.badge.isNotEmpty
                          ? const Color(0xFF43B5F5)
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(plan.emoji, style: const TextStyle(fontSize: 40)),
                      const SizedBox(height: 5),
                      Text(
                        plan.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Text(
                        'Strazh Infinity',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFFB7C7D6),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF203D53),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '${plan.priceEnc} ENC',
                          style: TextStyle(
                            color: enoughBalance
                                ? const Color(0xFF43B5F5)
                                : Colors.white54,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (plan.badge.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            plan.badge,
                            style: const TextStyle(
                              color: Color(0xFFFFC34D),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _giftsGrid() {
    if (_gifts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'Подарков пока нет',
            style: TextStyle(color: Colors.white60),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 640 ? 4 : 3;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _gifts.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.83,
          ),
          itemBuilder: (context, index) {
            final gift = _gifts[index];
            final selected = gift.id == _selectedGift?.id;
            final affordable = _balance >= gift.priceEnc;
            return Material(
              color: const Color(0xFF192630),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: affordable && !_isSending
                    ? () {
                        setState(() {
                          _selectedGift = gift;
                          _selectedPlan = null;
                          _upgradeToNft = false;
                        });
                      }
                    : null,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF43B5F5)
                          : Colors.white.withValues(alpha: 0.06),
                      width: selected ? 2 : 1,
                    ),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: GiftAnimation(
                          name: gift.name,
                          giftId: gift.id,
                          animationUrl: gift.animationUrl,
                          size: 80,
                        ),
                      ),
                      Text(
                        gift.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: affordable ? Colors.white : Colors.white38,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF34404A),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '${gift.priceEnc} ENC',
                          style: TextStyle(
                            color: affordable
                                ? const Color(0xFFFFC34D)
                                : Colors.white38,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _GiftSubscriptionPlan {
  const _GiftSubscriptionPlan({
    required this.id,
    required this.title,
    required this.priceEnc,
    required this.badge,
    required this.emoji,
  });

  final String id;
  final String title;
  final int priceEnc;
  final String badge;
  final String emoji;
}
