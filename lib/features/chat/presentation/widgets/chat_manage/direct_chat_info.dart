import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/core/utils/rpc_user.dart';

class DirectChatInfoWidget extends StatefulWidget {
  final String chatId;
  final String currentUserId;

  const DirectChatInfoWidget({
    super.key,
    required this.chatId,
    required this.currentUserId,
  });

  @override
  State<DirectChatInfoWidget> createState() => _DirectChatInfoWidgetState();
}

class _DirectChatInfoWidgetState extends State<DirectChatInfoWidget> {
  Map<String, dynamic>? _otherUser;
  bool _isLoading = true;
  bool _isBlocked = false;
  String? _error;
  String? _otherUserId;
  RealtimeChannel? _statusChannel;
  Timer? _statusPollingTimer;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    try {
      setState(() => _isLoading = true);
      
      final participantsResponse = await Supabase.instance.client
          .from('room_participants')
          .select('user_id')
          .eq('room_id', widget.chatId)
          .neq('user_id', widget.currentUserId)
          .maybeSingle();

      if (participantsResponse == null) {
        setState(() {
          _error = 'Участник не найден';
          _isLoading = false;
        });
        return;
      }

      _otherUserId = participantsResponse['user_id'] as String;

      // Получаем данные пользователя через RPC функцию
      final userResponse = await Supabase.instance.client.rpc(
        'get_user_by_id',
        params: {'p_id': _otherUserId},
      );
      final userRecord = rpcUserRecord(userResponse);

      // Проверяем, заблокирован ли пользователь (в обе стороны)
      final blockResponse = await Supabase.instance.client
          .from('blocks')
          .select()
          .eq('blocker_id', widget.currentUserId)
          .eq('blocked_id', _otherUserId!)
          .maybeSingle();

      final reverseBlockResponse = await Supabase.instance.client
          .from('blocks')
          .select()
          .eq('blocker_id', _otherUserId!)
          .eq('blocked_id', widget.currentUserId)
          .maybeSingle();

      if (mounted) {
        if (userRecord == null) {
          setState(() {
            _error = 'Пользователь не найден';
            _isLoading = false;
          });
        } else {
          setState(() {
            _otherUser = userRecord;
            _isBlocked = blockResponse != null || reverseBlockResponse != null;
            _isLoading = false;
            _error = null;
          });
        }
      }

      await _subscribeToUserStatus();
    } catch (e) {
      debugPrint('Ошибка загрузки: $e');
      if (mounted) {
        setState(() {
          _error = 'Ошибка загрузки';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _blockUser() async {
    if (_otherUserId == null) return;
    
    try {
      final now = DateTime.now().toIso8601String();
      await Supabase.instance.client.from('blocks').insert([
        {
          'blocker_id': widget.currentUserId,
          'blocked_id': _otherUserId!,
          'created_at': now,
        },
        {
          'blocker_id': _otherUserId!,
          'blocked_id': widget.currentUserId,
          'created_at': now,
        },
      ]);

      if (mounted) {
        setState(() => _isBlocked = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Пользователь заблокирован')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Ошибка блокировки: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка при блокировке')),
        );
      }
    }
  }

  Future<void> _unblockUser() async {
    if (_otherUserId == null) return;
    
    try {
      await Supabase.instance.client
          .from('blocks')
          .delete()
          .or(
            'and(blocker_id.eq.${widget.currentUserId},blocked_id.eq.$_otherUserId),and(blocker_id.eq.$_otherUserId,blocked_id.eq.${widget.currentUserId})',
          );

      if (mounted) {
        setState(() => _isBlocked = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Пользователь разблокирован')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Ошибка разблокировки: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка при разблокировке')),
        );
      }
    }
  }

