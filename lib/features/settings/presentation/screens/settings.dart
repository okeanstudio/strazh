import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:strazh/features/auth/data/services/auth_service.dart';
import 'package:strazh/core/services/app_language_service.dart';
import 'package:strazh/features/gifts/data/services/gift_animation_cache.dart';
import 'package:strazh/features/gifts/data/services/gift_service.dart';
import 'package:strazh/features/settings/data/services/theme_service.dart';
import 'package:strazh/features/gifts/data/services/encoins_service.dart';
import 'package:strazh/features/settings/data/services/subscription_service.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';
import 'package:strazh/features/auth/presentation/screens/auth.dart';
import 'package:strazh/features/admin/presentation/screens/admin.dart';
import 'package:strazh/features/profile/presentation/screens/edit_profile.dart';
import 'package:strazh/features/settings/presentation/screens/accounts_screen.dart';
import 'package:strazh/core/utils/rpc_user.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/features/settings/presentation/screens/theme_settings.dart';
import 'package:strazh/features/settings/presentation/screens/encoins_manage.dart';
import 'package:strazh/features/settings/presentation/screens/subscription_screen.dart';
import 'package:strazh/features/settings/presentation/screens/privacy_settings_screen.dart';
import 'package:strazh/features/settings/presentation/screens/change_password_screen.dart';
import 'package:strazh/features/settings/presentation/screens/reaction_settings_screen.dart';
import 'package:strazh/features/settings/presentation/screens/sound_settings.dart';
import 'package:strazh/features/support/presentation/screens/support_tickets_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedLanguage = AppLanguageService().currentLanguage.nativeName;
  String _selectedAccent = 'Океанский синий';
  int _encoinsBalance = 0;
  bool _isSubscribed = false;
  String? _subscriptionPlan;
  bool _isLoading = false;
  bool _isAdmin = false;
  bool _isDeletingAccount = false;
  bool _isClearingGiftCache = false;
  String _appVersion = '...';

  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _selectedLanguage = AppLanguageService().currentLanguage.nativeName;
    _selectedAccent = ThemeService().currentTheme.value.name;
    _loadAppVersion();
    _loadUserData();
    _checkAdminRole();
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _appVersion = packageInfo.version);
    } catch (error) {
      debugPrint('Не удалось загрузить версию приложения: $error');
    }
  }

  Future<void> _clearGiftAnimationCache() async {
    if (_isClearingGiftCache) return;
    setState(() => _isClearingGiftCache = true);
    try {
      await GiftAnimationCache.clear();
      GiftService.clearAnimationUrlCache();
      if (mounted) {
        Toast.success(context, 'Кэш анимаций подарков очищен');
      }
    } catch (error) {
      debugPrint('Не удалось очистить кэш анимаций подарков: $error');
      if (mounted) {
        Toast.error(context, 'Не удалось очистить кэш анимаций подарков');
      }
    } finally {
      if (mounted) setState(() => _isClearingGiftCache = false);
    }
  }

  Future<void> _checkAdminRole() async {
    try {
      await Supabase.instance.client.auth.refreshSession();
    } catch (e) {
      debugPrint('⚠️ Не удалось обновить сессию перед проверкой роли: $e');
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    // Проверяем оба места: user_metadata и app_metadata
    var userRole = user.userMetadata?['role'] as String? ?? 'user';
    final appRole = user.appMetadata['role'] as String? ?? 'user';

    if (userRole == 'user' && appRole == 'user') {
      try {
        final response = await Supabase.instance.client.rpc(
          'get_user_by_id',
          params: {'p_id': user.id},
        );
        final freshUser = rpcUserRecord(response);
        userRole = freshUser?['role'] as String? ?? userRole;
      } catch (e) {
        debugPrint('⚠️ Не удалось получить свежую роль пользователя: $e');
      }
    }

    // Если в любом месте роль admin/owner/moderator - показываем админку
    final role = (userRole == 'owner' || appRole == 'owner')
        ? 'owner'
        : (userRole == 'admin' || appRole == 'admin')
        ? 'admin'
        : (userRole == 'moderator' || appRole == 'moderator')
        ? 'moderator'
        : 'user';

    final adminRoles = ['admin', 'owner', 'moderator'];
    if (!mounted) return;
    setState(() {
      _isAdmin = adminRoles.contains(role);
    });
  }

  Future<void> _loadUserData() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final balance = await EncoinsService.getBalance();
      final subscription = await SubscriptionService.getCurrentSubscription();

      if (!mounted) return;

      setState(() {
        _encoinsBalance = balance;
        _isLoading = false;

        if (subscription != null) {
          final expiresRaw = subscription['subscription_expires_at'];
          final plan = subscription['subscription_plan_id'] as String?;
          _subscriptionPlan = plan;

          if (expiresRaw == null) {
            _isSubscribed = false;
            return;
          }

          final expiresText = expiresRaw.toString();
          if (expiresText.toLowerCase() == 'forever') {
            _isSubscribed = true;
            return;
          }

          final date = DateTime.tryParse(expiresText);
          _isSubscribed = date != null && date.isAfter(DateTime.now());
        } else {
          _isSubscribed = false;
        }
      });
    } catch (e) {
      debugPrint('Ошибка загрузки данных настроек: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSubscribed = false;
        });
      }
    }
  }

  String _getSubscriptionStatus() {
    if (_isSubscribed) {
      final planNames = {
        '1m': '1 месяц',
        '3m': '3 месяца',
        '1y': '1 год',
        '2y': '2 года',
      };
      final plan = planNames[_subscriptionPlan] ?? 'активна';
      return '✅ ${plan.tr}';
    }
    return '❌ ${'Не активна'.tr}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      appBar: AppBar(
        title: Text(
          'Настройки'.tr,
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: const Color(0xFF0D0A0A),
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _loadUserData,
            icon: const Icon(Icons.refresh, color: Colors.white70, size: 22),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileCard(),
            const SizedBox(height: 20),

            _buildSectionHeader('АККАУНТЫ'),
            const SizedBox(height: 6),
            _buildSectionCard(
              children: [
                _buildMenuItem(
                  icon: Icons.switch_account_outlined,
                  title: 'Аккаунты',
                  subtitle: 'Добавить аккаунт или быстро переключиться',
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AccountsScreen()),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 18),

            // ===== АДМИН-ПАНЕЛЬ (только для админов) =====
            if (_isAdmin) ...[
              _buildSectionHeader('УПРАВЛЕНИЕ'),
              const SizedBox(height: 6),
              _buildSectionCard(
                children: [
                  _buildMenuItem(
                    icon: Icons.admin_panel_settings,
                    title: 'Админ-панель',
                    subtitle: 'Управление пользователями, роли, галочки',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AdminScreen(),
                        ),
                      );
                    },
                    isAdmin: true,
                  ),
                ],
              ),
              const SizedBox(height: 18),
            ],

            _buildSectionHeader('ОСНОВНЫЕ'),
            const SizedBox(height: 6),
            _buildSectionCard(
              children: [
                _buildMenuItem(
                  icon: Icons.notifications_outlined,
                  title: 'Уведомления',
                  subtitle: 'Звук, вибрация и режим уведомлений',
                  onTap: () => _openSubSettings('Уведомления'),
                ),
                _buildDivider(),
                _buildMenuItem(
                  icon: Icons.palette_outlined,
                  title: 'Темы и оформление',
                  subtitle: _selectedAccent,
                  onTap: () => _openSubSettings('Темы и оформление'),
                ),
                _buildDivider(),
                _buildMenuItem(
                  icon: Icons.language_outlined,
                  title: 'Язык',
                  subtitle: _selectedLanguage,
                  onTap: _showLanguagePicker,
                ),
                _buildDivider(),
                _buildMenuItem(
                  icon: Icons.add_reaction_outlined,
                  title: 'Реакции',
                  subtitle: 'Эмодзи для двойного нажатия',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ReactionSettingsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 18),

            _buildSectionHeader('ПРИВАТНОСТЬ'),
            const SizedBox(height: 6),
            _buildSectionCard(
              children: [
                _buildMenuItem(
                  icon: Icons.visibility_outlined,
                  title: 'Конфиденциальность',
                  subtitle: 'Онлайн-статус, прочтения, автоскачивание',
                  onTap: () => _openSubSettings('Конфиденциальность'),
                ),
                _buildDivider(),
                _buildMenuItem(
                  icon: Icons.password_outlined,
                  title: 'Сменить пароль',
                  subtitle: 'Подтвердите текущий пароль',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ChangePasswordScreen(),
                      ),
                    );
                  },
                ),
                _buildDivider(),
                _buildMenuItem(
                  icon: Icons.security_outlined,
                  title: 'Безопасность',
                  subtitle: 'Скрытие контента, блокировка',
                  onTap: () => _openSubSettings('Безопасность'),
                ),
              ],
            ),

            const SizedBox(height: 18),

            _buildSectionHeader('ДОПОЛНИТЕЛЬНО'),
            const SizedBox(height: 6),
            _buildSectionCard(
              children: [
                _buildMenuItem(
                  icon: Icons.bolt_rounded,
                  title: 'Strazh Infinity',
                  subtitle: _getSubscriptionStatus(),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SubscriptionScreen(),
                      ),
                    );
                    _loadUserData();
                  },
                ),
                _buildDivider(),
                _buildMenuItem(
                  icon: Icons.bolt_rounded,
                  title: 'Energy Coins',
                  subtitle: '${_encoinsBalance} ENC',
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const EncoinsManageScreen(),
                      ),
                    );
                    _loadUserData();
                  },
                ),
              ],
            ),

            const SizedBox(height: 18),

            _buildSectionHeader('КЭШ'),
            const SizedBox(height: 6),
            _buildSectionCard(
              children: [
                _buildMenuItem(
                  icon: Icons.cleaning_services_outlined,
                  title: 'Очистить кэш анимаций подарков',
                  subtitle: _isClearingGiftCache
                      ? 'Очистка...'
                      : 'Загруженные анимации можно будет скачать заново',
                  onTap: _clearGiftAnimationCache,
                ),
              ],
            ),

            const SizedBox(height: 18),

            _buildSectionHeader('ПОДДЕРЖКА'),
            const SizedBox(height: 6),
            _buildSectionCard(
              children: [
                _buildMenuItem(
                  icon: Icons.help_outline,
                  title: 'Помощь',
                  subtitle: 'Связаться с поддержкой',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SupportTicketsScreen(),
                      ),
                    );
                  },
                ),
                _buildDivider(),
                _buildMenuItem(
                  icon: Icons.description_outlined,
                  title: 'О приложении',
                  subtitle: '${'Версия'.tr} $_appVersion',
                  onTap: () => _showAboutDialog(),
                ),
                _buildDivider(),
                _buildMenuItem(
                  icon: Icons.logout,
                  title: 'Выйти',
                  subtitle: 'Выйти из аккаунта',
                  onTap: () => _showLogoutDialog(),
                  isDestructive: true,
                ),
                _buildDivider(),
                _buildMenuItem(
                  icon: Icons.delete_forever_outlined,
                  title: 'Удалить аккаунт',
                  subtitle: 'Безвозвратно удалить аккаунт и данные',
                  onTap: () {
                    if (!_isDeletingAccount) _showDeleteAccountDialog();
                  },
                  isDestructive: true,
                ),
              ],
            ),

            const SizedBox(height: 24),
            Center(
              child: Text(
                'Denote Studio • 2026',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openAccountEditor,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [const Color(0xFF1A1428), const Color(0xFF0D0A0A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_outline,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Аккаунт'.tr,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Редактировать профиль и данные аккаунта'.tr,
                      style: TextStyle(color: Colors.grey[500], fontSize: 13),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[600], size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openAccountEditor() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) Toast.error(context, 'Не удалось открыть аккаунт'.tr);
      return;
    }

    final metadata = user.userMetadata ?? const <String, dynamic>{};
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(
          initialName:
              metadata['name']?.toString() ?? metadata['tag']?.toString() ?? '',
          initialTag: metadata['tag']?.toString() ?? '',
          initialPhone: metadata['phone']?.toString() ?? '',
          initialEmail: user.email ?? '',
          initialBio: metadata['bio']?.toString() ?? '',
          initialBirthDate: metadata['birth_date']?.toString(),
        ),
      ),
    );
  }

  Future<void> _showLanguagePicker() async {
    final service = AppLanguageService();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          decoration: const BoxDecoration(
            color: Color(0xFF17131F),
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Язык приложения'.tr,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Выберите язык интерфейса'.tr,
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
              const SizedBox(height: 18),
              ...AppLanguageService.languages.map((language) {
                final selected = service.currentLanguage.code == language.code;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: selected
                        ? const Color(0xFF302543)
                        : const Color(0xFF201C28),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        try {
                          await service.setLanguage(language.code);
                          if (!mounted) return;
                          setState(
                            () => _selectedLanguage = language.nativeName,
                          );
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        } catch (error) {
                          debugPrint('Не удалось изменить язык: $error');
                          if (mounted) {
                            Toast.error(
                              context,
                              'Не удалось сохранить язык'.tr,
                            );
                          }
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Text(
                                language.flag,
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    language.nativeName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    language.name,
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (selected)
                              const Icon(
                                Icons.check_circle,
                                color: Color(0xFF9B7AE8),
                                size: 22,
                              )
                            else
                              Icon(
                                Icons.radio_button_unchecked,
                                color: Colors.grey[600],
                                size: 22,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'Перевод постепенно появляется в разных разделах приложения.'
                      .tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        title.tr,
        style: TextStyle(
          color: Colors.grey[500],
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSectionCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF15121C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
    bool isAdmin = false,
  }) {
    final textColor = isDestructive ? Colors.redAccent : Colors.white;
    final iconColor = isDestructive
        ? Colors.redAccent
        : (isAdmin ? Colors.amber : Colors.grey[400]!);
    final bgColor = isAdmin
        ? Colors.amber.withOpacity(0.15)
        : Colors.white.withOpacity(0.06);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDestructive ? Colors.red.withOpacity(0.12) : bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.tr,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle.tr,
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isAdmin)
              const Icon(Icons.shield, color: Colors.amber, size: 16),
            Icon(Icons.chevron_right, color: Colors.grey[600], size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      color: Colors.white.withOpacity(0.05),
      height: 1,
      indent: 60,
    );
  }

  void _openSubSettings(String title) async {
    if (_isNavigating) return;
    _isNavigating = true;

    if (title == 'Уведомления') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SoundSettingsScreen()),
      );
      _isNavigating = false;
      return;
    }

    if (title == 'Темы и оформление') {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ThemeSettingsScreen()),
      );
      if (result == true) {
        setState(() {
          _selectedAccent = ThemeService().currentTheme.value.name;
        });
      }
      _isNavigating = false;
      return;
    }

    if (title == 'Конфиденциальность') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const PrivacySettingsScreen()),
      );
      _isNavigating = false;
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _SubSettingsScreen(
          title: title,
          onSave: (values) {
            Toast.success(context, 'Настройки сохранены'.tr);
          },
        ),
      ),
    );

    _isNavigating = false;
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1428),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'О приложении'.tr,
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Strazh Messenger',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              '${'Версия'.tr} $_appVersion',
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              'Защищённый мессенджер с end-to-end шифрованием'.tr,
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Закрыть'.tr, style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1428),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Выйти из аккаунта?'.tr,
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: Text(
          'Вы будете перенаправлены на экран входа'.tr,
          style: TextStyle(color: Colors.grey, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена'.tr, style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await AuthService().logout();
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const AuthScreen()),
                );
              }
            },
            style: TextButton.styleFrom(
              backgroundColor: Colors.red.withOpacity(0.12),
            ),
            child: Text(
              'Выйти'.tr,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteAccountDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1428),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Удалить аккаунт?',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: const Text(
          'Аккаунт будет удалён без возможности восстановления. Связанные с ним данные в приложении также могут быть удалены.',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Отмена',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.redAccent,
              backgroundColor: Colors.red.withValues(alpha: 0.12),
            ),
            child: const Text('Удалить навсегда'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeletingAccount = true);
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) {
        throw StateError('Для удаления аккаунта необходимо войти');
      }
      await client.rpc('delete_my_account');
      await AuthService().logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (_) => false,
      );
    } catch (error) {
      debugPrint('Не удалось удалить аккаунт: $error');
      if (mounted) {
        setState(() => _isDeletingAccount = false);
        Toast.error(context, 'Не удалось удалить аккаунт. Попробуйте позже.');
      }
    }
  }
}

