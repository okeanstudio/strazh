import 'dart:convert';
import 'package:http/http.dart' as http;

class SmsRuService {
  String _lastCode = '';
  
  // API URL твоего сервера (VPS)
  // Если сервер не используется, оставь как есть — будет работать в тестовом режиме
  final String _apiUrl = 'http://81.19.136.44:3000';
  
  /// Отправка SMS кода
  /// Если сервер недоступен, генерирует тестовый код
  Future<bool> sendCode(String phoneNumber) async {
    try {
      // Пытаемся отправить запрос на сервер
      final response = await http.post(
        Uri.parse('$_apiUrl/send-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phoneNumber}),
      ).timeout(const Duration(seconds: 10));
      
      final data = jsonDecode(response.body);
      
      if (data['success'] == true) {
        _lastCode = data['code'] ?? '';
        print('[SmsRuService] Код отправлен: $_lastCode');
        return true;
      } else {
        print('[SmsRuService] Ошибка сервера: ${data['error']}');
        // Если сервер вернул ошибку — генерируем тестовый код
        _generateTestCode();
        return true;
      }
    } catch (e) {
      print('[SmsRuService] Сервер недоступен: $e');
      // Если сервер не отвечает — генерируем тестовый код
      _generateTestCode();
      return true;
    }
  }
  
  /// Генерация тестового кода (когда сервер недоступен)
  void _generateTestCode() {
    _lastCode = (1000 + DateTime.now().millisecondsSinceEpoch % 9000).toString();
    print('[SmsRuService] Тестовый режим. Код: $_lastCode');
  }
  
  /// Проверка введённого кода
  bool verifyCode(String userCode) {
    return userCode == _lastCode;
  }
  
  /// Получить последний сгенерированный код
  String getLastCode() => _lastCode;
  
  /// Сбросить код (при повторной отправке)
  void resetCode() {
    _lastCode = '';
  }
}