  String _getStatusText(String? status) {
    switch (status) {
      case 'online':
        return 'В сети';
      case 'away':
        return 'Отошёл';
      case 'busy':
        return 'Занят';
      default:
        return 'Не в сети';
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'online':
        return Colors.green;
      case 'away':
        return Colors.orange;
      case 'busy':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatPhone(String? phone) {
    if (phone == null || phone.isEmpty) return 'Не указан';
    String cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.length == 11) {
      if (cleaned.startsWith('7') || cleaned.startsWith('8')) {
        return '+7 (${cleaned.substring(1, 4)}) ${cleaned.substring(4, 7)}-${cleaned.substring(7, 9)}-${cleaned.substring(9, 11)}';
      }
    }
    return phone;
  }

  Future<void> _subscribeToUserStatus() async {
    if (_otherUserId == null) return;

    try {
      _statusChannel?.unsubscribe();
      _startStatusPolling();
    } catch (e) {
      debugPrint('⚠️ Ошибка подписки на статус: $e');
    }
  }

  void _startStatusPolling() {
    _statusPollingTimer?.cancel();
    _statusPollingTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted || _otherUserId == null) return;
      try {
        // Получаем статус пользователя через RPC функцию
        final response = await Supabase.instance.client.rpc(
          'get_user_by_id',
          params: {'p_id': _otherUserId},
        );
        final userRecord = rpcUserRecord(response);
        if (mounted && userRecord != null && _otherUser != null) {
          setState(() {
            _otherUser = {
              ..._otherUser!,
              'status': userRecord['status'],
            };
          });
        }
      } catch (e) {
        debugPrint('⚠️ Ошибка опроса статуса пользователя: $e');
      }
    });
  }

  @override
  void dispose() {
    _statusChannel?.unsubscribe();
    _statusPollingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.deepPurple),
              )
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadUserInfo,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Аватар
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Colors.deepPurple, Colors.purpleAccent],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.deepPurple.withValues(alpha: 0.3),
                                blurRadius: 15,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Center(
                            child: _otherUser?['avatar_url'] != null && _otherUser!['avatar_url'].toString().isNotEmpty
                                ? ClipOval(
                                    child: Image.network(
                                      _otherUser!['avatar_url'],
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Icon(
                                        Icons.person,
                                        size: 50,
                                        color: Colors.white.withValues(alpha: 0.7),
                                      ),
                                    ),
                                  )
                                : Text(
                                    _otherUser?['name']?.isNotEmpty == true
                                        ? _otherUser!['name'][0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 42,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Имя
                        Text(
                          _otherUser?['name'] ?? 'Пользователь',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        // Тэг
                        GestureDetector(
                          onTap: () {
                            final tag = _otherUser?['tag'];
                            if (tag != null && tag.toString().isNotEmpty) {
                              Clipboard.setData(ClipboardData(text: '@$tag'));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Тэг скопирован')),
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A2A2A),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              _otherUser?['tag'] != null && _otherUser!['tag'].toString().isNotEmpty
                                  ? '@${_otherUser!['tag']}'
                                  : '@нет_тега',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Статус
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _getStatusColor(_otherUser?['status']),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _getStatusText(_otherUser?['status']),
                              style: TextStyle(
                                color: _getStatusColor(_otherUser?['status']),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // Телефон
                        if (_otherUser?['phone'] != null && _otherUser!['phone'].toString().isNotEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A2A2A),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.phone, color: Colors.grey, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Телефон',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatPhone(_otherUser!['phone']),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: _otherUser!['phone']));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Номер скопирован')),
                                    );
                                  },
                                  icon: const Icon(Icons.copy, color: Colors.grey, size: 18),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 24),
                        // Кнопка блокировки/разблокировки
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: _isBlocked ? _unblockUser : () {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  backgroundColor: const Color(0xFF2A2A2A),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  title: const Text(
                                    'Заблокировать пользователя?',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  content: Text(
                                    'Вы больше не сможете писать @${_otherUser?['tag'] ?? 'пользователю'}',
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text(
                                        'Отмена',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        _blockUser();
                                      },
                                      style: TextButton.styleFrom(
                                        backgroundColor: Colors.red.withValues(alpha: 0.1),
                                      ),
                                      child: const Text(
                                        'Заблокировать',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                            style: TextButton.styleFrom(
                              backgroundColor: _isBlocked 
                                  ? Colors.green.withValues(alpha: 0.15)
                                  : Colors.red.withValues(alpha: 0.15),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _isBlocked ? Icons.check_circle : Icons.block,
                                  color: _isBlocked ? Colors.green : Colors.red,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _isBlocked ? 'Разблокировать' : 'Заблокировать',
                                  style: TextStyle(
                                    color: _isBlocked ? Colors.green : Colors.red,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Кнопка закрыть
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            'Закрыть',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}