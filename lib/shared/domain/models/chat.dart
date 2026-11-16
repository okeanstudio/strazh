class Chat {
  final String id;
  final String name;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final String? avatarUrl;
  final int unreadCount;
  final String type;
  final bool lastMessageIsMe;
  final bool lastMessageReadByOthers;
  final bool isVerified;

  const Chat({
    required this.id,
    required this.name,
    this.lastMessage,
    this.lastMessageTime,
    this.avatarUrl,
    this.unreadCount = 0,
    required this.type,
    this.lastMessageIsMe = false,
    this.lastMessageReadByOthers = false,
    this.isVerified = false,
  });

  Chat withLastMessageReadByOthers(bool value) {
    return Chat(
      id: id,
      name: name,
      lastMessage: lastMessage,
      lastMessageTime: lastMessageTime,
      avatarUrl: avatarUrl,
      unreadCount: unreadCount,
      type: type,
      lastMessageIsMe: lastMessageIsMe,
      lastMessageReadByOthers: value,
      isVerified: isVerified,
    );
  }

  Chat withUnreadCount(int value) {
    return Chat(
      id: id,
      name: name,
      lastMessage: lastMessage,
      lastMessageTime: lastMessageTime,
      avatarUrl: avatarUrl,
      unreadCount: value,
      type: type,
      lastMessageIsMe: lastMessageIsMe,
      lastMessageReadByOthers: lastMessageReadByOthers,
      isVerified: isVerified,
    );
  }
}