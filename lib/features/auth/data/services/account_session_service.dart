import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/features/chat/data/services/crypto_service.dart';

class AccountSessionInfo {
  final String userId;
  final String tag;
  final String name;
  final String? email;
  final String? avatarUrl;
  final String accessToken;
  final String refreshToken;

  const AccountSessionInfo({
    required this.userId,
    required this.tag,
    required this.name,
    required this.email,
    required this.avatarUrl,
    required this.accessToken,
    required this.refreshToken,
  });

  factory AccountSessionInfo.fromJson(Map<String, dynamic> json) {
    return AccountSessionInfo(
      userId: json['userId'] as String,
      tag: json['tag'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
    );
  }

  factory AccountSessionInfo.fromSession(Session session) {
    final metadata = session.user.userMetadata ?? const <String, dynamic>{};
    final refreshToken = session.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw StateError('У сессии аккаунта отсутствует refresh token');
    }
    return AccountSessionInfo(
      userId: session.user.id,
      tag: metadata['tag'] as String? ?? '',
      name:
          metadata['name'] as String? ??
          metadata['tag'] as String? ??
          session.user.email ??
          '',
      email: session.user.email,
      avatarUrl: metadata['avatar_url'] as String?,
      accessToken: session.accessToken,
      refreshToken: refreshToken,
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'tag': tag,
    'name': name,
    'email': email,
    'avatarUrl': avatarUrl,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
  };
}

class AccountSessionService {
  static final AccountSessionService _instance =
      AccountSessionService._internal();
  factory AccountSessionService() => _instance;
  AccountSessionService._internal();

  static const _storageKey = 'saved_account_sessions_v1';
  static const _storage = FlutterSecureStorage();

  Future<void> _writeQueue = Future<void>.value();
  StreamSubscription<AuthState>? _authSubscription;
  String? _registeredEncryptionUserId;
  String? _encryptionRegistrationUserId;
  Future<void>? _encryptionRegistration;

  Future<void> initialize() async {
    _authSubscription ??= Supabase.instance.client.auth.onAuthStateChange
        .listen((state) {
          if (state.session != null) {
            unawaited(registerCurrentEncryptionDevice());
            unawaited(
              saveCurrentSession().catchError((Object error, StackTrace stack) {
                debugPrint('Не удалось сохранить сессию аккаунта: $error');
              }),
            );
          }
        });
    await saveCurrentSession();
    await registerCurrentEncryptionDevice();
  }

  Future<void> registerCurrentEncryptionDevice() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId == _registeredEncryptionUserId) return;

    final pendingRegistration = _encryptionRegistration;
    if (pendingRegistration != null &&
        _encryptionRegistrationUserId == userId) {
      await pendingRegistration;
      return;
    }

    final registration = _registerEncryptionDevice(userId);
    _encryptionRegistrationUserId = userId;
    _encryptionRegistration = registration;
    try {
      await registration;
    } finally {
      if (identical(_encryptionRegistration, registration)) {
        _encryptionRegistration = null;
        _encryptionRegistrationUserId = null;
      }
    }
  }

  Future<void> _registerEncryptionDevice(String userId) async {
    try {
      await CryptoService().ensureCurrentDevice();
      if (Supabase.instance.client.auth.currentUser?.id == userId) {
        _registeredEncryptionUserId = userId;
      }
    } catch (error) {
      debugPrint(
        'Вход выполнен, но ключ E2EE устройства не зарегистрирован: $error',
      );
    }
  }

  Future<void> saveCurrentSession() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    final account = AccountSessionInfo.fromSession(session);

    await _serialize(() async {
      final accounts = await _readAccounts();
      final existingIndex = accounts.indexWhere(
        (item) => item.userId == account.userId,
      );
      if (existingIndex == -1) {
        accounts.add(account);
      } else {
        accounts[existingIndex] = account;
      }
      await _writeAccounts(accounts);
    });
  }

  Future<List<AccountSessionInfo>> getAccounts() async {
    await saveCurrentSession();
    return _serialize(_readAccounts);
  }

  Future<void> switchTo(String userId) async {
    final accounts = await _serialize(_readAccounts);
    final account = accounts.where((item) => item.userId == userId).firstOrNull;
    if (account == null) {
      throw StateError('Сохранённая сессия этого аккаунта не найдена');
    }

    final response = await Supabase.instance.client.auth.setSession(
      account.refreshToken,
      accessToken: account.accessToken,
    );
    if (response.session == null) {
      throw StateError('Не удалось восстановить сессию аккаунта');
    }
    await registerCurrentEncryptionDevice();
    await saveCurrentSession();
  }

  Future<void> removeAccount(String userId) async {
    await _serialize(() async {
      final accounts = await _readAccounts();
      accounts.removeWhere((item) => item.userId == userId);
      await _writeAccounts(accounts);
    });
  }

  Future<List<AccountSessionInfo>> _readAccounts() async {
    final value = await _storage.read(key: _storageKey);
    if (value == null || value.isEmpty) return [];

    final decoded = jsonDecode(value);
    if (decoded is! List) {
      throw const FormatException('Некорректное хранилище аккаунтов');
    }

    return decoded.map((entry) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Некорректная запись аккаунта');
      }
      return AccountSessionInfo.fromJson(entry);
    }).toList();
  }

  Future<void> _writeAccounts(List<AccountSessionInfo> accounts) async {
    await _storage.write(
      key: _storageKey,
      value: jsonEncode(accounts.map((account) => account.toJson()).toList()),
    );
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}
