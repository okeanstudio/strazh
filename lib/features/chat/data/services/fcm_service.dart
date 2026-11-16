import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/core/config/firebase_options.dart';
import 'package:strazh/core/services/supabase_initializer.dart';
import 'package:strazh/features/chat/data/services/notification_service.dart';
import 'package:strazh/features/settings/data/services/sound_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('Получено фоновое уведомление: ${message.messageId}');
  try {
    await SupabaseInitializer.initialize();
  } catch (error) {
    debugPrint('Не удалось инициализировать Supabase для push: $error');
  }
  await NotificationService().showPushNotification(message);
}

class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<AuthState>? _authStateSubscription;
  String? _registeredUserId;

  Future<void> initialize() async {
    if (!_isMobilePlatform) return;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    if (!SoundService().settings.value.notificationsEnabled) {
      await setNotificationsEnabled(false);
      return;
    }

    if (await _enableNotifications()) {
      _listenForAuthChanges();
    }
  }

  Future<bool> setNotificationsEnabled(bool enabled) async {
    if (!_isMobilePlatform) return true;

    try {
      if (!enabled) {
        String? token;
        try {
          token = await _messaging.getToken();
        } catch (error) {
          debugPrint(
            'Не удалось прочитать FCM-токен перед отключением: $error',
          );
        }
        await _messaging.setAutoInitEnabled(false);
        final userId =
            Supabase.instance.client.auth.currentUser?.id ?? _registeredUserId;
        if (token != null && userId != null) {
          await _deleteTokenFromSupabase(token, userId);
        }
        _registeredUserId = null;
        await _authStateSubscription?.cancel();
        _authStateSubscription = null;
        await _tokenRefreshSubscription?.cancel();
        _tokenRefreshSubscription = null;
        await _messaging.deleteToken();
        return true;
      }

      await _messaging.setAutoInitEnabled(true);
      final notificationsEnabled = await _enableNotifications();
      if (notificationsEnabled) _listenForAuthChanges();
      return notificationsEnabled;
    } catch (error) {
      debugPrint('Не удалось изменить доставку уведомлений: $error');
      return false;
    }
  }

  bool get _isMobilePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<bool> _enableNotifications() async {
    final permission = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final isAuthorized =
        permission.authorizationStatus == AuthorizationStatus.authorized ||
        permission.authorizationStatus == AuthorizationStatus.provisional;
    if (!isAuthorized) return false;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      String? apnsToken;
      for (var attempt = 0; attempt < 10 && apnsToken == null; attempt++) {
        apnsToken = await _messaging.getAPNSToken();
        if (apnsToken == null) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
      if (apnsToken == null) {
        debugPrint('APNs-токен пока недоступен, FCM инициализация отложена');
        return false;
      }
    }

    final token = await _messaging.getToken();
    if (token != null) await _saveTokenToSupabase(token);

    _tokenRefreshSubscription ??= _messaging.onTokenRefresh.listen(
      _saveTokenToSupabase,
      onError: (Object error) {
        debugPrint('Ошибка обновления FCM-токена: $error');
      },
    );
    return true;
  }

  void _listenForAuthChanges() {
    if (_authStateSubscription != null) return;

    _authStateSubscription = Supabase.instance.client.auth.onAuthStateChange
        .listen(
          (authState) async {
            final userId = authState.session?.user.id;
            if (userId == null) {
              final previousUserId = _registeredUserId;
              _registeredUserId = null;
              try {
                final preferences = await SharedPreferences.getInstance();
                await preferences.remove(_registeredUserPreferenceKey);
              } catch (error) {
                debugPrint('Не удалось очистить локальный FCM user ID: $error');
              }
              if (previousUserId == null) return;

              try {
                final token = await _messaging.getToken();
                if (token != null) {
                  await _deleteTokenFromSupabase(token, previousUserId);
                }
              } catch (error) {
                debugPrint('Не удалось удалить FCM-токен после выхода: $error');
              }
              return;
            }

            final previousUserId = _registeredUserId;
            if (previousUserId != null && previousUserId != userId) {
              try {
                final token = await _messaging.getToken();
                if (token != null) {
                  await _deleteTokenFromSupabase(token, previousUserId);
                }
              } catch (error) {
                debugPrint('Не удалось обновить владельца FCM-токена: $error');
              }
            }

            try {
              final token = await _messaging.getToken();
              if (token != null) await _saveTokenToSupabase(token);
            } catch (error) {
              debugPrint('Не удалось обновить FCM-токен после входа: $error');
            }
          },
          onError: (Object error) {
            debugPrint('Ошибка отслеживания сессии для FCM: $error');
          },
        );
  }

  Future<void> _saveTokenToSupabase(String token) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      await Supabase.instance.client.from('user_devices').upsert({
        'user_id': userId,
        'fcm_token': token,
        'platform': 'mobile',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'fcm_token');
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_registeredUserPreferenceKey, userId);
      _registeredUserId = userId;
    } catch (e) {
      debugPrint('Ошибка сохранения токена: $e');
    }
  }

  Future<void> _deleteTokenFromSupabase(String token, String userId) async {
    try {
      await Supabase.instance.client
          .from('user_devices')
          .delete()
          .eq('user_id', userId)
          .eq('fcm_token', token);
    } catch (error) {
      debugPrint('Не удалось удалить FCM-токен из профиля: $error');
    }
  }

  static const String _registeredUserPreferenceKey = 'fcm_registered_user_id';
}
