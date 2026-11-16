import 'package:flutter_test/flutter_test.dart';
import 'package:strazh/shared/domain/models/message.dart';

void main() {
  test('parses video note metadata and keeps it when serialized', () {
    final message = Message.fromJson({
      'id': 'video-note-1',
      'room_id': 'chat-1',
      'profile_id': 'sender-1',
      'encrypted_content': 'https://storage.example/video-note.mp4',
      'encrypted_content_type': 'video_note',
      'is_file': true,
      'file_url': 'https://storage.example/video-note.mp4',
      'file_name': 'video_note.mp4',
      'file_size': 1024,
      'file_mime_type': 'video/mp4',
      'created_at': '2026-11-01T10:00:00Z',
    }, 'receiver-1');

    expect(message.isVideoNote, isTrue);
    expect(message.isFile, isTrue);
    expect(message.fileUrl, 'https://storage.example/video-note.mp4');
    expect(Message.notificationPreview(message.toJson()), 'Видеокружок');
    expect(message.copyWith().isVideoNote, isTrue);
    expect(message.toJson()['encrypted_content_type'], 'video_note');
  });

  test('keeps ordinary video files distinct from video notes', () {
    final message = Message.fromJson({
      'id': 'video-file-1',
      'room_id': 'chat-1',
      'profile_id': 'sender-1',
      'encrypted_content': 'video.mp4',
      'is_file': true,
      'file_name': 'video.mp4',
      'file_mime_type': 'video/mp4',
      'created_at': '2026-11-01T10:00:00Z',
    }, 'receiver-1');

    expect(message.isVideoNote, isFalse);
    expect(Message.notificationPreview(message.toJson()), 'Видео');
  });
}
