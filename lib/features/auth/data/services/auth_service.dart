
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/features/auth/data/services/account_session_service.dart';
import 'package:strazh/shared/domain/models/user.dart' as app;
import 'package:strazh/core/utils/rpc_user.dart';

class AuthService {
  // ========== РАБОТА С ХРАНИЛИЩЕМ ==========
  static Future<String?> _readStorage(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } else {
      const storage = FlutterSecureStorage();
      return await storage.read(key: key);
    }
  }

  static Future<void> _writeStorage(String key, String value) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } else {
      const storage = FlutterSecureStorage();
      await storage.write(key: key, value: value);
    }
  }

  static Future<void> _deleteStorage(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } else {
      const storage = FlutterSecureStorage();
      await storage.delete(key: key);
    }
  }

  // ========== ПОЛУЧЕНИЕ ПОЛЬЗОВАТЕЛЯ ==========
  User? getCurrentUser() {
    try {
      return Supabase.instance.client.auth.currentUser;
    } catch (e) {
      debugPrint('❌ Ошибка получения пользователя: $e');
      return null;
    }
  }

  String? get currentUserId => getCurrentUser()?.id;

  // ========== ПОЛУЧЕНИЕ ПОЛЬЗОВАТЕЛЯ ИЗ МЕТАДАННЫХ ==========
  app.User? getCurrentUserFromMetadata() {
    final user = getCurrentUser();
    if (user == null) return null;

    final metadata = user.userMetadata;
    if (metadata == null) return null;

    return app.User(
      id: user.id,
      tag: metadata['tag'] ?? '',
      name: metadata['name'] ?? metadata['tag'] ?? 'Без имени',
      email: user.email,
      phone: metadata['phone'] ?? '',
      avatarUrl: metadata['avatar_url'],
      status: metadata['status'] ?? 'offline',
      role: metadata['role'] ?? 'user',
      birthDate: metadata['birth_date'] != null
          ? DateTime.tryParse(metadata['birth_date'])
          : null,
      inviteCode: metadata['invite_code'],
      invitedByUserId: metadata['invited_by_user_id'],
      emailVerified: user.emailConfirmedAt != null,
    );
  }

  Map<String, dynamic>? getUserMetadata() {
    final user = getCurrentUser();
    return user?.userMetadata;
  }

  T? getMetadataField<T>(String key) {
    final metadata = getUserMetadata();
    return metadata?[key] as T?;
  }

  String? getUserTag() => getMetadataField<String>('tag');
  String? getUserName() => getMetadataField<String>('name');
  String? getUserStatus() => getMetadataField<String>('status');
  String? getAvatarUrl() => getMetadataField<String>('avatar_url');
  String? getInviteCode() => getMetadataField<String>('invite_code');
  String? getUserRole() => getMetadataField<String>('role');
  String? getUserBio() => getMetadataField<String>('bio');
  String? getUserPhone() => getMetadataField<String>('phone');

  // ========== ОБНОВЛЕНИЕ МЕТАДАННЫХ ==========
  Future<void> updateUserMetadata(Map<String, dynamic> metadata) async {
    try {
      try {
        await Supabase.instance.client.auth.refreshSession();
      } catch (e) {
        debugPrint('⚠️ Не удалось обновить сессию: $e');
      }

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: metadata),
      );
      debugPrint('✅ Метаданные обновлены: $metadata');
    } catch (e) {
      debugPrint('❌ Ошибка обновления метаданных: $e');
      rethrow;
    }
  }

  // ========== ОБНОВЛЕНИЕ ТЕЛЕФОНА ==========
  Future<void> updateUserPhone(String phone) async {
    try {
      final user = getCurrentUser();
      if (user == null) return;

      final metadata = user.userMetadata ?? {};
      metadata['phone'] = phone;

      await updateUserMetadata(metadata);
      debugPrint('✅ Телефон обновлен: $phone');
    } catch (e) {
      debugPrint('❌ Ошибка обновления телефона: $e');
      rethrow;
    }
  }

  // ========== ОБНОВЛЕНИЕ СТАТУСА ==========
  Future<void> setUserStatus(String status) async {
    try {
      final userId = currentUserId;
      if (userId == null) return;

      // ❗ Идём через RPC, который обновит ТОЛЬКО status и last_seen
      await Supabase.instance.client.rpc(
        'set_user_status',
        params: {'p_status': status},
      );
      debugPrint('✅ Статус пользователя обновлён: $status');
    } catch (e) {
      debugPrint('❌ Ошибка обновления статуса: $e');
    }
  }

  Future<void> setUserOnline() async => setUserStatus('online');
  Future<void> setUserOffline() async => setUserStatus('offline');

  // ========== ПОЛУЧЕНИЕ СЕССИИ ==========
  Future<Session?> getSession() async {
    try {
      return Supabase.instance.client.auth.currentSession;
    } catch (e) {
      debugPrint('❌ Ошибка получения сессии: $e');
      return null;
    }
  }

  Future<bool> isAuthenticated() async {
    try {
      final session = await getSession();
      return session != null;
    } catch (e) {
      return false;
    }
  }

  // ========== ВХОД ==========
  Future<Session?> signInWithEmail(String email, String password) async {
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        throw Exception('Сессия не была создана после входа');
      }

      await AccountSessionService().registerCurrentEncryptionDevice();
      debugPrint('✅ Вход выполнен через Supabase Auth');
      await _writeStorage('is_logged_in', 'true');
      return session;
    } catch (e) {
      debugPrint('❌ Ошибка входа: $e');
      rethrow;
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final client = Supabase.instance.client;
    final email = client.auth.currentUser?.email;
    if (email == null || email.isEmpty) {
      throw StateError('У аккаунта не указан адрес электронной почты');
    }

    await client.auth.signInWithPassword(
      email: email,
      password: currentPassword,
    );
    await client.auth.updateUser(UserAttributes(password: newPassword));
  }

  // ========== РЕГИСТРАЦИЯ ==========
  Future<Session?> signUpWithEmail({
    required String email,
    required String password,
    required String tag,
    required String name,
    String? phone,
    String? inviteCode,
    String? invitedByCode,
  }) async {
    try {
      final metadata = {
        'tag': tag,
        'name': name,
        'status': 'offline',
        'avatar_url': null,
        'invite_code': inviteCode,
        'invited_by_code': invitedByCode,
        'bio': null,
        'last_seen': null,
        'role': 'user',
        'phone': phone,
      };

      await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: metadata,
      );

      debugPrint('✅ Пользователь зарегистрирован: $email');

      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        throw Exception('Сессия не была создана');
      }

      await AccountSessionService().registerCurrentEncryptionDevice();
      await _writeStorage('is_logged_in', 'true');
      return session;
    } catch (e) {
      debugPrint('❌ Ошибка регистрации: $e');
      rethrow;
    }
  }

  // ========== ВЫХОД ==========
  Future<void> logout() async {
    final currentUserId = getCurrentUser()?.id;
    if (currentUserId != null) {
      await AccountSessionService().removeAccount(currentUserId);
    }
    await setUserOffline();

    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      debugPrint('❌ Ошибка выхода из Supabase: $e');
    }

    await _deleteStorage('user_tag');
    await _deleteStorage('user_id');
    await _deleteStorage('is_logged_in');

    debugPrint('✅ Выход выполнен');
  }

  Future<bool> isLoggedIn() async {
    final isLoggedIn = await _readStorage('is_logged_in');
    return isLoggedIn == 'true';
  }

  Future<bool> restoreSession() async {
    try {
      final session = await getSession();
      if (session != null) {
        debugPrint('✅ Сессия восстановлена: ${session.user.id}');
        return true;
      }

      if (kIsWeb) {
        debugPrint('ℹ️ Пропускаем refreshSession в web-сборке');
        return false;
      }

      try {
        await Supabase.instance.client.auth.refreshSession();
        debugPrint('✅ Сессия обновлена');
        return true;
      } catch (e) {
        debugPrint('❌ Не удалось обновить сессию: $e');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Ошибка восстановления сессии: $e');
      return false;
    }
  }

  // ========== ✅ ДОБАВЛЕНО: OAuth-сессия от backend-моста ==========
  //
  // Метод для случая, когда backend-мост передаёт access_token и refresh_token
  // напрямую (не через OkeanAuthService). Пока не используется, но может
  // пригодиться, если захочешь делать refresh вручную или переиспользовать
  // логику в других местах.
  //
  // Если используешь — после вызова не забудь вызвать saveUser(...),
  // иначе SplashScreen не увидит флаг is_logged_in.
  // ========== ✅ OAuth-сессия от backend-моста ==========
  // ========== ✅ OAuth-сессия от backend-моста ==========
  // ========== ✅ OAuth-сессия от backend-моста ==========
  // ========== OAuth-сессия от backend-моста ==========
  Future<Session?> signInWithBackendSession({
    required String accessToken,
    required String refreshToken,
  }) async {
    try {
      final response = await Supabase.instance.client.auth.setSession(
        refreshToken,
        accessToken: accessToken,
      );
      final session = response.session;
      if (session == null) {
        throw StateError('Supabase не создал сессию');
      }
      await AccountSessionService().registerCurrentEncryptionDevice();
      await _writeStorage('is_logged_in', 'true');
      debugPrint('✅ Backend-сессия установлена: ${session.user.id}');
      return session;
    } catch (e) {
      debugPrint('❌ Ошибка установки backend-сессии: $e');
      rethrow;
    }
  }
  // ========== ✅ КОНЕЦ ДОБАВЛЕННОГО ==========

  // ========== RPC ФУНКЦИИ (ИСПРАВЛЕНЫ) ==========

  Future<Map<String, dynamic>?> getUserByTag(String tag) async {
    try {
      final response = await Supabase.instance.client.rpc(
        'get_user_by_tag_ci',
        params: {'p_tag': tag},
      );
      // ✅ ИСПРАВЛЕНО: проверяем, что response - это Map
      return rpcUserRecord(response);
    } catch (e) {
      debugPrint('❌ Ошибка поиска пользователя по тегу: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getUserById(String userId) async {
    try {
      final response = await Supabase.instance.client.rpc(
        'get_user_by_id',
        params: {'p_id': userId},
      );
      return rpcUserRecord(response);
    } catch (e) {
      debugPrint('❌ Ошибка поиска пользователя по ID: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final normalizedQuery = query.trim().replaceFirst(RegExp(r'^@'), '');
    if (normalizedQuery.isEmpty) return [];

    try {
      final response = await Supabase.instance.client.rpc(
        'search_users_by_query',
        params: {'p_query': normalizedQuery},
      );
      final users = <String, Map<String, dynamic>>{};
      if (response is List) {
        for (final record in response) {
          final user = rpcUserRecord(record);
          final id = user?['id']?.toString();
          if (user != null && id != null) users[id] = user;
        }
      }

      final additionalUsernameResponse = await Supabase.instance.client.rpc(
        'search_users_by_additional_username',
        params: {'p_query': normalizedQuery},
      );
      if (additionalUsernameResponse is List) {
        for (final record in additionalUsernameResponse) {
          final user = rpcUserRecord(record);
          final id = user?['id']?.toString();
          if (user != null && id != null) {
            users[id] = {
              ...?users[id],
              ...user,
              'matched_username': user['matched_username'],
            };
          }
        }
      }

      return users.values.where((user) {
        final tag = user['tag']?.toString().toLowerCase();
        final matchedUsername = user['matched_username']
            ?.toString()
            .toLowerCase();
        return (tag != null && tag.contains(normalizedQuery.toLowerCase())) ||
            (matchedUsername != null &&
                matchedUsername.contains(normalizedQuery.toLowerCase()));
      }).toList();
    } catch (e) {
      debugPrint('❌ Ошибка поиска пользователей: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    try {
      final response = await Supabase.instance.client.rpc('get_all_users');
      if (response is List) {
        return response
            .map(rpcUserRecord)
            .whereType<Map<String, dynamic>>()
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('❌ Ошибка получения всех пользователей: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> getUserByInviteCode(String code) async {
    try {
      final response = await Supabase.instance.client.rpc(
        'get_user_by_invite_code',
        params: {'p_code': code},
      );
      if (response is Map<String, dynamic>) {
        return response;
      }
      return null;
    } catch (e) {
      debugPrint('❌ Ошибка поиска по инвайт-коду: $e');
      return null;
    }
  }

  Future<bool> isTagTaken(String tag) async {
    final user = await getUserByTag(tag);
    return user != null;
  }

  Future<bool> isInviteCodeValid(String code) async {
    final user = await getUserByInviteCode(code);
    return user != null;
  }

  Future<void> saveUser(String tag, String userId) async {
    await _writeStorage('user_tag', tag);
    await _writeStorage('user_id', userId);
    await _writeStorage('is_logged_in', 'true');
    await AccountSessionService().saveCurrentSession();
    await setUserOnline();
  }

  String? get currentUserTag => getMetadataField<String>('tag');

  // ========== ПРОВЕРКА EMAIL ==========
  Future<void> resendEmailConfirmation(String email) async {
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: email,
      );
      debugPrint('✅ Письмо с подтверждением отправлено на $email');
    } catch (e) {
      debugPrint('❌ Ошибка отправки письма: $e');
      rethrow;
    }
  }

  Future<bool> isEmailVerified() async {
    final user = getCurrentUser();
    return user?.emailConfirmedAt != null;
  }
}
