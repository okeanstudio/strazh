import 'package:flutter/material.dart';
import 'package:strazh/features/admin/presentation/screens/admin_users.dart';
import 'package:strazh/features/admin/presentation/screens/admin_roles.dart';
import 'package:strazh/features/admin/presentation/screens/admin_verified.dart';
import 'package:strazh/features/admin/presentation/screens/admin_channel_verified.dart';
import 'package:strazh/features/admin/presentation/screens/admin_premium.dart';
import 'package:strazh/features/admin/presentation/screens/admin_bans.dart';
import 'package:strazh/features/admin/presentation/screens/admin_badges.dart';
import 'package:strazh/features/admin/presentation/screens/admin_support_tickets.dart';
import 'package:strazh/features/admin/presentation/screens/admin_moderation_reports.dart';
import 'package:strazh/features/admin/presentation/screens/admin_tree_of_users.dart';
import 'package:strazh/features/admin/presentation/screens/admin_encoins.dart';
import 'package:strazh/features/admin/presentation/screens/admin_gifts.dart';
import 'package:strazh/features/admin/presentation/screens/admin_bots.dart';
import 'package:strazh/features/auth/data/services/invite_registration_settings_service.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  bool _isInviteCodeRequired = true;
  bool _isLoadingInviteSetting = true;
  bool _isUpdatingInviteSetting = false;

  @override
  void initState() {
    super.initState();
    _loadInviteSetting();
  }

  Future<void> _loadInviteSetting() async {
    try {
      final required = await InviteRegistrationSettingsService.instance
          .isInviteCodeRequired();
      if (!mounted) return;
      setState(() {
        _isInviteCodeRequired = required;
        _isLoadingInviteSetting = false;
      });
    } catch (error) {
      debugPrint('Не удалось загрузить настройку инвайт-кода: $error');
      if (!mounted) return;
      setState(() => _isLoadingInviteSetting = false);
      Toast.error(context, 'Не удалось загрузить настройку регистрации');
    }
  }

  Future<void> _setInviteCodeRequired(bool required) async {
    if (_isUpdatingInviteSetting) return;
    setState(() {
      _isInviteCodeRequired = required;
      _isUpdatingInviteSetting = true;
    });
    try {
      await InviteRegistrationSettingsService.instance
          .setInviteCodeRequired(required);
    } catch (error) {
      debugPrint('Не удалось изменить настройку инвайт-кода: $error');
      if (!mounted) return;
      setState(() => _isInviteCodeRequired = !required);
      Toast.error(context, 'Не удалось изменить настройку регистрации');
    } finally {
      if (mounted) setState(() => _isUpdatingInviteSetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Админ панель',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield, color: Colors.amber, size: 16),
                SizedBox(width: 4),
                Text(
                  'Owner',
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1428), Color(0xFF0D0A0A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings,
                      color: Colors.amber,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Управление сервером',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Управляйте пользователями, ролями и настройками',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 1.0,
                children: [
                  _buildInviteCodeToggle(),
                  _buildMenuItem(
                    context,
                    icon: Icons.people_alt,
                    title: 'Пользователи',
                    subtitle: 'Список и управление',
                    color: const Color(0xFF4A9EFF),
                    gradient: const [Color(0xFF4A9EFF), Color(0xFF2563EB)],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminUsersScreen(),
                      ),
                    ),
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.people_alt,
                    title: 'Древо',
                    subtitle: 'Древо кто от кого пришел',
                    color: const Color(0xFF4A9EFF),
                    gradient: const [Color(0xFF4A9EFF), Color(0xFF2563EB)],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminTreeOfUsersScreen(),
                      ),
                    ),
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.flash_on,
                    title: 'Encoins',
                    subtitle: 'Выдача валюты пользователям',
                    color: const Color(0xFFB69AFF),
                    gradient: const [Color(0xFF9B7AE8), Color(0xFF6C3BD8)],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminEncoinsScreen(),
                      ),
                    ),
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.card_giftcard,
                    title: 'Подарки',
                    subtitle: 'Выдача подарков пользователям',
                    color: const Color(0xFFFFC86B),
                    gradient: const [Color(0xFFFFC86B), Color(0xFFF08A4B)],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminGiftsScreen(),
                      ),
                    ),
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.verified,
                    title: 'Галочки',
                    subtitle: 'Верификация',
                    color: const Color(0xFF34D399),
                    gradient: const [Color(0xFF34D399), Color(0xFF059669)],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminVerifiedScreen(),
                      ),
                    ),
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.smart_toy,
                    title: 'Боты',
                    subtitle: 'Управление ботами и галочками',
                    color: const Color(0xFF60A5FA),
                    gradient: const [Color(0xFF60A5FA), Color(0xFF2563EB)],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminBotsScreen(),
                      ),
                    ),
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.campaign_outlined,
                    title: 'Галочки каналов',
                    subtitle: 'Верификация каналов',
                    color: const Color(0xFF4A9EFF),
                    gradient: const [Color(0xFF4A9EFF), Color(0xFF2563EB)],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminChannelVerifiedScreen(),
                      ),
                    ),
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.star,
                    title: 'Infinity',
                    subtitle: 'Подписки',
                    color: const Color(0xFFFBBF24),
                    gradient: const [Color(0xFFFBBF24), Color(0xFFD97706)],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminPremiumScreen(),
                      ),
                    ),
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.emoji_events,
                    title: 'Бейджи',
                    subtitle: 'Выдача значков',
                    color: const Color(0xFFFF8A65),
                    gradient: const [Color(0xFFFF8A65), Color(0xFFE64A19)],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminBadgesScreen(),
                      ),
                    ),
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.admin_panel_settings,
                    title: 'Роли',
                    subtitle: 'Назначение',
                    color: const Color(0xFFA78BFA),
                    gradient: const [Color(0xFFA78BFA), Color(0xFF7C3AED)],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminRolesScreen(),
                      ),
                    ),
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.block,
                    title: 'Баны',
                    subtitle: 'Блокировка',
                    color: const Color(0xFFF87171),
                    gradient: const [Color(0xFFF87171), Color(0xFFDC2626)],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminBansScreen(),
                      ),
                    ),
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.support_agent,
                    title: 'Тикеты',
                    subtitle: 'Обращения пользователей',
                    color: const Color(0xFF58C7B4),
                    gradient: const [Color(0xFF58C7B4), Color(0xFF238B81)],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminSupportTicketsScreen(),
                      ),
                    ),
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.flag_outlined,
                    title: 'Жалобы',
                    subtitle: 'Очередь модерации',
                    color: const Color(0xFFFF9F43),
                    gradient: const [Color(0xFFFF9F43), Color(0xFFE86A17)],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminModerationReportsScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteCodeToggle() {
    final enabled = _isInviteCodeRequired;
    final color = enabled ? const Color(0xFF34D399) : Colors.orangeAccent;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF171329), Color(0xFF100D18)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.card_giftcard, color: color, size: 26),
          ),
          const SizedBox(height: 8),
          const Text(
            'Регистрация по инвайту',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _isLoadingInviteSetting
                ? 'Загрузка настройки...'
                : enabled
                ? 'Код приглашения обязателен'
                : 'Регистрация без инвайта',
            maxLines: 2,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500], fontSize: 11),
          ),
          const SizedBox(height: 4),
          Switch(
            value: enabled,
            onChanged: _isLoadingInviteSetting || _isUpdatingInviteSetting
                ? null
                : _setInviteCodeRequired,
            activeThumbColor: const Color(0xFF34D399),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required List<Color> gradient,
    required VoidCallback onTap,
    int? count,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0.03),
              Colors.white.withValues(alpha: 0.01),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[500], fontSize: 11),
              ),
              if (count != null)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
