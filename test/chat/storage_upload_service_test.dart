import 'package:flutter_test/flutter_test.dart';
import 'package:strazh/features/chat/data/services/storage_upload_service.dart';

void main() {
  group('StorageUploadService.objectPathFromStorageUrl', () {
    test('extracts an S3 object path after its bucket segment', () {
      final path = StorageUploadService.objectPathFromStorageUrl(
        'chat_files',
        'https://s3.example.test/account/chat_files/chat-1/music.mp3?signature=test',
      );

      expect(path, 'chat-1/music.mp3');
    });

    test('extracts a Supabase storage object path', () {
      final path = StorageUploadService.objectPathFromStorageUrl(
        'chat_files',
        'https://supabase.example.test/storage/v1/object/sign/chat_files/chat-1/music.mp3?token=test',
      );

      expect(path, 'chat-1/music.mp3');
    });

    test('rejects URLs for another bucket', () {
      final path = StorageUploadService.objectPathFromStorageUrl(
        'chat_files',
        'https://s3.example.test/account/avatars/user/avatar.jpg',
      );

      expect(path, isNull);
    });
  });
}
