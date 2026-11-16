import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatListPreferences {
  ChatListPreferences._({
    required this.userId,
    required SharedPreferences preferences,
    required this.pinnedChatIds,
    required this.archivedChatIds,
    required this.mutedChatIds,
    required this.folderNames,
    required this.folderByChatId,
    required bool syncToCloud,
  }) : _preferences = preferences,
       _syncToCloud = syncToCloud;

  static const _currentUserKey = 'chat_list_preferences_current_user';

  final String userId;
  final SharedPreferences _preferences;
  final Set<String> pinnedChatIds;
  final Set<String> archivedChatIds;
  final Set<String> mutedChatIds;
  final Set<String> folderNames;
  final Map<String, String> folderByChatId;
  final bool _syncToCloud;

  static Future<ChatListPreferences?> load(
    String? userId, {
    bool synchronize = true,
  }) async {
    if (userId == null || userId.isEmpty) return null;

    final preferences = await SharedPreferences.getInstance();
    await _writeString(preferences, _currentUserKey, userId);

    var pinnedChatIds = _readSet(preferences, _key(userId, 'pinned'));
    var archivedChatIds = _readSet(preferences, _key(userId, 'archived'));
    var mutedChatIds = _readSet(preferences, _key(userId, 'muted'));
    var folderNames = _readSet(preferences, _key(userId, 'folders'));
    var folderByChatId = _readFolderAssignments(
      preferences,
      _key(userId, 'folder_assignments'),
    );
    var syncToCloud = false;
    if (synchronize) {
      try {
        final rows = await Supabase.instance.client
            .from('chat_user_settings')
            .select('room_id, is_pinned, is_archived, is_muted, folder_name')
            .eq('user_id', userId);
        final folders = await Supabase.instance.client
            .from('chat_list_folders')
            .select('name')
            .eq('user_id', userId);
        pinnedChatIds = _readRemoteSet(rows, 'is_pinned');
        archivedChatIds = _readRemoteSet(rows, 'is_archived');
        mutedChatIds = _readRemoteSet(rows, 'is_muted');
        folderNames = folders.map((row) => row['name'] as String).toSet();
        folderByChatId = {
          for (final row in rows)
            if (row['folder_name'] is String)
              row['room_id'] as String: row['folder_name'] as String,
        };
        syncToCloud = true;
        await _writeList(preferences, _key(userId, 'pinned'), pinnedChatIds);
        await _writeList(
          preferences,
          _key(userId, 'archived'),
          archivedChatIds,
        );
        await _writeList(preferences, _key(userId, 'muted'), mutedChatIds);
        await _writeList(preferences, _key(userId, 'folders'), folderNames);
        await _writeFolderAssignments(
          preferences,
          _key(userId, 'folder_assignments'),
          folderByChatId,
        );
      } catch (error) {
        debugPrint(
          'Не удалось синхронизировать настройки чатов; используются локальные: '
          '$error',
        );
      }
    }

    return ChatListPreferences._(
      userId: userId,
      preferences: preferences,
      pinnedChatIds: pinnedChatIds,
      archivedChatIds: archivedChatIds,
      mutedChatIds: mutedChatIds,
      folderNames: folderNames,
      folderByChatId: folderByChatId,
      syncToCloud: syncToCloud,
    );
  }

  static Future<bool> isMutedForCurrentUser(String chatId) async {
    final preferences = await SharedPreferences.getInstance();
    final userId = preferences.getString(_currentUserKey);
    if (userId == null || userId.isEmpty) return false;
    return preferences.getStringList(_key(userId, 'muted'))?.contains(chatId) ??
        false;
  }

  static Set<String> _readSet(SharedPreferences preferences, String key) {
    return (preferences.getStringList(key) ?? const <String>[]).toSet();
  }

  static Map<String, String> _readFolderAssignments(
    SharedPreferences preferences,
    String key,
  ) {
    final value = preferences.getString(key);
    if (value == null) return {};
    try {
      return (jsonDecode(value) as Map<String, dynamic>).map(
        (chatId, folder) => MapEntry(chatId, folder as String),
      );
    } on FormatException catch (error) {
      debugPrint('Не удалось прочитать локальные папки чатов: $error');
      return {};
    } on TypeError catch (error) {
      debugPrint('Некорректный формат локальных папок чатов: $error');
      return {};
    }
  }

  static Set<String> _readRemoteSet(List<dynamic> rows, String setting) {
    return rows
        .where((row) => row[setting] == true)
        .map((row) => row['room_id'] as String)
        .toSet();
  }

  static String _key(String userId, String setting) =>
      'chat_list_${userId}_$setting';

  Future<void> setPinned(String chatId, bool value) =>
      _update('pinned', pinnedChatIds, _key(userId, 'pinned'), chatId, value);

  Future<void> setArchived(String chatId, bool value) => _update(
    'archived',
    archivedChatIds,
    _key(userId, 'archived'),
    chatId,
    value,
  );

  Future<void> setMuted(String chatId, bool value) =>
      _update('muted', mutedChatIds, _key(userId, 'muted'), chatId, value);

  Future<void> createFolder(String name) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty || normalizedName.length > 32) {
      throw ArgumentError(
        'Название папки должно содержать от 1 до 32 символов',
      );
    }
    if (folderNames.any(
      (folder) => folder.toLowerCase() == normalizedName.toLowerCase(),
    )) {
      throw StateError('Папка с таким названием уже существует');
    }

    if (_syncToCloud) {
      await Supabase.instance.client.from('chat_list_folders').insert({
        'user_id': userId,
        'name': normalizedName,
      });
    }

    folderNames.add(normalizedName);
    await _writeList(_preferences, _key(userId, 'folders'), folderNames);
  }

  Future<void> deleteFolder(String name) async {
    if (_syncToCloud) {
      await Supabase.instance.client
          .from('chat_user_settings')
          .update({'folder_name': null})
          .eq('user_id', userId)
          .eq('folder_name', name);
      await Supabase.instance.client
          .from('chat_list_folders')
          .delete()
          .eq('user_id', userId)
          .eq('name', name);
    }

    folderNames.remove(name);
    folderByChatId.removeWhere((_, folder) => folder == name);
    await _writeList(_preferences, _key(userId, 'folders'), folderNames);
    await _writeFolderAssignments(
      _preferences,
      _key(userId, 'folder_assignments'),
      folderByChatId,
    );
  }

  Future<void> setChatFolder(String chatId, String? folderName) async {
    if (folderName != null && !folderNames.contains(folderName)) {
      throw StateError('Папка больше не существует');
    }

    if (_syncToCloud) {
      final existing = {
        'user_id': userId,
        'room_id': chatId,
        'is_pinned': pinnedChatIds.contains(chatId),
        'is_archived': archivedChatIds.contains(chatId),
        'is_muted': mutedChatIds.contains(chatId),
        'folder_name': folderName,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      await Supabase.instance.client
          .from('chat_user_settings')
          .upsert(existing, onConflict: 'user_id,room_id');
    }

    if (folderName == null) {
      folderByChatId.remove(chatId);
    } else {
      folderByChatId[chatId] = folderName;
    }
    await _writeFolderAssignments(
      _preferences,
      _key(userId, 'folder_assignments'),
      folderByChatId,
    );
  }

  Future<void> _update(
    String setting,
    Set<String> target,
    String key,
    String chatId,
    bool value,
  ) async {
    final updated = Set<String>.from(target);
    if (value) {
      updated.add(chatId);
    } else {
      updated.remove(chatId);
    }

    if (_syncToCloud) {
      final pinned = setting == 'pinned' ? updated : pinnedChatIds;
      final archived = setting == 'archived' ? updated : archivedChatIds;
      final muted = setting == 'muted' ? updated : mutedChatIds;
      await Supabase.instance.client.from('chat_user_settings').upsert({
        'user_id': userId,
        'room_id': chatId,
        'is_pinned': pinned.contains(chatId),
        'is_archived': archived.contains(chatId),
        'is_muted': muted.contains(chatId),
        'folder_name': folderByChatId[chatId],
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,room_id');
    }

    final saved = await _preferences.setStringList(key, updated.toList());
    if (!saved) throw StateError('Не удалось сохранить настройки списка чатов');

    target
      ..clear()
      ..addAll(updated);
  }

  static Future<void> _writeString(
    SharedPreferences preferences,
    String key,
    String value,
  ) async {
    final saved = await preferences.setString(key, value);
    if (!saved) throw StateError('Не удалось сохранить пользователя настроек');
  }

  static Future<void> _writeList(
    SharedPreferences preferences,
    String key,
    Set<String> value,
  ) async {
    final saved = await preferences.setStringList(key, value.toList());
    if (!saved) throw StateError('Не удалось сохранить настройки чатов');
  }

  static Future<void> _writeFolderAssignments(
    SharedPreferences preferences,
    String key,
    Map<String, String> value,
  ) async {
    final saved = await preferences.setString(key, jsonEncode(value));
    if (!saved) throw StateError('Не удалось сохранить папки чатов');
  }
}
