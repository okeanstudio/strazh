import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EndToEndEncryptionService {
  EndToEndEncryptionService._();

  static final EndToEndEncryptionService instance =
      EndToEndEncryptionService._();

  static const _version = 2;
  static final _storage = FlutterSecureStorage();
  static final _x25519 = X25519();
  static final _cipher = AesGcm.with256bits();
  static final _kdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static const legacyMessageUnavailable =
      '[Это сообщение было создано экспериментальной E2E-версией и недоступно '
      'в текущем формате]';

  Future<void> ensureCurrentDevice() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) throw StateError('Пользователь не авторизован');
    await _loadOrCreateDevice(userId);
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
    final device = await _loadExistingDevice(userId);
    final recipientBox = recipientBoxes['$userId:${device.deviceId}'];
    if (recipientBox is! Map<String, dynamic> ||
        recipientBox['user_id'] != userId) {
      throw StateError('Для этого устройства нет ключа сообщения');
    }

    final ephemeralPublicKey = SimplePublicKey(
      base64Decode(envelope['ephemeral_public_key'] as String),
      type: KeyPairType.x25519,
    );
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

  Future<_LocalDevice> _loadExistingDevice(String userId) async {
    final keyPrefix = 'strazh_e2ee_v2_${userId}_';
    final deviceId = await _storage.read(key: '${keyPrefix}device_id');
    final seedText = await _storage.read(key: '${keyPrefix}private_seed');
    if (deviceId == null || seedText == null) {
      throw StateError('Приватный ключ устройства не найден');
    }

    final keyPair = await _x25519.newKeyPairFromSeed(base64Decode(seedText));
    final publicKey = await keyPair.extractPublicKey();
    return _LocalDevice(
      deviceId: deviceId,
      keyPair: keyPair,
      publicKey: publicKey,
    );
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
