import 'package:flutter_test/flutter_test.dart';
import 'package:strazh/features/chat/data/services/chat_service.dart';
import 'package:strazh/features/chat/data/services/crypto_service.dart';

void main() {
  test('private Storage URLs can be forwarded as stable object paths', () {
    const signedUrl =
        'https://storage.example/storage/v1/object/sign/chat_files/'
        'room-id/document.pdf?token=example';

    expect(storageObjectPath('chat_files', signedUrl), 'room-id/document.pdf');
    expect(
      storageObjectPath('chat_files', 'room-id/document.pdf'),
      'room-id/document.pdf',
    );
    expect(storageObjectPath('chat_media', signedUrl), isNull);
    expect(
      storageObjectPath('chat_files', 'https://example.com/file.pdf'),
      isNull,
    );
  });

  group('Cloud chat content', () {
    final service = CryptoService();

    test('stores regular chat content for account-wide synchronization', () {
      const content = 'Сообщение для своих устройств';

      expect(service.encodeCloudContent(content), content);
      expect(service.decodeCloudContent(content), content);
    });

    test('does not expose experimental per-device E2E envelopes as text', () {
      const envelope =
          '{"version":1,"sender_device_id":"device","recipients":{}}';

      expect(
        service.decodeCloudContent(envelope),
        CryptoService.legacyMessageUnavailable,
      );
    });

    test('keeps existing plaintext messages readable', () async {
      expect(
        await service.decodeRoomContent(
          roomId: 'room',
          senderId: 'sender',
          content: 'Старое сообщение',
        ),
        'Старое сообщение',
      );
    });

    test('does not render legacy E2E envelopes as raw JSON', () async {
      const envelope =
          '{"version":1,"sender_device_id":"device","recipients":{}}';

      expect(
        await service.decodeRoomContent(
          roomId: 'room',
          senderId: 'sender',
          content: envelope,
        ),
        CryptoService.legacyMessageUnavailable,
      );
    });
  });
}
