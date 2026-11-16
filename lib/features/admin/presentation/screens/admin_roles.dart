import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

class AdminRolesScreen extends StatefulWidget {
  const AdminRolesScreen({super.key});

  @override
  State<AdminRolesScreen> createState() => _AdminRolesScreenState();
}

class _AdminRolesScreenState extends State<AdminRolesScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String _searchQuery = '';

  final List<String> _roles = ['user', 'admin', 'moderator', 'owner', 'premium'];

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      // Загружаем свежие данные через RPC
      final result = await Supabase.instance.client.rpc('get_all_users');
      if (mounted) {
        if (result is List) {
          setState(() {
            _users = result.cast<Map<String, dynamic>>();
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      debugPrint('Ошибка загрузки: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        Toast.error(context, 'Ошибка загрузки');
      }
    }
  }

  Future<void> _changeRole(String userId, String newRole) async {
    try {
      // Используем RPC функцию для обновления роли
      await Supabase.instance.client.rpc(
        'update_user_metadata',
        params: {
          'p_user_id': userId,
          'p_metadata': {'role': newRole},
        },
      );

      // Обновляем локальный список
      setState(() {
        final index = _users.indexWhere((u) => u['id'] == userId);
        if (index != -1) {
          _users[index]['role'] = newRole;
        }
      });

      Toast.success(context, '✅ Роль изменена на $newRole');
      
      // Перезагружаем список для синхронизации
      await _loadUsers();
    } catch (e) {
      debugPrint('Ошибка изменения роли: $e');
      Toast.error(context, 'Ошибка: $e');
    }
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'owner': return Colors.amber;
      case 'admin': return Colors.red;
      case 'moderator': return Colors.blue;
      case 'premium': return Colors.purple;
      default: return Colors.grey;
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
          'Управление ролями',
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
              onChanged: (v) {
                if (mounted) {
                  setState(() => _searchQuery = v);
                }
              },
              decoration: InputDecoration(
                hintText: 'Поиск по имени или тегу...',
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
                      // Принудительно берем роль из данных, если null - user
                      final currentRole = user['role']?.toString() ?? 'user';
                      final isAdmin = ['admin', 'owner', 'moderator'].contains(currentRole);
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isAdmin 
                              ? Colors.amber.withValues(alpha: 0.08)
                              : const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(12),
                          border: isAdmin
                              ? Border.all(color: Colors.amber.withValues(alpha: 0.3), width: 1)
                              : null,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isAdmin ? Colors.amber : Colors.grey[800],
                            child: Text(
                              (user['name'] ?? '?')[0].toUpperCase(),
                              style: TextStyle(
                                color: isAdmin ? Colors.black : Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            user['name'] ?? 'Без имени',
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            '@${user['tag'] ?? ''}',
                            style: TextStyle(
                              color: isAdmin ? Colors.amber[300] : Colors.grey[500],
                            ),
                          ),
                          trailing: DropdownButton<String>(
                            value: currentRole,
                            dropdownColor: const Color(0xFF2A2A2A),
                            style: TextStyle(
                              color: _getRoleColor(currentRole),
                              fontWeight: FontWeight.w600,
                            ),
                            underline: const SizedBox(),
                            items: _roles.map((role) {
                              return DropdownMenuItem(
                                value: role,
                                child: Text(
                                  role,
                                  style: TextStyle(
                                    color: _getRoleColor(role),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (newRole) {
                              if (newRole != null && newRole != currentRole) {
                                _changeRole(user['id'], newRole);
                              }
                            },
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