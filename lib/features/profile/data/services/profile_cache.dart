import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ProfileCache {
  ProfileCache._();

  static final ProfileCache instance = ProfileCache._();

  static const _keyPrefix = 'profile_cache_v1_';
  static const _storage = FlutterSecureStorage();

  Future<Map<String, dynamic>?> read(String userId) async {
    final value = await _storage.read(key: '$_keyPrefix$userId');
    if (value == null) return null;

    final decoded = jsonDecode(value);
    if (decoded is! Map) {
      throw const FormatException('Некорректный кэш профиля');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> write(String userId, Map<String, dynamic> profile) {
    return _storage.write(
      key: '$_keyPrefix$userId',
      value: jsonEncode(profile),
    );
  }
}
