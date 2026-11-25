import 'package:flutter_test/flutter_test.dart';
import 'package:strazh/shared/domain/models/message.dart';
import 'package:strazh/shared/domain/models/user.dart';

void main() {
  test('cached message restores text, sender, and interactive state', () {
    const sender = User(
      id: 'sender-id',
      name: 'Sender',
      tag: 'sender',
      avatarUrl: 'https://example.test/avatar.png',
    );
    final message = Message(
      id: 'message-id',
      chatId: 'room-id',
      senderId: sender.id,
      content: 'Offline readable text',
      createdAt: DateTime.utc(2026, 11, 23, 12),
      isMe: false,
      sender: sender,
      isEdited: true,
      readByOthers: true,
      reactions: const {'❤️': 3},
      myReaction: '❤️',
    );

    final restored = Message.fromCacheJson(
      message.toCacheJson(),
      'current-user',
    );

    expect(restored.id, message.id);
    expect(restored.content, message.content);
    expect(restored.sender?.name, sender.name);
    expect(restored.sender?.avatarUrl, sender.avatarUrl);
    expect(restored.isEdited, isTrue);
    expect(restored.readByOthers, isTrue);
    expect(restored.reactions, {'❤️': 3});
    expect(restored.myReaction, '❤️');
  });
}
