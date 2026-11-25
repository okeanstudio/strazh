import 'dart:convert';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

class BotService {
  static const botFatherId = '00000000-0000-4000-8000-000000000001';

  final SupabaseClient _supabase;

  BotService([SupabaseClient? supabase])
    : _supabase = supabase ?? Supabase.instance.client;

  String createToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return 'BOT_${base64Url.encode(bytes).replaceAll('=', '')}';
  }

  Future<List<Map<String, dynamic>>> getMyBots() async {
    final response = await _supabase.rpc('get_my_bots');
    return response is List
        ? response
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
        : const [];
  }

  Future<String?> getBotToken(String botId) async {
    final token = await _supabase.rpc(
      'get_my_bot_token',
      params: {'p_bot_id': botId},
    );
    return token is String ? token : null;
  }

  Future<void> updateMyBot({
    required String botId,
    required String field,
    required String value,
  }) async {
    await _supabase.rpc(
      'update_my_bot',
      params: {'p_bot_id': botId, 'p_field': field, 'p_value': value},
    );
  }

  Future<String> rotateMyBotToken(String botId) async {
    final token = createToken();
    await _supabase.rpc(
      'rotate_my_bot_token',
      params: {'p_bot_id': botId, 'p_token': token},
    );
    return token;
  }

  Future<String?> sendBotFatherMessage({
    required String roomId,
    required String text,
  }) async {
    final messageId = await _supabase.rpc(
      'send_botfather_message',
      params: {'p_room_id': roomId, 'p_text': text},
    );
    return messageId is String ? messageId : null;
  }

  Future<String> createBot({
    required String name,
    required String tag,
    required String description,
    required String? avatarUrl,
    required String token,
  }) async {
    final botId = await _supabase.rpc(
      'create_bot',
      params: {
        'p_name': name,
        'p_tag': tag,
        'p_description': description,
        'p_avatar_url': avatarUrl,
        'p_token': token,
      },
    );
    if (botId is! String || botId.isEmpty) {
      throw StateError('The bot service did not return a bot ID');
    }
    return botId;
  }

  Future<List<Map<String, dynamic>>> getAllBots() async {
    final response = await _supabase.rpc('get_all_bots');
    return response is List
        ? response
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
        : const [];
  }

  Future<void> setVerified({
    required String botId,
    required bool verified,
  }) async {
    await _supabase.rpc(
      'set_bot_verified',
      params: {'p_bot_id': botId, 'p_verified': verified},
    );
  }
}
