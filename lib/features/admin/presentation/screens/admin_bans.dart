import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

class AdminBansScreen extends StatefulWidget {
  const AdminBansScreen({super.key});

  @override
  State<AdminBansScreen> createState() => _AdminBansScreenState();
}

class _AdminBansScreenState extends State<AdminBansScreen> {
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

  Future<void> _toggleBan(Map<String, dynamic> user) async {
    final userId = user['id'] as String;
    final isBanned = user['is_banned'] == true;
    final newStatus = !isBanned;

    try {
      // 1) Метаданные — для UI
      await Supabase.instance.client.rpc(
        'update_user_metadata',
        params: {
          'p_user_id': userId,
          'p_metadata': {'is_banned': newStatus},
        },
      );

      // 2) Реальный бан в auth.users
      await Supabase.instance.client.rpc(
        'set_user_ban',
        params: {
          'p_user_id': userId,
          'p_banned': newStatus,
        },
      );

      if (!mounted) return;
      setState(() {
        final index = _users.indexWhere((u) => u['id'] == userId);
        if (index != -1) {
          _users[index] = {
            ..._users[index],
            'is_banned': newStatus,
          };
        }
      });

      Toast.success(context, newStatus ? '⛔ Забанен' : '✅ Бан снят');
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
          'Баны',
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
                      final isBanned = user['is_banned'] == true;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isBanned
                              ? Colors.red.withValues(alpha: 0.1)
                              : const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(12),
                          border: isBanned
                              ? Border.all(color: Colors.red, width: 1)
                              : null,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                isBanned ? Colors.red : Colors.grey[800],
                            child: Text(
                              (user['name'] ?? '?')[0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            user['name'] ?? 'Без имени',
                            style: TextStyle(
                              color: isBanned ? Colors.red : Colors.white,
                            ),
                          ),
                          subtitle: Text(
                            '@${user['tag'] ?? ''}',
                            style: TextStyle(
                              color: isBanned
                                  ? Colors.red[300]
                                  : Colors.grey[500],
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isBanned)
                                const Icon(Icons.block, color: Colors.red),
                              const SizedBox(width: 8),
                              Switch(
                                value: isBanned,
                                onChanged: (_) => _toggleBan(user),
                                activeThumbColor: Colors.red,
                              ),
                            ],
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