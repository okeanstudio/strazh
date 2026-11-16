import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/features/auth/data/services/auth_service.dart';
import 'package:strazh/core/utils/subscription_utils.dart';

class SubscriptionService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static final AuthService _authService = AuthService();

  static Future<Map<String, dynamic>?> getCurrentSubscription() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;

      final metadata = user.userMetadata;
      if (metadata == null) return null;

      return {
        'subscription_type': metadata['subscription_type'] ?? 'free',
        'subscription_expires_at': metadata['subscription_expires_at'],
        'subscription_plan_id': metadata['subscription_plan_id'],
      };
    } catch (e) {
      debugPrint('Ошибка получения подписки: $e');
      return null;
    }
  }

  static Future<bool> isSubscriptionActive() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      final metadata = user.userMetadata;
      return isPremiumSubscriptionActive(metadata);
    } catch (e) {
      debugPrint('Ошибка проверки подписки: $e');
      return false;
    }
  }

  static Future<bool> subscribe({
    required String planId,
    required String planTitle,
    required int priceRub,
    required int priceEnc,
    required String paymentMethod,
    required int durationDays,
  }) async {
    final metadata = _supabase.auth.currentUser?.userMetadata;
    if (isPremiumSubscriptionActive(metadata) &&
        (metadata?['subscription_expires_at']
                    ?.toString()
                    .trim()
                    .toLowerCase() ==
                'forever' ||
            metadata?['subscription_plan_id']
                    ?.toString()
                    .trim()
                    .toLowerCase() ==
                'forever')) {
      throw StateError('У вас уже есть бессрочная подписка Strazh Infinity');
    }

    try {
      if (_authService.currentUserId == null || paymentMethod != 'enc') {
        return false;
      }

      final result = await _supabase.rpc(
        'purchase_subscription_with_encoins',
        params: {'p_plan_id': planId},
      );
      if (result is! Map) {
        throw const FormatException(
          'Некорректный ответ при оформлении подписки',
        );
      }

      try {
        await _supabase.auth.refreshSession();
      } catch (e) {
        debugPrint('Подписка куплена, но сессию обновить не удалось: $e');
      }
      return true;
    } catch (e) {
      debugPrint('Ошибка оформления подписки: $e');
      return false;
    }
  }

  static Future<void> giftSubscription({
    required String roomId,
    required String recipientId,
    required String planId,
  }) async {
    final result = await _supabase.rpc(
      'gift_subscription_with_encoins',
      params: {
        'p_room_id': roomId,
        'p_recipient_id': recipientId,
        'p_plan_id': planId,
      },
    );
    if (result is! Map) {
      throw const FormatException(
        'Некорректный ответ при отправке подарочной подписки',
      );
    }
    try {
      await _supabase.auth.refreshSession();
    } catch (error) {
      debugPrint('Подписка подарена, но сессию обновить не удалось: $error');
    }
  }

  static Future<bool> cancelSubscription() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return false;

      // Обновляем сессию перед обновлением метаданных
      try {
        await _supabase.auth.refreshSession();
      } catch (e) {
        debugPrint('⚠️ Не удалось обновить сессию: $e');
      }

      // Обновляем метаданные в Supabase Auth
      final metadata = _supabase.auth.currentUser?.userMetadata ?? {};
      metadata['subscription_type'] = 'free';
      metadata['subscription_plan_id'] = null;
      metadata['subscription_expires_at'] = null;
      await _supabase.auth.updateUser(UserAttributes(data: metadata));

      return true;
    } catch (e) {
      debugPrint('Ошибка отмены подписки: $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getSubscriptionHistory() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return [];

      final response = await _supabase
          .from('subscriptions_history')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(10);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Ошибка получения истории: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getCurrentPlanInfo() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;

      final metadata = user.userMetadata;
      if (metadata == null) return null;

      final planId = metadata['subscription_plan_id'] as String?;
      if (planId == null) return null;

      final plans = {
        '1m': {'title': '1 месяц', 'duration': 30},
        '3m': {'title': '3 месяца', 'duration': 90},
        '1y': {'title': '1 год', 'duration': 365},
        '2y': {'title': '2 года', 'duration': 730},
      };

      final planInfo = plans[planId] ?? {};
      return {
        'plan_id': planId,
        'title': planInfo['title'],
        'duration': planInfo['duration'],
        'expires_at': metadata['subscription_expires_at'],
      };
    } catch (e) {
      debugPrint('Ошибка получения информации о плане: $e');
      return null;
    }
  }
}
