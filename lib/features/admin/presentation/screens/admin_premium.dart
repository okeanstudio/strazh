import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

class AdminPremiumScreen extends StatefulWidget {
  const AdminPremiumScreen({super.key});

  @override
  State<AdminPremiumScreen> createState() => _AdminPremiumScreenState();
}

class _AdminPremiumScreenState extends State<AdminPremiumScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final result = await Supabase.instance.client.rpc('get_all_users');
      if (!mounted) return;
      if (result is List) {
        setState(() {
          _users = result.cast<Map<String, dynamic>>();
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      Toast.error(context, 'Ошибка загрузки');
    }
  }

  bool _isSubscriptionActive(Map<String, dynamic> user) {
    final active = user['subscription_active'] == true;
    final expiresRaw = user['subscription_expires_at'];
    if (!active || expiresRaw == null) return false;

    if (expiresRaw.toString() == 'forever') return true;

    final expires = DateTime.tryParse(expiresRaw.toString());
    if (expires == null) return false;

    return expires.isAfter(DateTime.now());
  }

  bool _isForever(Map<String, dynamic> user) {
    return user['subscription_expires_at']?.toString() == 'forever';
  }

  String _formatExpires(Map<String, dynamic> user) {
    final raw = user['subscription_expires_at'];
    if (raw == null) return '';
    if (raw.toString() == 'forever') return 'навсегда';
    final date = DateTime.tryParse(raw.toString());
    if (date == null) return '';
    final local = date.toLocal();
    return 'до ${local.day.toString().padLeft(2, '0')}.'
        '${local.month.toString().padLeft(2, '0')}.'
        '${local.year}';
  }

  String _planName(String? plan) {
    switch (plan) {
      case '1d':
        return '1 день';
      case '15d':
        return '15 дней';
      case '1m':
        return '1 месяц';
      case '1y':
        return '1 год';
      case '3y':
        return '3 года';
      case 'forever':
        return 'Навсегда';
      default:
        return '';
    }
  }

  Future<void> _showDurationPicker(Map<String, dynamic> user) async {
    final userId = user['id'] as String;
    final isActive = _isSubscriptionActive(user);

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _DurationPickerSheet(isActive: isActive),
    );

    if (result == null || !mounted) return;

    final action = result['action'] as String;
    if (action == 'cancel') {
      await _cancelSubscription(userId);
    } else if (action == 'set') {
      final months = result['months'] as int;
      final days = result['days'] as int? ?? 0;
      final forever = result['forever'] as bool? ?? false;
      final planId = result['planId'] as String;
      await _setSubscription(userId, planId, months, days, forever);
    }
  }

  Future<void> _setSubscription(
    String userId,
    String planId,
    int months,
    int days,
    bool forever,
  ) async {
    try {
      if (forever) {
        await Supabase.instance.client.rpc(
          'set_user_subscription_forever',
          params: {'p_user_id': userId},
        );

        setState(() {
          final index = _users.indexWhere((u) => u['id'] == userId);
          if (index != -1) {
            _users[index] = {
              ..._users[index],
              'subscription_active': true,
              'subscription_expires_at': 'forever',
              'subscription_plan_id': planId,
            };
          }
        });

        if (!mounted) return;
        Toast.success(context, '⭐ Подписка выдана навсегда');
        return;
      }

      await Supabase.instance.client.rpc(
        'set_user_subscription',
        params: {
          'p_user_id': userId,
          'p_plan_id': planId,
          'p_months': months,
          'p_days': days,
        },
      );

      final expires = DateTime.now()
          .add(Duration(days: days))
          .add(Duration(days: months * 30));

      setState(() {
        final index = _users.indexWhere((u) => u['id'] == userId);
        if (index != -1) {
          _users[index] = {
            ..._users[index],
            'subscription_active': true,
            'subscription_expires_at': expires.toIso8601String(),
            'subscription_plan_id': planId,
          };
        }
      });

      if (!mounted) return;
      Toast.success(context, '⭐ Подписка выдана: ${_planName(planId)}');
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Ошибка: $e');
    }
  }

  Future<void> _cancelSubscription(String userId) async {
    try {
      await Supabase.instance.client.rpc(
        'cancel_user_subscription',
        params: {'p_user_id': userId},
      );

      setState(() {
        final index = _users.indexWhere((u) => u['id'] == userId);
        if (index != -1) {
          _users[index] = {
            ..._users[index],
            'subscription_active': false,
            'subscription_expires_at': null,
            'subscription_plan_id': null,
          };
        }
      });

      if (!mounted) return;
      Toast.success(context, '⭐ Подписка снята');
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Ошибка: $e');
    }
  }

  List<Map<String, dynamic>> get _filteredUsers {
    return _users.where((user) {
      final name = (user['name'] ?? '').toLowerCase();
      final tag = (user['tag'] ?? '').toLowerCase();
      final query = _searchQuery.toLowerCase();
      return name.contains(query) || tag.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0A0A),
        elevation: 0,
        title: const Text(
          'Strazh Infinity',
          style: TextStyle(color: Colors.white, fontSize: 20),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        actions: [
          IconButton(
            onPressed: _loadUsers,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Поиск...',
                hintStyle: TextStyle(color: Colors.grey[500]),
                prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                filled: true,
                fillColor: const Color(0xFF1A1A1A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _filteredUsers.length,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemBuilder: (context, index) {
                      final user = _filteredUsers[index];
                      final isActive = _isSubscriptionActive(user);
                      final forever = _isForever(user);
                      final expiresText = _formatExpires(user);
                      final planText =
                          _planName(user['subscription_plan_id'] as String?);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(12),
                          border: isActive
                              ? Border.all(
                                  color: forever
                                      ? Colors.purpleAccent
                                      : Colors.amber.withValues(alpha: 0.5),
                                  width: 1,
                                )
                              : null,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                isActive ? Colors.amber : Colors.grey[800],
                            child: Text(
                              (user['name'] ?? '?')[0].toUpperCase(),
                              style: TextStyle(
                                color:
                                    isActive ? Colors.black : Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  user['name'] ?? 'Без имени',
                                  style:
                                      const TextStyle(color: Colors.white),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isActive)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Icon(
                                    forever
                                        ? Icons.all_inclusive
                                        : Icons.verified,
                                    color: forever
                                        ? Colors.purpleAccent
                                        : Colors.amber,
                                    size: 16,
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '@${user['tag'] ?? ''}',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 12,
                                ),
                              ),
                              if (isActive && planText.isNotEmpty)
                                Text(
                                  expiresText.isEmpty
                                      ? planText
                                      : '$planText · $expiresText',
                                  style: TextStyle(
                                    color: forever
                                        ? Colors.purpleAccent
                                        : Colors.amber,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                          onTap: () => _showDurationPicker(user),
                          trailing: Switch(
                            value: isActive,
                            onChanged: (_) => _showDurationPicker(user),
                            activeThumbColor: forever
                                ? Colors.purpleAccent
                                : Colors.amber,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DurationPickerSheet extends StatelessWidget {
  final bool isActive;

  const _DurationPickerSheet({required this.isActive});

  @override
  Widget build(BuildContext context) {
    final options = [
      {
        'action': 'set',
        'planId': '1d',
        'label': '1 день',
        'months': 0,
        'days': 1,
        'forever': false,
        'icon': Icons.today_outlined,
      },
      {
        'action': 'set',
        'planId': '15d',
        'label': '15 дней',
        'months': 0,
        'days': 15,
        'forever': false,
        'icon': Icons.date_range_outlined,
      },
      {
        'action': 'set',
        'planId': '1m',
        'label': '1 месяц',
        'months': 1,
        'days': 0,
        'forever': false,
        'icon': Icons.calendar_month_outlined,
      },
      {
        'action': 'set',
        'planId': '1y',
        'label': '1 год',
        'months': 12,
        'days': 0,
        'forever': false,
        'icon': Icons.workspace_premium_outlined,
      },
      {
        'action': 'set',
        'planId': '3y',
        'label': '3 года',
        'months': 36,
        'days': 0,
        'forever': false,
        'icon': Icons.military_tech_outlined,
      },
      {
        'action': 'set',
        'planId': 'forever',
        'label': 'Навсегда',
        'months': 0,
        'days': 0,
        'forever': true,
        'icon': Icons.all_inclusive,
      },
    ];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[700],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Срок подписки',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              ...options.map((opt) {
                final forever = opt['forever'] as bool;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    onTap: () => Navigator.pop(context, opt),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(12),
                        border: forever
                            ? Border.all(
                                color: Colors.purpleAccent
                                    .withValues(alpha: 0.5),
                              )
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            opt['icon'] as IconData,
                            color:
                                forever ? Colors.purpleAccent : Colors.amber,
                            size: 22,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              opt['label'] as String,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: Colors.grey[600],
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              if (isActive) ...[
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => Navigator.pop(
                    context,
                    {'action': 'cancel'},
                  ),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.cancel_outlined,
                          color: Colors.red,
                          size: 22,
                        ),
                        SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'Снять подписку',
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}