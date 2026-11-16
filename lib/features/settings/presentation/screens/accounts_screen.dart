import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/features/auth/presentation/screens/auth.dart';
import 'package:strazh/features/home/presentation/screens/home.dart';
import 'package:strazh/features/auth/data/services/account_session_service.dart';
import 'package:strazh/features/auth/data/services/auth_service.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  final _accountService = AccountSessionService();
  List<AccountSessionInfo> _accounts = [];
  bool _isLoading = true;
  String? _error;
  String? _switchingUserId;

  String? get _currentUserId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    try {
      final accounts = await _accountService.getAccounts();
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _isLoading = false;
        _error = null;
      });
    } catch (error) {
      debugPrint('Не удалось загрузить аккаунты: $error');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Не удалось загрузить сохранённые аккаунты';
      });
    }
  }

  Future<void> _switchAccount(AccountSessionInfo account) async {
    if (account.userId == _currentUserId || _switchingUserId != null) return;
    setState(() => _switchingUserId = account.userId);

    try {
      await _accountService.switchTo(account.userId);
      await AuthService().saveUser(account.tag, account.userId);
      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } catch (error) {
      debugPrint('Не удалось переключить аккаунт: $error');
      if (!mounted) return;
      setState(() => _switchingUserId = null);
      Toast.error(context, 'Не удалось переключить аккаунт'.tr());
    }
  }

  Future<void> _addAccount() async {
    try {
      await _accountService.saveCurrentSession();
    } catch (error) {
      debugPrint('Не удалось сохранить текущий аккаунт: $error');
      if (!mounted) return;
      Toast.error(context, 'Не удалось сохранить текущий аккаунт'.tr());
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  Future<void> _removeAccount(AccountSessionInfo account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить аккаунт с устройства?'.tr()),
        content: Text(
          'Сохранённая сессия будет удалена. Сам аккаунт и переписка не удалятся.'
              .tr(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Удалить'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _accountService.removeAccount(account.userId);
      if (mounted) {
        setState(() {
          _accounts.removeWhere((item) => item.userId == account.userId);
        });
      }
    } catch (error) {
      debugPrint('Не удалось удалить сохранённый аккаунт: $error');
      if (mounted) Toast.error(context, 'Не удалось удалить аккаунт'.tr());
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _currentUserId;
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(title: Text('Аккаунты'.tr())),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!.tr(), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        setState(() => _isLoading = true);
                        _loadAccounts();
                      },
                      child: Text('Повторить'.tr()),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(
                  'Переключайтесь между аккаунтами без повторного ввода пароля.'
                      .tr(),
                  style: TextStyle(color: Colors.grey[400], height: 1.4),
                ),
                const SizedBox(height: 16),
                ..._accounts.map((account) {
                  final isCurrent = account.userId == currentUserId;
                  final isSwitching = account.userId == _switchingUserId;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      onTap: isCurrent || _switchingUserId != null
                          ? null
                          : () => _switchAccount(account),
                      leading: CircleAvatar(
                        backgroundColor: accent.withValues(alpha: 0.18),
                        backgroundImage: account.avatarUrl == null
                            ? null
                            : NetworkImage(account.avatarUrl!),
                        child: account.avatarUrl == null
                            ? Text(
                                account.name.isNotEmpty
                                    ? account.name.characters.first
                                          .toUpperCase()
                                    : '?',
                                style: TextStyle(color: accent),
                              )
                            : null,
                      ),
                      title: Text(
                        account.name.isNotEmpty ? account.name : account.tag,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        account.tag.isNotEmpty
                            ? '@${account.tag}'
                            : account.email ?? account.userId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: isCurrent
                          ? Icon(Icons.check_circle, color: accent)
                          : isSwitching
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              tooltip: 'Удалить с устройства'.tr(),
                              onPressed: () => _removeAccount(account),
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _switchingUserId == null ? _addAccount : null,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: Text('Добавить аккаунт'.tr()),
                ),
                const SizedBox(height: 8),
                Text(
                  'Войдите через Okean ID или используйте существующий аккаунт. '
                          'Новый аккаунт можно создать на экране регистрации.'
                      .tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            ),
    );
  }
}
