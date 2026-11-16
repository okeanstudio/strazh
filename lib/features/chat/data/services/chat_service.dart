import 'package:flutter/foundation.dart';
import 'package:strazh/features/auth/data/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/shared/domain/models/chat.dart';
import 'package:strazh/shared/domain/models/message.dart';
import 'package:strazh/shared/domain/models/user.dart' as app;
import 'package:strazh/features/chat/data/services/crypto_service.dart';
import 'package:strazh/core/utils/date_time_utils.dart';
import 'package:strazh/core/utils/rpc_user.dart';
import 'package:strazh/features/chat/data/services/storage_upload_service.dart';

String normalizeStoragePath(String path) {
  if (path.trim().isEmpty) return '';

  final normalized = path.replaceAll('\\', '/');
  final parts = normalized
      .split('/')
      .where((segment) => segment.trim().isNotEmpty)
      .toList();

  return parts.join('/');
}

String? storageObjectPath(String bucket, Object? value) {
  return StorageUploadService.objectPathFromStorageUrl(bucket, value);
}

String normalizeStorageUrl(String url) {
  var normalized = url.replaceAll(
    'http://81.19.136.44:54321',
    'https://strazh.denotestudio.ru',
  );
  normalized = normalized.replaceAll('\\', '/');

  if (normalized.contains('/storage/v1/object/') &&
      !normalized.contains('/storage/v1/object/public/')) {
    normalized = normalized.replaceFirst(
      '/storage/v1/object/',
      '/storage/v1/object/public/',
    );
  }

  return normalized;
}

class MessageReactionSummary {
  final Map<String, int> counts;
  final Map<String, List<app.User>> users;
  final String? myReaction;

  const MessageReactionSummary({
    this.counts = const {},
    this.users = const {},
    this.myReaction,
  });
}

class MessageAuthor {
  final String name;
  final String tag;
  final String? avatarUrl;
  final bool isChannel;

  const MessageAuthor({
    required this.name,
    required this.tag,
    required this.avatarUrl,
    this.isChannel = false,
  });
}

