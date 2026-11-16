import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/core/config/app_config.dart';
import 'package:strazh/core/services/http_client_config.dart';

class SupabaseInitializer {
  /// Инициализирует Supabase с диагностикой проблем
  static Future<void> initialize() async {
    try {
      debugPrint('🔧 Инициализация Supabase...');
      debugPrint('   URL: ${AppConfig.supabaseUrl}');
      
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseAnonKey,
        authOptions: FlutterAuthClientOptions(
          autoRefreshToken: !kIsWeb,
          detectSessionInUri: !kIsWeb,
        ),
      );
      
      debugPrint('✅ Supabase инициализирован успешно');
      
      // Диагностика Storage
      try {
        final client = Supabase.instance.client;
        debugPrint('📦 Supabase Storage API: ${client.storage.runtimeType}');
      } catch (e) {
        debugPrint('⚠️ Не удалось получить информацию о Storage: $e');
      }
    } catch (e) {
      debugPrint('❌ Ошибка инициализации Supabase: $e');
      rethrow;
    }
  }
}
