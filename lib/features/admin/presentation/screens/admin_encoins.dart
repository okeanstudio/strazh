import 'package:flutter/material.dart';
import 'package:strazh/features/admin/presentation/screens/encoins_grant_dialog.dart';
import 'package:strazh/features/gifts/data/services/encoins_service.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

class AdminEncoinsScreen extends StatefulWidget {
  const AdminEncoinsScreen({super.key});

  @override
  State<AdminEncoinsScreen> createState() => _AdminEncoinsScreenState();
}

class _AdminEncoinsScreenState extends State<AdminEncoinsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoading = true;
  bool _isGrantDialogOpen = false;
  String _query = '';
  String? _grantingUserId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final data = await Future.wait([
        EncoinsService.getAdminBalances(),
        EncoinsService.getAdminTransactions(),
      ]);
      if (!mounted) return;
      setState(() {
        _users = data[0];
        _transactions = data[1];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      Toast.error(context, 'Не удалось загрузить данные Encoins: $e');
    }
  }

  List<Map<String, dynamic>> get _filteredUsers {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _users;
    return _users.where((user) {
      return [user['name'], user['tag'], user['email'], user['id']].any(
        (value) => value?.toString().toLowerCase().contains(query) ?? false,
      );
    }).toList();
  }

  Future<void> _showAdjustmentDialog(
    Map<String, dynamic> user, {
    required bool isWithdrawal,
  }) async {
    if (_isGrantDialogOpen || _grantingUserId != null) return;
    setState(() => _isGrantDialogOpen = true);

    final rawBalance = user['encoins'];
    final currentBalance = rawBalance is num
        ? rawBalance.toInt()
        : int.tryParse(rawBalance?.toString() ?? '') ?? 0;
    final grant = await showDialog<EncoinsGrant>(
      context: context,
      builder: (_) => EncoinsGrantDialog(
        userName: user['name']?.toString() ?? 'Без имени',
        isWithdrawal: isWithdrawal,
        currentBalance: currentBalance,
      ),
    );

    if (mounted) setState(() => _isGrantDialogOpen = false);
    if (grant == null || !mounted) return;

    final userId = user['id']?.toString();
    if (userId == null || userId.isEmpty) {
      Toast.error(context, 'У пользователя отсутствует идентификатор');
      return;
    }

    setState(() => _grantingUserId = userId);
    try {
      final balance = isWithdrawal
          ? await EncoinsService.withdrawEncoins(
              userId: userId,
              amount: grant.amount,
              description: grant.description,
            )
          : await EncoinsService.grantEncoins(
              userId: userId,
              amount: grant.amount,
              description: grant.description,
            );
      if (!mounted) return;
      setState(() {
        final index = _users.indexWhere(
          (item) => item['id']?.toString() == userId,
        );
        if (index != -1) _users[index]['encoins'] = balance;
        _grantingUserId = null;
      });
      await _loadData();
      if (mounted) {
        Toast.success(
          context,
          isWithdrawal
              ? 'Списано ${grant.amount} ENC'
              : 'Выдано ${grant.amount} ENC',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _grantingUserId = null);
      Toast.error(
        context,
        '${isWithdrawal ? 'Не удалось списать' : 'Не удалось выдать'} Encoins: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0A0A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0D0A0A),
          title: const Text(
            'Encoins',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              onPressed: _loadData,
              tooltip: 'Обновить',
              icon: const Icon(Icons.refresh, color: Colors.white70),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Color(0xFF9B7AE8),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: [
              Tab(text: 'Баланс пользователей'),
              Tab(text: 'Все операции'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF9B7AE8)),
              )
            : TabBarView(children: [_buildUsersTab(), _buildTransactionsTab()]),
      ),
    );
  }

  Widget _buildUsersTab() {
    final users = _filteredUsers;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Поиск по имени, тегу или email',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              filled: true,
              fillColor: const Color(0xFF191522),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: users.isEmpty
              ? const Center(
                  child: Text(
                    'Пользователи не найдены',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: users.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _buildUserTile(users[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildUserTile(Map<String, dynamic> user) {
    final userId = user['id']?.toString();
    final name = user['name']?.toString() ?? 'Без имени';
    final tag = user['tag']?.toString() ?? '';
    final email = user['email']?.toString() ?? '';
    final avatarUrl = user['avatar_url']?.toString();
    final rawBalance = user['encoins'];
    final balance = rawBalance is num
        ? rawBalance.toInt()
        : int.tryParse(rawBalance?.toString() ?? '') ?? 0;
    final isGranting = userId == _grantingUserId;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF191522),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF332852),
          backgroundImage: avatarUrl == null || avatarUrl.isEmpty
              ? null
              : NetworkImage(avatarUrl),
          child: avatarUrl == null || avatarUrl.isEmpty
              ? Text(
                  name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : null,
        ),
        title: Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          '${tag.isEmpty ? '' : '@$tag  •  '}$balance ENC'
          '${email.isEmpty ? '' : '\n$email'}',
          style: const TextStyle(color: Colors.white54),
        ),
        isThreeLine: email.isNotEmpty,
        trailing: isGranting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF9B7AE8),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Списать Encoins',
                    onPressed: userId == null || balance <= 0
                        ? null
                        : () => _showAdjustmentDialog(
                              user,
                              isWithdrawal: true,
                            ),
                    icon: const Icon(
                      Icons.remove_circle_outline,
                      color: Color(0xFFFF7D8D),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Выдать Encoins',
                    onPressed: userId == null
                        ? null
                        : () => _showAdjustmentDialog(
                              user,
                              isWithdrawal: false,
                            ),
                    icon: const Icon(
                      Icons.add_circle_outline,
                      color: Color(0xFFB69AFF),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildTransactionsTab() {
    if (_transactions.isEmpty) {
      return const Center(
        child: Text(
          'Операций пока нет',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _transactions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) =>
          _buildTransactionTile(_transactions[index]),
    );
  }

  Widget _buildTransactionTile(Map<String, dynamic> transaction) {
    final amount = (transaction['amount'] as num?)?.toInt() ?? 0;
    final isGrant = amount > 0;
    final recipient = transaction['user_name']?.toString() ?? 'Неизвестный';
    final recipientTag = transaction['user_tag']?.toString() ?? '';
    final actor = transaction['actor_name']?.toString() ?? 'Не записан';
    final actorTag = transaction['actor_tag']?.toString() ?? '';
    final type = transaction['type']?.toString() ?? '';
    final description = transaction['description']?.toString() ?? '';
    final isAdminGrant =
        isGrant && (type == 'bonus' || description.startsWith('Выдача от '));
    final isAdminWithdrawal = type == 'admin_withdraw';
    final color = isGrant ? const Color(0xFF7DE2A5) : const Color(0xFFFF7D8D);
    final recipientSuffix = recipientTag.isNotEmpty ? ' (@$recipientTag)' : '';
    final actorSuffix = actorTag.isNotEmpty ? ' (@$actorTag)' : '';
    final action = isAdminGrant || isAdminWithdrawal
        ? '${isAdminGrant ? 'Выдал' : 'Списал'} $actor$actorSuffix → '
            '$recipient$recipientSuffix'
        : isGrant
        ? 'Зачислено пользователю $recipient$recipientSuffix'
        : 'Списание у $recipient$recipientSuffix';
    final createdAt = _formatDate(transaction['created_at']?.toString());
    final before = transaction['balance_before'];
    final after = transaction['balance_after'];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF191522),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(
              isGrant ? Icons.card_giftcard : Icons.flash_on,
              color: color,
              size: 19,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  '$createdAt  •  Баланс: ${before ?? '?'} → ${after ?? '?'} ENC'
                  '${type.isEmpty ? '' : '  •  $type'}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${isGrant ? '+' : ''}$amount ENC',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? value) {
    final date = value == null ? null : DateTime.tryParse(value)?.toLocal();
    if (date == null) return 'Дата неизвестна';
    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }
}
