import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';
import 'package:strazh/shared/presentation/widgets/username_mention_text.dart';

class ManageUsernamesScreen extends StatefulWidget {
  const ManageUsernamesScreen({super.key});

  @override
  State<ManageUsernamesScreen> createState() => _ManageUsernamesScreenState();
}

class _ManageUsernamesScreenState extends State<ManageUsernamesScreen> {
  final _usernameController = TextEditingController();
  List<String> _usernames = [];
  String _primaryUsername = '';
  int _balance = 0;
  bool _isLoading = true;
  bool _isPurchasing = false;

  static const _background = Color(0xFF0D0A0A);
  static const _surface = Color(0xFF1A1A1A);
  static const _border = Color(0xFF333333);
  static const _accent = Color(0xFF1A73E8);

  @override
  void initState() {
    super.initState();
    _loadUsernames();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _loadUsernames() async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) throw StateError('Пользователь не найден');

      try {
        await client.auth.refreshSession();
      } catch (error) {
        debugPrint('Не удалось обновить баланс ENC: $error');
      }

      final rows = await client
          .from('user_additional_usernames')
          .select('username')
          .eq('user_id', user.id)
          .order('created_at');
      final metadata = client.auth.currentUser?.userMetadata ?? {};
      final balance = metadata['encoins'];

      if (!mounted) return;
      setState(() {
        _primaryUsername = metadata['tag']?.toString() ?? '';
        _usernames = rows.map((row) => row['username'] as String).toList();
        _balance = balance is num ? balance.toInt() : 0;
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('Ошибка загрузки юзернеймов: $error');
      if (!mounted) return;
      setState(() => _isLoading = false);
      Toast.error(context, 'Не удалось загрузить юзернеймы');
    }
  }

  Future<void> _purchaseUsername() async {
    final username = _usernameController.text.trim().toLowerCase();
    if (!RegExp(r'^[a-zA-Z0-9_]{3,}$').hasMatch(username)) {
      Toast.error(context, 'Минимум 3 символа: буквы, цифры или _');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Подтвердить покупку?',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '@$username',
              style: const TextStyle(
                color: Color(0xFF91B9FF),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'С вашего баланса будет списано 1 000 ENC.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              'Баланс после покупки: '
              '${_balance >= 1000 ? _balance - 1000 : 0} ENC',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Купить за 1 000 ENC'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isPurchasing = true);
    try {
      final result = await Supabase.instance.client.rpc(
        'purchase_additional_username',
        params: {'p_username': username},
      );
      if (result is! Map ||
          result['username'] is! String ||
          result['balance'] is! num) {
        throw const FormatException('Некорректный ответ при покупке юзернейма');
      }

      if (!mounted) return;
      setState(() {
        _usernames = [..._usernames, result['username'] as String];
        _balance = (result['balance'] as num).toInt();
        _usernameController.clear();
      });
      Toast.success(context, 'Юзернейм @${result['username']} куплен');
    } catch (error) {
      debugPrint('Ошибка покупки юзернейма: $error');
      if (!mounted) return;
      final message = error.toString().contains('already taken')
          ? 'Этот юзернейм уже занят'
          : error.toString().contains('Insufficient Encoins')
          ? 'Недостаточно ENC: нужно 1 000'
          : 'Не удалось купить юзернейм: $error';
      Toast.error(context, message);
    } finally {
      if (mounted) setState(() => _isPurchasing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        title: const Text(
          'Мои юзернеймы',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  _buildIntroCard(),
                  const SizedBox(height: 20),
                  _buildPurchaseCard(),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Ваши юзернеймы',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '${_usernames.length + (_primaryUsername.isEmpty ? 0 : 1)}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_primaryUsername.isNotEmpty)
                    _usernameTile(_primaryUsername, isPrimary: true),
                  for (final username in _usernames) _usernameTile(username),
                  if (_usernames.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _border),
                      ),
                      child: const Text(
                        'Пока у вас только основной юзернейм. '
                        'Добавьте ещё один, чтобы вас было проще найти.',
                        style: TextStyle(color: Colors.white60, height: 1.45),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildIntroCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF202C43), Color(0xFF17151F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.alternate_email, color: Color(0xFF91B9FF), size: 25),
          const SizedBox(height: 14),
          const Text(
            'Больше способов найти вас',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Дополнительные юзернеймы ведут к тому же аккаунту. '
            'По ним можно найти вас и начать чат.',
            style: TextStyle(color: Colors.white60, height: 1.45),
          ),
          const SizedBox(height: 14),
          Text(
            'Баланс  $_balance ENC',
            style: const TextStyle(
              color: Color(0xFF91B9FF),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchaseCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Добавить юзернейм',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Стоимость — 1 000 ENC за один юзернейм',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _usernameController,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              prefixText: '@ ',
              prefixStyle: const TextStyle(
                color: Colors.white54,
                fontWeight: FontWeight.w600,
              ),
              hintText: 'новый_юзернейм',
              hintStyle: const TextStyle(color: Colors.white30),
              filled: true,
              fillColor: const Color(0xFF101116),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 15,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: const BorderSide(color: _border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: const BorderSide(color: _border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: const BorderSide(color: _accent),
              ),
            ),
            onSubmitted: (_) => _purchaseUsername(),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: _isPurchasing ? null : _purchaseUsername,
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              icon: _isPurchasing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add),
              label: Text(
                _isPurchasing ? 'Покупаем...' : 'Добавить за 1 000 ENC',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _usernameTile(String username, {bool isPrimary = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Icon(
            isPrimary ? Icons.verified_user_outlined : Icons.alternate_email,
            size: 18,
            color: isPrimary ? const Color(0xFF91B9FF) : Colors.white54,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: UsernameMentionText(
              text: '@$username',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              linkColor: Colors.white,
              onUsernameTap: null,
            ),
          ),
          if (isPrimary)
            const Text(
              'основной',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
        ],
      ),
    );
  }
}
