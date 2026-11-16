class Story {
  final String id;
  final String userId;
  final String authorName;
  final String authorTag;
  final String? authorAvatarUrl;
  final String text;
  final String? imageUrl;
  final String backgroundColor;
  final double textPositionX;
  final double textPositionY;
  final DateTime createdAt;
  final DateTime expiresAt;

  const Story({
    required this.id,
    required this.userId,
    required this.authorName,
    required this.authorTag,
    required this.authorAvatarUrl,
    required this.text,
    required this.imageUrl,
    required this.backgroundColor,
    this.textPositionX = 0.5,
    this.textPositionY = 0.5,
    required this.createdAt,
    required this.expiresAt,
  });

  factory Story.fromJson(Map<String, dynamic> json) {
    return Story(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      authorName: json['author_name'] as String? ?? 'Пользователь',
      authorTag: json['author_tag'] as String? ?? '',
      authorAvatarUrl: json['author_avatar_url'] as String?,
      text: json['content'] as String,
      imageUrl: json['image_url'] as String?,
      backgroundColor: json['background_color'] as String? ?? '#6C4AB6',
      textPositionX: (json['text_position_x'] as num?)?.toDouble() ?? 0.5,
      textPositionY: (json['text_position_y'] as num?)?.toDouble() ?? 0.5,
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  Story withImageUrl(String imageUrl) {
    return Story(
      id: id,
      userId: userId,
      authorName: authorName,
      authorTag: authorTag,
      authorAvatarUrl: authorAvatarUrl,
      text: text,
      imageUrl: imageUrl,
      backgroundColor: backgroundColor,
      textPositionX: textPositionX,
      textPositionY: textPositionY,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }
}
