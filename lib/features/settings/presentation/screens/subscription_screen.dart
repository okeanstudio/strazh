import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/features/gifts/data/services/encoins_service.dart';
import 'package:strazh/features/settings/data/services/subscription_service.dart';
import 'package:strazh/core/utils/subscription_utils.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  int _balance = 0;
  bool _isLoading = true;
  bool _isPurchasing = false;
  String? _selectedPlan;
  bool _isSubscribed = false;
  String? _currentPlan;
  DateTime? _expiresAt;
  String _displayName = 'Пользователь';
  String? _avatarUrl;

  final List<SubscriptionPlan> _plans = [
    SubscriptionPlan(
      id: '1m',
      title: '1 месяц',
      duration: 30,
      priceRub: 199,
      priceEnc: 200,
      discount: 0,
      isPopular: false,
    ),
    SubscriptionPlan(
      id: '3m',
      title: '3 месяца',
      duration: 90,
      priceRub: 499,
      priceEnc: 500,
      discount: 16,
      isPopular: true,
    ),
    SubscriptionPlan(
      id: '1y',
      title: '1 год',
      duration: 365,
      priceRub: 1499,
      priceEnc: 1500,
      discount: 37,
      isPopular: false,
    ),
    SubscriptionPlan(
      id: '2y',
      title: '2 года',
      duration: 730,
      priceRub: 2499,
      priceEnc: 2500,
      discount: 48,
      isPopular: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
    _loadData();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final balance = await EncoinsService.getBalance();
    final subscription = await SubscriptionService.getCurrentSubscription();
    final user = Supabase.instance.client.auth.currentUser;
    final metadata = user?.userMetadata ?? const <String, dynamic>{};
    final displayName =
        [
              metadata['name'],
              metadata['full_name'],
              metadata['tag'],
              user?.email?.split('@').first,
            ]
            .map((value) => value?.toString().trim() ?? '')
            .firstWhere(
              (value) => value.isNotEmpty,
              orElse: () => 'Пользователь',
            );
    final avatar = [metadata['avatar_url'], metadata['picture']]
        .map((value) => value?.toString().trim() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');

    if (mounted) {
      setState(() {
        _balance = balance;
        _displayName = displayName;
        _avatarUrl = avatar.isEmpty ? null : avatar;
        _isLoading = false;

        if (subscription != null) {
          final expiresAt = subscription['subscription_expires_at'];
          if (isPremiumSubscriptionActive(subscription)) {
            final expiresText = expiresAt?.toString().trim() ?? '';
            final isForever =
                expiresText.toLowerCase() == 'forever' ||
                subscription['subscription_plan_id']
                        ?.toString()
                        .trim()
                        .toLowerCase() ==
                    'forever';
            if (isForever) {
              _isSubscribed = true;
              _expiresAt = null;
            } else {
              final parsed = DateTime.tryParse(expiresText);
              _expiresAt = parsed;
              _isSubscribed = parsed != null && parsed.isAfter(DateTime.now());
            }
            _currentPlan = subscription['subscription_plan_id'] as String?;
          } else {
            _isSubscribed = false;
            _expiresAt = null;
            _currentPlan = null;
          }
        } else {
          _isSubscribed = false;
          _expiresAt = null;
          _currentPlan = null;
        }
      });
    }
  }

  Future<void> _buySubscription(SubscriptionPlan plan) async {
    if (_isPurchasing) return;

    final metadata = Supabase.instance.client.auth.currentUser?.userMetadata;
    final hasPermanentSubscription =
        isPremiumSubscriptionActive(metadata) &&
        (metadata?['subscription_expires_at']
                    ?.toString()
                    .trim()
                    .toLowerCase() ==
                'forever' ||
            metadata?['subscription_plan_id']
                    ?.toString()
                    .trim()
                    .toLowerCase() ==
                'forever');
    if (hasPermanentSubscription || (_isSubscribed && _expiresAt == null)) {
      Toast.info(context, 'У вас уже есть бессрочная подписка Strazh Infinity');
      return;
    }

    if (_isSubscribed) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1A1428),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Продлить подписку?',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'У вас уже есть активная подписка. Хотите продлить её на ${plan.title}?',
            style: const TextStyle(color: Colors.grey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Продлить',
                style: TextStyle(color: Color(0xFF9B7AE8)),
              ),
            ),
          ],
        ),
      );
      if (!mounted || confirm != true) return;
    }

    if (_balance < plan.priceEnc) {
      Toast.error(context, 'Недостаточно Encoins. Нужно ${plan.priceEnc} ENC');
      return;
    }

    final paymentMethod = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Способ оплаты',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              // ENCOINS — АКТИВНА
              _buildPaymentOption(
                icon: Icons.bolt_rounded,
                title: 'Encoins',
                subtitle: '${plan.priceEnc} ENC (баланс: $_balance)',
                onTap: () => Navigator.pop(context, 'enc'),
                isActive: true,
              ),
              const Divider(color: Color(0xFF2A2337), height: 1),
              // КАРТА — ЗАБЛОКИРОВАНА
              _buildPaymentOption(
                icon: Icons.credit_card,
                title: 'Банковская карта',
                subtitle: '${plan.priceRub} ₽',
                onTap: () => Navigator.pop(context, 'card'),
                isActive: false,
                isDisabled: true,
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || paymentMethod == null) return;

    if (paymentMethod == 'enc') {
      setState(() => _isPurchasing = true);

      try {
        final subscribed = await SubscriptionService.subscribe(
          planId: plan.id,
          planTitle: plan.title,
          priceRub: plan.priceRub,
          priceEnc: plan.priceEnc,
          paymentMethod: 'enc',
          durationDays: plan.duration,
        );

        if (!mounted) return;
        setState(() => _isPurchasing = false);
        if (subscribed) {
          Toast.success(context, 'Подписка ${plan.title} оформлена!');
          await _loadData();
        } else {
          Toast.error(
            context,
            'Не удалось оформить подписку. Баланс не изменён.',
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isPurchasing = false);
          Toast.error(context, 'Ошибка: $e');
        }
      }
    } else {
      Toast.info(context, 'Оплата картой временно недоступна');
    }
  }

  Widget _buildPaymentOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isActive = true,
    bool isDisabled = false,
  }) {
    final color = isDisabled
        ? Colors.grey[600]
        : (isActive ? Colors.white : Colors.grey[400]);
    final iconColor = isDisabled
        ? Colors.grey[600]
        : (isActive ? const Color(0xFF9B7AE8) : Colors.grey[400]);

    return InkWell(
      onTap: isDisabled ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDisabled
                    ? Colors.grey.withValues(alpha: 0.1)
                    : const Color(0xFF6C3BD8).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: color,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isDisabled) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Временно недоступно',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      if (isActive && !isDisabled) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Доступно',
                            style: TextStyle(
                              color: Colors.green[400],
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isDisabled ? Colors.grey[600] : Colors.grey[400],
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (isDisabled)
              Icon(Icons.lock_outline, color: Colors.grey[600], size: 18)
            else
              Icon(Icons.chevron_right, color: Colors.grey[500], size: 18),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101820),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF43B5F5),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _buildHeaderCard(),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Выберите срок Strazh Infinity',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _buildPlansGrid(),
                          const SizedBox(height: 18),
                          _buildBenefitsSection(),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          SizedBox(
            height: 270,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: 62,
                  left: 18,
                  child: Icon(
                    Icons.bolt_rounded,
                    color: const Color(0xFFFFC34D).withValues(alpha: 0.65),
                    size: 32,
                  ),
                ),
                Positioned(
                  top: 46,
                  right: 24,
                  child: Icon(
                    Icons.bolt_rounded,
                    color: const Color(0xFF43B5F5).withValues(alpha: 0.72),
                    size: 25,
                  ),
                ),
                Positioned(
                  top: 130,
                  left: 56,
                  child: Icon(
                    Icons.bolt_rounded,
                    color: const Color(0xFF43B5F5).withValues(alpha: 0.45),
                    size: 18,
                  ),
                ),
                Positioned(
                  top: 140,
                  right: 50,
                  child: Icon(
                    Icons.bolt_rounded,
                    color: const Color(0xFFFFC34D).withValues(alpha: 0.55),
                    size: 20,
                  ),
                ),
                Positioned(
                  top: 4,
                  left: 0,
                  child: _roundHeaderButton(
                    icon: Icons.close_rounded,
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 0,
                  child: _roundHeaderButton(
                    icon: Icons.refresh_rounded,
                    onPressed: _loadData,
                  ),
                ),
                Positioned(top: 26, child: _buildAvatar()),
                Positioned(
                  bottom: 10,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      Text(
                        'Strazh Infinity',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Дополнительные возможности для $_displayName',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _isSubscribed
                              ? const Color(0xFF234A3B)
                              : const Color(0xFF263442),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _isSubscribed
                              ? _expiresAt == null
                                    ? 'Подписка активна без ограничения срока'
                                    : 'Активна до ${_expiresAt!.day}.${_expiresAt!.month}.${_expiresAt!.year}'
                              : 'Оплата Encoins · баланс $_balance ENC',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _isSubscribed
                                ? const Color(0xFF8EE0B0)
                                : const Color(0xFFB7C7D6),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (_isSubscribed)
                        TextButton(
                          onPressed: _confirmCancelSubscription,
                          child: const Text(
                            'Отменить подписку',
                            style: TextStyle(color: Color(0xFFFF8B8B)),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundHeaderButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: const Color(0xFF26323C),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: 22),
        tooltip: icon == Icons.close_rounded ? 'Закрыть' : 'Обновить',
      ),
    );
  }

  Widget _buildAvatar() {
    final initials = _displayName.trim().isEmpty
        ? '?'
        : _displayName.trim().characters.first.toUpperCase();
    return Container(
      width: 136,
      height: 136,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF38BDF8), Color(0xFF7C65E8), Color(0xFFFFC34D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF43B5F5).withValues(alpha: 0.28),
            blurRadius: 32,
            spreadRadius: 4,
          ),
        ],
      ),
      child: ClipOval(
        child: _avatarUrl == null
            ? _avatarFallback(initials)
            : Image.network(
                _avatarUrl!,
                width: 128,
                height: 128,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  debugPrint('Не удалось загрузить аватар подписки: $error');
                  return _avatarFallback(initials);
                },
              ),
      ),
    );
  }

  Widget _avatarFallback(String initials) {
    return Container(
      width: 128,
      height: 128,
      color: const Color(0xFF263442),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 42,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Future<void> _confirmCancelSubscription() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A2530),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Отменить Strazh Infinity?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Доступ останется активен до окончания оплаченного периода.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Оставить', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Отменить',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final cancelled = await SubscriptionService.cancelSubscription();
    if (!mounted) return;
    if (cancelled) {
      Toast.success(context, 'Strazh Infinity отменён');
      await _loadData();
    } else {
      Toast.error(context, 'Не удалось отменить подписку');
    }
  }

  Widget _buildPlansGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth > 700 ? 205.0 : 150.0;
        return SizedBox(
          height: 232,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _plans.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final plan = _plans[index];
              return SizedBox(
                width: cardWidth,
                child: _buildPlanCard(
                  plan,
                  plan.id == _selectedPlan,
                  cardWidth > 180,
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildPlanCard(
    SubscriptionPlan plan,
    bool isSelected,
    bool isDesktop,
  ) {
    final isPopular = plan.isPopular;
    final isCurrent = plan.id == _currentPlan && _isSubscribed;
    final hasEnoughBalance = _balance >= plan.priceEnc;
    final isPermanent = _isSubscribed && _expiresAt == null;

    return Stack(
      children: [
        Material(
          color: const Color(0xFF192630),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: _isPurchasing || isPermanent
                ? null
                : () {
                    setState(() => _selectedPlan = plan.id);
                    _buySubscription(plan);
                  },
            borderRadius: BorderRadius.circular(20),
            child: Ink(
              decoration: BoxDecoration(
                color: const Color(0xFF192630),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isCurrent
                      ? const Color(0xFF67D79A)
                      : isSelected || isPopular
                      ? const Color(0xFF43B5F5)
                      : Colors.white.withValues(alpha: 0.06),
                  width: isSelected || isCurrent || isPopular ? 1.5 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      plan.id == '1m'
                          ? '🎁'
                          : plan.id == '3m'
                          ? '🎀'
                          : plan.id == '1y'
                          ? '💎'
                          : '🏆',
                      style: TextStyle(fontSize: isDesktop ? 54 : 46),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      plan.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Strazh Infinity',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Color(0xFFB7C7D6), fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF203D53),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: isPermanent
                          ? const Text(
                              'ВКЛЮЧЕНО',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF8EE0B0),
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.bolt_rounded,
                                  size: 19,
                                  color: hasEnoughBalance
                                      ? const Color(0xFFFFC34D)
                                      : Colors.white38,
                                ),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    '${plan.priceEnc} ENC',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: hasEnoughBalance
                                          ? const Color(0xFF43B5F5)
                                          : Colors.white54,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 6),
                    if (isPermanent)
                      const Text(
                        'Уже активна навсегда',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF67D79A),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else if (isCurrent)
                      const Text(
                        'Активен',
                        style: TextStyle(
                          color: Color(0xFF67D79A),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else if (plan.discount > 0)
                      Text(
                        '−${plan.discount}%',
                        style: const TextStyle(
                          color: Color(0xFFFFC34D),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      Text(
                        '${plan.duration} дней',
                        style: const TextStyle(
                          color: Color(0xFFB7C7D6),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBenefitsSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF15121C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Что даёт Strazh Infinity?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _buildBenefitItem(
            icon: Icons.emoji_emotions,
            title: 'Эксклюзивные стикеры',
            subtitle: 'Доступ к эксклюзивной коллекции стикеров',
          ),
          const SizedBox(height: 8),
          _buildBenefitItem(
            icon: Icons.palette,
            title: 'Кастомные темы',
            subtitle: 'Создавайте свои цветовые схемы',
          ),
          const SizedBox(height: 8),
          _buildBenefitItem(
            icon: Icons.cloud_upload,
            title: 'Больше хранилища',
            subtitle: 'До 10 ГБ для медиафайлов',
          ),
          const SizedBox(height: 8),
          _buildBenefitItem(
            icon: Icons.verified,
            title: 'Значок Strazh Infinity',
            subtitle: 'Выделяйтесь среди других пользователей',
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitItem({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF6C3BD8).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF9B7AE8), size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SubscriptionPlan {
  final String id;
  final String title;
  final int duration;
  final int priceRub;
  final int priceEnc;
  final int discount;
  final bool isPopular;

  const SubscriptionPlan({
    required this.id,
    required this.title,
    required this.duration,
    required this.priceRub,
    required this.priceEnc,
    required this.discount,
    required this.isPopular,
  });
}
