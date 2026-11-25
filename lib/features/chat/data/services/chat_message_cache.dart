import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strazh/shared/domain/models/message.dart';

class ChatMessageCache {
  ChatMessageCache._();

  static final ChatMessageCache instance = ChatMessageCache._();

  static const _preferenceKey = 'chat_message_cache_limit_bytes_v1';
  static const _storageKeyPrefix = 'chat_message_cache_key_v1_';
  static const _defaultLimitBytes = 1024 * 1024 * 1024;
  static const _targetAfterCleanup = 0.8;
  static const _storage = FlutterSecureStorage();
  static final _cipher = AesGcm.with256bits();
  static final _random = Random.secure();

  Future<void> _queue = Future<void>.value();

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<List<Message>> loadMessages({
    required String userId,
    required String roomId,
  }) {
    return _serialize(() async {
      final file = await _chatFile(userId, roomId);
      if (!await file.exists()) return <Message>[];
      final messages = await _readFile(file, userId);
      await file.setLastModified(DateTime.now());
      return messages;
    });
  }

  Future<void> saveMessages({
    required String userId,
    required String roomId,
    required List<Message> messages,
  }) {
    return _serialize(() async {
      final file = await _chatFile(userId, roomId);
      final existing = await file.exists()
          ? await _readFile(file, userId)
          : <Message>[];
      final mergedById = <String, Message>{
        for (final message in existing)
          if (!message.viewOnce && !message.isDeleted) message.id: message,
      };
      for (final message in messages) {
        if (message.viewOnce || message.id.startsWith('temp_')) continue;
        if (message.isDeleted) {
          mergedById.remove(message.id);
        } else {
          mergedById[message.id] = message;
        }
      }
      final merged = mergedById.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      if (merged.isEmpty) {
        if (await file.exists()) await file.delete();
        return;
      }

      await _writeFile(file, userId, merged);
      await _enforceLimit(userId);
    });
  }

  Future<int> getSizeBytes({required String userId}) {
    return _serialize(() async {
      final files = await _cacheFiles(userId);
      var total = 0;
      for (final file in files) {
        total += await file.length();
      }
      return total;
    });
  }

  Future<int> getLimitBytes() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getInt(_preferenceKey) ?? _defaultLimitBytes;
  }

  Future<void> setLimitBytes({
    required String userId,
    required int bytes,
  }) async {
    if (bytes <= 0) throw ArgumentError.value(bytes, 'bytes');
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_preferenceKey, bytes);
    await _serialize(() => _enforceLimit(userId));
  }

  Future<void> clear({required String userId}) {
    return _serialize(() async {
      final directory = await _userDirectory(userId);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      await directory.create(recursive: true);
      await _storage.delete(key: '$_storageKeyPrefix$userId');
    });
  }

  Future<void> _enforceLimit(String userId) async {
    final limit = await getLimitBytes();
    final files = await _cacheFiles(userId);
    var totalBytes = 0;
    for (final file in files) {
      totalBytes += await file.length();
    }
    if (totalBytes <= limit) return;

    final targetBytes = (limit * _targetAfterCleanup).round();
    final fileDates = await Future.wait(
      files.map((file) async => MapEntry(file, await file.lastModified())),
    );
    fileDates.sort((first, second) => first.value.compareTo(second.value));

    for (final entry in fileDates) {
      if (totalBytes <= targetBytes) break;
      final file = entry.key;
      final originalLength = await file.length();
      final messages = await _readFile(file, userId);
      if (messages.length <= 1) {
        await file.delete();
        totalBytes -= originalLength;
        continue;
      }

      final excessBytes = totalBytes - targetBytes;
      final removeCount = max(
        1,
        min(
          messages.length - 1,
          (messages.length * excessBytes / originalLength).ceil(),
        ),
      );
      final retainedMessages = messages.skip(removeCount).toList();
      await _writeFile(file, userId, retainedMessages);
      totalBytes += await file.length() - originalLength;
    }
  }

  Future<List<File>> _cacheFiles(String userId) async {
    final directory = await _userDirectory(userId);
    if (!await directory.exists()) return <File>[];
    return directory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.enc'))
        .toList();
  }

  Future<Directory> _userDirectory(String userId) async {
    final supportDirectory = await getApplicationSupportDirectory();
    final safeUserId = base64Url
        .encode(utf8.encode(userId))
        .replaceAll('=', '');
    return Directory(
      '${supportDirectory.path}/chat_message_cache_v1/$safeUserId',
    );
  }

  Future<File> _chatFile(String userId, String roomId) async {
    final directory = await _userDirectory(userId);
    await directory.create(recursive: true);
    final safeRoomId = base64Url
        .encode(utf8.encode(roomId))
        .replaceAll('=', '');
    return File('${directory.path}/$safeRoomId.enc');
  }

  Future<SecretKey> _loadOrCreateKey(String userId) async {
    final storageKey = '$_storageKeyPrefix$userId';
    final storedKey = await _storage.read(key: storageKey);
    if (storedKey != null) return SecretKey(base64Decode(storedKey));
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    await _storage.write(key: storageKey, value: base64Encode(bytes));
    return SecretKey(bytes);
  }

  Future<SecretKey> _loadExistingKey(String userId) async {
    final storedKey = await _storage.read(key: '$_storageKeyPrefix$userId');
    if (storedKey == null) {
      throw StateError('Не найден ключ для расшифровки кэша сообщений');
    }
    return SecretKey(base64Decode(storedKey));
  }

  Future<List<Message>> _readFile(File file, String userId) async {
    final envelope = jsonDecode(await file.readAsString());
    if (envelope is! Map<String, dynamic> ||
        envelope['version'] != 1 ||
        envelope['nonce'] is! String ||
        envelope['ciphertext'] is! String ||
        envelope['mac'] is! String) {
      throw const FormatException('Некорректный файл кэша сообщений');
    }
    final plaintext = await _cipher.decrypt(
      SecretBox(
        base64Decode(envelope['ciphertext'] as String),
        nonce: base64Decode(envelope['nonce'] as String),
        mac: Mac(base64Decode(envelope['mac'] as String)),
      ),
      secretKey: await _loadExistingKey(userId),
      aad: utf8.encode('strazh-message-cache-v1:$userId'),
    );
    final decoded = jsonDecode(utf8.decode(plaintext));
    if (decoded is! List) {
      throw const FormatException('Неверный формат кэша сообщений');
    }
    return decoded
        .whereType<Map>()
        .map(
          (message) =>
              Message.fromCacheJson(Map<String, dynamic>.from(message), userId),
        )
        .toList();
  }

  Future<void> _writeFile(
    File file,
    String userId,
    List<Message> messages,
  ) async {
    final encrypted = await _cipher.encrypt(
      utf8.encode(
        jsonEncode(messages.map((message) => message.toCacheJson()).toList()),
      ),
      secretKey: await _loadOrCreateKey(userId),
      aad: utf8.encode('strazh-message-cache-v1:$userId'),
    );
    final temporaryFile = File('${file.path}.tmp');
    await temporaryFile.writeAsString(
      jsonEncode({
        'version': 1,
        'nonce': base64Encode(encrypted.nonce),
        'ciphertext': base64Encode(encrypted.cipherText),
        'mac': base64Encode(encrypted.mac.bytes),
      }),
      flush: true,
    );
    await temporaryFile.rename(file.path);
  }
}
