import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/features/auth/data/services/account_session_service.dart';

/// Сервис для входа через Okean ID (SSO).
class OkeanAuthService {
  static const String authorizeUrl = 'https://id.okeanstudio.ru/authorize';
  static const String clientId = 'okean_59c2c5db0776';
  static const String callbackUrl = 'strazh://callback';
  static const String exchangeEndpoint =
      'https://auth-bridge.okeanstudio.ru/okean-exchange';

  static Future<OkeanAuthResult> signInWithOkean() async {
    try {
      final state = _generateState();

      final authUri = Uri.parse(authorizeUrl).replace(
        queryParameters: {
          'client_id': clientId,
          'redirect_uri': callbackUrl,
          'response_type': 'code',
          'state': state,
        },
      );

      debugPrint('🔐 Okean: открываем $authUri');

      final resultUrl = await FlutterWebAuth2.authenticate(
        url: authUri.toString(),
        callbackUrlScheme: 'strazh',
        options: const FlutterWebAuth2Options(preferEphemeral: false),
      );

      debugPrint('🔐 Okean: callback → $resultUrl');

      final callbackUri = Uri.parse(resultUrl);
      final code = callbackUri.queryParameters['code'];
      final returnedState = callbackUri.queryParameters['state'];
      final error = callbackUri.queryParameters['error'];

      if (error != null) {
        return OkeanAuthResult.failure('Okean ID вернул ошибку: $error');
      }
      if (code == null || code.isEmpty) {
        return OkeanAuthResult.failure('Не пришёл code в callback');
      }
      if (returnedState != state) {
        return OkeanAuthResult.failure('State не совпал (возможен CSRF)');
      }

      return await _exchangeCodeForSession(code);
    } catch (e, st) {
      debugPrint('❌ Okean auth failed: $e\n$st');
      return OkeanAuthResult.failure(_humanizeError(e));
    }
  }

  static Future<OkeanAuthResult> _exchangeCodeForSession(String code) async {
    try {
      final resp = await http
          .post(
            Uri.parse(exchangeEndpoint),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'code': code,
              'redirect_uri': callbackUrl,
              'client_id': clientId,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode != 200) {
        debugPrint(
          '❌ Backend exchange failed: ${resp.statusCode} ${resp.body}',
        );
        return OkeanAuthResult.failure(
          'Сервер авторизации ответил ${resp.statusCode}',
        );
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final accessToken = data['access_token'] as String?;
      final refreshToken = data['refresh_token'] as String?;

      if (accessToken == null || refreshToken == null) {
        debugPrint('❌ Backend response missing tokens: $data');
        return OkeanAuthResult.failure('Сервер не вернул токены');
      }

      // setSession принимает refreshToken первым позиционным, accessToken — именованным
      final response = await Supabase.instance.client.auth.setSession(
        refreshToken,
        accessToken: accessToken,
      );

      final session = response.session;
      if (session == null) {
        return OkeanAuthResult.failure('Supabase не создал сессию');
      }

      await AccountSessionService().registerCurrentEncryptionDevice();
      debugPrint('✅ Supabase session установлена: ${session.user.id}');
      return OkeanAuthResult.success(session);
    } on Exception catch (e) {
      debugPrint('❌ _exchangeCodeForSession: $e');
      return OkeanAuthResult.failure('Ошибка соединения с сервером: $e');
    }
  }

  static String _generateState() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(24, (_) => rnd.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _humanizeError(Object e) {
    final s = e.toString();
    if (s.contains('CANCELED') || s.contains('UserCanceled')) {
      return 'Отменено пользователем';
    }
    if (s.contains('SocketException') || s.contains('Failed host lookup')) {
      return 'Нет соединения с интернетом';
    }
    return 'Ошибка: $s';
  }
}

class OkeanAuthResult {
  final bool isSuccess;
  final Session? session;
  final String? errorMessage;

  const OkeanAuthResult._({
    required this.isSuccess,
    this.session,
    this.errorMessage,
  });

  factory OkeanAuthResult.success(Session session) =>
      OkeanAuthResult._(isSuccess: true, session: session);

  factory OkeanAuthResult.failure(String message) =>
      OkeanAuthResult._(isSuccess: false, errorMessage: message);
}
