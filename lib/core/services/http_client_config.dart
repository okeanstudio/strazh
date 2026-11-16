import 'dart:io';
import 'package:flutter/foundation.dart';

class HttpClientConfig {
  /// Настраивает HttpClient для работы с Supabase
  /// с диагностикой проблем с сертификатами
  static HttpClient createHttpClient() {
    final httpClient = HttpClient();
    
    // Настройка для обработки сертификатов
    httpClient.badCertificateCallback = (cert, host, port) {
      debugPrint('🔒 Проверка сертификата:');
      debugPrint('   Host: $host:$port');
      debugPrint('   Subject: ${cert.subject}');
      debugPrint('   Issuer: ${cert.issuer}');
      
      // Для Supabase доменов
      if (host.contains('strazh.chat') || host.contains('supabase.co')) {
        debugPrint('✅ Сертификат для Supabase домена разрешен');
        return true;
      }
      
      debugPrint('❌ Сертификат отклонен для домена: $host');
      return false;
    };
    
    return httpClient;
  }
}
