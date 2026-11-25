import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MissingKeyVaultBackupException implements Exception {
  const MissingKeyVaultBackupException();

  @override
  String toString() => 'Резервная копия ключей на сервере не найдена';
}

class EndToEndEncryptionService {
  EndToEndEncryptionService._();

  static final EndToEndEncryptionService instance =
      EndToEndEncryptionService._();

  static const _version = 2;
  static final _storage = FlutterSecureStorage();
  static final _x25519 = X25519();
  static final _cipher = AesGcm.with256bits();
  static final _kdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _vaultKdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 600000,
    bits: 256,
  );
  static final _random = Random.secure();
  RealtimeChannel? _vaultChannel;
  String? _vaultChannelUserId;
  Future<void>? _vaultSync;
  static const legacyMessageUnavailable =
      '[Это сообщение было создано экспериментальной E2E-версией и недоступно '
      'в текущем формате]';
  static const messageUnavailableOnDevice =
      '[Сообщение недоступно на этом устройстве. Попросите отправителя '
      'переслать его.]';

  Future<void> ensureCurrentDevice() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) throw StateError('Пользователь не авторизован');
    await _loadOrCreateDevice(userId);
  }

  Future<bool> isKeyVaultUnlocked() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return false;
    return await _storage.read(key: '${_keyPrefix(userId)}vault_key') != null;
  }

  Future<void> syncKeyVaultWithServerEscrow({
    bool createDeviceIfMissing = true,
  }) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) throw StateError('Пользователь не авторизован');

    final escrow = await _readServerKeyEscrow(userId);
    var bundles = <Map<String, String>>[];
    final escrowDevices = escrow?['device_keys'];
    if (escrowDevices != null) {
      if (escrowDevices is! List) {
        throw const FormatException('Некорректное хранилище ключей устройств');
      }
      bundles = escrowDevices
          .map((item) => Map<String, String>.from(item as Map))
          .toList();
      await _importDeviceKeys(userId, bundles);
    }

    if (await isKeyVaultUnlocked()) {
      await syncKeyVaultWithStoredKey();
    }

    final localBundles = await _readLocalDeviceKeys(userId);
    if (createDeviceIfMissing || localBundles.isNotEmpty) {
      await _loadOrCreateDevice(userId);
    }
    final mergedBundles = await _readLocalDeviceKeys(userId);
    final knownIds = bundles.map((bundle) => bundle['device_id']).toSet();
    bundles.addAll(
      mergedBundles.where((bundle) => !knownIds.contains(bundle['device_id'])),
    );
    if (bundles.isNotEmpty) {
      await _writeServerKeyEscrow(userId, bundles);
    }
  }

  Future<void> syncKeyVaultWithPassword(
    String password, {
    bool createIfMissing = true,
  }) async {
    if (password.isEmpty) throw ArgumentError('Пароль не может быть пустым');
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) throw StateError('Пользователь не авторизован');

    final storagePrefix = _keyPrefix(userId);
    final vault = await _readKeyVault(userId);
    if (vault == null &&
        !createIfMissing &&
        (await _readLocalDeviceKeys(userId)).isEmpty) {
      throw const MissingKeyVaultBackupException();
    }

    final salt = vault == null
        ? List<int>.generate(16, (_) => _random.nextInt(256))
        : base64Decode(vault['salt'] as String);
    final vaultKey = await _deriveVaultKey(password, salt);
    var bundles = <Map<String, String>>[];

    if (vault != null) {
      final cleartext = await _cipher.decrypt(
        SecretBox(
          base64Decode(vault['ciphertext'] as String),
          nonce: base64Decode(vault['nonce'] as String),
          mac: Mac(base64Decode(vault['mac'] as String)),
        ),
        secretKey: vaultKey,
        aad: _vaultAssociatedData(userId),
      );
      final payload = jsonDecode(utf8.decode(cleartext));
      if (payload is! Map<String, dynamic> || payload['devices'] is! List) {
        throw const FormatException('Некорректная резервная копия ключей');
      }
      bundles = (payload['devices'] as List)
          .map((item) => Map<String, String>.from(item as Map))
          .toList();
      await _importDeviceKeys(userId, bundles);
    }

    await _loadOrCreateDevice(userId);
    final localBundles = await _readLocalDeviceKeys(userId);
    if (localBundles.isNotEmpty) {
      final knownIds = bundles.map((bundle) => bundle['device_id']).toSet();
      bundles.addAll(
        localBundles.where((bundle) => !knownIds.contains(bundle['device_id'])),
      );
    }
    if (bundles.isEmpty) {
      throw StateError('На этом устройстве нет ключей для синхронизации');
    }

    await _writeKeyVault(userId, bundles, salt, vaultKey);
    await _storage.write(
      key: '${storagePrefix}vault_key',
      value: base64Encode(await vaultKey.extractBytes()),
    );
    _subscribeToKeyVault(userId);
  }

  Future<void> changeKeyVaultPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (currentPassword.isEmpty || newPassword.isEmpty) {
      throw ArgumentError('Пароль не может быть пустым');
    }
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) throw StateError('Пользователь не авторизован');
    await _loadOrCreateDevice(userId);

    final vault = await _readKeyVault(userId);
    var bundles = <Map<String, String>>[];
    if (vault != null) {
      final oldKey = await _deriveVaultKey(
        currentPassword,
        base64Decode(vault['salt'] as String),
      );
      final cleartext = await _cipher.decrypt(
        SecretBox(
          base64Decode(vault['ciphertext'] as String),
          nonce: base64Decode(vault['nonce'] as String),
          mac: Mac(base64Decode(vault['mac'] as String)),
        ),
        secretKey: oldKey,
        aad: _vaultAssociatedData(userId),
      );
      final payload = jsonDecode(utf8.decode(cleartext));
      if (payload is! Map<String, dynamic> || payload['devices'] is! List) {
        throw const FormatException('Некорректная резервная копия ключей');
      }
      bundles = (payload['devices'] as List)
          .map((item) => Map<String, String>.from(item as Map))
          .toList();
      await _importDeviceKeys(userId, bundles);
    }
    final localBundles = await _readLocalDeviceKeys(userId);
    final knownIds = bundles.map((bundle) => bundle['device_id']).toSet();
    bundles.addAll(
      localBundles.where((bundle) => !knownIds.contains(bundle['device_id'])),
    );
    if (bundles.isEmpty) {
      throw StateError('На этом устройстве нет ключей для синхронизации');
    }

    final salt = List<int>.generate(16, (_) => _random.nextInt(256));
    final newKey = await _deriveVaultKey(newPassword, salt);
    await _writeKeyVault(userId, bundles, salt, newKey);
    await _storage.write(
      key: '${_keyPrefix(userId)}vault_key',
      value: base64Encode(await newKey.extractBytes()),
    );
    _subscribeToKeyVault(userId);
  }

  Future<void> syncKeyVaultWithStoredKey() async {
    final pendingSync = _vaultSync;
    if (pendingSync != null) {
      await pendingSync;
      return;
    }
    final sync = _syncKeyVaultWithStoredKey();
    _vaultSync = sync;
    try {
      await sync;
    } finally {
      if (identical(_vaultSync, sync)) _vaultSync = null;
    }
  }

  Future<void> _syncKeyVaultWithStoredKey() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) throw StateError('Пользователь не авторизован');
    final storagePrefix = _keyPrefix(userId);
    final storedKey = await _storage.read(key: '${storagePrefix}vault_key');
    final vault = await _readKeyVault(userId);
    if (storedKey == null || vault == null) return;

    final vaultKey = SecretKey(base64Decode(storedKey));
    final cleartext = await _cipher.decrypt(
      SecretBox(
        base64Decode(vault['ciphertext'] as String),
        nonce: base64Decode(vault['nonce'] as String),
        mac: Mac(base64Decode(vault['mac'] as String)),
      ),
      secretKey: vaultKey,
      aad: _vaultAssociatedData(userId),
    );
    final payload = jsonDecode(utf8.decode(cleartext));
    if (payload is! Map<String, dynamic> || payload['devices'] is! List) {
      throw const FormatException('Некорректная резервная копия ключей');
    }
    final bundles = (payload['devices'] as List)
        .map((item) => Map<String, String>.from(item as Map))
        .toList();
    await _importDeviceKeys(userId, bundles);
    final merged = await _readLocalDeviceKeys(userId);
    final vaultDeviceIds = bundles.map((bundle) => bundle['device_id']).toSet();
    final mergedDeviceIds = merged.map((bundle) => bundle['device_id']).toSet();
    if (vaultDeviceIds.length != mergedDeviceIds.length ||
        !vaultDeviceIds.containsAll(mergedDeviceIds)) {
      await _writeKeyVault(
        userId,
        merged,
        base64Decode(vault['salt'] as String),
        vaultKey,
      );
    }
    await _writeServerKeyEscrow(userId, merged);
    _subscribeToKeyVault(userId);
  }

  void _subscribeToKeyVault(String userId) {
    if (_vaultChannelUserId == userId && _vaultChannel != null) return;
    final client = Supabase.instance.client;
    final oldChannel = _vaultChannel;
    if (oldChannel != null) {
      unawaited(client.removeChannel(oldChannel));
    }
    _vaultChannelUserId = userId;
    _vaultChannel = client
        .channel('chat_encryption_key_vault_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_encryption_key_vault',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) {
            unawaited(
              syncKeyVaultWithStoredKey().catchError((Object error) {
                debugPrint('Не удалось синхронизировать ключи E2EE: $error');
              }),
            );
          },
        )
        .subscribe();
  }

  String _keyPrefix(String userId) => 'strazh_e2ee_v2_${userId}_';

  List<int> _vaultAssociatedData(String userId) =>
      utf8.encode('strazh-e2ee-key-vault-v1:$userId');

  Future<SecretKey> _deriveVaultKey(String password, List<int> salt) {
    return _vaultKdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  Future<Map<String, dynamic>?> _readKeyVault(String userId) async {
    return Supabase.instance.client
        .from('chat_encryption_key_vault')
        .select('salt, nonce, ciphertext, mac')
        .eq('user_id', userId)
        .maybeSingle();
  }

  Future<Map<String, dynamic>?> _readServerKeyEscrow(String userId) async {
    return Supabase.instance.client
        .from('chat_encryption_key_escrow')
        .select('device_keys')
        .eq('user_id', userId)
        .maybeSingle();
  }

  Future<void> _writeServerKeyEscrow(
    String userId,
    List<Map<String, String>> bundles,
  ) async {
    await Supabase.instance.client.from('chat_encryption_key_escrow').upsert({
      'user_id': userId,
      'device_keys': bundles,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id');
  }

  Future<void> _writeKeyVault(
    String userId,
    List<Map<String, String>> bundles,
    List<int> salt,
    SecretKey vaultKey,
  ) async {
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode({'version': 1, 'devices': bundles})),
      secretKey: vaultKey,
      aad: _vaultAssociatedData(userId),
    );
    await Supabase.instance.client.from('chat_encryption_key_vault').upsert({
      'user_id': userId,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id');
    await _writeServerKeyEscrow(userId, bundles);
  }

  Future<List<Map<String, String>>> _readLocalDeviceKeys(String userId) async {
    final prefix = _keyPrefix(userId);
    final values = await _storage.readAll();
    final bundles = <Map<String, String>>[];
    final primaryId = values['${prefix}device_id'];
    final primarySeed = values['${prefix}private_seed'];
    if (primaryId != null && primarySeed != null) {
      bundles.add({'device_id': primaryId, 'private_seed': primarySeed});
    }

    const linkedPrefix = 'linked_';
    const seedSuffix = '_private_seed';
    for (final entry in values.entries) {
      if (!entry.key.startsWith('$prefix$linkedPrefix') ||
          !entry.key.endsWith(seedSuffix)) {
        continue;
      }
      final deviceId = entry.key
          .substring(prefix.length + linkedPrefix.length)
          .substring(
            0,
            entry.key.length -
                prefix.length -
                linkedPrefix.length -
                seedSuffix.length,
          );
      if (deviceId.isNotEmpty) {
        bundles.add({'device_id': deviceId, 'private_seed': entry.value});
      }
    }
    return bundles;
  }

  Future<void> _importDeviceKeys(
    String userId,
    List<Map<String, String>> bundles,
  ) async {
    final keyPrefix = _keyPrefix(userId);
    final rows = await Supabase.instance.client
        .from('chat_encryption_devices')
        .select('device_id, public_key')
        .eq('user_id', userId);
    final publicKeys = {
      for (final row in rows)
        row['device_id'] as String: row['public_key'] as String,
    };
    final primaryId = await _storage.read(key: '${keyPrefix}device_id');

    for (final bundle in bundles) {
      final deviceId = bundle['device_id'];
      final seedText = bundle['private_seed'];
      if (deviceId == null || seedText == null) {
        throw const FormatException('Повреждён ключ устройства');
      }
      final keyPair = await _x25519.newKeyPairFromSeed(base64Decode(seedText));
      final publicKey = await keyPair.extractPublicKey();
      final registeredPublicKey = publicKeys[deviceId];
      if (registeredPublicKey == null ||
          base64Encode(publicKey.bytes) != registeredPublicKey) {
        throw StateError('Ключ устройства не совпадает с зарегистрированным');
      }
      if (deviceId == primaryId) continue;
      await _storage.write(
        key: '${keyPrefix}linked_${deviceId}_private_seed',
        value: seedText,
      );
    }
  }

  Future<String> encryptText({
    required String roomId,
    required String senderId,
    required String plaintext,
  }) async {
    final client = Supabase.instance.client;
    final localDevice = await _loadOrCreateDevice(senderId);
    final participantRows = await client
        .from('room_participants')
        .select('user_id')
        .eq('room_id', roomId);
    final participantIds = participantRows
        .map((row) => row['user_id'] as String)
        .toSet();
    if (!participantIds.contains(senderId)) {
      throw StateError('Отправитель больше не состоит в чате');
    }

    final deviceRows = await client
        .from('chat_encryption_devices')
        .select('user_id, device_id, public_key')
        .inFilter('user_id', participantIds.toList());
    final devices = deviceRows
        .map(
          (row) => _RemoteDevice(
            userId: row['user_id'] as String,
            deviceId: row['device_id'] as String,
            publicKey: base64Decode(row['public_key'] as String),
          ),
        )
        .toList();

    for (final participantId in participantIds) {
      if (!devices.any((device) => device.userId == participantId)) {
        throw StateError(
          'Для сквозного шифрования каждый участник должен открыть этот чат '
          'в обновлённом приложении хотя бы на одном устройстве.',
        );
      }
    }

    final ephemeralKeyPair = await _x25519.newKeyPair();
    final ephemeralPublicKey = await ephemeralKeyPair.extractPublicKey();
    final recipientBoxes = <String, Map<String, String>>{};
    for (final device in devices) {
      final sharedSecret = await _x25519.sharedSecretKey(
        keyPair: ephemeralKeyPair,
        remotePublicKey: SimplePublicKey(
          device.publicKey,
          type: KeyPairType.x25519,
        ),
      );
      final secretKey = await _deriveMessageKey(
        sharedSecret,
        roomId: roomId,
        senderId: senderId,
        recipientUserId: device.userId,
        recipientDeviceId: device.deviceId,
      );
      final aad = _associatedData(
        roomId,
        senderId,
        device.userId,
        device.deviceId,
      );
      final box = await _cipher.encrypt(
        utf8.encode(plaintext),
        secretKey: secretKey,
        aad: aad,
      );
      recipientBoxes['${device.userId}:${device.deviceId}'] = {
        'user_id': device.userId,
        'nonce': base64Encode(box.nonce),
        'ciphertext': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      };
    }

    if (!recipientBoxes.containsKey('$senderId:${localDevice.deviceId}')) {
      throw StateError('Не удалось создать ключ для этого устройства');
    }

    return jsonEncode({
      'version': _version,
      'sender_id': senderId,
      'sender_device_id': localDevice.deviceId,
      'ephemeral_public_key': base64Encode(ephemeralPublicKey.bytes),
      'recipients': recipientBoxes,
    });
  }

  Future<String> decryptText({
    required String roomId,
    required String senderId,
    required String content,
  }) async {
    final envelope = _parseEnvelope(content);
    if (envelope == null) return content;
    if (envelope['version'] == 1) return legacyMessageUnavailable;
    if (envelope['version'] != _version || envelope['sender_id'] != senderId) {
      throw const FormatException('Некорректный конверт E2EE');
    }

    final recipientBoxes = envelope['recipients'];
    if (recipientBoxes is! Map<String, dynamic>) {
      throw const FormatException('Некорректный список ключей E2EE');
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) throw StateError('Пользователь не авторизован');
    final devices = await _loadExistingDevices(userId);
    final matchingDevices = devices.where((device) {
      final box = recipientBoxes['$userId:${device.deviceId}'];
      return box is Map<String, dynamic> && box['user_id'] == userId;
    });
    if (matchingDevices.isEmpty) {
      return messageUnavailableOnDevice;
    }

    final ephemeralPublicKey = SimplePublicKey(
      base64Decode(envelope['ephemeral_public_key'] as String),
      type: KeyPairType.x25519,
    );
    Object? lastError;
    for (final device in matchingDevices) {
      try {
        final recipientBox =
            recipientBoxes['$userId:${device.deviceId}']
                as Map<String, dynamic>;
        final sharedSecret = await _x25519.sharedSecretKey(
          keyPair: device.keyPair,
          remotePublicKey: ephemeralPublicKey,
        );
        final secretKey = await _deriveMessageKey(
          sharedSecret,
          roomId: roomId,
          senderId: senderId,
          recipientUserId: userId,
          recipientDeviceId: device.deviceId,
        );
        final secretBox = SecretBox(
          base64Decode(recipientBox['ciphertext'] as String),
          nonce: base64Decode(recipientBox['nonce'] as String),
          mac: Mac(base64Decode(recipientBox['mac'] as String)),
        );
        final cleartext = await _cipher.decrypt(
          secretBox,
          secretKey: secretKey,
          aad: _associatedData(roomId, senderId, userId, device.deviceId),
        );
        return utf8.decode(cleartext);
      } catch (error) {
        lastError = error;
      }
    }
    Error.throwWithStackTrace(
      lastError ?? StateError('Не удалось расшифровать сообщение'),
      StackTrace.current,
    );
  }

  Future<String> decryptPushedMessage({
    required String roomId,
    required String messageId,
    required String expectedSenderId,
  }) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) throw StateError('Пользователь не авторизован');

    final record = await Supabase.instance.client
        .from('messages')
        .select(
          'room_id, profile_id, encrypted_content, encrypted_content_type, '
          'is_image, is_file, is_voice',
        )
        .eq('id', messageId)
        .eq('room_id', roomId)
        .maybeSingle();

    if (record == null) throw StateError('Сообщение push не найдено');
    if (record['profile_id'] != expectedSenderId) {
      throw StateError('Отправитель push не совпадает с сообщением');
    }
    if (record['encrypted_content_type'] != 'text/plain' ||
        record['is_image'] == true ||
        record['is_file'] == true ||
        record['is_voice'] == true) {
      throw StateError('Этот тип сообщения не поддерживает текстовый push');
    }

    return decryptText(
      roomId: roomId,
      senderId: expectedSenderId,
      content: record['encrypted_content']?.toString() ?? '',
    );
  }

  Map<String, dynamic>? _parseEnvelope(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic> &&
          ((decoded['version'] == 1 &&
                  decoded['sender_device_id'] is String &&
                  decoded['recipients'] is Map) ||
              decoded['version'] == _version ||
              decoded['ephemeral_public_key'] is String)) {
        return decoded;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  Future<SecretKey> _deriveMessageKey(
    SecretKey sharedSecret, {
    required String roomId,
    required String senderId,
    required String recipientUserId,
    required String recipientDeviceId,
  }) {
    return _kdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode(roomId),
      info: utf8.encode(
        'strazh-e2ee-v2:$senderId:$recipientUserId:$recipientDeviceId',
      ),
    );
  }

  List<int> _associatedData(
    String roomId,
    String senderId,
    String recipientUserId,
    String recipientDeviceId,
  ) => utf8.encode(
    'strazh-e2ee-v2:$roomId:$senderId:$recipientUserId:$recipientDeviceId',
  );

  Future<_LocalDevice> _loadOrCreateDevice(String userId) async {
    final keyPrefix = 'strazh_e2ee_v2_${userId}_';
    var deviceId = await _storage.read(key: '${keyPrefix}device_id');
    var seedText = await _storage.read(key: '${keyPrefix}private_seed');

    if (deviceId == null || seedText == null) {
      final random = Random.secure();
      deviceId = base64UrlEncode(
        List<int>.generate(18, (_) => random.nextInt(256)),
      ).replaceAll('=', '');
      final seed = List<int>.generate(32, (_) => random.nextInt(256));
      seedText = base64Encode(seed);
      await _storage.write(key: '${keyPrefix}device_id', value: deviceId);
      await _storage.write(key: '${keyPrefix}private_seed', value: seedText);
    }

    final keyPair = await _x25519.newKeyPairFromSeed(base64Decode(seedText));
    final publicKey = await keyPair.extractPublicKey();
    await Supabase.instance.client.from('chat_encryption_devices').upsert({
      'user_id': userId,
      'device_id': deviceId,
      'public_key': base64Encode(publicKey.bytes),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,device_id');
    return _LocalDevice(
      deviceId: deviceId,
      keyPair: keyPair,
      publicKey: publicKey,
    );
  }

  Future<List<_LocalDevice>> _loadExistingDevices(String userId) async {
    final bundles = await _readLocalDeviceKeys(userId);
    final devices = <_LocalDevice>[];
    for (final bundle in bundles) {
      final keyPair = await _x25519.newKeyPairFromSeed(
        base64Decode(bundle['private_seed']!),
      );
      final publicKey = await keyPair.extractPublicKey();
      devices.add(
        _LocalDevice(
          deviceId: bundle['device_id']!,
          keyPair: keyPair,
          publicKey: publicKey,
        ),
      );
    }
    return devices;
  }
}

class _LocalDevice {
  const _LocalDevice({
    required this.deviceId,
    required this.keyPair,
    required this.publicKey,
  });

  final String deviceId;
  final KeyPair keyPair;
  final SimplePublicKey publicKey;
}

class _RemoteDevice {
  const _RemoteDevice({
    required this.userId,
    required this.deviceId,
    required this.publicKey,
  });

  final String userId;
  final String deviceId;
  final List<int> publicKey;
}
