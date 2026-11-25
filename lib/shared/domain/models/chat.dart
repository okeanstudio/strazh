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
  final bool isBot;
  final bool botVerified;
  final bool hasVoltStreak;
  final bool voltExtendedToday;

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
    this.isBot = false,
    this.botVerified = false,
    this.hasVoltStreak = false,
    this.voltExtendedToday = false,
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
      isBot: isBot,
      botVerified: botVerified,
      hasVoltStreak: hasVoltStreak,
      voltExtendedToday: voltExtendedToday,
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
      isBot: isBot,
      botVerified: botVerified,
      hasVoltStreak: hasVoltStreak,
      voltExtendedToday: voltExtendedToday,
    );
  }

  Chat withVoltStreak({
    required bool hasVoltStreak,
    required bool voltExtendedToday,
  }) {
    return Chat(
      id: id,
      name: name,
      lastMessage: lastMessage,
      lastMessageTime: lastMessageTime,
      avatarUrl: avatarUrl,
      unreadCount: unreadCount,
      type: type,
      lastMessageIsMe: lastMessageIsMe,
      lastMessageReadByOthers: lastMessageReadByOthers,
      isVerified: isVerified,
      isBot: isBot,
      botVerified: botVerified,
      hasVoltStreak: hasVoltStreak,
      voltExtendedToday: voltExtendedToday,
    );
  }
}
