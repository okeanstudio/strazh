import 'package:flutter/material.dart';
import 'package:strazh/shared/domain/models/gift.dart';
import 'package:strazh/features/gifts/data/services/encoins_service.dart';
import 'package:strazh/features/gifts/data/services/gift_service.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

class AdminGiftsScreen extends StatefulWidget {
  const AdminGiftsScreen({super.key});

  @override
  State<AdminGiftsScreen> createState() => _AdminGiftsScreenState();
}

class _AdminGiftsScreenState extends State<AdminGiftsScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _history = [];
  List<Gift> _gifts = [];
  String _query = '';
  String? _grantingUserId;
  bool _isLoading = true;
  bool _isHistoryLoading = true;

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
    try {
      final results = await Future.wait([
        EncoinsService.getAdminBalances(),
        GiftService.getCatalog(),
        GiftService.getAdminGiftHistory(),
      ]);
      if (!mounted) return;
      setState(() {
        _users = results[0] as List<Map<String, dynamic>>;
        _gifts = results[1] as List<Gift>;
        _history = results[2] as List<Map<String, dynamic>>;
        _isLoading = false;
        _isHistoryLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isHistoryLoading = false;
      });
      Toast.error(context, 'Не удалось загрузить данные о подарках: $e');
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

  Future<void> _showGrantDialog(Map<String, dynamic> user) async {
    if (_grantingUserId != null) return;
    final userId = user['id']?.toString();
    if (userId == null || userId.isEmpty) {
      Toast.error(context, 'У пользователя отсутствует идентификатор');
      return;
    }

    final grant = await showDialog<(Gift, String)>(
      context: context,
      builder: (_) => _AdminGiftGrantDialog(gifts: _gifts),
    );
    if (grant == null || !mounted) return;

    setState(() => _grantingUserId = userId);
    try {
      await GiftService.grantGift(
        userId: userId,
        gift: grant.$1,
        caption: grant.$2,
      );
      if (!mounted) return;
      Toast.success(
        context,
        '${grant.$1.name} выдан пользователю '
        '${user['name']?.toString() ?? 'Без имени'}',
      );
      await _refreshHistory();
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Не удалось выдать подарок: $e');
    } finally {
      if (mounted) setState(() => _grantingUserId = null);
    }
  }

  Future<void> _showInventoryDialog(Map<String, dynamic> user) async {
    final userId = user['id']?.toString();
    if (userId == null || userId.isEmpty) {
      Toast.error(context, 'У пользователя отсутствует идентификатор');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _AdminGiftInventoryDialog(
        userId: userId,
        userName: user['name']?.toString() ?? 'Без имени',
        onGiftRevoked: _refreshHistory,
      ),
    );
  }

  Future<void> _refreshHistory() async {
    try {
      final history = await GiftService.getAdminGiftHistory();
      if (mounted) setState(() => _history = history);
    } catch (e) {
      if (mounted) Toast.error(context, 'Не удалось обновить историю: $e');
    }
  }

  Widget _buildUsers(List<Map<String, dynamic>> users) {
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
                  itemBuilder: (context, index) {
                    final user = users[index];
                    final name = user['name']?.toString() ?? 'Без имени';
                    final tag = user['tag']?.toString() ?? '';
                    final avatar = user['avatar_url']?.toString();
                    final isGranting =
                        user['id']?.toString() == _grantingUserId;
                    return Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF191522),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF332852),
                          backgroundImage:
                              avatar == null || avatar.isEmpty
                                  ? null
                                  : NetworkImage(avatar),
                          child: avatar == null || avatar.isEmpty
                              ? Text(
                                  name.isEmpty ? '?' : name[0].toUpperCase(),
                                  style: const TextStyle(color: Colors.white),
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
                          tag.isEmpty ? 'Пользователь' : '@$tag',
                          style: const TextStyle(color: Colors.white54),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Инвентарь и отзыв подарков',
                              onPressed: () => _showInventoryDialog(user),
                              icon: const Icon(
                                Icons.inventory_2_outlined,
                                color: Colors.white70,
                              ),
                            ),
                            isGranting
                                ? const SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: Padding(
                                      padding: EdgeInsets.all(9),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFFFFC86B),
                                      ),
                                    ),
                                  )
                                : IconButton(
                                    tooltip: 'Выдать подарок',
                                    onPressed: () => _showGrantDialog(user),
                                    icon: const Icon(
                                      Icons.card_giftcard,
                                      color: Color(0xFFFFC86B),
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
    );
  }

  Widget _buildHistory() {
    if (_isHistoryLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFC86B)),
      );
    }
    final query = _query.trim().toLowerCase();
    final history = _history.where((event) {
      if (query.isEmpty) return true;
      return [
        event['gift_name'],
        event['recipient_name'],
        event['sender_name'],
        event['actor_name'],
        event['action'],
      ].any((value) => value?.toString().toLowerCase().contains(query) ?? false);
    }).toList();
    if (history.isEmpty) {
      return const Center(
        child: Text(
          'История подарков пуста',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: history.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final event = history[index];
        final isRevoked = event['action'] == 'revoked';
        final isRemoved = event['action'] == 'removed';
        final action = isRevoked
            ? 'Отозван'
            : isRemoved
                ? 'Удалён вместе с исходным сообщением'
                : 'Выдан';
        final date = DateTime.tryParse(event['created_at']?.toString() ?? '');
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF191522),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Text(
                event['gift_emoji']?.toString() ?? '🎁',
                style: const TextStyle(fontSize: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${event['gift_name'] ?? 'Подарок'} · $action',
                      style: TextStyle(
                        color: isRevoked
                            ? const Color(0xFFFF8A80)
                            : Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${event['recipient_name'] ?? 'Пользователь'} · '
                      'от ${event['sender_name'] ?? 'неизвестно'}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    Text(
                      'Действие: ${event['actor_name'] ?? 'Система'} · '
                      '${event['source'] == 'admin' ? 'админка' : 'чат'}'
                      '${date == null ? '' : ' · ${date.toLocal().toString().substring(0, 16)}'}',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                    if ((event['caption']?.toString() ?? '').isNotEmpty)
                      Text(
                        event['caption'].toString(),
                        style: const TextStyle(color: Colors.white54),
                      ),
                  ],
                ),
              ),
              if (!isRevoked && !isRemoved)
                const Icon(Icons.check_circle_outline, color: Colors.green),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final users = _filteredUsers;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0A0A),
        title: const Text(
          'Подарки',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: const TabBar(
          labelColor: Color(0xFFFFC86B),
          unselectedLabelColor: Colors.white54,
          indicatorColor: Color(0xFFFFC86B),
          tabs: [
            Tab(text: 'Пользователи'),
            Tab(text: 'История'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _loadData,
            icon: const Icon(Icons.refresh, color: Colors.white70),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFC86B)),
            )
          : TabBarView(
              children: [
                _buildUsers(users),
                _buildHistory(),
              ],
            ),
      ),
    );
  }
}

