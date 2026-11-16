import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/core/utils/rpc_user.dart';
import 'package:strazh/features/auth/data/services/auth_service.dart';
import 'package:strazh/shared/domain/models/chat.dart';
import 'package:strazh/shared/domain/models/user.dart' as app;

class UsernameChat {
  final Chat chat;
  final app.User user;

  const UsernameChat({required this.chat, required this.user});
}

class UsernameChatService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  static Future<UsernameChat?> findOrCreate(String username) async {
    final normalizedUsername = username.trim().replaceFirst(RegExp(r'^@'), '');
    if (normalizedUsername.isEmpty) return null;

    final lookupResponse = await _supabase.rpc(
      'get_user_by_tag_ci',
      params: {'p_tag': normalizedUsername},
    );
    final lookupRecord = rpcUserRecord(lookupResponse);
    final targetUserId = lookupRecord?['id']?.toString();
    if (targetUserId == null || targetUserId.isEmpty) return null;

    final userResponse = await _supabase.rpc(
      'get_user_by_id',
      params: {'p_id': targetUserId},
    );
    final userRecord = rpcUserRecord(userResponse);
    if (userRecord == null) return null;

    final targetUser = app.User(
      id: targetUserId,
      name: userRecord['name']?.toString() ?? 'Пользователь',
      tag: userRecord['tag']?.toString() ?? normalizedUsername,
      avatarUrl: userRecord['avatar_url']?.toString(),
      role: userRecord['role']?.toString(),
      status: userRecord['status']?.toString(),
      phone: userRecord['phone']?.toString(),
      bio: userRecord['bio']?.toString(),
    );

    final currentUserId = AuthService().currentUserId;
    if (currentUserId == null) {
      throw StateError('Не удалось определить текущего пользователя');
    }
    if (targetUserId == currentUserId) {
      throw StateError('Нельзя открыть чат с самим собой');
    }

    final roomId = await _findDirectRoom(currentUserId, targetUserId) ??
        await _createDirectRoom(currentUserId, targetUserId);

    return UsernameChat(
      chat: Chat(
        id: roomId,
        name: targetUser.name,
        avatarUrl: targetUser.avatarUrl,
        type: 'direct',
      ),
      user: targetUser,
    );
  }

  static Future<String?> _findDirectRoom(
    String currentUserId,
    String targetUserId,
  ) async {
    final currentRooms = await _supabase
        .from('room_participants')
        .select('room_id')
        .eq('user_id', currentUserId);
    final roomIds = currentRooms
        .map((row) => row['room_id'].toString())
        .toSet()
        .toList();
    if (roomIds.isEmpty) return null;

    final sharedRooms = await _supabase
        .from('room_participants')
        .select('room_id')
        .eq('user_id', targetUserId)
        .inFilter('room_id', roomIds);

    for (final row in sharedRooms) {
      final room = await _supabase
          .from('rooms')
          .select('id, type')
          .eq('id', row['room_id'])
          .maybeSingle();
      if (room?['type'] == 'direct') return room!['id'].toString();
    }
    return null;
  }

  static Future<String> _createDirectRoom(
    String currentUserId,
    String targetUserId,
  ) async {
    final room = await _supabase
        .from('rooms')
        .insert({
          'type': 'direct',
          'created_by': currentUserId,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select('id')
        .single();
    final roomId = room['id'].toString();

    await _supabase.from('room_participants').insert([
      {
        'room_id': roomId,
        'user_id': currentUserId,
        'joined_at': DateTime.now().toUtc().toIso8601String(),
      },
      {
        'room_id': roomId,
        'user_id': targetUserId,
        'joined_at': DateTime.now().toUtc().toIso8601String(),
      },
    ]);

    return roomId;
  }
}
