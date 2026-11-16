import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class EmailService {
  // 🔥 URL твоего PHP скрипта на okeanstudio.ru
  static const String sendVerificationUrl =
      'https://okeanstudio.ru/api/send_code.php';

  Future<void> sendVerificationEmail({
    required String email,
    required String code,
    required String name,
  }) async {
    await _sendEmail(
      url: sendVerificationUrl,
      email: email,
      code: code,
      name: name,
    );
  }

  Future<void> _sendEmail({
    required String url,
    required String email,
    required String code,
    required String name,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'code': code, 'name': name}),
      );

      final responseBody = response.body.replaceFirst('\uFEFF', '').trim();
      dynamic decoded;
      try {
        decoded = jsonDecode(responseBody);
      } on FormatException {
        final contentType = response.headers['content-type'] ?? 'не указан';
        final normalizedBody = responseBody.replaceAll(RegExp(r'\s+'), ' ');
        final excerpt = normalizedBody.substring(
          0,
          normalizedBody.length > 240 ? 240 : normalizedBody.length,
        );
        debugPrint(
          'Email endpoint returned non-JSON: '
          'HTTP ${response.statusCode}, content-type=$contentType, body=$excerpt',
        );
        throw Exception(
          'PHP-скрипт вернул не JSON '
          '(HTTP ${response.statusCode}, $contentType): '
          '${excerpt.isEmpty ? 'пустой ответ' : excerpt}',
        );
      }

      if (decoded is! Map<String, dynamic>) {
        throw Exception('PHP-скрипт вернул JSON неправильного формата');
      }

      if (response.statusCode != 200 || decoded['success'] != true) {
        throw Exception(decoded['message'] ?? 'Ошибка отправки письма');
      }

      debugPrint('✅ Email sent to $email');
    } catch (e) {
      debugPrint('❌ Error sending email: $e');
      rethrow;
    }
  }
}