// ===== ВНУТРЕННИЙ ЭКРАН НАСТРОЕК =====

class _SubSettingsScreen extends StatefulWidget {
  final String title;
  final Function(Map<String, dynamic>) onSave;

  const _SubSettingsScreen({required this.title, required this.onSave});

  @override
  State<_SubSettingsScreen> createState() => _SubSettingsScreenState();
}

class _SubSettingsScreenState extends State<_SubSettingsScreen> {
  bool _notificationsEnabled = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;

  bool _showOnlineStatus = true;
  bool _readReceipts = false;
  bool _autoDownload = true;
  bool _blurSensitiveContent = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title.tr,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: const Color(0xFF0D0A0A),
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () {
              widget.onSave(_collectValues());
              Navigator.pop(context);
            },
            child: Text(
              'Сохранить'.tr,
              style: TextStyle(
                color: Color(0xFF7C6F9E),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    switch (widget.title) {
      case 'Уведомления':
        return _buildNotificationsSection();
      case 'Конфиденциальность':
        return _buildPrivacySection();
      case 'Безопасность':
        return _buildSecuritySection();
      default:
        return Center(
          child: Text(
            'Настройки в разработке'.tr,
            style: TextStyle(color: Colors.grey),
          ),
        );
    }
  }

  Widget _buildNotificationsSection() {
    return Column(
      children: [
        _buildSwitchTile(
          icon: Icons.notifications_outlined,
          title: 'Уведомления'.tr,
          subtitle: 'Входящие сообщения и события'.tr,
          value: _notificationsEnabled,
          onChanged: (v) => setState(() => _notificationsEnabled = v),
        ),
        _buildDivider(),
        _buildSwitchTile(
          icon: Icons.volume_up_outlined,
          title: 'Звук'.tr,
          subtitle: 'Воспроизводить звук при сообщениях'.tr,
          value: _soundEnabled,
          onChanged: (v) => setState(() => _soundEnabled = v),
        ),
        _buildDivider(),
        _buildSwitchTile(
          icon: Icons.vibration_outlined,
          title: 'Вибрация'.tr,
          subtitle: 'Тактильный отклик на действия'.tr,
          value: _vibrationEnabled,
          onChanged: (v) => setState(() => _vibrationEnabled = v),
        ),
      ],
    );
  }

  Widget _buildPrivacySection() {
    return Column(
      children: [
        _buildSwitchTile(
          icon: Icons.visibility_outlined,
          title: 'Показывать онлайн-статус'.tr,
          subtitle: 'Другие видят, когда вы в сети'.tr,
          value: _showOnlineStatus,
          onChanged: (v) => setState(() => _showOnlineStatus = v),
        ),
        _buildDivider(),
        _buildSwitchTile(
          icon: Icons.mark_chat_read_outlined,
          title: 'Отчёты о прочтении'.tr,
          subtitle: 'Показывать, что вы прочитали сообщение'.tr,
          value: _readReceipts,
          onChanged: (v) => setState(() => _readReceipts = v),
        ),
        _buildDivider(),
        _buildSwitchTile(
          icon: Icons.download_outlined,
          title: 'Автозагрузка медиа'.tr,
          subtitle: 'Автоматически скачивать фото и видео'.tr,
          value: _autoDownload,
          onChanged: (v) => setState(() => _autoDownload = v),
        ),
      ],
    );
  }

  Widget _buildSecuritySection() {
    return Column(
      children: [
        _buildSwitchTile(
          icon: Icons.blur_on_outlined,
          title: 'Скрывать чувствительный контент'.tr,
          subtitle: 'Размывать предпросмотр в уведомлениях'.tr,
          value: _blurSensitiveContent,
          onChanged: (v) => setState(() => _blurSensitiveContent = v),
        ),
        _buildDivider(),
        _buildMenuItem(
          icon: Icons.lock_outlined,
          title: 'Блокировка приложения'.tr,
          subtitle: 'Включить PIN-код или биометрию'.tr,
          onTap: () => Toast.info(context, 'В разработке'.tr),
        ),
        _buildDivider(),
        _buildMenuItem(
          icon: Icons.devices_outlined,
          title: 'Активные сессии'.tr,
          subtitle: 'Управление устройствами'.tr,
          onTap: () => Toast.info(context, 'В разработке'.tr),
        ),
      ],
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.grey[400], size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.tr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  subtitle.tr,
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF6C5B8F),
            activeTrackColor: const Color(0xFF6C5B8F).withOpacity(0.35),
            inactiveThumbColor: Colors.grey[400],
            inactiveTrackColor: Colors.grey.withOpacity(0.2),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.grey[400], size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.tr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle.tr,
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[600], size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      color: Colors.white.withOpacity(0.05),
      height: 1,
      indent: 48,
    );
  }

  Map<String, dynamic> _collectValues() {
    return {
      'notifications': _notificationsEnabled,
      'sound': _soundEnabled,
      'vibration': _vibrationEnabled,
      'showOnline': _showOnlineStatus,
      'readReceipts': _readReceipts,
      'autoDownload': _autoDownload,
      'blurContent': _blurSensitiveContent,
    };
  }
}
