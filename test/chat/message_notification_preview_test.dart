import 'package:flutter_test/flutter_test.dart';
import 'package:strazh/shared/domain/models/message.dart';

void main() {
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
