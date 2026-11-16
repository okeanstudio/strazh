import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/features/auth/data/services/auth_service.dart';
import 'package:strazh/features/chat/presentation/screens/chat.dart';
import 'package:strazh/shared/domain/models/chat.dart';
import 'package:strazh/shared/domain/models/user.dart' as app;

class SearchUsersDialog extends StatefulWidget {
  final app.User currentUser;

  const SearchUsersDialog({super.key, required this.currentUser});

  @override
  State<SearchUsersDialog> createState() => _SearchUsersDialogState();
}

class _SearchUsersDialogState extends State<SearchUsersDialog> {
  final TextEditingController _searchController = TextEditingController();
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query.length >= 2) {
      _searchUsers(query);
    } else {
      setState(() {
        _results = [];
        _isLoading = false;
      });
    }
  }

  Future<void> _searchUsers(String query) async {
    setState(() => _isLoading = true);

    try {
      final results = await _authService.searchUsers(query);
      if (!mounted || query != _searchController.text.trim()) return;

      setState(() {
        _results = results
            .where((user) => user['id'] != widget.currentUser.id)
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Ошибка поиска: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String?> _getOrCreateDirectChat(String otherUserId) async {
    final supabase = Supabase.instance.client;
    final currentUserId = widget.currentUser.id;

    // Проверяем, существует ли уже чат
    final existingChats = await supabase
        .from('room_participants')
        .select('room_id')
        .eq('user_id', currentUserId);

    final List<String> roomIds = existingChats
        .map((e) => e['room_id'] as String)
        .toList();

    if (roomIds.isNotEmpty) {
      final directChat = await supabase
          .from('room_participants')
          .select('room_id')
          .eq('user_id', otherUserId)
          .inFilter('room_id', roomIds);

      if (directChat.isNotEmpty) {
        // Проверяем, что это direct чат
        final roomData = await supabase
            .from('rooms')
            .select('type')
            .eq('id', directChat[0]['room_id'])
            .maybeSingle();

        if (roomData != null && roomData['type'] == 'direct') {
          return directChat[0]['room_id'];
        }
      }
    }

    // Создаём новый чат
    final newRoom = await supabase
        .from('rooms')
        .insert({
          'type': 'direct',
          'created_by': currentUserId,
          'created_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();

    final roomId = newRoom['id'];

    await supabase.from('room_participants').insert([
      {
        'room_id': roomId,
        'user_id': currentUserId,
        'joined_at': DateTime.now().toIso8601String(),
      },
      {
        'room_id': roomId,
        'user_id': otherUserId,
        'joined_at': DateTime.now().toIso8601String(),
      },
    ]);

    return roomId;
  }

  void _openChat(String userId, String userName) async {
    final roomId = await _getOrCreateDirectChat(userId);
    if (roomId != null && mounted) {
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            chat: Chat(id: roomId, name: userName, type: 'direct'),
            currentUser: widget.currentUser,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 400,
        height: 500,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            const Text(
              'Поиск пользователей',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Введите тег...',
                hintStyle: TextStyle(color: Colors.grey[600]),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Colors.deepPurple,
                      ),
                    )
                  : _results.isEmpty
                  ? const Center(
                      child: Text(
                        'Никого не найдено',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final user = _results[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.deepPurple,
                                child: Text(
                                  user['name']?.isNotEmpty == true
                                      ? user['name'][0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              title: Text(
                                user['name'] ?? 'Без имени',
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                '@${user['tag']}',
                                style: const TextStyle(color: Colors.grey),
                              ),
                              onTap: () => _openChat(
                                user['id'],
                                user['name'] ?? user['tag'],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
