import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';
import 'package:strazh/core/utils/badges.dart';

class AdminBadgesScreen extends StatefulWidget {
  const AdminBadgesScreen({super.key});

  @override
  State<AdminBadgesScreen> createState() => _AdminBadgesScreenState();
}

class _AdminBadgesScreenState extends State<AdminBadgesScreen> {
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

  Future<void> _showBadgePicker(Map<String, dynamic> user) async {
    final userId = user['id'] as String;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const _BadgePickerSheet(),
    );

    if (result == null || !mounted) return;

    final badgeId = result['badgeId'] as String?;
    await _setBadge(userId, badgeId);
  }

  Future<void> _setBadge(String userId, String? badgeId) async {
    try {
      await Supabase.instance.client.rpc(
        'update_user_metadata',
        params: {
          'p_user_id': userId,
          'p_metadata': {'badge': badgeId},
        },
      );

      setState(() {
        final index = _users.indexWhere((u) => u['id'] == userId);
        if (index != -1) {
          _users[index] = {
            ..._users[index],
            'badge': badgeId,
          };
        }
      });

      if (!mounted) return;
      Toast.success(
        context,
        badgeId == null ? 'Бейдж снят' : 'Бейдж выдан',
      );
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
          'Бейджи',
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
                      final badgeId = user['badge'] as String?;
                      final badge = Badges.byId(badgeId);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(12),
                          border: badge != null
                              ? Border.all(
                                  color: badge.color.withValues(alpha: 0.4),
                                  width: 1,
                                )
                              : null,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                badge != null ? badge.color : Colors.grey[800],
                            child: Text(
                              (user['name'] ?? '?')[0].toUpperCase(),
                              style: TextStyle(
                                color: badge != null
                                    ? Colors.black
                                    : Colors.white,
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
                              if (badge != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child:
                                      BadgeIcon(badgeId: badgeId, size: 18),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            '@${user['tag'] ?? ''}',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                          onTap: () => _showBadgePicker(user),
                          trailing: Icon(
                            Icons.chevron_right,
                            color: Colors.grey[600],
                            size: 20,
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

class _BadgePickerSheet extends StatelessWidget {
  const _BadgePickerSheet();

  @override
  Widget build(BuildContext context) {
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
                'Выбрать бейдж',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              // ===== СНЯТЬ =====
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  onTap: () => Navigator.pop(
                    context,
                    {'badgeId': null},
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
                          Icons.close,
                          color: Colors.red,
                          size: 22,
                        ),
                        SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'Снять бейдж',
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
              ),
              const SizedBox(height: 6),
              // ===== СПИСОК БЕЙДЖЕЙ =====
              ...Badges.all.map((badge) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    onTap: () => Navigator.pop(
                      context,
                      {'badgeId': badge.id},
                    ),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: badge.color.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          BadgeIcon(badgeId: badge.id, size: 28),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              badge.name,
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
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}