class ChatService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final AuthService _authService = AuthService();
  final CryptoService _crypto = CryptoService();
  MessageAuthor? _messageAuthor;

  void setMessageAuthor(MessageAuthor? author) {
    _messageAuthor = author;
  }

  Future<String?> resolveChatStorageUrl(String bucket, Object? value) async {
    final rawValue = value?.toString();
    if (rawValue == null || rawValue.isEmpty) return null;

    final objectPath = storageObjectPath(bucket, rawValue);
    if (objectPath == null) return rawValue;
    return StorageUploadService.createSignedUrl(
      bucket: bucket,
      path: objectPath,
      expiresIn: 3600,
    );
  }

  Map<String, dynamic> _senderFields(Map<String, dynamic> metadata) {
    final author = _messageAuthor;
    return {
      'sender_name': author?.name ?? metadata['name'] ?? 'Пользователь',
      'sender_tag': author?.tag ?? metadata['tag'] ?? '',
      'sender_avatar': author == null
          ? metadata['avatar_url']
          : author.avatarUrl,
      'sender_is_channel': author?.isChannel ?? false,
    };
  }

  @visibleForTesting
  static Map<String, dynamic> buildMessagePayload({
    required String roomId,
    required String userId,
    required String encryptedContent,
    String? replyToId,
    String? replyToContent,
    String? replyToSender,
    String encryptedContentType = 'text/plain',
    bool isImage = false,
    bool isVoice = false,
    String? imageCaption,
    String? voiceUrl,
    int? voiceDuration,
    String senderName = 'Пользователь',
    String senderTag = '',
    String? senderAvatar,
    bool senderIsChannel = false,
  }) {
    final payload = <String, dynamic>{
      'room_id': roomId,
      'profile_id': userId,
      'encrypted_content': encryptedContent,
      'encrypted_content_type': encryptedContentType,
      'sender_name': senderName,
      'sender_tag': senderTag,
      'sender_avatar': senderAvatar,
      'sender_is_channel': senderIsChannel,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (replyToId != null) {
      payload['reply_to_id'] = replyToId;
    }
    if (replyToContent != null) {
      payload['reply_to_content'] = replyToContent;
    }
    if (replyToSender != null) {
      payload['reply_to_sender'] = replyToSender;
    }
    if (isImage) {
      payload['is_image'] = true;
    }
    if (isVoice) {
      payload['is_voice'] = true;
    }
    if (imageCaption != null) {
      payload['image_caption'] = imageCaption;
    }
    if (voiceUrl != null) {
      payload['voice_url'] = voiceUrl;
    }
    if (voiceDuration != null) {
      payload['voice_duration'] = voiceDuration;
    }

    return payload;
  }

  Future<List<Chat>> getMyChats() async {
    final userId = _authService.currentUserId;
    if (userId == null) return [];

    final savedRoomId = await _getOrCreateSavedChat(userId);

    final response = await _supabase
        .from('room_participants')
        .select('''
          room_id,
          rooms!inner (
            id,
            name,
            type,
            created_at,
            updated_at,
            avatar_url,
            is_verified
          )
        ''')
        .eq('user_id', userId);

    final unreadCountRows = await _supabase.rpc('get_unread_message_counts');
    final unreadCountsByRoomId = <String, int>{
      for (final row in unreadCountRows)
        row['room_id'] as String: (row['unread_count'] as num).toInt(),
    };

    final chats = <Chat>[];
    final ownLastMessageIdsByChatId = <String, String>{};
    for (var item in response) {
      final rawRoomData = item['rooms'];
      final roomData = rawRoomData is Map<String, dynamic>
          ? rawRoomData
          : rawRoomData is List && rawRoomData.isNotEmpty
          ? Map<String, dynamic>.from(rawRoomData.first as Map)
          : <String, dynamic>{};
      if (roomData.isEmpty || roomData['id'] == null) continue;

      final roomId = roomData['id'] as String;
      final isSavedChat = roomId == savedRoomId;
      final lastMessage = await _getLastMessage(roomId);
      if (!isSavedChat && lastMessage?.isMe == true) {
        ownLastMessageIdsByChatId[roomId] = lastMessage!.id;
      }

      String chatName = isSavedChat ? 'Избранное' : roomData['name'] ?? 'Чат';
      String? avatarUrl = roomData['avatar_url'];

      if (!isSavedChat && roomData['type'] == 'direct') {
        final otherUser = await _getChatPartner(roomId, userId);
        chatName = otherUser?.name ?? 'Чат';
        avatarUrl = otherUser?.avatarUrl;
      }

      chats.add(
        Chat(
          id: roomId,
          name: chatName,
          lastMessage: lastMessage?.content ?? 'Нет сообщений',
          lastMessageTime: lastMessage?.createdAt,
          avatarUrl: avatarUrl,
          unreadCount: unreadCountsByRoomId[roomId] ?? 0,
          type: isSavedChat ? 'saved' : roomData['type'] ?? 'direct',
          lastMessageIsMe: lastMessage?.isMe ?? false,
          lastMessageReadByOthers: isSavedChat && lastMessage?.isMe == true,
          isVerified: roomData['is_verified'] == true,
        ),
      );
    }

    final loginRequests = await _supabase
        .from('phone_login_challenges')
        .select('created_at, expires_at, seen_at, consumed_at, login_code')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50);
    final newestLoginRequest = loginRequests.firstOrNull;
    final activeLoginRequests = loginRequests.where((request) {
      final expiresAt = DateTime.tryParse(
        request['expires_at'] as String? ?? '',
      );
      return expiresAt != null &&
          expiresAt.isAfter(DateTime.now().toUtc()) &&
          request['consumed_at'] == null;
    }).toList();
    final unreadLoginRequests = activeLoginRequests
        .where((request) => request['seen_at'] == null)
        .length;
    chats.add(
      Chat(
        id: 'system:login-codes',
        name: 'Коды входа',
        lastMessage: activeLoginRequests.isNotEmpty
            ? 'Код входа: ${activeLoginRequests.first['login_code'] ?? ''}'
            : 'Здесь появятся коды для входа',
        lastMessageTime: newestLoginRequest == null
            ? null
            : DateTime.tryParse(
                newestLoginRequest['created_at'] as String? ?? '',
              )?.toLocal(),
        unreadCount: unreadLoginRequests,
        type: 'login_codes',
      ),
    );

    if (ownLastMessageIdsByChatId.isNotEmpty) {
      try {
        final readMessageIds = await getReadMessageIds(
          ownLastMessageIdsByChatId.values.toList(),
          userId,
        );
        for (var index = 0; index < chats.length; index++) {
          final messageId = ownLastMessageIdsByChatId[chats[index].id];
          if (messageId != null) {
            chats[index] = chats[index].withLastMessageReadByOthers(
              readMessageIds.contains(messageId),
            );
          }
        }
      } catch (error) {
        debugPrint('Не удалось загрузить статусы последних сообщений: $error');
      }
    }

    return sortChats(chats);
  }

  Future<Chat?> refreshChatLastMessage(
    Chat chat, {
    Map<String, dynamic>? messageRecord,
  }) async {
    final userId = _authService.currentUserId;
    if (userId == null) return null;

    final lastMessage = messageRecord == null
        ? await _getLastMessage(chat.id)
        : await _lastMessageFromRecord(messageRecord, userId);
    if (lastMessage == null) return null;
    if (lastMessage.chatId != chat.id) return null;
    if (chat.lastMessageTime != null &&
        lastMessage.createdAt.isBefore(chat.lastMessageTime!)) {
      return chat;
    }

    var unreadCount = chat.unreadCount;
    if (messageRecord != null && !lastMessage.isMe) {
      final unreadCountRows = await _supabase.rpc(
        'get_unread_message_counts',
        params: {'p_room_id': chat.id},
      );
      unreadCount = unreadCountRows.isEmpty
          ? 0
          : (unreadCountRows.first['unread_count'] as num).toInt();
    }

    return Chat(
      id: chat.id,
      name: chat.name,
      lastMessage: lastMessage.content,
      lastMessageTime: lastMessage.createdAt,
      avatarUrl: chat.avatarUrl,
      unreadCount: unreadCount,
      type: chat.type,
      lastMessageIsMe: lastMessage.isMe,
      lastMessageReadByOthers: chat.type == 'saved' && lastMessage.isMe,
      isVerified: chat.isVerified,
    );
  }

  Future<Message> _lastMessageFromRecord(
    Map<String, dynamic> data,
    String currentUserId,
  ) async {
    final isVoice = data['is_voice'] == true;
    final isImage = Message.isImageMessage(data);
    final isSticker = Message.isStickerMessage(data);
    final isFile = data['is_file'] == true;

    String content;
    if (isFile) {
      content = '📎 ${data['file_name'] as String? ?? 'Файл'}';
    } else if (isImage) {
      content = isSticker ? 'Стикер' : '📷 Фото';
      final encryptedCaption = data['image_caption'];
      if (encryptedCaption != null && !isSticker) {
        try {
          content =
              '📷 ${await _crypto.decodeRoomContent(roomId: data['room_id'] as String, senderId: data['profile_id'] as String, content: encryptedCaption.toString())}';
        } catch (error) {
          debugPrint('Не удалось расшифровать превью фото: $error');
        }
      }
    } else if (isVoice) {
      content = '🎤 Голосовое сообщение';
    } else {
      final encryptedContent = data['encrypted_content']?.toString() ?? '';
      if (encryptedContent.isEmpty) {
        content = '';
      } else {
        try {
          content = await _crypto.decodeRoomContent(
            roomId: data['room_id'] as String,
            senderId: data['profile_id'] as String,
            content: encryptedContent,
          );
        } catch (error) {
          debugPrint('Не удалось расшифровать превью сообщения: $error');
          content = '[Не удалось расшифровать сообщение]';
        }
      }
    }

    return Message(
      id: data['id'] as String,
      chatId: data['room_id'] as String,
      senderId: data['profile_id'] as String,
      content: content.replaceAll(
        'http://81.19.136.44:54321',
        'https://strazh.denotestudio.ru',
      ),
      createdAt: parseDateTimeSafely(data['created_at']),
      isMe: data['profile_id'] == currentUserId,
      isVoice: isVoice,
      isImage: isImage,
      isSticker: isSticker,
      isFile: isFile,
      isVideoNote: data['encrypted_content_type'] == 'video_note',
    );
  }

  Future<List<Chat>> searchGroups(String query) async {
    final userId = _authService.currentUserId;
    final normalizedQuery = query.trim();
    if (userId == null || normalizedQuery.length < 2) return [];

    final joinedRooms = await _supabase
        .from('room_participants')
        .select('room_id')
        .eq('user_id', userId);
    final joinedIds = joinedRooms
        .map((row) => row['room_id'] as String)
        .toList();

    var request = _supabase
        .from('rooms')
        .select(
          'id, name, type, avatar_url, description, tag, is_private, is_verified',
        )
        .inFilter('type', ['group', 'channel'])
        .eq('is_private', false)
        .or(
          'name.ilike.%$normalizedQuery%,tag.ilike.%$normalizedQuery%,description.ilike.%$normalizedQuery%',
        )
        .limit(30);

    final response = await request;
    return response
        .where((row) => !joinedIds.contains(row['id']))
        .map(
          (row) => Chat(
            id: row['id'] as String,
            name: row['name'] as String? ?? 'Группа',
            avatarUrl: row['avatar_url'] as String?,
            type: row['type'] as String? ?? 'group',
            isVerified: row['is_verified'] == true,
          ),
        )
        .toList();
  }

  Future<Chat?> joinGroup(String roomId) async {
    final userId = _authService.currentUserId;
    if (userId == null) return null;

    final existing = await _supabase
        .from('room_participants')
        .select('room_id')
        .eq('room_id', roomId)
        .eq('user_id', userId)
        .maybeSingle();

    final room = await _supabase
        .from('rooms')
        .select('id, name, type, avatar_url, is_private, is_verified')
        .eq('id', roomId)
        .inFilter('type', ['group', 'channel'])
        .maybeSingle();
    if (room == null || (room['is_private'] == true && existing == null)) {
      return null;
    }

    if (existing == null) {
      await _supabase.from('room_participants').insert({
        'room_id': roomId,
        'user_id': userId,
        'joined_at': DateTime.now().toUtc().toIso8601String(),
      });
    }

    return Chat(
      id: room['id'] as String,
      name: room['name'] as String? ?? 'Группа',
      avatarUrl: room['avatar_url'] as String?,
      type: room['type'] as String? ?? 'group',
      isVerified: room['is_verified'] == true,
    );
  }

  static List<Chat> sortChats(List<Chat> chats) {
    final sortedChats = List<Chat>.from(chats);

    sortedChats.sort((a, b) {
      if (a.type == 'saved' && b.type != 'saved') return -1;
      if (b.type == 'saved' && a.type != 'saved') return 1;
      final aTime = a.lastMessageTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.lastMessageTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final timeComparison = bTime.compareTo(aTime);
      if (timeComparison != 0) {
        return timeComparison;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return sortedChats;
  }

  static List<Chat> mergeChats(
    List<Chat> existingChats,
    List<Chat> refreshedChats,
  ) {
    final mergedChats = <Chat>[];
    final previousChatsById = {for (final chat in existingChats) chat.id: chat};

    for (final refreshedChat in refreshedChats) {
      final previousChat = previousChatsById[refreshedChat.id];
      if (previousChat != null) {
        mergedChats.add(
          Chat(
            id: refreshedChat.id,
            name: refreshedChat.name.isNotEmpty
                ? refreshedChat.name
                : previousChat.name,
            lastMessage: refreshedChat.lastMessage,
            lastMessageTime: refreshedChat.lastMessageTime,
            avatarUrl: refreshedChat.avatarUrl,
            unreadCount: refreshedChat.unreadCount,
            type: refreshedChat.type,
            lastMessageIsMe: refreshedChat.lastMessageIsMe,
            lastMessageReadByOthers: refreshedChat.lastMessageReadByOthers,
            isVerified: refreshedChat.isVerified,
          ),
        );
      } else {
        mergedChats.add(refreshedChat);
      }
    }

    return sortChats(mergedChats);
  }

  Future<String> _getOrCreateSavedChat(String userId) async {
    final savedChat = await _supabase
        .from('saved_chats')
        .select('room_id')
        .eq('user_id', userId)
        .maybeSingle();
    if (savedChat != null) return savedChat['room_id'] as String;

    final room = await _supabase
        .from('rooms')
        .insert({
          'type': 'direct',
          'created_by': userId,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select('id')
        .single();
    final roomId = room['id'] as String;

    await _supabase.from('room_participants').insert({
      'room_id': roomId,
      'user_id': userId,
      'joined_at': DateTime.now().toUtc().toIso8601String(),
    });
    await _supabase.from('saved_chats').insert({
      'user_id': userId,
      'room_id': roomId,
    });

    return roomId;
  }

  Future<List<Message>> getMessages(String roomId) async {
    final currentUserId = _authService.currentUserId;
    if (currentUserId == null) return [];

    final currentUser = _authService.getCurrentUser();
    final currentUserMetadata = currentUser?.userMetadata ?? {};
    final currentUserAvatar = currentUserMetadata['avatar_url'] as String?;

    final response = await _supabase
        .from('messages')
        .select()
        .eq('room_id', roomId)
        .order('created_at', ascending: true);

    final List<Message> messages = [];

    for (var data in response) {
      app.User? sender;

      var isMe = data['profile_id'] == currentUserId;

      if (!isMe &&
          data['sender_avatar'] != null &&
          currentUserAvatar != null &&
          data['sender_avatar'] == currentUserAvatar) {
        isMe = true;
      }

      if (data['sender_is_channel'] == true) {
        sender = app.User(
          id: data['profile_id'],
          name: data['sender_name'] ?? 'Канал',
          tag: data['sender_tag'] ?? '',
          avatarUrl: data['sender_avatar'],
        );
      } else if (!isMe) {
        final userData = await _supabase.rpc(
          'get_user_by_id',
          params: {'p_id': data['profile_id']},
        );

        sender = app.User(
          id: data['profile_id'],
          name: userData?['name'] ?? data['sender_name'] ?? 'Пользователь',
          tag: userData?['tag'] ?? data['sender_tag'] ?? '',
          avatarUrl: userData?['avatar_url'] ?? data['sender_avatar'],
          badge: userData?['badge'] as String?,
        );
      } else {
        sender = app.User(
          id: currentUserId,
          name:
              currentUserMetadata['name'] ??
              data['sender_name'] ??
              'Пользователь',
          tag: currentUserMetadata['tag'] ?? data['sender_tag'] ?? '',
          avatarUrl: currentUserMetadata['avatar_url'] ?? data['sender_avatar'],
          badge: currentUserMetadata['badge'] as String?,
        );
      }

      final isVoice = data['is_voice'] ?? false;
      final isImage = Message.isImageMessage(data);
      final isPoll = data['encrypted_content_type'] == 'poll';
      var isGift = Message.isGiftMessage(data);
      final rawGiftName = data['gift_name']?.toString();
      var giftName = rawGiftName?.isNotEmpty == true
          ? rawGiftName
          : Message.giftNameFromContent(data['encrypted_content']?.toString());
      final isSticker = Message.isStickerMessage(data);
      final isFile = data['is_file'] ?? false;
      final pollOptions = <String>[];
      if (isPoll) {
        for (final value
            in data['poll_options'] as List<dynamic>? ?? const []) {
          pollOptions.add(
            await _crypto.decodeRoomContent(
              roomId: roomId,
              senderId: data['profile_id'] as String,
              content: value.toString(),
            ),
          );
        }
      }

      String decryptedContent = '';
      String? decryptedCaption;

      if (isGift) {
        decryptedContent = data['encrypted_content']?.toString() ?? 'Подарок';
      } else if (isFile) {
        final fileName = data['file_name'] as String? ?? 'Файл';
        decryptedContent = '📎 $fileName';
      } else if (isPoll) {
        decryptedContent = await _crypto.decodeRoomContent(
          roomId: roomId,
          senderId: data['profile_id'] as String,
          content: data['encrypted_content']?.toString() ?? '',
        );
      } else if (isImage) {
        decryptedContent = data['encrypted_content'] ?? '';
        decryptedContent = normalizeStorageUrl(decryptedContent);
        decryptedContent =
            await resolveChatStorageUrl('chat_media', decryptedContent) ??
            decryptedContent;

        if (data['image_caption'] != null &&
            data['image_caption'].toString().isNotEmpty) {
          try {
            decryptedCaption = await _crypto.decodeRoomContent(
              roomId: roomId,
              senderId: data['profile_id'] as String,
              content: data['image_caption'].toString(),
            );
          } catch (e) {
            debugPrint('Не удалось расшифровать подпись: $e');
            decryptedCaption = '[Не удалось расшифровать подпись]';
          }
        }
      } else if (isVoice) {
        decryptedContent = '🎤 Голосовое сообщение';
      } else {
        final encryptedContent = data['encrypted_content'] ?? '';
        if (encryptedContent.isNotEmpty) {
          try {
            decryptedContent = await _crypto.decodeRoomContent(
              roomId: roomId,
              senderId: data['profile_id'] as String,
              content: encryptedContent.toString(),
            );
          } catch (e) {
            debugPrint('Не удалось расшифровать сообщение ${data['id']}: $e');
            decryptedContent = '[Не удалось расшифровать сообщение]';
          }
        }
      }

      final legacyGiftName = Message.giftNameFromContent(decryptedContent);
      if (legacyGiftName != null) {
        isGift = true;
        giftName ??= legacyGiftName;
      }

      messages.add(
        Message(
          id: data['id'],
          chatId: data['room_id'],
          senderId: data['profile_id'],
          forwardedFromUserId: data['forwarded_from_user_id'] as String?,
          forwardedFromName: data['forwarded_from_name'] as String?,
          content: decryptedContent,
          createdAt: parseDateTimeSafely(data['created_at']),
          isMe: isMe,
          senderIsChannel: data['sender_is_channel'] == true,
          sender: sender,
          isVoice: isVoice,
          isImage: isImage,
          isPoll: isPoll,
          pollOptions: pollOptions,
          pollAllowMultiple: data['poll_allow_multiple'] == true,
          pollClosed: data['poll_closed'] == true,
          isSticker: isSticker,
          isGift: isGift,
          giftName: giftName,
          giftEmoji: data['gift_emoji'] as String?,
          giftPriceEnc: (data['gift_price_enc'] as num?)?.toInt(),
          giftCaption: data['gift_caption'] as String?,
          giftNftSerial: (data['gift_nft_serial'] as num?)?.toInt(),
          giftNftSkinName: data['gift_nft_skin_name'] as String?,
          giftNftSkinEmoji: data['gift_nft_skin_emoji'] as String?,
          giftNftBackgroundColor: data['gift_nft_background_color'] as String?,
          giftNftPattern: data['gift_nft_pattern'] as String?,
          giftNftAnimationUrl: data['gift_nft_animation_url'] as String?,
          imageCaption: decryptedCaption,
          voiceUrl: await resolveChatStorageUrl(
            'voice_messages',
            data['voice_url'],
          ),
          voiceDuration: data['voice_duration'] != null
              ? Duration(seconds: data['voice_duration'] as int)
              : null,
          isEdited: data['is_edited'] ?? false,
          isDeleted: data['is_deleted'] ?? false,
          replyToId: data['reply_to_id'] as String?,
          replyToContent: data['reply_to_content'] as String?,
          replyToSender: data['reply_to_sender'] as String?,
          isFile: isFile,
          fileName: data['file_name'] as String?,
          fileUrl: await resolveChatStorageUrl(
            data['encrypted_content_type'] == 'video_note'
                ? 'chat_media'
                : 'chat_files',
            data['file_url'],
          ),
          fileSize: data['file_size'] as int?,
          fileMimeType: data['file_mime_type'] as String?,
          isVideoNote: data['encrypted_content_type'] == 'video_note',
          isPinned: data['is_pinned'] ?? false,
        ),
      );
    }

    final withReactions = await _attachReactions(messages, currentUserId);
    return _attachPollVotes(withReactions, currentUserId);
  }

  Future<String?> sendMessage(String roomId, String content) async {
    final userId = _authService.currentUserId;
    if (userId == null) return null;

    final currentUser = _authService.getCurrentUser();
    final metadata = currentUser?.userMetadata ?? {};

    final encryptedContent = await _crypto.encryptRoomContent(
      roomId: roomId,
      senderId: userId,
      content: content,
    );
    final payload = buildMessagePayload(
      roomId: roomId,
      userId: userId,
      encryptedContent: encryptedContent,
      senderName: metadata['name'] ?? 'Пользователь',
      senderTag: metadata['tag'] ?? '',
      senderAvatar: metadata['avatar_url'],
    );

    final response = await _supabase
        .from('messages')
        .insert({...payload, ..._senderFields(metadata)})
        .select('id')
        .single();

    return response['id'] as String?;
  }

  Future<void> forwardMessage(Message message, String targetRoomId) async {
    final userId = _authService.currentUserId;
    if (userId == null) throw Exception('Пользователь не авторизован');

    final currentUser = _authService.getCurrentUser();
    final metadata = currentUser?.userMetadata ?? {};
    final payload = <String, dynamic>{
      'room_id': targetRoomId,
      'profile_id': userId,
      'forwarded_from_user_id': message.forwardedFromUserId ?? message.senderId,
      'forwarded_from_name':
          message.forwardedFromName ?? message.sender?.name ?? 'Пользователь',
      'sender_name': metadata['name'] ?? 'Пользователь',
      'sender_tag': metadata['tag'] ?? '',
      'sender_avatar': metadata['avatar_url'],
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (message.isGift) {
      payload.addAll({
        'is_gift': true,
        'gift_name': message.giftName,
        'gift_emoji': message.giftEmoji,
        'gift_price_enc': message.giftPriceEnc,
        'gift_caption': message.giftCaption,
        'encrypted_content_type': 'gift',
        'encrypted_content': message.content,
      });
    } else if (message.isVoice) {
      payload.addAll({
        'is_voice': true,
        'voice_url':
            storageObjectPath('voice_messages', message.voiceUrl) ??
            message.voiceUrl,
        'voice_duration': message.voiceDuration?.inSeconds,
        'encrypted_content': _crypto.encodeCloudContent(
          'voice_message_forwarded',
        ),
      });
    } else if (message.isVideoNote) {
      payload.addAll({
        'is_file': true,
        'file_url':
            storageObjectPath('chat_media', message.fileUrl) ?? message.fileUrl,
        'file_name': message.fileName,
        'file_size': message.fileSize,
        'file_mime_type': message.fileMimeType,
        'encrypted_content_type': 'video_note',
        'encrypted_content': message.content,
      });
    } else if (message.isFile) {
      payload.addAll({
        'is_file': true,
        'file_url':
            storageObjectPath('chat_files', message.fileUrl) ?? message.fileUrl,
        'file_name': message.fileName,
        'file_size': message.fileSize,
        'file_mime_type': message.fileMimeType,
        'encrypted_content': _crypto.encodeCloudContent(
          '📎 ${message.fileName ?? 'Файл'}',
        ),
      });
    } else if (message.isImage) {
      payload.addAll({
        'is_image': true,
        'encrypted_content_type': message.isSticker
            ? 'sticker'
            : message.fileMimeType ?? 'image/jpeg',
        'encrypted_content':
            storageObjectPath('chat_media', message.content) ?? message.content,
        'image_caption': message.imageCaption?.isNotEmpty == true
            ? await _crypto.encryptRoomContent(
                roomId: targetRoomId,
                senderId: userId,
                content: message.imageCaption!,
              )
            : null,
      });
    } else {
      payload['encrypted_content'] = await _crypto.encryptRoomContent(
        roomId: targetRoomId,
        senderId: userId,
        content: message.content,
      );
    }

    await _supabase.from('messages').insert(payload);
  }

  Future<void> sendPhotoMessage(
    String roomId,
    String photoUrl, {
    String caption = '',
  }) async {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    final currentUser = _authService.getCurrentUser();
    final metadata = currentUser?.userMetadata ?? {};

    final encryptedCaption = caption.isNotEmpty
        ? await _crypto.encryptRoomContent(
            roomId: roomId,
            senderId: userId,
            content: caption,
          )
        : null;

    await _supabase.from('messages').insert({
      'room_id': roomId,
      'profile_id': userId,
      'encrypted_content': photoUrl,
      'encrypted_content_type': 'image/jpeg',
      'is_image': true,
      'image_caption': encryptedCaption,
      ..._senderFields(metadata),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> sendStickerMessage(String roomId, String stickerUrl) async {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    final currentUser = _authService.getCurrentUser();
    final metadata = currentUser?.userMetadata ?? {};

    await _supabase.from('messages').insert({
      'room_id': roomId,
      'profile_id': userId,
      'encrypted_content': stickerUrl,
      'encrypted_content_type': 'sticker',
      'is_image': true,
      ..._senderFields(metadata),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<String?> sendPollMessage({
    required String roomId,
    required String question,
    required List<String> options,
    required bool allowMultiple,
  }) async {
    final userId = _authService.currentUserId;
    if (userId == null) throw StateError('Необходимо войти в аккаунт');
    if (options.length < 2 || options.length > 10) {
      throw ArgumentError('В опросе должно быть от 2 до 10 вариантов');
    }

    final currentUser = _authService.getCurrentUser();
    final metadata = currentUser?.userMetadata ?? {};
    final encryptedOptions = await Future.wait(
      options.map(
        (option) => _crypto.encryptRoomContent(
          roomId: roomId,
          senderId: userId,
          content: option.trim(),
        ),
      ),
    );
    final response = await _supabase
        .from('messages')
        .insert({
          'room_id': roomId,
          'profile_id': userId,
          'encrypted_content': await _crypto.encryptRoomContent(
            roomId: roomId,
            senderId: userId,
            content: question.trim(),
          ),
          'encrypted_content_type': 'poll',
          'poll_options': encryptedOptions,
          'poll_allow_multiple': allowMultiple,
          'poll_closed': false,
          ..._senderFields(metadata),
          'created_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select('id')
        .single();
    return response['id'] as String?;
  }

  Future<Map<String, dynamic>> getPollVoteSummary(
    String messageId, {
    String? userId,
  }) async {
    final currentUserId = userId ?? _authService.currentUserId;
    final rows = await _supabase
        .from('message_poll_votes')
        .select('user_id, option_indices')
        .eq('message_id', messageId);

    final counts = <int, int>{};
    List<int> myVotes = [];
    for (final row in rows) {
      final selectedOptions = (row['option_indices'] as List<dynamic>)
          .map((index) => (index as num).toInt())
          .toList();
      for (final optionIndex in selectedOptions) {
        counts[optionIndex] = (counts[optionIndex] ?? 0) + 1;
      }
      if (row['user_id'] == currentUserId) myVotes = selectedOptions;
    }
    return {'counts': counts, 'my_votes': myVotes, 'total': rows.length};
  }

  Future<void> voteOnPoll({
    required String messageId,
    required List<int> optionIndices,
  }) async {
    final userId = _authService.currentUserId;
    if (userId == null) throw StateError('Необходимо войти в аккаунт');
    if (optionIndices.isEmpty) {
      await _supabase
          .from('message_poll_votes')
          .delete()
          .eq('message_id', messageId)
          .eq('user_id', userId);
      return;
    }
    await _supabase.from('message_poll_votes').upsert({
      'message_id': messageId,
      'user_id': userId,
      'option_indices': optionIndices.toSet().toList()..sort(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'message_id,user_id');
  }

  Future<String> sendFileMessage(
    String chatId,
    String fileUrl,
    String fileName,
    int fileSize,
  ) async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) {
        throw Exception('Не авторизован');
      }

      final currentUser = _authService.getCurrentUser();
      final metadata = currentUser?.userMetadata ?? {};

      final data = {
        'room_id': chatId,
        'profile_id': userId,
        'is_file': true,
        'file_url': fileUrl,
        'file_name': fileName,
        'file_size': fileSize,
        'encrypted_content': '📎 $fileName',
        ..._senderFields(metadata),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      final response = await Supabase.instance.client
          .from('messages')
          .insert(data)
          .select('id')
          .single();

      return response['id'] as String;
    } catch (e) {
      throw Exception('Ошибка отправки файла: $e');
    }
  }

  Future<String> sendVideoNoteMessage(
    String roomId,
    String videoUrl,
    String fileName,
    int fileSize,
  ) async {
    final userId = _authService.currentUserId;
    if (userId == null) throw StateError('Пользователь не авторизован');

    final currentUser = _authService.getCurrentUser();
    final metadata = currentUser?.userMetadata ?? {};
    final response = await _supabase
        .from('messages')
        .insert({
          'room_id': roomId,
          'profile_id': userId,
          'is_file': true,
          'file_url': videoUrl,
          'file_name': fileName,
          'file_size': fileSize,
          'file_mime_type': 'video/mp4',
          'encrypted_content': videoUrl,
          'encrypted_content_type': 'video_note',
          ..._senderFields(metadata),
          'created_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select('id')
        .single();

    return response['id'] as String;
  }

  Future<void> editMessage(
    String messageId,
    String newContent,
    String userId, {
    bool editCaption = false,
  }) async {
    try {
      final message = await _supabase
          .from('messages')
          .select(
            'profile_id, room_id, encrypted_content_type, is_image, '
            'is_voice, is_file, forwarded_from_user_id',
          )
          .eq('id', messageId)
          .maybeSingle();

      if (message == null) {
        throw Exception('Сообщение не найдено');
      }
      if (message['profile_id'] != userId) {
        throw Exception('Нельзя редактировать чужое сообщение');
      }
      if (message['forwarded_from_user_id'] != null) {
        throw Exception('Пересланные сообщения нельзя редактировать');
      }
      if ((editCaption && message['is_image'] != true) ||
          (!editCaption &&
              (message['encrypted_content_type'] != 'text/plain' ||
                  message['is_image'] == true)) ||
          message['is_voice'] == true ||
          message['is_file'] == true) {
        throw StateError('Этот тип сообщения нельзя отредактировать');
      }

      final encryptedContent = await _crypto.encryptRoomContent(
        roomId: message['room_id'] as String,
        senderId: userId,
        content: newContent,
      );

      final updateData = <String, dynamic>{
        'is_edited': true,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (editCaption) {
        updateData['image_caption'] = encryptedContent;
      } else {
        updateData['encrypted_content'] = encryptedContent;
      }

      final result = await _supabase
          .from('messages')
          .update(updateData)
          .eq('id', messageId)
          .select('id, is_edited, updated_at');

      if (result.isEmpty) {
        throw Exception('UPDATE затронул 0 строк (RLS или неверный id)');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteMessage(String messageId, String userId) async {
    try {
      final deleted = await _supabase
          .from('messages')
          .delete()
          .eq('id', messageId)
          .select('id');

      debugPrint('DELETE >> deleted rows = ${deleted.length}');

      if (deleted.isEmpty) {
        throw Exception(
          'Не удалось удалить: DELETE затронул 0 строк. Проверь RLS на messages.',
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> sendVoiceMessage(
    String roomId,
    String voiceUrl,
    Duration duration,
    String encryptedContent,
  ) async {
    final userId = _authService.currentUserId;
    if (userId == null) {
      throw Exception('Пользователь не авторизован');
    }

    final currentUser = _authService.getCurrentUser();
    final metadata = currentUser?.userMetadata ?? {};

    await _supabase.from('messages').insert({
      'room_id': roomId,
      'profile_id': userId,
      'is_voice': true,
      'voice_url': voiceUrl,
      'voice_duration': duration.inSeconds,
      'encrypted_content': encryptedContent,
      ..._senderFields(metadata),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<String?> sendReplyMessage(
    String roomId,
    String content,
    String replyToId,
  ) async {
    final userId = _authService.currentUserId;
    if (userId == null) {
      throw Exception('Пользователь не авторизован');
    }

    final currentUser = _authService.getCurrentUser();
    final metadata = currentUser?.userMetadata ?? {};

    final replyMessage = await _supabase
        .from('messages')
        .select('room_id, sender_name')
        .eq('id', replyToId)
        .maybeSingle();

    if (replyMessage == null) {
      throw Exception('Сообщение не найдено');
    }
    if (replyMessage['room_id'] != roomId) {
      throw StateError('Нельзя ответить на сообщение из другого чата');
    }

    final encryptedContent = await _crypto.encryptRoomContent(
      roomId: roomId,
      senderId: userId,
      content: content,
    );
    const replyToContent = 'Зашифрованное сообщение';
    final senderFields = _senderFields(metadata);

    final payload = buildMessagePayload(
      roomId: roomId,
      userId: userId,
      encryptedContent: encryptedContent,
      replyToId: replyToId,
      replyToContent: replyToContent,
      replyToSender: replyMessage['sender_name'] ?? 'Пользователь',
      senderName: senderFields['sender_name'] as String,
      senderTag: senderFields['sender_tag'] as String,
      senderAvatar: senderFields['sender_avatar'] as String?,
      senderIsChannel: senderFields['sender_is_channel'] == true,
    );

    final response = await _supabase
        .from('messages')
        .insert(payload)
        .select('id')
        .single();

    return response['id'] as String?;
  }

  Future<Message?> _getLastMessage(String roomId) async {
    final currentUserId = _authService.currentUserId;
    if (currentUserId == null) return null;

    final response = await _supabase
        .from('messages')
        .select()
        .eq('room_id', roomId)
        .order('created_at', ascending: false)
        .limit(1);

    if (response.isEmpty) return null;

    final data = response[0];

    final isVoice = data['is_voice'] ?? false;
    final isImage = Message.isImageMessage(data);
    final isSticker = Message.isStickerMessage(data);
    final isFile = data['is_file'] ?? false;

    String decryptedContent;

    if (isFile) {
      if (data['encrypted_content_type'] == 'video_note') {
        decryptedContent = 'Кружок';
      } else {
        final fileName = data['file_name'] as String? ?? 'Файл';
        decryptedContent = '📎 $fileName';
      }
    } else if (isImage) {
      decryptedContent = isSticker ? 'Стикер' : '📷 Фото';
      if (data['image_caption'] != null && !isSticker) {
        try {
          final caption = await _crypto.decodeRoomContent(
            roomId: roomId,
            senderId: data['profile_id'] as String,
            content: data['image_caption'].toString(),
          );
          decryptedContent = '📷 $caption';
        } catch (_) {}
      }
    } else if (isVoice) {
      decryptedContent = '🎤 Голосовое сообщение';
    } else {
      final encryptedContent = data['encrypted_content'] ?? '';
      if (encryptedContent.isEmpty) {
        decryptedContent = '';
      } else {
        try {
          decryptedContent = await _crypto.decodeRoomContent(
            roomId: roomId,
            senderId: data['profile_id'] as String,
            content: encryptedContent.toString(),
          );
        } catch (e) {
          decryptedContent = 'Сообщение';
        }
      }
    }

    decryptedContent = decryptedContent.replaceAll(
      'http://81.19.136.44:54321',
      'https://strazh.denotestudio.ru',
    );

    return Message(
      id: data['id'],
      chatId: data['room_id'],
      senderId: data['profile_id'],
      forwardedFromUserId: data['forwarded_from_user_id'] as String?,
      forwardedFromName: data['forwarded_from_name'] as String?,
      content: decryptedContent,
      createdAt: parseDateTimeSafely(data['created_at']),
      isMe: data['profile_id'] == currentUserId,
      sender: null,
      isVoice: isVoice,
      isImage: isImage,
      isSticker: isSticker,
      imageCaption: data['image_caption'] as String?,
      voiceUrl: data['voice_url'] as String?,
      voiceDuration: data['voice_duration'] != null
          ? Duration(seconds: data['voice_duration'] as int)
          : null,
      isFile: isFile,
      isVideoNote: data['encrypted_content_type'] == 'video_note',
      fileName: data['file_name'] as String?,
      fileUrl: data['file_url'] as String?,
      fileSize: data['file_size'] as int?,
    );
  }

  Future<void> clearChatHistory(String roomId, String userId) async {
    try {
      await Supabase.instance.client
          .from('messages')
          .delete()
          .eq('room_id', roomId);
    } catch (e) {
      throw Exception('Ошибка очистки истории: $e');
    }
  }

  Future<List<Message>> getMessagesPaginated(
    String roomId, {
    int limit = 20,
    DateTime? before,
    required app.User currentUser,
    required CryptoService cryptoService,
  }) async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) throw Exception('Не авторизован');

      var filterQuery = _supabase
          .from('messages')
          .select('*')
          .eq('room_id', roomId);

      if (before != null) {
        filterQuery = filterQuery.lt(
          'created_at',
          before.toUtc().toIso8601String(),
        );
      }

      final response = await filterQuery
          .order('created_at', ascending: false)
          .limit(limit);

      final List<Message> messages = [];
      for (final record in response.reversed) {
        try {
          final isMe = record['profile_id'] == currentUser.id;
          final isVoice = record['is_voice'] ?? false;
          final isImage = Message.isImageMessage(record);
          final isPoll = record['encrypted_content_type'] == 'poll';
          var isGift = Message.isGiftMessage(record);
          final rawGiftName = record['gift_name']?.toString();
          var giftName = rawGiftName?.isNotEmpty == true
              ? rawGiftName
              : Message.giftNameFromContent(
                  record['encrypted_content']?.toString(),
                );
          final isSticker = Message.isStickerMessage(record);
          final isFile = record['is_file'] ?? false;
          final pollOptions = <String>[];
          if (isPoll) {
            for (final value
                in record['poll_options'] as List<dynamic>? ?? const []) {
              pollOptions.add(
                await cryptoService.decodeRoomContent(
                  roomId: roomId,
                  senderId: record['profile_id'] as String,
                  content: value.toString(),
                ),
              );
            }
          }

          String decryptedContent = '';
          String? decryptedCaption;

          if (isGift) {
            decryptedContent =
                record['encrypted_content']?.toString() ?? 'Подарок';
          } else if (isImage) {
            decryptedContent = normalizeStorageUrl(
              cryptoService.decodeCloudContent(
                record['encrypted_content']?.toString() ?? '',
              ),
            );
            decryptedContent =
                await resolveChatStorageUrl('chat_media', decryptedContent) ??
                decryptedContent;
            if (record['image_caption'] != null &&
                record['image_caption'].toString().isNotEmpty) {
              try {
                decryptedCaption = await cryptoService.decodeRoomContent(
                  roomId: roomId,
                  senderId: record['profile_id'] as String,
                  content: record['image_caption'].toString(),
                );
              } catch (e) {
                debugPrint('Не удалось расшифровать подпись: $e');
                decryptedCaption = '[Не удалось расшифровать подпись]';
              }
            }
          } else if (isPoll) {
            decryptedContent = await cryptoService.decodeRoomContent(
              roomId: roomId,
              senderId: record['profile_id'] as String,
              content: record['encrypted_content']?.toString() ?? '',
            );
          } else if (isFile) {
            final fileName = record['file_name'] as String? ?? 'Файл';
            decryptedContent = '📎 $fileName';
          } else if (!isVoice) {
            final encryptedContent = record['encrypted_content'] ?? '';
            if (encryptedContent.isNotEmpty) {
              try {
                decryptedContent = await cryptoService.decodeRoomContent(
                  roomId: roomId,
                  senderId: record['profile_id'] as String,
                  content: encryptedContent.toString(),
                );
              } catch (e) {
                debugPrint(
                  'Не удалось расшифровать сообщение ${record['id']}: $e',
                );
                decryptedContent = '[Не удалось расшифровать сообщение]';
              }
            } else {
              decryptedContent = '';
            }
          } else {
            decryptedContent = '🎤 Голосовое сообщение';
          }

          final legacyGiftName = Message.giftNameFromContent(decryptedContent);
          if (legacyGiftName != null) {
            isGift = true;
            giftName ??= legacyGiftName;
          }

          app.User? sender;
          if (record['sender_is_channel'] == true) {
            sender = app.User(
              id: record['profile_id'],
              name: record['sender_name'] ?? 'Канал',
              tag: record['sender_tag'] ?? '',
              avatarUrl: record['sender_avatar'],
            );
          } else if (isMe) {
            sender = currentUser;
          } else {
            try {
              final userData = await _supabase.rpc(
                'get_user_by_id',
                params: {'p_id': record['profile_id']},
              );
              if (userData != null) {
                sender = app.User(
                  id: record['profile_id'],
                  name:
                      userData['name'] ??
                      record['sender_name'] ??
                      'Пользователь',
                  tag: userData['tag'] ?? record['sender_tag'] ?? '',
                  avatarUrl: userData['avatar_url'] ?? record['sender_avatar'],
                  badge: userData['badge'] as String?,
                );
              } else {
                sender = app.User(
                  id: record['profile_id'],
                  name: record['sender_name'] ?? 'Пользователь',
                  tag: record['sender_tag'] ?? '',
                  avatarUrl: record['sender_avatar'],
                );
              }
            } catch (e) {
              sender = app.User(
                id: record['profile_id'],
                name: record['sender_name'] ?? 'Пользователь',
                tag: record['sender_tag'] ?? '',
                avatarUrl: record['sender_avatar'],
              );
            }
          }

          messages.add(
            Message(
              id: record['id'],
              chatId: record['room_id'],
              senderId: record['profile_id'],
              forwardedFromUserId: record['forwarded_from_user_id'] as String?,
              forwardedFromName: record['forwarded_from_name'] as String?,
              content: decryptedContent,
              createdAt: parseDateTimeSafely(record['created_at']),
              isMe: isMe,
              senderIsChannel: record['sender_is_channel'] == true,
              sender: sender,
              isVoice: isVoice,
              isImage: isImage,
              isPoll: isPoll,
              pollOptions: pollOptions,
              pollAllowMultiple: record['poll_allow_multiple'] == true,
              pollClosed: record['poll_closed'] == true,
              isSticker: isSticker,
              isGift: isGift,
              giftName: giftName,
              giftEmoji: record['gift_emoji'] as String?,
              giftPriceEnc: (record['gift_price_enc'] as num?)?.toInt(),
              giftCaption: record['gift_caption'] as String?,
              giftNftSerial: (record['gift_nft_serial'] as num?)?.toInt(),
              giftNftSkinName: record['gift_nft_skin_name'] as String?,
              giftNftSkinEmoji: record['gift_nft_skin_emoji'] as String?,
              giftNftBackgroundColor:
                  record['gift_nft_background_color'] as String?,
              giftNftPattern: record['gift_nft_pattern'] as String?,
              giftNftAnimationUrl: record['gift_nft_animation_url'] as String?,
              imageCaption: decryptedCaption,
              voiceUrl: await resolveChatStorageUrl(
                'voice_messages',
                record['voice_url'],
              ),
              voiceDuration: record['voice_duration'] != null
                  ? Duration(seconds: record['voice_duration'] as int)
                  : null,
              replyToId: record['reply_to_id'] as String?,
              replyToContent: record['reply_to_content'] as String?,
              replyToSender: record['reply_to_sender'] as String?,
              isFile: isFile,
              fileName: record['file_name'] as String?,
              fileUrl: await resolveChatStorageUrl(
                record['encrypted_content_type'] == 'video_note'
                    ? 'chat_media'
                    : 'chat_files',
                record['file_url'],
              ),
              fileSize: record['file_size'] as int?,
              fileMimeType: record['file_mime_type'] as String?,
              isVideoNote: record['encrypted_content_type'] == 'video_note',
              isEdited: record['is_edited'] ?? false,
              isDeleted: record['is_deleted'] ?? false,
              isPinned: record['is_pinned'] ?? false,
            ),
          );
        } catch (e) {
          debugPrint('Ошибка обработки сообщения: $e');
        }
      }

      final newestFirstMessages = messages.reversed.toList();
      final withReactions = await _attachReactions(
        newestFirstMessages,
        currentUser.id,
      );
      return await _attachPollVotes(withReactions, currentUser.id);
    } catch (e) {
      debugPrint('Ошибка загрузки сообщений: $e');
      return [];
    }
  }

  Future<Set<String>> getReadMessageIds(
    List<String> messageIds,
    String senderId,
  ) async {
    if (messageIds.isEmpty) return {};

    final rows = await _supabase
        .from('message_reads')
        .select('message_id')
        .inFilter('message_id', messageIds)
        .neq('user_id', senderId);

    return rows.map((row) => row['message_id'] as String).toSet();
  }

  Future<Map<String, MessageReactionSummary>> getReactionSummaries(
    List<String> messageIds, {
    String? userId,
  }) async {
    if (messageIds.isEmpty) return {};

    final currentUserId = userId ?? _authService.currentUserId;
    final rows = await _supabase
        .from('message_reactions')
        .select('message_id, user_id, reaction')
        .inFilter('message_id', messageIds)
        .order('created_at');

    final countsByMessage = <String, Map<String, int>>{};
    final userIdsByReaction = <String, Map<String, List<String>>>{};
    final ownReactionByMessage = <String, String>{};
    for (final row in rows) {
      final messageId = row['message_id'] as String;
      final reactionUserId = row['user_id'] as String;
      final reaction = row['reaction'] as String;
      final counts = countsByMessage.putIfAbsent(messageId, () => {});
      counts[reaction] = (counts[reaction] ?? 0) + 1;
      final messageUsers = userIdsByReaction.putIfAbsent(messageId, () => {});
      final reactionUsers = messageUsers.putIfAbsent(reaction, () => []);
      if (reactionUsers.length < 3) reactionUsers.add(reactionUserId);
      if (row['user_id'] == currentUserId) {
        ownReactionByMessage[messageId] = reaction;
      }
    }

    final userIds = userIdsByReaction.values
        .expand((reactions) => reactions.values)
        .expand((ids) => ids)
        .toSet();
    final usersById = <String, app.User>{};
    await Future.wait(
      userIds.map((id) async {
        try {
          final response = await _supabase.rpc(
            'get_user_by_id',
            params: {'p_id': id},
          );
          final record = rpcUserRecord(response);
          if (record != null) {
            usersById[id] = app.User(
              id: id,
              name: record['name'] as String? ?? 'Пользователь',
              tag: record['tag'] as String? ?? '',
              avatarUrl: record['avatar_url'] as String?,
            );
          }
        } catch (error) {
          debugPrint('Не удалось загрузить аватар участника реакции: $error');
        }
      }),
    );

    return {
      for (final messageId in messageIds)
        messageId: MessageReactionSummary(
          counts: countsByMessage[messageId] ?? const {},
          users: {
            for (final entry
                in (userIdsByReaction[messageId] ?? const {}).entries)
              entry.key: [
                for (final id in entry.value)
                  usersById[id] ??
                      app.User(id: id, name: 'Пользователь', tag: ''),
              ],
          },
          myReaction: ownReactionByMessage[messageId],
        ),
    };
  }

  Future<MessageReactionSummary> getReactionSummary(String messageId) async {
    final summaries = await getReactionSummaries([messageId]);
    return summaries[messageId] ?? const MessageReactionSummary();
  }

  Future<String?> toggleMessageReaction({
    required String messageId,
    required String reaction,
  }) async {
    final userId = _authService.currentUserId;
    if (userId == null) throw StateError('Необходимо войти в аккаунт');

    final existing = await _supabase
        .from('message_reactions')
        .select('reaction')
        .eq('message_id', messageId)
        .eq('user_id', userId)
        .maybeSingle();

    if (existing?['reaction'] == reaction) {
      await _supabase
          .from('message_reactions')
          .delete()
          .eq('message_id', messageId)
          .eq('user_id', userId);
      return null;
    }

    await _supabase.from('message_reactions').upsert({
      'message_id': messageId,
      'user_id': userId,
      'reaction': reaction,
    }, onConflict: 'message_id,user_id');
    return reaction;
  }

  Future<List<Message>> _attachReactions(
    List<Message> messages,
    String userId,
  ) async {
    if (messages.isEmpty) return messages;
    try {
      final summaries = await getReactionSummaries(
        messages.map((message) => message.id).toList(),
        userId: userId,
      );
      return messages.map((message) {
        final summary = summaries[message.id] ?? const MessageReactionSummary();
        return message.copyWith(
          reactions: summary.counts,
          reactionUsers: summary.users,
          myReaction: summary.myReaction,
          clearMyReaction: summary.myReaction == null,
        );
      }).toList();
    } catch (error) {
      debugPrint('Не удалось загрузить реакции: $error');
      return messages;
    }
  }

  Future<List<Message>> _attachPollVotes(
    List<Message> messages,
    String userId,
  ) async {
    final pollIds = messages
        .where((message) => message.isPoll)
        .map((message) => message.id)
        .toList();
    if (pollIds.isEmpty) return messages;

    try {
      final rows = await _supabase
          .from('message_poll_votes')
          .select('message_id, user_id, option_indices')
          .inFilter('message_id', pollIds);

      final countsByMessage = <String, Map<int, int>>{};
      final myVotesByMessage = <String, List<int>>{};
      for (final row in rows) {
        final messageId = row['message_id'] as String;
        final selectedOptions = (row['option_indices'] as List<dynamic>)
            .map((index) => (index as num).toInt())
            .toList();
        final counts = countsByMessage.putIfAbsent(messageId, () => {});
        for (final optionIndex in selectedOptions) {
          counts[optionIndex] = (counts[optionIndex] ?? 0) + 1;
        }
        if (row['user_id'] == userId) {
          myVotesByMessage[messageId] = selectedOptions;
        }
      }

      return messages.map((message) {
        if (!message.isPoll) return message;
        return message.copyWith(
          pollVotes: countsByMessage[message.id] ?? const {},
          myPollVotes: myVotesByMessage[message.id] ?? const [],
        );
      }).toList();
    } catch (error) {
      debugPrint('Не удалось загрузить голоса опросов: $error');
      return messages;
    }
  }

  Future<void> markMessagesRead({
    required String roomId,
    required String userId,
    required List<String> messageIds,
  }) async {
    if (messageIds.isEmpty) return;

    await _supabase
        .from('message_reads')
        .upsert(
          messageIds
              .map(
                (messageId) => {
                  'message_id': messageId,
                  'room_id': roomId,
                  'user_id': userId,
                },
              )
              .toList(),
          onConflict: 'message_id,user_id',
          ignoreDuplicates: true,
        );
  }

  Future<app.User?> _getChatPartner(String roomId, String currentUserId) async {
    final response = await _supabase
        .from('room_participants')
        .select('user_id')
        .eq('room_id', roomId)
        .neq('user_id', currentUserId)
        .maybeSingle();

    if (response == null) return null;

    final userId = response['user_id'];

    final userData = await _supabase.rpc(
      'get_user_by_id',
      params: {'p_id': userId},
    );

    final userRecord = rpcUserRecord(userData);
    if (userRecord == null) return null;

    return app.User(
      id: userId,
      tag: userRecord['tag'] ?? '',
      name: userRecord['name'] ?? 'Пользователь',
      avatarUrl: userRecord['avatar_url'],
      badge: userRecord['badge'] as String?,
    );
  }

  Future<void> pinMessage(
    String messageId,
    String roomId,
    String userId,
  ) async {
    try {
      await _supabase.rpc(
        'pin_message',
        params: {'p_message_id': messageId, 'p_room_id': roomId},
      );
      debugPrint('PIN >> успешно через RPC');
    } catch (e) {
      debugPrint('PIN >> ошибка RPC: $e');
      rethrow;
    }
  }

  Future<void> unpinMessage(String messageId, String roomId) async {
    try {
      await _supabase.rpc(
        'unpin_message',
        params: {'p_message_id': messageId, 'p_room_id': roomId},
      );
      debugPrint('UNPIN >> успешно через RPC');
    } catch (e) {
      debugPrint('UNPIN >> ошибка RPC: $e');
      rethrow;
    }
  }

  Future<Message?> getPinnedMessage(String roomId) async {
    try {
      final currentUserId = _authService.currentUserId;

      final response = await _supabase
          .from('messages')
          .select('*')
          .eq('room_id', roomId)
          .eq('is_pinned', true)
          .maybeSingle();

      if (response == null) return null;

      return await _parseMessage(response, currentUserId);
    } catch (e) {
      debugPrint('Ошибка получения закреплённого сообщения: $e');
      return null;
    }
  }

  Future<List<Message>> getPinnedMessages(String roomId) async {
    try {
      final currentUserId = _authService.currentUserId;

      final response = await _supabase
          .from('messages')
          .select('*')
          .eq('room_id', roomId)
          .eq('is_pinned', true)
          .order('pinned_at', ascending: true);

      return await Future.wait(
        response.map((data) => _parseMessage(data, currentUserId)),
      );
    } catch (e) {
      debugPrint('Ошибка получения закреплённых сообщений: $e');
      return [];
    }
  }

  Future<bool> hasPinnedMessage(String roomId) async {
    try {
      final response = await _supabase
          .from('messages')
          .select('id')
          .eq('room_id', roomId)
          .eq('is_pinned', true)
          .maybeSingle();

      return response != null;
    } catch (e) {
      return false;
    }
  }

  Future<Message> _parseMessage(
    Map<String, dynamic> data,
    String? currentUserId,
  ) async {
    final isMe = data['profile_id'] == currentUserId;

    final sender = app.User(
      id: data['profile_id'],
      name: data['sender_name'] ?? 'Пользователь',
      tag: data['sender_tag'] ?? '',
      avatarUrl: data['sender_avatar'],
    );

    return Message(
      id: data['id'],
      chatId: data['room_id'],
      senderId: data['profile_id'],
      forwardedFromUserId: data['forwarded_from_user_id'] as String?,
      forwardedFromName: data['forwarded_from_name'] as String?,
      content: Message.isImageMessage(data)
          ? await resolveChatStorageUrl(
                  'chat_media',
                  await _crypto.decodeRoomContent(
                    roomId: data['room_id'] as String,
                    senderId: data['profile_id'] as String,
                    content: data['encrypted_content']?.toString() ?? '',
                  ),
                ) ??
                ''
          : await _crypto.decodeRoomContent(
              roomId: data['room_id'] as String,
              senderId: data['profile_id'] as String,
              content: data['encrypted_content']?.toString() ?? '',
            ),
      createdAt: parseDateTimeSafely(data['created_at']),
      isMe: isMe,
      sender: sender,
      isVoice: data['is_voice'] ?? false,
      isImage: Message.isImageMessage(data),
      isSticker: Message.isStickerMessage(data),
      imageCaption: data['image_caption'] == null
          ? null
          : await _crypto.decodeRoomContent(
              roomId: data['room_id'] as String,
              senderId: data['profile_id'] as String,
              content: data['image_caption'].toString(),
            ),
      voiceUrl: await resolveChatStorageUrl(
        'voice_messages',
        data['voice_url'],
      ),
      voiceDuration: data['voice_duration'] != null
          ? Duration(seconds: data['voice_duration'] as int)
          : null,
      replyToId: data['reply_to_id'] as String?,
      replyToContent: data['reply_to_content'] as String?,
      replyToSender: data['reply_to_sender'] as String?,
      isFile: data['is_file'] ?? false,
      fileName: data['file_name'] as String?,
      fileUrl: await resolveChatStorageUrl(
        data['encrypted_content_type'] == 'video_note'
            ? 'chat_media'
            : 'chat_files',
        data['file_url'],
      ),
      fileSize: data['file_size'] as int?,
      fileMimeType: data['file_mime_type'] as String?,
      isVideoNote: data['encrypted_content_type'] == 'video_note',
      isEdited: data['is_edited'] ?? false,
      isDeleted: data['is_deleted'] ?? false,
      isPinned: data['is_pinned'] ?? false,
    );
  }
}
