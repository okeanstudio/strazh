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

    final botRecord = await _supabase
        .from('bots')
        .select('id, name, tag, avatar_url, is_verified')
        .ilike('tag', normalizedUsername.toLowerCase())
        .eq('is_enabled', true)
        .maybeSingle();
    if (botRecord != null) {
      return _findOrCreateBotChat(botRecord);
    }

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

    final roomId =
        await _findDirectRoom(currentUserId, targetUserId) ??
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

  static Future<UsernameChat> _findOrCreateBotChat(
    Map<String, dynamic> botRecord,
  ) async {
    final botId = botRecord['id'].toString();
    final bot = app.User(
      id: botId,
      name: botRecord['name']?.toString() ?? 'Бот',
      tag: botRecord['tag']?.toString() ?? '',
      avatarUrl: botRecord['avatar_url']?.toString(),
      isBot: true,
      botVerified: botRecord['is_verified'] == true,
    );
    final currentUserId = AuthService().currentUserId;
    if (currentUserId == null) {
      throw StateError('Не удалось определить текущего пользователя');
    }

    final existingBotRooms = await _supabase
        .from('bot_chat_participants')
        .select('room_id')
        .eq('bot_id', botId);
    final botRoomIds = existingBotRooms
        .map((row) => row['room_id'].toString())
        .toList();
    String? roomId;
    if (botRoomIds.isNotEmpty) {
      final myRooms = await _supabase
          .from('room_participants')
          .select('room_id')
          .eq('user_id', currentUserId)
          .inFilter('room_id', botRoomIds);
      for (final row in myRooms) {
        final room = await _supabase
            .from('rooms')
            .select('id, type')
            .eq('id', row['room_id'])
            .maybeSingle();
        if (room?['type'] == 'direct') {
          roomId = room!['id'].toString();
          break;
        }
      }
    }

    if (roomId == null) {
      final room = await _supabase
          .from('rooms')
          .insert({
            'type': 'direct',
            'created_by': currentUserId,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          })
          .select('id')
          .single();
      roomId = room['id'].toString();
      await _supabase.from('room_participants').insert({
        'room_id': roomId,
        'user_id': currentUserId,
        'joined_at': DateTime.now().toUtc().toIso8601String(),
      });
      await _supabase.rpc(
        'add_bot_to_direct_chat',
        params: {'p_room_id': roomId, 'p_bot_id': botId},
      );
    }

    return UsernameChat(
      chat: Chat(
        id: roomId,
        name: bot.name,
        avatarUrl: bot.avatarUrl,
        type: 'direct',
        isBot: true,
        botVerified: bot.botVerified,
      ),
      user: bot,
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
