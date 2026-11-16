import 'package:strazh/shared/domain/models/user.dart';
import 'package:strazh/core/utils/date_time_utils.dart';

class Message {
  final String id;
  final String chatId;
  final String senderId;
  final String? forwardedFromUserId;
  final String? forwardedFromName;
  final String content;
  final DateTime createdAt;
  final bool isMe;
  final bool senderIsChannel;
  final User? sender;
  final bool isEdited;
  final bool isDeleted;
  final bool isPinned;
  final bool readByOthers;
  final Map<String, int> reactions;
  final Map<String, List<User>> reactionUsers;
  final String? myReaction;
  final bool isPoll;
  final List<String> pollOptions;
  final bool pollAllowMultiple;
  final bool pollClosed;
  final Map<int, int> pollVotes;
  final List<int> myPollVotes;
  final String? replyToId;
  final String? replyToContent;
  final String? replyToSender;
  final bool isVoice;
  final String? voiceUrl;
  final Duration? voiceDuration;
  final bool isImage;
  final bool isSticker;
  final bool isGift;
  final String? giftName;
  final String? giftId;
  final String? giftEmoji;
  final int? giftPriceEnc;
  final String? giftCaption;
  final int? giftNftSerial;
  final String? giftNftSkinName;
  final String? giftNftSkinEmoji;
  final String? giftNftBackgroundColor;
  final String? giftNftPattern;
  final String? giftNftAnimationUrl;
  final String? imageCaption;
  final bool isFile;
  final String? fileName;
  final String? fileUrl;
  final int? fileSize;
  final String? fileMimeType;
  final bool isVideoNote;

