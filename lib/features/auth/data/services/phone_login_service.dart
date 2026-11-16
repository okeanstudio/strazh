import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/features/auth/data/services/account_session_service.dart';

class PhoneLoginService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<String> requestCode(String phoneNumber) async {
    final requestId = await _client.rpc(
      'request_phone_login_message',
      params: {'p_phone_number': phoneNumber},
    );
    if (requestId is! String) {
      throw const FormatException('Сервер вернул некорректный запрос входа');
    }
    return requestId;
  }

  Future<AuthResponse> verifyCode({
    required String requestId,
    required String code,
  }) async {
    final response = await _client.functions.invoke(
      'verify-phone-login',
      body: {'requestId': requestId, 'code': code},
    );
    final data = _asMap(response.data);
    if (response.status < 200 || response.status >= 300) {
      throw StateError(
        data['error']?.toString() ?? 'Неверный или просроченный код',
      );
    }
    final email = data['email'];
    final emailOtp = data['emailOtp'];
    if (email is! String || emailOtp is! String || emailOtp.isEmpty) {
      throw const FormatException('Сервер вернул некорректное подтверждение');
    }
    final authResponse = await _client.auth.verifyOTP(
      email: email,
      token: emailOtp,
      type: OtpType.magiclink,
    );
    if (authResponse.session != null) {
      await AccountSessionService().registerCurrentEncryptionDevice();
    }
    return authResponse;
  }

  Future<List<Map<String, dynamic>>> getRecentRequests() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Необходимо войти в аккаунт для просмотра кодов');
    }

    final response = await _client
        .from('phone_login_challenges')
        .select(
          'id, phone_number, login_code, created_at, expires_at, seen_at, consumed_at',
        )
        .eq('user_id', userId)
        .order('created_at', ascending: true)
        .limit(50);
    return response.map((request) {
      final result = Map<String, dynamic>.from(request);
      result['login_code'] ??= '';
      return result;
    }).toList();
  }

  Future<void> markRequestsSeen() async {
    await _client.rpc('mark_phone_login_challenges_seen');
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const FormatException('Сервер вернул некорректный ответ');
  }
}
