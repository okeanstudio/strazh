import 'dart:convert';

import 'package:strazh/features/chat/data/services/end_to_end_encryption_service.dart';

class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  factory CryptoService() => _instance;
  CryptoService._internal();

  static const legacyMessageUnavailable =
      EndToEndEncryptionService.legacyMessageUnavailable;

  String encodeCloudContent(String content) => content;

  Future<void> ensureCurrentDevice() {
    return EndToEndEncryptionService.instance.ensureCurrentDevice();
  }

  Future<String> encryptRoomContent({
    required String roomId,
    required String senderId,
    required String content,
  }) {
    return EndToEndEncryptionService.instance.encryptText(
      roomId: roomId,
      senderId: senderId,
      plaintext: content,
    );
  }

  Future<String> decodeRoomContent({
    required String roomId,
    required String senderId,
    required String content,
  }) {
    return EndToEndEncryptionService.instance.decryptText(
      roomId: roomId,
      senderId: senderId,
      content: content,
    );
  }

  String decodeCloudContent(String content) {
    if (content.isEmpty) return '';

    try {
      final decoded = jsonDecode(content);
      if (decoded is Map &&
          decoded['version'] == 1 &&
          decoded['sender_device_id'] is String &&
          decoded['recipients'] is Map) {
        return legacyMessageUnavailable;
      }
    } on FormatException {
      return content;
    }

    return content;
  }
}
