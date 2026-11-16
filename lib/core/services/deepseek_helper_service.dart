import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class DeepSeekHelperService {
  // ⚠️ Прокси-сервер (не храни ключ в код!)
  final String serverUrl = 'http://81.19.136.44:5000/api/help';

  Future<String> getHelp(String userQuestion) async {
    debugPrint('🚀 Отправляем запрос на сервер (прокси)...');
    debugPrint('📝 Вопрос: $userQuestion');

    try {
      final response = await http.post(
        Uri.parse(serverUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'question': userQuestion,
        }),
      );

      debugPrint('📟 Статус ответа: ${response.statusCode}');

      if (response.statusCode == 200) {
        debugPrint('✅ Ответ получен!');
        final data = jsonDecode(response.body);
        final result = data['answer'] as String;
        debugPrint('💬 Ответ модели: $result');
        return result;
      } else {
        debugPrint('❌ Ошибка: ${response.statusCode}');
        debugPrint('📄 Тело ошибки: ${response.body}');
        return 'Ошибка сервера. Попробуйте позже.';
      }
    } catch (e) {
      debugPrint('🛑 Сетевая ошибка: $e');
      return 'Не удалось получить ответ. Попробуйте позже.';
    }
  }
}