import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

class AdminVerifiedScreen extends StatefulWidget {
  const AdminVerifiedScreen({super.key});

  @override
  State<AdminVerifiedScreen> createState() => _AdminVerifiedScreenState();
}

class _AdminVerifiedScreenState extends State<AdminVerifiedScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    try {
      final result = await Supabase.instance.client.rpc('get_all_users');
      if (result is List) {
        setState(() {
          _users = result.cast<Map<String, dynamic>>();
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      Toast.error(context, 'Ошибка загрузки');
    }
  }

  Future<void> _toggleVerified(String userId, bool currentVerified) async {
    try {
      final newStatus = !currentVerified;
      
      // Используем RPC функцию для обновления email_verified
      await Supabase.instance.client.rpc(
        'update_user_metadata',
        params: {
          'p_user_id': userId,
          'p_metadata': {'email_verified': newStatus},
        },
      );

      setState(() {
        final index = _users.indexWhere((u) => u['id'] == userId);
        if (index != -1) {
          _users[index]['email_verified'] = newStatus;
        }
      });

      Toast.success(context, newStatus ? '✅ Галочка выдана' : '❌ Галочка снята');
    } catch (e) {
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
          'Галочки',
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
                      final isVerified = user['email_verified'] ?? false;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.grey[800],
                            child: Text(
                              (user['name'] ?? '?')[0].toUpperCase(),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(
                            user['name'] ?? 'Без имени',
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            '@${user['tag'] ?? ''}',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isVerified ? Icons.verified : Icons.verified_outlined,
                                color: isVerified ? Colors.green : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Switch(
                                value: isVerified,
                                onChanged: (_) => _toggleVerified(user['id'], isVerified),
                                activeColor: Colors.green,
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