import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class EmailChangeService {
  static final Uri _endpoint = Uri.parse(
    'https://okeanstudio.ru/api/send_email_change_code.php',
  );

  Future<void> start(String newEmail) async {
    await _request({'action': 'start', 'new_email': newEmail});
  }

  Future<void> verifyOldEmail(String code) async {
    await _request({'action': 'verify_old', 'code': code});
  }

  Future<void> verifyNewEmail(String code) async {
    await _request({'action': 'verify_new', 'code': code});
  }

  Future<void> _request(Map<String, dynamic> payload) async {
    final accessToken =
        Supabase.instance.client.auth.currentSession?.accessToken;
    if (accessToken == null) {
      throw Exception('Сессия истекла. Войдите в аккаунт повторно.');
    }

    final response = await http.post(
      _endpoint,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({...payload, 'access_token': accessToken}),
    );

    final body = response.body.replaceFirst('\uFEFF', '').trim();
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      final excerpt = body.substring(0, body.length > 200 ? 200 : body.length);
      throw Exception(
        'Сервер подтверждения email вернул '
        'HTTP ${response.statusCode}: '
        '${excerpt.isEmpty ? 'пустой ответ' : excerpt}',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw Exception('Сервер подтверждения email вернул неверный формат');
    }
    if (response.statusCode != 200 || decoded['success'] != true) {
      throw Exception(decoded['message'] ?? 'Не удалось изменить email');
    }
  }
}
