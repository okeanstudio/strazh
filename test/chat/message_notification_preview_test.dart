import 'package:flutter_test/flutter_test.dart';
import 'package:strazh/shared/domain/models/message.dart';

void main() {
  group('Message.fromJson bot identity', () {
    test('uses the standalone bot ID and keeps the message plaintext', () {
      final message = Message.fromJson({
        'id': 'message-id',
        'room_id': 'room-id',
        'profile_id': 'owner-id',
        'bot_id': 'bot-id',
        'encrypted_content': 'Hello from the bot',
        'bot_plaintext': true,
        'created_at': '2026-11-18T00:00:00.000Z',
      }, 'owner-id');

      expect(message.senderId, 'bot-id');
      expect(message.isMe, isFalse);
      expect(message.content, 'Hello from the bot');
    });
  });

  group('Message.notificationPreview', () {
    test('recognizes stickers without decrypting their URL', () {
      expect(
        Message.notificationPreview({
          'encrypted_content': 'https://media.example/sticker.webp',
          'encrypted_content_type': 'sticker',
        }),
        'Стикер',
      );
    });

    test('recognizes images from their media type', () {
      expect(
        Message.notificationPreview({
          'encrypted_content': 'https://media.example/photo.jpg',
          'encrypted_content_type': 'image/jpeg',
        }),
        'Фото',
      );
      expect(
        Message.notificationPreview({'encrypted_content_type': 'image/gif'}),
        'GIF',
      );
    });

    test('uses descriptive previews for other attachments', () {
      expect(
        Message.notificationPreview({'is_voice': true}),
        'Голосовое сообщение',
      );
      expect(
        Message.notificationPreview({
          'is_file': true,
          'file_name': 'report.pdf',
        }),
        'Файл: report.pdf',
      );
      expect(
        Message.notificationPreview({'encrypted_content_type': 'video/mp4'}),
        'Видео',
      );
    });

    test('recognizes image media even when the image flag is absent', () {
      expect(
        Message.isImageMessage({'encrypted_content_type': 'image/webp'}),
        isTrue,
      );
    });
  });
}