  const Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.forwardedFromUserId,
    this.forwardedFromName,
    required this.content,
    required this.createdAt,
    required this.isMe,
    this.senderIsChannel = false,
    this.sender,
    this.isVoice = false,
    this.voiceUrl,
    this.voiceDuration,
    this.isEdited = false,
    this.isDeleted = false,
    this.replyToId,
    this.replyToContent,
    this.replyToSender,
    this.isImage = false,
    this.isSticker = false,
    this.isGift = false,
    this.giftName,
    this.giftId,
    this.giftEmoji,
    this.giftPriceEnc,
    this.giftCaption,
    this.giftNftSerial,
    this.giftNftSkinName,
    this.giftNftSkinEmoji,
    this.giftNftBackgroundColor,
    this.giftNftPattern,
    this.giftNftAnimationUrl,
    this.imageCaption,
    this.isFile = false,
    this.fileName,
    this.fileUrl,
    this.fileSize,
    this.fileMimeType,
    this.isVideoNote = false,
    this.isPoll = false,
    this.pollOptions = const [],
    this.pollAllowMultiple = false,
    this.pollClosed = false,
    this.pollVotes = const {},
    this.myPollVotes = const [],
    this.isPinned = false,
    this.readByOthers = false,
    this.reactions = const {},
    this.reactionUsers = const {},
    this.myReaction,
  });

  bool get canEditText {
    if (isDeleted ||
        forwardedFromUserId != null ||
        isVoice ||
        isSticker ||
        isGift ||
        isFile) {
      return false;
    }
    if (isImage) {
      final caption = imageCaption?.trim() ?? '';
      return caption.isNotEmpty;
    }
    return true;
  }

  bool get canDelete {
    return !isDeleted && (isMe || senderId == '');
  }

  static bool isStickerMessage(Map<String, dynamic> json) {
    if (!_isTrue(json['is_sticker']) && !isImageMessage(json)) return false;

    final contentType = (json['encrypted_content_type'] ?? '')
        .toString()
        .toLowerCase();
    final content = (json['encrypted_content'] ?? '').toString().toLowerCase();
    final hasCaption =
        json['image_caption'] != null &&
        json['image_caption'].toString().isNotEmpty;

    return _isTrue(json['is_sticker']) ||
        contentType == 'sticker' ||
        contentType == 'image/sticker' ||
        contentType == 'application/x-sticker' ||
        contentType.contains('sticker') ||
        (contentType == 'image/png' &&
            !hasCaption &&
            (content.contains('tenor.com') ||
                content.contains('media1.tenor.com') ||
                content.contains('media.tenor.com')));
  }

  static bool isImageMessage(Map<String, dynamic> json) {
    if (_isTrue(json['is_image']) || _isTrue(json['is_sticker'])) return true;

    final contentType = (json['encrypted_content_type'] ?? '')
        .toString()
        .toLowerCase();
    return contentType.startsWith('image/') || contentType.contains('sticker');
  }

  static String notificationPreview(Map<String, dynamic> json) {
    final contentType = (json['encrypted_content_type'] ?? '')
        .toString()
        .toLowerCase();
    final fileMimeType = (json['file_mime_type'] ?? '').toString().toLowerCase();

    if (isGiftMessage(json)) return 'Подарок';
    if (isStickerMessage(json)) return 'Стикер';
    if (isImageMessage(json)) {
      return contentType == 'image/gif' ? 'GIF' : 'Фото';
    }
    if (contentType == 'video_note') return 'Видеокружок';
    if (_isTrue(json['is_voice'])) return 'Голосовое сообщение';
    if (contentType.startsWith('video/') || fileMimeType.startsWith('video/')) {
      return 'Видео';
    }
    if (contentType.startsWith('audio/') || fileMimeType.startsWith('audio/')) {
      return 'Аудио';
    }
    if (contentType == 'poll') return 'Опрос';
    if (isFileMessage(json)) {
      final fileName = json['file_name']?.toString().trim();
      return fileName == null || fileName.isEmpty ? 'Файл' : 'Файл: $fileName';
    }
    return 'Новое сообщение';
  }

  static bool _isTrue(Object? value) => value == true || value == 'true';

  static bool isFileMessage(Map<String, dynamic> json) {
    return _isTrue(json['is_file']);
  }

  static bool isGiftMessage(Map<String, dynamic> json) {
    final contentType = json['encrypted_content_type']?.toString();
    final content = json['encrypted_content']?.toString() ?? '';
    return _isTrue(json['is_gift']) ||
        contentType == 'gift' ||
        isGiftContent(content);
  }

  static bool isGiftContent(String? content) {
    return content?.trimLeft().toLowerCase().startsWith('подарок:') ?? false;
  }

  static String? giftNameFromContent(String? content) {
    if (!isGiftContent(content)) return null;
    final separator = content!.indexOf(':');
    final name = content.substring(separator + 1).trim();
    return name.isEmpty ? null : name;
  }

  // Фабрика для создания из JSON (из Supabase)
  factory Message.fromJson(Map<String, dynamic> json, String currentUserId) {
    final senderId = json['profile_id'] ?? '';
    final isMe = senderId == currentUserId;

    // Проверяем, голосовое ли сообщение
    final isVoice = json['is_voice'] ?? false;
    final voiceUrl = json['voice_url'] as String?;
    final voiceDuration = json['voice_duration'] != null
        ? Duration(seconds: json['voice_duration'] as int)
        : null;

    final isImage = isImageMessage(json);
    final isSticker = isStickerMessage(json);
    final isFile = isFileMessage(json);
    final isGift = isGiftMessage(json);
    final rawGiftName = json['gift_name']?.toString();
    final giftName = rawGiftName?.isNotEmpty == true
        ? rawGiftName
        : giftNameFromContent(json['encrypted_content']?.toString());

    // Для голосовых сообщений контент не расшифровываем
    String content = json['encrypted_content'] ?? '';
    if (isVoice) {
      content = '🎤 Голосовое сообщение';
    } else if (isFile) {
      final fileName = json['file_name'] as String? ?? 'Файл';
      content = '📎 $fileName';
    }

    return Message(
      id: json['id'] ?? '',
      chatId: json['room_id'] ?? '',
      senderId: senderId,
      forwardedFromUserId: json['forwarded_from_user_id'] as String?,
      forwardedFromName: json['forwarded_from_name'] as String?,
      content: content,
      createdAt: parseDateTimeSafely(
        json['created_at'] ?? DateTime.now().toIso8601String(),
      ),
      isMe: isMe,
      senderIsChannel: json['sender_is_channel'] == true,
      isVoice: isVoice,
      voiceUrl: voiceUrl,
      voiceDuration: voiceDuration,
      isImage: isImage,
      isSticker: isSticker,
      isGift: isGift,
      giftName: giftName,
      giftId: json['gift_id'] as String?,
      giftEmoji: json['gift_emoji'] as String?,
      giftPriceEnc: (json['gift_price_enc'] as num?)?.toInt(),
      giftCaption: json['gift_caption'] as String?,
      giftNftSerial: (json['gift_nft_serial'] as num?)?.toInt(),
      giftNftSkinName: json['gift_nft_skin_name'] as String?,
      giftNftSkinEmoji: json['gift_nft_skin_emoji'] as String?,
      giftNftBackgroundColor: json['gift_nft_background_color'] as String?,
      giftNftPattern: json['gift_nft_pattern'] as String?,
      giftNftAnimationUrl: json['gift_nft_animation_url'] as String?,
      imageCaption: json['image_caption'] as String?,
      isEdited: json['is_edited'] ?? false,
      isDeleted: json['is_deleted'] ?? false,
      replyToId: json['reply_to_id'] as String?,
      replyToContent: json['reply_to_content'] as String?,
      replyToSender: json['reply_to_sender'] as String?,
      isFile: isFile,
      fileName: json['file_name'] as String?,
      fileUrl: json['file_url'] as String?,
      fileSize: json['file_size'] as int?,
      fileMimeType: json['file_mime_type'] as String?,
      isVideoNote: json['encrypted_content_type'] == 'video_note',
      isPoll: json['encrypted_content_type'] == 'poll',
      pollOptions: (json['poll_options'] as List<dynamic>? ?? const [])
          .map((option) => option.toString())
          .toList(),
      pollAllowMultiple: json['poll_allow_multiple'] == true,
      pollClosed: json['poll_closed'] == true,
    );
  }

  // Метод для копирования с изменениями
  Message copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? forwardedFromUserId,
    String? forwardedFromName,
    String? content,
    DateTime? createdAt,
    bool? isMe,
    bool? senderIsChannel,
    User? sender,
    bool? isVoice,
    String? voiceUrl,
    Duration? voiceDuration,
    bool? isImage,
    bool? isSticker,
    bool? isGift,
    String? giftName,
    String? giftId,
    String? giftEmoji,
    int? giftPriceEnc,
    String? giftCaption,
    int? giftNftSerial,
    String? giftNftSkinName,
    String? giftNftSkinEmoji,
    String? giftNftBackgroundColor,
    String? giftNftPattern,
    String? giftNftAnimationUrl,
    String? imageCaption,
    bool? isEdited,
    bool? isDeleted,
    String? replyToId,
    String? replyToContent,
    String? replyToSender,
    bool? isFile,
    String? fileName,
    String? fileUrl,
    int? fileSize,
    String? fileMimeType,
    bool? isVideoNote,
    bool? isPoll,
    List<String>? pollOptions,
    bool? pollAllowMultiple,
    bool? pollClosed,
    Map<int, int>? pollVotes,
    List<int>? myPollVotes,
    bool? isPinned,
    bool? readByOthers,
    Map<String, int>? reactions,
    Map<String, List<User>>? reactionUsers,
    String? myReaction,
    bool clearMyReaction = false,
  }) {
    return Message(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      forwardedFromUserId: forwardedFromUserId ?? this.forwardedFromUserId,
      forwardedFromName: forwardedFromName ?? this.forwardedFromName,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      isMe: isMe ?? this.isMe,
      senderIsChannel: senderIsChannel ?? this.senderIsChannel,
      sender: sender ?? this.sender,
      isVoice: isVoice ?? this.isVoice,
      voiceUrl: voiceUrl ?? this.voiceUrl,
      voiceDuration: voiceDuration ?? this.voiceDuration,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
      replyToId: replyToId ?? this.replyToId,
      replyToContent: replyToContent ?? this.replyToContent,
      replyToSender: replyToSender ?? this.replyToSender,
      isImage: isImage ?? this.isImage,
      isSticker: isSticker ?? this.isSticker,
      isGift: isGift ?? this.isGift,
      giftName: giftName ?? this.giftName,
      giftId: giftId ?? this.giftId,
      giftEmoji: giftEmoji ?? this.giftEmoji,
      giftPriceEnc: giftPriceEnc ?? this.giftPriceEnc,
      giftCaption: giftCaption ?? this.giftCaption,
      giftNftSerial: giftNftSerial ?? this.giftNftSerial,
      giftNftSkinName: giftNftSkinName ?? this.giftNftSkinName,
      giftNftSkinEmoji: giftNftSkinEmoji ?? this.giftNftSkinEmoji,
      giftNftBackgroundColor:
          giftNftBackgroundColor ?? this.giftNftBackgroundColor,
      giftNftPattern: giftNftPattern ?? this.giftNftPattern,
      giftNftAnimationUrl:
          giftNftAnimationUrl ?? this.giftNftAnimationUrl,
      imageCaption: imageCaption ?? this.imageCaption,
      isFile: isFile ?? this.isFile,
      fileName: fileName ?? this.fileName,
      fileUrl: fileUrl ?? this.fileUrl,
      fileSize: fileSize ?? this.fileSize,
      fileMimeType: fileMimeType ?? this.fileMimeType,
      isVideoNote: isVideoNote ?? this.isVideoNote,
      isPoll: isPoll ?? this.isPoll,
      pollOptions: pollOptions ?? this.pollOptions,
      pollAllowMultiple: pollAllowMultiple ?? this.pollAllowMultiple,
      pollClosed: pollClosed ?? this.pollClosed,
      pollVotes: pollVotes ?? this.pollVotes,
      myPollVotes: myPollVotes ?? this.myPollVotes,
      isPinned: isPinned ?? this.isPinned,
      readByOthers: readByOthers ?? this.readByOthers,
      reactions: reactions ?? this.reactions,
      reactionUsers: reactionUsers ?? this.reactionUsers,
      myReaction: clearMyReaction ? null : myReaction ?? this.myReaction,
    );
  }

  // Преобразование в JSON для отправки
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'room_id': chatId,
      'profile_id': senderId,
      'sender_is_channel': senderIsChannel,
      'forwarded_from_user_id': forwardedFromUserId,
      'forwarded_from_name': forwardedFromName,
      'encrypted_content': content,
      'created_at': createdAt.toIso8601String(),
      'is_voice': isVoice,
      'voice_url': voiceUrl,
      'voice_duration': voiceDuration?.inSeconds,
      'is_image': isImage,
      'is_sticker': isSticker,
      'is_gift': isGift,
      'gift_id': giftId,
      'gift_name': giftName,
      'gift_emoji': giftEmoji,
      'gift_price_enc': giftPriceEnc,
      'gift_caption': giftCaption,
      'gift_nft_serial': giftNftSerial,
      'gift_nft_skin_name': giftNftSkinName,
      'gift_nft_skin_emoji': giftNftSkinEmoji,
      'gift_nft_background_color': giftNftBackgroundColor,
      'gift_nft_pattern': giftNftPattern,
      'gift_nft_animation_url': giftNftAnimationUrl,
      'image_caption': imageCaption,
      'reply_to_id': replyToId,
      'reply_to_content': replyToContent,
      'reply_to_sender': replyToSender,
      'is_file': isFile,
      'file_name': fileName,
      'file_url': fileUrl,
      'file_size': fileSize,
      'file_mime_type': fileMimeType,
      'encrypted_content_type': isVideoNote
          ? 'video_note'
          : isPoll
          ? 'poll'
          : null,
      'poll_options': pollOptions,
      'poll_allow_multiple': pollAllowMultiple,
      'poll_closed': pollClosed,
      'reactions': reactions,
      'my_reaction': myReaction,
    };
  }
}