class _AdminGiftInventoryDialog extends StatefulWidget {
  const _AdminGiftInventoryDialog({
    required this.userId,
    required this.userName,
    required this.onGiftRevoked,
  });

  final String userId;
  final String userName;
  final Future<void> Function() onGiftRevoked;

  @override
  State<_AdminGiftInventoryDialog> createState() =>
      _AdminGiftInventoryDialogState();
}

class _AdminGiftInventoryDialogState
    extends State<_AdminGiftInventoryDialog> {
  List<Map<String, dynamic>> _gifts = [];
  bool _isLoading = true;
  String? _revokingGiftId;

  @override
  void initState() {
    super.initState();
    _loadGifts();
  }

  Future<void> _loadGifts() async {
    try {
      final gifts = await GiftService.getAdminUserGifts(widget.userId);
      if (!mounted) return;
      setState(() {
        _gifts = gifts;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      Toast.error(context, 'Не удалось загрузить инвентарь подарков: $e');
    }
  }

  Future<void> _revokeGift(Map<String, dynamic> gift) async {
    final id = gift['id']?.toString();
    if (id == null || id.isEmpty || _revokingGiftId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF17131F),
        title: const Text(
          'Отозвать подарок?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Подарок «${gift['gift_name'] ?? 'Подарок'}» будет удалён '
          'из инвентаря пользователя. Действие сохранится в истории.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF8A80),
              foregroundColor: const Color(0xFF241A0B),
            ),
            child: const Text('Отозвать'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _revokingGiftId = id);
    try {
      await GiftService.revokeGift(id);
      await _loadGifts();
      await widget.onGiftRevoked();
      if (mounted) {
        Toast.success(context, 'Подарок отозван');
      }
    } catch (e) {
      if (mounted) Toast.error(context, 'Не удалось отозвать подарок: $e');
    } finally {
      if (mounted) setState(() => _revokingGiftId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF17131F),
      title: Text(
        'Подарки: ${widget.userName}',
        style: const TextStyle(color: Colors.white),
      ),
      content: SizedBox(
        width: 480,
        height: 440,
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFFFC86B)),
              )
            : _gifts.isEmpty
                ? const Center(
                    child: Text(
                      'В инвентаре нет подарков',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _gifts.length,
                    separatorBuilder: (_, __) => const Divider(
                      color: Colors.white12,
                      height: 1,
                    ),
                    itemBuilder: (context, index) {
                      final gift = _gifts[index];
                      final giftId = gift['id']?.toString();
                      final isRevoking = giftId == _revokingGiftId;
                      final createdAt = DateTime.tryParse(
                        gift['created_at']?.toString() ?? '',
                      );
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Text(
                          gift['gift_emoji']?.toString() ?? '🎁',
                          style: const TextStyle(fontSize: 26),
                        ),
                        title: Text(
                          gift['gift_name']?.toString() ?? 'Подарок',
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          'От ${gift['sender_name'] ?? 'неизвестно'}'
                          '${createdAt == null ? '' : ' · ${createdAt.toLocal().toString().substring(0, 16)}'}'
                          '${(gift['caption']?.toString() ?? '').isEmpty ? '' : '\n${gift['caption']}'}',
                          style: const TextStyle(color: Colors.white54),
                        ),
                        trailing: isRevoking
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFFFF8A80),
                                ),
                              )
                            : IconButton(
                                tooltip: 'Отозвать подарок',
                                onPressed: () => _revokeGift(gift),
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  color: Color(0xFFFF8A80),
                                ),
                              ),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}

class _AdminGiftGrantDialog extends StatefulWidget {
  const _AdminGiftGrantDialog({required this.gifts});

  final List<Gift> gifts;

  @override
  State<_AdminGiftGrantDialog> createState() => _AdminGiftGrantDialogState();
}

class _AdminGiftGrantDialogState extends State<_AdminGiftGrantDialog> {
  final _captionController = TextEditingController();
  Gift? _selectedGift;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF17131F),
      title: const Text(
        'Выдать подарок',
        style: TextStyle(color: Colors.white),
      ),
      content: SizedBox(
        width: 420,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  itemCount: widget.gifts.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.65,
                  ),
                  itemBuilder: (context, index) {
                    final gift = widget.gifts[index];
                    final selected = gift.id == _selectedGift?.id;
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _selectedGift = gift),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFFFFC86B).withValues(alpha: 0.15)
                              : const Color(0xFF24202D),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected
                                ? const Color(0xFFFFC86B)
                                : Colors.white12,
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(gift.emoji, style: const TextStyle(fontSize: 28)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                gift.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _captionController,
                maxLength: 120,
                maxLines: 2,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Подпись (необязательно)',
                  labelStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: const Color(0xFF24202D),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _selectedGift == null
              ? null
              : () => Navigator.pop(
                    context,
                    (_selectedGift!, _captionController.text.trim()),
                  ),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFFC86B),
            foregroundColor: const Color(0xFF241A0B),
          ),
          child: const Text('Выдать'),
        ),
      ],
    );
  }
}
