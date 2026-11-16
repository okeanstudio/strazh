import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/features/auth/data/services/auth_service.dart';

class EncoinsService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static final AuthService _authService = AuthService();

  static Future<int> getBalance() async {
    try {
      try {
        await _supabase.auth.refreshSession();
      } catch (e) {
        debugPrint('Не удалось обновить баланс Encoins из сессии: $e');
      }
      final balance = _supabase.auth.currentUser?.userMetadata?['encoins'];
      return balance is num ? balance.toInt() : 0;
    } catch (e) {
      debugPrint('Ошибка получения баланса Encoins: $e');
      return 0;
    }
  }

  static Future<int> grantEncoins({
    required String userId,
    required int amount,
    required String description,
  }) async {
    final result = await _supabase.rpc(
      'grant_encoins',
      params: {
        'p_user_id': userId,
        'p_amount': amount,
        'p_description': description,
      },
    );
    if (result is! num) {
      throw const FormatException('Некорректный ответ при выдаче Encoins');
    }
    return result.toInt();
  }

  static Future<int> withdrawEncoins({
    required String userId,
    required int amount,
    required String description,
  }) async {
    final result = await _supabase.rpc(
      'withdraw_encoins_admin',
      params: {
        'p_user_id': userId,
        'p_amount': amount,
        'p_description': description,
      },
    );
    if (result is! num) {
      throw const FormatException('Некорректный ответ при списании Encoins');
    }
    return result.toInt();
  }

  static Future<List<Map<String, dynamic>>> getAdminBalances() async {
    final response = await _supabase.rpc('get_encoins_admin_users');
    if (response is! List) {
      throw const FormatException('Некорректный список балансов Encoins');
    }
    return response
        .whereType<Map>()
        .map((user) => Map<String, dynamic>.from(user))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> getAdminTransactions() async {
    final response = await _supabase.rpc('get_encoins_admin_transactions');
    if (response is! List) {
      throw const FormatException('Некорректная история операций Encoins');
    }
    return response
        .whereType<Map>()
        .map((transaction) => Map<String, dynamic>.from(transaction))
        .toList();
  }

  static Future<bool> spendEncoins(
    int amount, {
    String description = 'Списание',
  }) async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return false;

      await _supabase.rpc(
        'spend_encoins',
        params: {'p_amount': amount, 'p_description': description},
      );
      return true;
    } catch (e) {
      debugPrint('Ошибка списания Encoins: $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getTransactions({
    int limit = 20,
  }) async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return [];

      final response = await _supabase
          .from('encoins_transactions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Ошибка получения истории Encoins: $e');
      return [];
    }
  }
}
