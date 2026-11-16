import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:strazh/shared/domain/models/message.dart';
import 'package:strazh/features/auth/presentation/screens/auth.dart';
import 'package:strazh/features/chat/presentation/screens/gift_shop_screen.dart';
import 'package:strazh/features/auth/data/services/auth_service.dart';
import 'package:strazh/features/settings/data/services/sound_service.dart';
import 'package:strazh/features/settings/data/services/subscription_service.dart';
import 'package:strazh/features/chat/data/services/upload_limits_service.dart';
import 'package:strazh/features/settings/data/services/wallpaper_service.dart';
import 'package:strazh/features/settings/presentation/screens/wallpaper_screen.dart';
import 'package:strazh/shared/presentation/widgets/pdf_viewer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/shared/domain/models/chat.dart';
import 'package:strazh/shared/domain/models/user.dart' as app;
import 'package:strazh/features/chat/presentation/widgets/message_bubble.dart';
import 'package:strazh/features/gifts/presentation/widgets/gift_chat_item.dart';
import 'package:strazh/features/gifts/presentation/widgets/gift_details_dialog.dart';
import 'package:strazh/features/chat/presentation/widgets/chat_message_loading.dart';
import 'package:strazh/features/chat/presentation/widgets/forward_chat_picker.dart';
import 'package:strazh/features/chat/data/services/chat_service.dart';
import 'package:strazh/features/chat/data/services/username_chat_service.dart';
import 'package:strazh/features/gifts/data/services/gift_service.dart';
import 'package:strazh/features/chat/data/services/video_note_service.dart';
import 'package:strazh/features/settings/data/services/reaction_settings_service.dart';
import 'package:strazh/core/config/reactions.dart';
import 'package:strazh/features/chat/data/services/crypto_service.dart';
import 'package:strazh/features/chat/data/services/file_upload_service.dart';
import 'package:strazh/features/chat/data/services/storage_upload_service.dart';
import 'package:strazh/features/chat/presentation/widgets/chat_manage/group_info.dart';
import 'package:strazh/features/profile/presentation/widgets/profile.dart';
import 'package:strazh/features/chat/presentation/widgets/create_poll_dialog.dart';
import 'package:strazh/features/chat/presentation/widgets/media/voice_recorder.dart';
import 'package:strazh/features/chat/presentation/widgets/media/audio_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import 'package:strazh/shared/presentation/widgets/toast.dart';
import 'package:strazh/shared/presentation/widgets/avatar_preview.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:strazh/features/chat/data/services/user_status_service.dart';
import 'package:strazh/features/calls/presentation/screens/audio_call.dart';
import 'package:strazh/features/chat/data/services/webrtc_service.dart';
import 'package:strazh/core/utils/date_time_utils.dart';
import 'package:strazh/core/utils/rpc_user.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:camera/camera.dart';

class ChatScreen extends StatefulWidget {
  final Chat chat;
  final app.User currentUser;
  final VoidCallback? onMembershipChanged;

  const ChatScreen({
    super.key,
    required this.chat,
    required this.currentUser,
    this.onMembershipChanged,
  });

  @override
  State<ChatScreen> createState() => ChatScreenState();
}

class _PendingUpload {
  final String? previewPath;
  final String label;
  int totalBytes;
  int uploadedBytes = 0;
  bool isPreparing;

  _PendingUpload({
    required this.label,
    this.previewPath,
    this.totalBytes = 0,
    this.isPreparing = false,
  });
}

class ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ChatService _chatService = ChatService();
  final VideoNoteService _videoNoteService = VideoNoteService();
  final CryptoService _cryptoService = CryptoService();
  final FocusNode _focusNode = FocusNode();
  int _participantsCount = 0;

  final WebRTCService _webrtc = WebRTCService();
  final String _signalingServerUrl = 'http://81.19.136.44:3000';

  Message? _replyingTo;
  Message? _editingMessage;
  bool _isEditingCaption = false;
  bool _isSavingEdit = false;
  bool _showSendAfterEdit = false;
  String? _highlightedMessageId;
  int _highlightToken = 0;

  final Map<String, GlobalKey> _messageKeys = {};
  List<Message> _messages = [];
  bool _isLoading = true;
  final ScrollController _scrollController = ScrollController();
  final Set<String> _selectedMessageIds = {};
  bool _isSelectingMessages = false;
  final Map<String, _PendingUpload> _pendingUploads = {};
  CameraController? _videoNoteCameraController;
  bool _isPreparingVideoNote = false;
  bool _isRecordingVideoNote = false;
  bool _isStoppingVideoNote = false;
  bool _isSendingVideoNote = false;
  int _videoNoteSession = 0;
  DateTime? _videoNoteRecordingStartedAt;
  Duration _videoNoteElapsed = Duration.zero;
  Timer? _videoNoteTimer;

  bool _showScrollDownButton = false;
  bool _isBlocked = false;
  bool _canPostToChannel = true;
  bool _isChannelSubscribed = false;
  bool _channelSoundEnabled = true;
  bool _isSubscribing = false;
  bool _sendAsChannel = true;
  String? _otherUserId;
  String? _otherUserName;
  String? _otherUserTag;
  String? _otherUserStatus;
  String? _otherUserAvatar;
  String? _otherUserBadge;

  RealtimeChannel? _realtimeChannel;
  RealtimeChannel? _statusChannel;
  Timer? _pollingTimer;
  Timer? _statusPollingTimer;
  Timer? _replyHighlightTimer;
  Timer? _readReceiptTimer;
  bool _isMarkingReadReceipts = false;
  final Set<String> _markedAsReadMessageIds = {};

  bool _showAudioPlayer = false;
  String? _currentAudioUrl;
  final AudioPlayer _soundPlayer = AudioPlayer();

  bool _isSearchingForMessage = false;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  DateTime? _oldestMessageDate;
  DateTime? _latestObservedMessageAt;
  static const int _messagesPageSize = 20;
  bool _isInitialLoadComplete = false;

  bool _showEmojiPicker = false;
  int _emojiTab = 0;
  String _doubleTapReaction = defaultDoubleTapReaction;

  static const int _stickerColumns = 4;
  static const int _stickerInitialRows = 3;
  static const int _stickerLoadMoreRows = 4;
  static const int _stickerPageSize = _stickerColumns * _stickerLoadMoreRows;

  final List<String> _stickers = [];
  final ScrollController _stickerScrollController = ScrollController();
  bool _isLoadingStickers = false;
  bool _hasMoreStickers = true;
  int _stickerOffset = 0;
  String _stickerSearchQuery = 'funny';
  static const String _giphyApiKey = 'ViPUNMReluiovgeu7KdGdxXSHwkCaID4';
  static const String _giphyBaseUrl = 'https://api.giphy.com/v1/gifs/search';
  Timer? _stickerSearchDebounce;
  final TextEditingController _stickerSearchController =
      TextEditingController();
  String _stickerError = '';
  bool _stickerInitialLoaded = false;
  static const int _stickerInitialLoadSize =
      _stickerColumns * _stickerInitialRows;

  final List<String> _emojis = [
    '😀',
    '😁',
    '😂',
    '🤣',
    '😃',
    '😄',
    '😅',
    '😆',
    '😉',
    '😊',
    '😋',
    '😎',
    '😍',
    '🥰',
    '😘',
    '😗',
    '😙',
    '😚',
    '🙂',
    '🤗',
    '🤩',
    '🤔',
    '🤨',
    '😐',
    '😑',
    '😶',
    '🙄',
    '😏',
    '😣',
    '😥',
    '😮',
    '🤐',
    '😯',
    '😪',
    '😫',
    '😴',
    '😌',
    '😛',
    '😜',
    '😝',
    '🤤',
    '😒',
    '😓',
    '😔',
    '😕',
    '🙃',
    '🤑',
    '😲',
    '☹️',
    '🙁',
    '😖',
    '😞',
    '😟',
    '😤',
    '😢',
    '😭',
    '😦',
    '😧',
    '😨',
    '😩',
    '🤯',
    '😬',
    '😰',
    '😱',
    '🥵',
    '🥶',
    '😳',
    '🤪',
    '😵',
    '😡',
    '😠',
    '🤬',
    '👍',
    '👎',
    '👊',
    '✊',
    '🤛',
    '🤜',
    '👏',
    '🙌',
    '🤲',
    '🤝',
    '🙏',
    '✌️',
    '🤟',
    '🤘',
    '🤙',
    '💪',
    '🖕',
    '❤️',
    '🧡',
    '💛',
    '💚',
    '💙',
    '💜',
    '🖤',
    '🛒',
    '🚫',
    '🎁',
    '✅',
    '⭐',
    '❓',
    '🔥',
    '🥳',
    '💥',
    '🚀',
    '👋',
    '💀',
    '🤖',
    '😈',
    '🤡',
    '💩',
  ];

  List<Message> _pinnedMessages = [];
  int _currentPinnedIndex = 0;
  bool _isLoadingPinned = true;

  String _wallpaper = WallpaperService.defaultWallpaper;
  String? _floatingDate;
  bool _showFloatingDate = false;
  Timer? _floatingDateHideTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sendAsChannel = widget.chat.type == 'channel';
    _updateMessageAuthor();
    _canPostToChannel = widget.chat.type != 'channel';
    unawaited(_loadDoubleTapReaction());
    _messageController.addListener(() {
      setState(() {});
    });
    _scrollController.addListener(_onScroll);
    _stickerScrollController.addListener(_onStickerScroll);
    _stickerSearchController.addListener(() {
      if (mounted) setState(() {});
    });

    _webrtc.initialize();
    _webrtc
        .connectToServer(
          serverUrl: _signalingServerUrl,
          userId: widget.currentUser.id,
          roomId: widget.chat.id,
          onIncomingCall: (data) {
            _showIncomingCallDialog(data);
          },
        )
        .catchError((error) {
          debugPrint('Сервер звонков недоступен: $error');
        });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final authService = AuthService();
      final isLoggedIn = await authService.isLoggedIn();

      if (!isLoggedIn) {
        if (mounted) {
          Toast.error(context, 'Вы не авторизованы! Войдите заново');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const AuthScreen()),
          );
        }
        return;
      }

      final session = Supabase.instance.client.auth.currentSession;
      if (session == null && mounted) {
        debugPrint('Сессия Supabase пуста, но флаг в storage есть');
        final restored = await authService.restoreSession();
        if (!restored && mounted) {
          Toast.error(context, 'Не удалось восстановить сессию');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const AuthScreen()),
          );
          return;
        }
      }

      if (mounted) {
        await _initializeChat();
        if (widget.chat.type == 'channel') await _loadChannelPermission();
      }
    });
  }

  Future<void> _loadDoubleTapReaction() async {
    final reaction = await ReactionSettingsService.getDoubleTapReaction();
    if (mounted) setState(() => _doubleTapReaction = reaction);
  }

  Future<void> _loadChannelPermission() async {
    try {
      final membership = await Supabase.instance.client
          .from('room_participants')
          .select('role')
          .eq('room_id', widget.chat.id)
          .eq('user_id', widget.currentUser.id)
          .maybeSingle();
      if (!mounted) return;

      if (membership == null) {
        setState(() {
          _isChannelSubscribed = false;
          _canPostToChannel = false;
        });
        return;
      }

      final preferences = await SharedPreferences.getInstance();
      final channelSoundEnabled =
          preferences.getBool(_channelSoundPreferenceKey) ?? true;
      final role = membership['role'];
      if (!mounted) return;
      setState(() {
        _isChannelSubscribed = true;
        _channelSoundEnabled = channelSoundEnabled;
        _canPostToChannel = role == 'owner' || role == 'admin';
      });
    } catch (error) {
      debugPrint('Не удалось проверить право публикации в канале: $error');
      if (mounted) {
        setState(() {
          _isChannelSubscribed = false;
          _canPostToChannel = false;
        });
      }
    }
  }

  String get _channelSoundPreferenceKey =>
      'channel_sound_enabled_${widget.chat.id}';

  void _updateMessageAuthor() {
    final useChannelIdentity = widget.chat.type == 'channel' && _sendAsChannel;
    _chatService.setMessageAuthor(
      useChannelIdentity
          ? MessageAuthor(
              name: widget.chat.name,
              tag: '',
              avatarUrl: widget.chat.avatarUrl,
              isChannel: true,
            )
          : null,
    );
  }

  Future<void> _subscribeToChannel() async {
    if (_isSubscribing) return;
    setState(() => _isSubscribing = true);
    try {
      final joinedChat = await _chatService.joinGroup(widget.chat.id);
      if (joinedChat == null) {
        if (mounted) Toast.error(context, 'Не удалось подписаться на канал');
        return;
      }

      await _loadChannelPermission();
      await _loadParticipantsCount();
      widget.onMembershipChanged?.call();
      if (mounted) Toast.success(context, 'Вы подписались на канал');
    } catch (error) {
      debugPrint('Ошибка подписки на канал: $error');
      if (mounted) Toast.error(context, 'Не удалось подписаться на канал');
    } finally {
      if (mounted) setState(() => _isSubscribing = false);
    }
  }

  Future<void> _toggleChannelSound() async {
    final enabled = !_channelSoundEnabled;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_channelSoundPreferenceKey, enabled);
    if (!mounted) return;
    setState(() => _channelSoundEnabled = enabled);
    Toast.info(
      context,
      enabled ? 'Звук канала включён' : 'Звук канала выключен',
    );
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chat.id == widget.chat.id) return;

    _sendAsChannel = widget.chat.type == 'channel';
    _updateMessageAuthor();
    _canPostToChannel = widget.chat.type != 'channel';
    _isChannelSubscribed = false;
    _channelSoundEnabled = true;
    if (widget.chat.type == 'channel') unawaited(_loadChannelPermission());

    _realtimeChannel?.unsubscribe();
    _statusChannel?.unsubscribe();
    _pollingTimer?.cancel();
    _statusPollingTimer?.cancel();
    _replyHighlightTimer?.cancel();
    _readReceiptTimer?.cancel();
    _markedAsReadMessageIds.clear();

    _messages.clear();
    _pinnedMessages.clear();
    _replyingTo = null;
    _otherUserId = null;
    _otherUserName = null;
    _otherUserTag = null;
    _otherUserStatus = null;
    _otherUserBadge = null;
    _participantsCount = 0;
    _isBlocked = false;
    _isLoading = true;
    _isLoadingMore = false;
    _hasMoreMessages = true;
    _oldestMessageDate = null;
    _isInitialLoadComplete = false;
    unawaited(_initializeChat());
  }

  void focusMessageInput() {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      _focusNode.requestFocus();
    }
  }

  Future<void> _startCall({required bool isVideo}) async {
    if (widget.chat.type == 'saved') {
      Toast.info(context, 'В избранном звонки недоступны');
      return;
    }
    if (widget.chat.type != 'direct' || _otherUserId == null) {
      Toast.info(context, 'Звонки доступны только в личном чате');
      return;
    }

    if (_isBlocked) {
      Toast.warning(
        context,
        'Вы не можете звонить заблокированному пользователю',
      );
      return;
    }

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AudioCallScreen(
            chatId: widget.chat.id,
            currentUserId: widget.currentUser.id,
            remoteUserId: _otherUserId!,
            contactName: widget.chat.name,
            avatarUrl: _otherUserAvatar,
            isVideo: isVideo,
            isIncoming: false,
            serverUrl: _signalingServerUrl,
          ),
        ),
      );
    } catch (e) {
      Toast.error(context, 'Ошибка запуска звонка: $e');
    }
  }

  void _showIncomingCallDialog(Map<String, dynamic> data) {
    final from = data['from'] as String;
    final isVideo = data['isVideo'] as bool? ?? false;

    if (SoundService().incomingCallEnabled) {
      unawaited(_playMessageSound('sounds/message_here.mp3'));
    }
    _vibrateIfEnabled();

    String callerName = widget.chat.name;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(isVideo ? Icons.videocam : Icons.call, color: Colors.green),
            const SizedBox(width: 10),
            Text(
              isVideo ? 'Входящий видеозвонок' : 'Входящий аудиозвонок',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: Text(
          '$callerName звонит вам',
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _webrtc.declineIncomingCall();
            },
            child: const Text('Отклонить', style: TextStyle(color: Colors.red)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AudioCallScreen(
                    chatId: widget.chat.id,
                    currentUserId: widget.currentUser.id,
                    remoteUserId: from,
                    contactName: callerName,
                    avatarUrl: _otherUserAvatar,
                    isVideo: isVideo,
                    isIncoming: true,
                    serverUrl: _signalingServerUrl,
                  ),
                ),
              );
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Принять'),
          ),
        ],
      ),
    );
  }

  void _openPdfViewer(String url, String fileName) {
    if (kIsWeb) {
      final uri = Uri.parse(url);
      launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PdfViewer(url: url, fileName: fileName),
      ),
    );
  }

  Future<void> _initializeChat() async {
    try {
      final wp = await WallpaperService.getWallpaper(widget.currentUser.id);
      if (mounted) setState(() => _wallpaper = wp);
    } catch (e) {
      debugPrint('Ошибка загрузки обоев: $e');
    }

    try {
      if (!mounted) return;
      try {
        await _cryptoService.ensureCurrentDevice();
      } catch (error) {
        debugPrint('Не удалось зарегистрировать ключ этого устройства: $error');
        if (mounted) {
          Toast.error(
            context,
            'Не удалось подготовить сквозное шифрование. '
            'Проверьте подключение и обновление сервера.',
          );
        }
      }
      await _checkBlockStatus();
      await _subscribeToOtherUserStatus();
      await _loadPinnedMessages();
      await _loadMessages(loadMore: false);
      _loadParticipantsCount();
      _subscribeToRealtime();
    } catch (e) {
      if (mounted) {
        Toast.error(context, 'Ошибка инициализации: $e');
      }
    }
  }

  Future<void> _loadPinnedMessages() async {
    if (!mounted) return;
    setState(() => _isLoadingPinned = true);

    final pinnedList = await _chatService.getPinnedMessages(widget.chat.id);

    if (!mounted) return;

    final decrypted = <Message>[];
    for (final pinned in pinnedList) {
      String decryptedContent = pinned.content;

      if (!pinned.isVoice && !pinned.isImage && !pinned.isFile) {
        decryptedContent = _cryptoService.decodeCloudContent(pinned.content);
      } else if (pinned.isImage) {
        decryptedContent = pinned.isSticker ? 'Стикер' : 'Фото';
        if (pinned.imageCaption != null && pinned.imageCaption!.isNotEmpty) {
          try {
            final caption = _cryptoService.decodeCloudContent(
              pinned.imageCaption!,
            );
            decryptedContent = 'Фото: $caption';
          } catch (_) {}
        }
      } else if (pinned.isVoice) {
        decryptedContent = 'Голосовое сообщение';
      } else if (pinned.isFile) {
        decryptedContent = 'Файл: ${pinned.fileName ?? ''}';
      }

      decrypted.add(pinned.copyWith(content: decryptedContent, isPinned: true));
    }

    setState(() {
      _pinnedMessages = decrypted;
      if (_pinnedMessages.isEmpty) {
        _currentPinnedIndex = 0;
      } else if (_currentPinnedIndex >= _pinnedMessages.length) {
        _currentPinnedIndex = _pinnedMessages.length - 1;
      }
      _isLoadingPinned = false;
    });
  }

  Future<void> _pinMessage(Message message) async {
    final double? previousOffset = _scrollController.hasClients
        ? _scrollController.offset
        : null;

    try {
      await _chatService.pinMessage(
        message.id,
        widget.chat.id,
        widget.currentUser.id,
      );

      setState(() {
        final index = _messages.indexWhere((m) => m.id == message.id);
        if (index != -1) {
          _messages[index] = _messages[index].copyWith(isPinned: true);
        }
      });

      if (mounted) {
        await _loadPinnedMessages();
        final newIndex = _pinnedMessages.indexWhere((m) => m.id == message.id);
        if (newIndex != -1) {
          setState(() => _currentPinnedIndex = newIndex);
        }
      }
    } catch (e) {
      if (mounted) {
        Toast.error(context, 'Ошибка закрепления: $e');
      }
    } finally {
      _restoreScrollOffset(previousOffset);
    }
  }

  Future<void> _unpinMessage(Message message) async {
    final double? previousOffset = _scrollController.hasClients
        ? _scrollController.offset
        : null;

    try {
      await _chatService.unpinMessage(message.id, widget.chat.id);

      setState(() {
        final index = _messages.indexWhere((m) => m.id == message.id);
        if (index != -1) {
          _messages[index] = _messages[index].copyWith(isPinned: false);
        }
      });

      if (mounted) {
        await _loadPinnedMessages();
      }
    } catch (e) {
      if (mounted) {
        Toast.error(context, 'Ошибка открепления: $e');
      }
    } finally {
      _restoreScrollOffset(previousOffset);
    }
  }

  void _restoreScrollOffset(double? previousOffset) {
    if (previousOffset == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(previousOffset.clamp(0.0, max));
    });
  }

  String _formatMessageDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(date.year, date.month, date.day);
    final diff = today.difference(msgDay).inDays;

    const months = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];

    if (diff == 0) return 'Сегодня';
    if (diff == 1) return 'Вчера';
    if (date.year == now.year) {
      return '${date.day} ${months[date.month - 1]}';
    }
    return '${date.day} ${months[date.month - 1]} ${date.year} года';
  }

  bool _shouldShowDateHeader(int index, List<Message> messagesList) {
    if (index < 0 || index >= messagesList.length) return false;
    if (index == messagesList.length - 1) return true;
    final current = messagesList[index].createdAt;
    final next = messagesList[index + 1].createdAt;
    return current.year != next.year ||
        current.month != next.month ||
        current.day != next.day;
  }

  Future<void> _scrollToMessageWithCenter(
    String messageId, {
    bool highlight = true,
  }) async {
    if (_isSearchingForMessage) return;

    if (!_messages.any((m) => m.id == messageId)) {
      setState(() => _isSearchingForMessage = true);

      int attempts = 0;
      while (mounted &&
          !_messages.any((m) => m.id == messageId) &&
          _hasMoreMessages &&
          attempts < 50) {
        await _loadMessages(loadMore: true);
        attempts++;
      }

      if (mounted) setState(() => _isSearchingForMessage = false);
      if (!mounted) return;

      if (!_messages.any((m) => m.id == messageId)) {
        Toast.error(context, 'Сообщение не найдено');
        return;
      }

      await Future.delayed(const Duration(milliseconds: 100));
    }

    var messageIndex = _messages.indexWhere((msg) => msg.id == messageId);
    var oldestPageChecks = 0;
    while (messageIndex == 0 && _hasMoreMessages && oldestPageChecks < 50) {
      if (mounted) setState(() => _isSearchingForMessage = true);
      await _loadMessages(loadMore: true);
      if (!mounted) return;
      messageIndex = _messages.indexWhere((msg) => msg.id == messageId);
      oldestPageChecks++;
    }
    if (mounted && _isSearchingForMessage) {
      setState(() => _isSearchingForMessage = false);
    }
    if (messageIndex == -1 || !_scrollController.hasClients) {
      if (mounted) Toast.info(context, 'Не удалось найти сообщение');
      return;
    }

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (messageIndex == 0 && !_hasMoreMessages) {
      await position.animateTo(
        position.maxScrollExtent,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
      if (highlight) _highlightMessage(messageId);
      return;
    }

    final targetDisplayIndex = _messages.length - 1 - messageIndex;
    for (var attempt = 0; attempt < 12; attempt++) {
      if (!mounted || !_scrollController.hasClients) return;
      await WidgetsBinding.instance.endOfFrame;

      final targetContext = _messageKeys[messageId]?.currentContext;
      if (targetContext != null) {
        final targetRender = targetContext.findRenderObject();
        final scrollable = Scrollable.of(targetContext);
        final viewportRender = scrollable.position.context.storageContext
            .findRenderObject();

        if (targetRender is RenderBox && viewportRender is RenderBox) {
          final targetTop = targetRender
              .localToGlobal(Offset.zero, ancestor: viewportRender)
              .dy;
          final targetCenter = targetTop + targetRender.size.height / 2;
          final delta =
              targetCenter - scrollable.position.viewportDimension / 2;
          if (delta.abs() <= 1) break;

          final isReversed = scrollable.axisDirection == AxisDirection.up;
          final targetOffset =
              scrollable.position.pixels + (isReversed ? -delta : delta);
          await scrollable.position.animateTo(
            targetOffset.clamp(0.0, scrollable.position.maxScrollExtent),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
          );
          continue;
        }
      }

      final visibleMessages = <(int, double, double)>[];
      for (var index = 0; index < _messages.length; index++) {
        final message = _messages[index];
        final itemContext = _messageKeys[message.id]?.currentContext;
        final render = itemContext?.findRenderObject();
        if (itemContext == null || render is! RenderBox || !render.attached) {
          continue;
        }
        final scrollable = Scrollable.of(itemContext);
        final viewportRender = scrollable.position.context.storageContext
            .findRenderObject();
        if (viewportRender is! RenderBox) continue;
        final top = render
            .localToGlobal(Offset.zero, ancestor: viewportRender)
            .dy;
        visibleMessages.add((
          _messages.length - 1 - index,
          top + render.size.height / 2,
          render.size.height,
        ));
      }

      if (visibleMessages.isEmpty) {
        if (mounted) Toast.info(context, 'Не удалось показать сообщение');
        return;
      }

      visibleMessages.sort((first, second) => first.$1.compareTo(second.$1));
      var nearest = visibleMessages.first;
      for (final visible in visibleMessages.skip(1)) {
        if ((visible.$1 - targetDisplayIndex).abs() <
            (nearest.$1 - targetDisplayIndex).abs()) {
          nearest = visible;
        }
      }

      var totalExtent = 0.0;
      var extentCount = 0;
      for (var index = 1; index < visibleMessages.length; index++) {
        final previous = visibleMessages[index - 1];
        final current = visibleMessages[index];
        final indexDistance = current.$1 - previous.$1;
        if (indexDistance <= 0) continue;
        totalExtent += (current.$2 - previous.$2).abs() / indexDistance;
        extentCount++;
      }
      final averageExtent = extentCount == 0
          ? nearest.$3 + 24
          : totalExtent / extentCount;
      final estimatedOffset =
          _scrollController.position.pixels +
          (targetDisplayIndex - nearest.$1) * averageExtent;
      _scrollController.jumpTo(
        estimatedOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      );
    }

    if (highlight) _highlightMessage(messageId);
  }

  Widget _buildPinnedMessageBanner() {
    if (_pinnedMessages.isEmpty || _isLoadingPinned) {
      return const SizedBox.shrink();
    }

    final safeIndex = _currentPinnedIndex.clamp(0, _pinnedMessages.length - 1);
    final current = _pinnedMessages[safeIndex];
    final hasMultiple = _pinnedMessages.length > 1;

    return Material(
      color: const Color(0xFF1A1A1A),
      child: InkWell(
        onTap: () => _scrollToMessageWithCenter(current.id, highlight: true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: const Color(0xFFFFD740).withValues(alpha: 0.3),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              if (hasMultiple)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      _pinnedMessages.length.clamp(0, 5),
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(vertical: 1.5),
                        width: 3,
                        height: i == safeIndex ? 14 : 8,
                        decoration: BoxDecoration(
                          color: i == safeIndex
                              ? const Color(0xFFFFD740)
                              : const Color(0xFFFFD740).withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Icon(
                    Icons.push_pin,
                    color: Color(0xFFFFD740),
                    size: 16,
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasMultiple
                          ? 'Закреплено ${safeIndex + 1} из ${_pinnedMessages.length}'
                          : 'Закреплённое сообщение',
                      style: const TextStyle(
                        color: Color(0xFFFFD740),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      current.content.length > 50
                          ? '${current.content.substring(0, 50)}...'
                          : current.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasMultiple)
                IconButton(
                  onPressed: () {
                    setState(() {
                      _currentPinnedIndex =
                          (safeIndex + 1) % _pinnedMessages.length;
                    });
                  },
                  icon: const Icon(
                    Icons.expand_more,
                    color: Colors.grey,
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Следующее закреплённое',
                ),
              if (widget.chat.type != 'channel' || _canPostToChannel)
                IconButton(
                  onPressed: () => _unpinMessage(current),
                  icon: const Icon(Icons.close, color: Colors.grey, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Открепить',
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    _scheduleVisibleMessagesRead();

    final position = _scrollController.position;

    if (position.pixels >= position.maxScrollExtent - 200) {
      if (_hasMoreMessages && !_isLoadingMore && _isInitialLoadComplete) {
        _loadMessages(loadMore: true);
      }
    }

    final isAtBottom = position.pixels < 50;

    if (isAtBottom && _showScrollDownButton) {
      setState(() {
        _showScrollDownButton = false;
      });
    } else if (!isAtBottom && !_showScrollDownButton) {
      setState(() {
        _showScrollDownButton = true;
      });
    }

    _updateFloatingDate(fromScroll: true);
  }

  Future<void> _refreshMessageReactions(dynamic rawMessageId) async {
    if (rawMessageId is! String) return;
    final index = _messages.indexWhere((message) => message.id == rawMessageId);
    if (index == -1) return;

    try {
      final summary = await _chatService.getReactionSummary(rawMessageId);
      if (!mounted) return;
      final currentIndex = _messages.indexWhere(
        (message) => message.id == rawMessageId,
      );
      if (currentIndex == -1) return;
      setState(() {
        _messages[currentIndex] = _messages[currentIndex].copyWith(
          reactions: summary.counts,
          reactionUsers: summary.users,
          myReaction: summary.myReaction,
          clearMyReaction: summary.myReaction == null,
        );
      });
    } catch (error) {
      debugPrint('Не удалось обновить реакции: $error');
    }
  }

  Future<void> _refreshAllMessageReactions() async {
    final messageIds = _messages
        .where((message) => !message.id.startsWith('temp_'))
        .map((message) => message.id)
        .toList();
    if (messageIds.isEmpty) return;

    try {
      final summaries = await _chatService.getReactionSummaries(messageIds);
      if (!mounted) return;
      var changed = false;
      final updatedMessages = _messages.map((message) {
        final summary = summaries[message.id];
        if (summary == null ||
            mapEquals(message.reactions, summary.counts) &&
                message.myReaction == summary.myReaction) {
          return message;
        }
        changed = true;
        return message.copyWith(
          reactions: summary.counts,
          reactionUsers: summary.users,
          myReaction: summary.myReaction,
          clearMyReaction: summary.myReaction == null,
        );
      }).toList();

      if (changed) setState(() => _messages = updatedMessages);
    } catch (error) {
      debugPrint('Не удалось обновить реакции: $error');
    }
  }

  bool get _supportsReadReceipts =>
      widget.chat.type == 'group' ||
      widget.chat.type == 'channel' ||
      widget.chat.type == 'direct' ||
      widget.chat.type == 'saved';

  void _scheduleVisibleMessagesRead() {
    if (!_supportsReadReceipts || !mounted) return;
    _readReceiptTimer?.cancel();
    _readReceiptTimer = Timer(const Duration(milliseconds: 450), () {
      unawaited(_markVisibleMessagesAsRead());
    });
  }

  Future<void> _markVisibleMessagesAsRead() async {
    if (_isMarkingReadReceipts ||
        !_supportsReadReceipts ||
        !_scrollController.hasClients) {
      return;
    }

    final position = _scrollController.position;
    final viewportRender = position.context.storageContext.findRenderObject();
    if (viewportRender is! RenderBox) return;

    final visibleMessageIds = <String>[];
    for (final message in _messages) {
      if (message.isMe || _markedAsReadMessageIds.contains(message.id)) {
        continue;
      }

      final itemContext = _messageKeys[message.id]?.currentContext;
      final itemRender = itemContext?.findRenderObject();
      if (itemContext == null ||
          itemRender is! RenderBox ||
          !itemRender.attached) {
        continue;
      }

      final top = itemRender
          .localToGlobal(Offset.zero, ancestor: viewportRender)
          .dy;
      final visibleTop = top.clamp(0.0, position.viewportDimension);
      final visibleBottom = (top + itemRender.size.height).clamp(
        0.0,
        position.viewportDimension,
      );
      if (visibleBottom - visibleTop >= itemRender.size.height * 0.5) {
        visibleMessageIds.add(message.id);
      }
    }

    if (visibleMessageIds.isEmpty) return;

    _isMarkingReadReceipts = true;
    try {
      await _chatService.markMessagesRead(
        roomId: widget.chat.id,
        userId: widget.currentUser.id,
        messageIds: visibleMessageIds,
      );
      _markedAsReadMessageIds.addAll(visibleMessageIds);
    } catch (error) {
      debugPrint('Не удалось отметить сообщения прочитанными: $error');
    } finally {
      _isMarkingReadReceipts = false;
    }
  }

  void _updateFloatingDate({bool fromScroll = false}) {
    if (!_scrollController.hasClients || _messages.isEmpty) {
      _floatingDateHideTimer?.cancel();
      if (_showFloatingDate) {
        setState(() => _showFloatingDate = false);
      }
      return;
    }

    final viewportHeight = _scrollController.position.viewportDimension;
    final centerY = viewportHeight / 2;

    Message? centerMsg;
    double bestDistance = double.infinity;

    for (final msg in _messages) {
      final key = _messageKeys[msg.id];
      final ctx = key?.currentContext;
      if (ctx == null) continue;

      final render = ctx.findRenderObject();
      if (render is! RenderBox) continue;
      if (!render.attached) continue;

      final scrollableBox = _scrollController.position.context.storageContext
          .findRenderObject();
      if (scrollableBox is! RenderBox) continue;

      final top = render.localToGlobal(Offset.zero, ancestor: scrollableBox).dy;
      final height = render.size.height;
      final center = top + height / 2;
      final dist = (center - centerY).abs();

      if (dist < bestDistance) {
        bestDistance = dist;
        centerMsg = msg;
      }
    }

    if (centerMsg == null) {
      _floatingDateHideTimer?.cancel();
      if (_showFloatingDate) {
        setState(() => _showFloatingDate = false);
      }
      return;
    }

    final messagesList = _messages.reversed.toList();
    final reversedIndex = messagesList.indexOf(centerMsg);
    if (reversedIndex == -1) return;

    final msgDate = _formatMessageDate(centerMsg.createdAt);
    final isHeaderVisible = _shouldShowDateHeader(reversedIndex, messagesList);

    if (!isHeaderVisible && fromScroll) {
      if (_floatingDate != msgDate || !_showFloatingDate) {
        setState(() {
          _floatingDate = msgDate;
          _showFloatingDate = true;
        });
      }
      _floatingDateHideTimer?.cancel();
      _floatingDateHideTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted && _showFloatingDate) {
          setState(() => _showFloatingDate = false);
        }
      });
    } else {
      _floatingDateHideTimer?.cancel();
      if (_showFloatingDate) {
        setState(() => _showFloatingDate = false);
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _openUrl(String url) async {
    String fullUrl = url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      fullUrl = 'https://$url';
    }

    try {
      final uri = Uri.parse(fullUrl);
      final giftSlug = GiftService.giftNftSlugFromUrl(fullUrl);
      if (giftSlug != null) {
        final gift = await GiftService.getGiftDetailsBySlug(giftSlug);
        if (!mounted) return;
        await showGiftDetails(
          context: context,
          gift: gift,
          canManageVisibility: gift['recipient_id'] == widget.currentUser.id,
        );
        return;
      }

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          Toast.error(context, 'Не удалось открыть ссылку');
        }
      }
    } catch (e) {
      if (mounted) {
        Toast.error(context, 'Ошибка при открытии ссылки');
      }
    }
  }

  Future<void> _openUsernameChat(String username) async {
    try {
      final result = await UsernameChatService.findOrCreate(username);
      if (!mounted) return;
      if (result == null) {
        Toast.info(context, 'Пользователь @$username не найден');
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ChatScreen(chat: result.chat, currentUser: widget.currentUser),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is StateError
          ? error.message
          : 'Не удалось открыть чат: $error';
      Toast.error(context, message.toString());
    }
  }

  Future<void> _downloadFileWithProgress(
    String url,
    String fileName, {
    bool saveToGallery = false,
  }) async {
    if (kIsWeb) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        Toast.error(context, 'Не удалось открыть файл');
      }
      return;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/file_cache');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final safeFileName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final localPath = '${cacheDir.path}/$safeFileName';
      final localFile = File(localPath);

      if (await localFile.exists()) {
        if (saveToGallery) {
          await _saveVideoNoteToGallery(localFile.path, fileName);
        } else {
          _openFile(localFile.path);
        }
        return;
      }

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _DownloadProgressDialog(
          url: url,
          localPath: localPath,
          fileName: fileName,
          onComplete: (filePath) {
            Navigator.pop(context);
            if (saveToGallery) {
              unawaited(_saveVideoNoteToGallery(filePath, fileName));
            } else {
              _openFile(filePath);
            }
          },
          onError: (error) {
            Navigator.pop(context);
            if (mounted) {
              Toast.error(context, 'Ошибка скачивания: $error');
            }
          },
        ),
      );
    } catch (e) {
      if (mounted) {
        Toast.error(context, 'Ошибка подготовки к скачиванию: $e');
      }
    }
  }

  Future<void> _saveVideoNoteToGallery(String filePath, String fileName) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      _openFile(filePath);
      return;
    }

    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        if (androidInfo.version.sdkInt < 29 &&
            !await Permission.storage.request().isGranted) {
          if (mounted) {
            Toast.error(context, 'Нужно разрешение для сохранения в галерею');
          }
          return;
        }
      } else if (!await Permission.photosAddOnly.request().isGranted) {
        if (mounted) {
          Toast.error(context, 'Нет доступа для сохранения в галерею');
        }
        return;
      }

      final result = await SaverGallery.saveFile(
        filePath: filePath,
        fileName: fileName,
        skipIfExists: false,
      );
      if (!mounted) return;
      if (result.isSuccess) {
        Toast.success(context, 'Видеокружок сохранён в галерею');
      } else {
        Toast.error(
          context,
          'Не удалось сохранить видео: ${result.errorMessage ?? 'неизвестная ошибка'}',
        );
      }
    } catch (error) {
      debugPrint('Ошибка сохранения видеокружка в галерею: $error');
      if (mounted) {
        Toast.error(context, 'Не удалось сохранить видеокружок в галерею');
      }
    }
  }

  void _openFile(String filePath) {
    if (kIsWeb) return;
    OpenFile.open(filePath).then((result) {
      if (result.type == ResultType.error && mounted) {
        Toast.error(context, 'Не удалось открыть файл');
      }
    });
  }

  Future<void> _downloadImage(String url) async {
    if (kIsWeb) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        Toast.error(context, 'Не удалось открыть изображение');
      }
      return;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/image_cache');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final fileName = url.split('/').last.split('?').first;
      final safeFileName = fileName.isEmpty
          ? 'image_${DateTime.now().millisecondsSinceEpoch}.jpg'
          : fileName;
      final localPath = '${cacheDir.path}/$safeFileName';
      final localFile = File(localPath);

      if (await localFile.exists()) {
        await _saveOrOpenImage(localPath, safeFileName);
        return;
      }

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _DownloadProgressDialog(
          url: url,
          localPath: localPath,
          fileName: safeFileName,
          onComplete: (filePath) {
            Navigator.pop(context);
            unawaited(_saveOrOpenImage(filePath, safeFileName));
          },
          onError: (error) {
            Navigator.pop(context);
            if (mounted) {
              Toast.error(context, 'Ошибка скачивания: $error');
            }
          },
        ),
      );
    } catch (e) {
      if (mounted) {
        Toast.error(context, 'Ошибка: $e');
      }
    }
  }

  Future<void> _saveOrOpenImage(String filePath, String fileName) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      _openFile(filePath);
      return;
    }

    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        if (androidInfo.version.sdkInt < 29 &&
            !await Permission.storage.request().isGranted) {
          if (mounted) {
            Toast.error(context, 'Нужно разрешение для сохранения в галерею');
          }
          return;
        }
      } else if (!await Permission.photosAddOnly.request().isGranted) {
        if (mounted) {
          Toast.error(context, 'Нет доступа для сохранения в галерею');
        }
        return;
      }

      final result = await SaverGallery.saveFile(
        filePath: filePath,
        fileName: fileName,
        skipIfExists: false,
      );
      if (!mounted) return;
      if (result.isSuccess) {
        Toast.success(context, 'Фото сохранено в галерею');
      } else {
        Toast.error(
          context,
          'Не удалось сохранить фото: ${result.errorMessage ?? 'неизвестная ошибка'}',
        );
      }
    } catch (error) {
      debugPrint('Ошибка сохранения фото в галерею: $error');
      if (mounted) Toast.error(context, 'Не удалось сохранить фото в галерею');
    }
  }

  Future<void> _checkBlockStatus() async {
    if (widget.chat.type != 'direct') return;

    try {
      final response = await Supabase.instance.client
          .from('room_participants')
          .select('user_id')
          .eq('room_id', widget.chat.id)
          .neq('user_id', widget.currentUser.id)
          .maybeSingle();

      if (response == null) return;

      _otherUserId = response['user_id'];

      final userData = await Supabase.instance.client.rpc(
        'get_user_by_id',
        params: {'p_id': _otherUserId},
      );

      final userRecord = rpcUserRecord(userData);
      if (userRecord != null) {
        _otherUserName =
            userRecord['name'] as String? ?? userRecord['full_name'] as String?;
        _otherUserTag = userRecord['tag'] as String?;
        _otherUserAvatar = userRecord['avatar_url'] as String?;
        _otherUserBadge = userRecord['badge'] as String?;
      }

      final blockResponse = await Supabase.instance.client
          .from('blocks')
          .select()
          .eq('blocker_id', widget.currentUser.id)
          .eq('blocked_id', _otherUserId!)
          .maybeSingle();

      final reverseBlockResponse = await Supabase.instance.client
          .from('blocks')
          .select()
          .eq('blocker_id', _otherUserId!)
          .eq('blocked_id', widget.currentUser.id)
          .maybeSingle();

      setState(() {
        _isBlocked = blockResponse != null || reverseBlockResponse != null;
      });
    } catch (e) {
      debugPrint('Ошибка проверки блокировки: $e');
      if (mounted) {
        Toast.error(context, 'Ошибка проверки блокировки: $e');
      }
    }
  }

  Future<void> _subscribeToOtherUserStatus() async {
    if (widget.chat.type != 'direct') return;
    if (_otherUserId == null) {
      await _checkBlockStatus();
      if (_otherUserId == null) return;
    }

    try {
      final response = await Supabase.instance.client.rpc(
        'get_user_by_id',
        params: {'p_id': _otherUserId},
      );

      final userRecord = rpcUserRecord(response);
      if (mounted) {
        setState(() {
          _otherUserStatus = userRecord?['status'] as String? ?? 'offline';
        });
      }

      _startStatusPolling();
    } catch (e) {
      if (mounted) {
        setState(() {
          _otherUserStatus = 'offline';
        });
      }
    }
  }

  void _startStatusPolling() {
    _statusPollingTimer?.cancel();
    _statusPollingTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted || _otherUserId == null) return;
      try {
        final response = await Supabase.instance.client.rpc(
          'get_user_by_id',
          params: {'p_id': _otherUserId},
        );
        final userRecord = rpcUserRecord(response);
        if (mounted) {
          setState(() {
            _otherUserStatus = userRecord?['status'] as String? ?? 'offline';
          });
        }
      } catch (e) {
        debugPrint('Ошибка опроса статуса пользователя: $e');
      }
    });
  }

  void _showEditDialog(Message message) {
    final isCaptionEdit =
        message.isImage &&
        !message.isSticker &&
        (message.imageCaption?.trim().isNotEmpty ?? false);
    final initialValue = isCaptionEdit
        ? (message.imageCaption ?? '')
        : message.content;
    _messageController.value = TextEditingValue(
      text: initialValue,
      selection: TextSelection.collapsed(offset: initialValue.length),
    );
    setState(() {
      _replyingTo = null;
      _editingMessage = message;
      _isEditingCaption = isCaptionEdit;
    });
    _focusNode.requestFocus();
  }

  void _cancelEditingMessage() {
    _messageController.clear();
    setState(() {
      _editingMessage = null;
      _isEditingCaption = false;
      _isSavingEdit = false;
      _showSendAfterEdit = true;
    });
    _focusNode.unfocus();
  }

  Future<void> _saveEditedMessage() async {
    final message = _editingMessage;
    if (message == null || _isSavingEdit) return;

    final newText = _messageController.text.trim();
    if (newText.isEmpty) {
      Toast.warning(context, 'Сообщение не может быть пустым');
      return;
    }

    final oldText = _isEditingCaption
        ? message.imageCaption ?? ''
        : message.content;
    if (newText == oldText) {
      _cancelEditingMessage();
      return;
    }

    setState(() => _isSavingEdit = true);
    try {
      await _chatService.editMessage(
        message.id,
        newText,
        widget.currentUser.id,
        editCaption: _isEditingCaption,
      );
      if (!mounted) return;

      final index = _messages.indexWhere((item) => item.id == message.id);
      setState(() {
        if (index != -1) {
          _messages[index] = _isEditingCaption
              ? message.copyWith(imageCaption: newText, isEdited: true)
              : message.copyWith(content: newText, isEdited: true);
        }
        _editingMessage = null;
        _isEditingCaption = false;
        _isSavingEdit = false;
        _showSendAfterEdit = true;
      });
      _messageController.clear();
      _focusNode.unfocus();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSavingEdit = false);
      Toast.error(context, 'Не удалось изменить сообщение');
    }
  }

  void _confirmDelete(Message message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Удалить сообщение?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Это действие нельзя отменить',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              try {
                final session = Supabase.instance.client.auth.currentSession;
                if (session == null) {
                  if (mounted) {
                    Toast.error(context, 'Вы не авторизованы');
                  }
                  Navigator.pop(context);
                  return;
                }

                await _chatService.deleteMessage(
                  message.id,
                  widget.currentUser.id,
                );

                setState(() {
                  _messages.removeWhere((msg) => msg.id == message.id);
                  _selectedMessageIds.remove(message.id);
                });
                if (!mounted) return;
                if (!mounted) return;
                Navigator.pop(context);
              } catch (e) {
                if (!mounted) return;
                Toast.error(context, 'Ошибка удаления: ${e.toString()}');
                Navigator.pop(context);
              }
            },
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  List<Message> get _selectedMessages {
    final selected = _messages
        .where((message) => _selectedMessageIds.contains(message.id))
        .toList();
    selected.sort(
      (first, second) => first.createdAt.compareTo(second.createdAt),
    );
    return selected;
  }

  List<Message> get _deletableSelectedMessages =>
      _selectedMessages.where((message) => message.isMe).toList();

  Message? get _reportableSelectedMessage {
    if (_selectedMessages.length != 1) return null;
    final message = _selectedMessages.single;
    if (message.isMe || message.senderIsChannel || message.senderId.isEmpty) {
      return null;
    }
    return message;
  }

  void _toggleMessageSelection(Message message) {
    setState(() {
      _isSelectingMessages = true;
      if (!_selectedMessageIds.add(message.id)) {
        _selectedMessageIds.remove(message.id);
      }
      if (_selectedMessageIds.isEmpty) {
        _isSelectingMessages = false;
      }
    });
  }

  void _clearMessageSelection() {
    setState(() {
      _selectedMessageIds.clear();
      _isSelectingMessages = false;
    });
  }

  void _replyToMessage(Message message) {
    if (_editingMessage != null) _messageController.clear();
    setState(() {
      _editingMessage = null;
      _isEditingCaption = false;
      _replyingTo = message;
    });
    _focusNode.requestFocus();
  }

  Future<void> _forwardMessage(Message message) async {
    await _forwardMessages([message]);
  }

  Future<void> _forwardMessages(List<Message> messages) async {
    if (messages.isEmpty) return;
    try {
      final chats = (await _chatService.getMyChats())
          .where((chat) => chat.id != widget.chat.id)
          .toList();
      if (!mounted) return;
      if (chats.isEmpty) {
        Toast.info(context, 'Нет чатов для пересылки');
        return;
      }

      final targetChat = await showForwardChatPicker(
        context,
        message: messages.first,
        messageCount: messages.length,
        chats: chats,
      );

      if (targetChat == null || !mounted) return;
      var forwardedCount = 0;
      try {
        for (final message in messages) {
          await _chatService.forwardMessage(message, targetChat.id);
          forwardedCount++;
        }
      } catch (error) {
        if (forwardedCount > 0) {
          throw StateError(
            'Переслано $forwardedCount из ${messages.length}. '
            'Не удалось переслать остальные сообщения: $error',
          );
        }
        rethrow;
      }
      if (!mounted) return;
      _clearMessageSelection();
      Toast.success(
        context,
        messages.length == 1
            ? 'Сообщение переслано'
            : 'Переслано сообщений: ${messages.length}',
      );
    } catch (error) {
      if (mounted) Toast.error(context, 'Не удалось переслать: $error');
    }
  }

  Future<void> _confirmDeleteSelectedMessages() async {
    final messages = _deletableSelectedMessages;
    if (messages.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Удалить выбранные сообщения?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Будет удалено ${messages.length} ваших сообщений. '
          'Это действие нельзя отменить.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final deletedIds = <String>{};
    Object? failure;
    for (final message in messages) {
      try {
        await _chatService.deleteMessage(message.id, widget.currentUser.id);
        deletedIds.add(message.id);
      } catch (error) {
        failure = error;
        break;
      }
    }

    if (!mounted) return;
    setState(() {
      _messages.removeWhere((message) => deletedIds.contains(message.id));
      _selectedMessageIds.removeAll(deletedIds);
      if (_selectedMessageIds.isEmpty) _isSelectingMessages = false;
    });

    if (failure == null) {
      Toast.success(context, 'Удалено сообщений: ${deletedIds.length}');
    } else {
      Toast.error(
        context,
        'Удалено ${deletedIds.length} из ${messages.length}. '
        'Остальные сообщения не удалось удалить.',
      );
      debugPrint('Ошибка пакетного удаления сообщений: $failure');
    }
  }

  Future<void> _handleMessageReaction(Message message, String reaction) async {
    try {
      await _chatService.toggleMessageReaction(
        messageId: message.id,
        reaction: reaction,
      );
      await _refreshMessageReactions(message.id);
    } catch (error) {
      if (mounted) Toast.error(context, 'Не удалось поставить реакцию');
    }
  }

  void _cancelReply() {
    _replyHighlightTimer?.cancel();
    _replyHighlightTimer = null;
    setState(() {
      _replyingTo = null;
      _highlightedMessageId = null;
    });
  }

  void _highlightMessage(String? messageId) {
    if (messageId == null || !mounted) return;

    _replyHighlightTimer?.cancel();
    setState(() {
      _highlightedMessageId = messageId;
      _highlightToken++;
    });

    _replyHighlightTimer = Timer(const Duration(milliseconds: 1700), () {
      if (!mounted) return;
      setState(() {
        _highlightedMessageId = null;
      });
    });
  }

  Future<void> _handleReplyPreviewTap(
    String? replyToId,
    String? replyToContent,
    String? replyToSender,
  ) async {
    if (replyToId != null) {
      await _scrollToMessageWithCenter(replyToId, highlight: true);
      final messageExists = _messages.any((msg) => msg.id == replyToId);
      if (messageExists) return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        title: const Text(
          'Оригинал ответа',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (replyToSender != null)
              Text(
                '@$replyToSender',
                style: const TextStyle(
                  color: Colors.blueAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (replyToSender != null) const SizedBox(height: 8),
            Text(
              replyToContent ?? 'Содержимое недоступно',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  void _showChatInfo() {
    if (widget.chat.type == 'saved') {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Избранное', style: TextStyle(color: Colors.white)),
          content: const Text(
            'Личное пространство для сообщений и файлов, сохранённых для себя.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
      return;
    }

    if (widget.chat.type == 'group' || widget.chat.type == 'channel') {
      showDialog<bool>(
        context: context,
        builder: (context) => ChatInfoWidget(
          chatId: widget.chat.id,
          currentUserId: widget.currentUser.id,
        ),
      ).then((didLeave) {
        if (didLeave != true) return;
        unawaited(_loadParticipantsCount());
        if (widget.chat.type == 'channel') {
          unawaited(_loadChannelPermission());
        }
        widget.onMembershipChanged?.call();
      });
      return;
    }

    showDialog(
      context: context,
      builder: (context) => ChatInfoWidget(
        chatId: widget.chat.id,
        currentUserId: widget.currentUser.id,
      ),
    ).then((needRefresh) {
      if (needRefresh == true) _refreshBlockStatus();
    });
  }

  Future<void> _showChatHeaderAction() async {
    if (widget.chat.type != 'direct') {
      _showChatInfo();
      return;
    }

    var userId = _otherUserId;
    if (userId == null || userId.isEmpty) {
      try {
        final participant = await Supabase.instance.client
            .from('room_participants')
            .select('user_id')
            .eq('room_id', widget.chat.id)
            .neq('user_id', widget.currentUser.id)
            .maybeSingle();
        userId = participant?['user_id'] as String?;
      } catch (error) {
        debugPrint('Ошибка загрузки профиля участника чата: $error');
        if (mounted) Toast.error(context, 'Не удалось открыть профиль');
        return;
      }
    }

    if (!mounted) return;
    if (userId == null || userId.isEmpty) {
      Toast.error(context, 'Не удалось найти пользователя');
      return;
    }

    showDialog<void>(
      context: context,
      builder: (context) => ProfileDialog(
        user: app.User(
          id: userId!,
          name: widget.chat.name,
          tag: _otherUserTag ?? '',
          avatarUrl: _otherUserAvatar,
          status: _otherUserStatus,
          badge: _otherUserBadge,
        ),
        onAudioCall: () => _startCall(isVideo: false),
        onVideoCall: () => _startCall(isVideo: true),
        onUsernameTap: _openUsernameChat,
      ),
    );
  }

  Future<void> _leaveChannel() async {
    if (_isSubscribing) return;
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Выйти из канала?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Чтобы снова получать звук и видеть канал в списке подписок, нужно будет подписаться заново.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    if (shouldLeave != true || !mounted) return;

    setState(() => _isSubscribing = true);
    try {
      await Supabase.instance.client.rpc(
        'remove_room_member',
        params: {
          'p_room_id': widget.chat.id,
          'p_user_id': widget.currentUser.id,
        },
      );
      if (!mounted) return;
      setState(() {
        _isChannelSubscribed = false;
        _canPostToChannel = false;
      });
      await _loadParticipantsCount();
      widget.onMembershipChanged?.call();
      Toast.success(context, 'Вы вышли из канала');
    } catch (error) {
      debugPrint('Ошибка выхода из канала: $error');
      if (mounted) Toast.error(context, 'Не удалось выйти из канала');
    } finally {
      if (mounted) setState(() => _isSubscribing = false);
    }
  }

  Future<void> _loadParticipantsCount() async {
    try {
      final int participantCount;
      if (widget.chat.type == 'channel') {
        participantCount = await Supabase.instance.client.rpc(
          'get_channel_subscriber_count',
          params: {'p_room_id': widget.chat.id},
        );
      } else {
        final response = await Supabase.instance.client
            .from('room_participants')
            .select('user_id')
            .eq('room_id', widget.chat.id);
        participantCount = response.length;
      }

      if (mounted) {
        setState(() {
          _participantsCount = participantCount;
        });
      }
    } catch (e) {
      if (mounted) {
        Toast.error(context, 'Ошибка загрузки участников');
      }
    }
  }

  Future<void> _refreshBlockStatus() async {
    if (widget.chat.type != 'direct') return;

    try {
      final response = await Supabase.instance.client
          .from('room_participants')
          .select('user_id')
          .eq('room_id', widget.chat.id)
          .neq('user_id', widget.currentUser.id)
          .maybeSingle();

      if (response == null) return;

      _otherUserId = response['user_id'] as String;

      final blockResponse = await Supabase.instance.client
          .from('blocks')
          .select()
          .eq('blocker_id', widget.currentUser.id)
          .eq('blocked_id', _otherUserId!)
          .maybeSingle();

      final reverseBlockResponse = await Supabase.instance.client
          .from('blocks')
          .select()
          .eq('blocker_id', _otherUserId!)
          .eq('blocked_id', widget.currentUser.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _isBlocked = blockResponse != null || reverseBlockResponse != null;
        });
      }
    } catch (e) {
      if (mounted) {
        Toast.error(context, 'Ошибка обновления блокировки');
      }
    }
  }

  Future<void> _loadMessages({bool loadMore = false}) async {
    if (loadMore) {
      if (_isLoadingMore || !_hasMoreMessages) return;
      setState(() {
        _isLoadingMore = true;
      });
    } else {
      setState(() {
        if (!_isInitialLoadComplete) _isLoading = true;
        _hasMoreMessages = true;
        _oldestMessageDate = null;
      });
    }

    try {
      final messages = await _chatService.getMessagesPaginated(
        widget.chat.id,
        limit: _messagesPageSize,
        before: loadMore ? _oldestMessageDate : null,
        currentUser: widget.currentUser,
        cryptoService: _cryptoService,
      );

      if (!mounted) return;

      final loadedMessages = messages.map((msg) {
        return msg.copyWith(
          sender: msg.senderIsChannel
              ? msg.sender
              : msg.isMe
              ? widget.currentUser
              : msg.sender,
          readByOthers: widget.chat.type == 'saved' && msg.isMe,
        );
      }).toList();
      for (final message in loadedMessages) {
        final latestObserved = _latestObservedMessageAt;
        if (latestObserved == null ||
            message.createdAt.isAfter(latestObserved)) {
          _latestObservedMessageAt = message.createdAt;
        }
      }

      final orderedPage = loadedMessages.reversed.toList();
      if (_supportsReadReceipts && widget.chat.type != 'saved') {
        final ownMessageIds = orderedPage
            .where((message) => message.isMe)
            .map((message) => message.id)
            .toList();
        try {
          final readMessageIds = await _chatService.getReadMessageIds(
            ownMessageIds,
            widget.currentUser.id,
          );
          for (var index = 0; index < orderedPage.length; index++) {
            if (readMessageIds.contains(orderedPage[index].id)) {
              orderedPage[index] = orderedPage[index].copyWith(
                readByOthers: true,
              );
            }
          }
        } catch (error) {
          debugPrint('Не удалось загрузить статусы прочтения: $error');
        }
      }
      if (!mounted) return;

      setState(() {
        final existingIds = <String>{};
        final pendingMessages = _messages
            .where((message) => _pendingUploads.containsKey(message.id))
            .toList();
        final combinedMessages = loadMore
            ? [...orderedPage, ..._messages]
            : [...orderedPage, ...pendingMessages];
        _messages = combinedMessages
            .where((message) => existingIds.add(message.id))
            .toList();

        _isLoading = false;
        _isLoadingMore = false;
        _isInitialLoadComplete = true;

        if (loadedMessages.isNotEmpty) {
          _oldestMessageDate = loadedMessages.last.createdAt;
          _hasMoreMessages = loadedMessages.length >= _messagesPageSize;
        } else {
          _hasMoreMessages = false;
        }
      });

      if (!loadMore) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients && _messages.isNotEmpty) {
            _scrollController.jumpTo(0);
            _updateFloatingDate();
            _scheduleVisibleMessagesRead();
          }
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scheduleVisibleMessagesRead();
        });
      }
    } catch (e) {
      if (mounted) {
        Toast.error(context, 'Ошибка загрузки сообщений');
      }
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  void _subscribeToRealtime() async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        if (mounted) {
          Toast.error(context, 'Вы не авторизованы');
        }
        return;
      }

      _realtimeChannel = Supabase.instance.client
          .channel('room_${widget.chat.id}')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'room_id',
              value: widget.chat.id,
            ),
            callback: (payload) async {
              if (!mounted) return;

              final newMessageId = payload.newRecord['id'];
              final alreadyExists = _messages.any((m) => m.id == newMessageId);
              if (alreadyExists) return;

              final senderId = payload.newRecord['profile_id'];
              final isMe = senderId == widget.currentUser.id;
              final isVoice = payload.newRecord['is_voice'] ?? false;
              final isImage = Message.isImageMessage(payload.newRecord);
              final isPoll =
                  payload.newRecord['encrypted_content_type'] == 'poll';
              var isGift = Message.isGiftMessage(payload.newRecord);
              final rawGiftName = payload.newRecord['gift_name']?.toString();
              var giftName = rawGiftName?.isNotEmpty == true
                  ? rawGiftName
                  : Message.giftNameFromContent(
                      payload.newRecord['encrypted_content']?.toString(),
                    );
              final isSticker = Message.isStickerMessage(payload.newRecord);
              final isFile = payload.newRecord['is_file'] ?? false;
              final isPinned = payload.newRecord['is_pinned'] == true;

              String decryptedContent = '';
              String? decryptedCaption;

              final pollOptions = isPoll
                  ? await Future.wait(
                      (payload.newRecord['poll_options'] as List<dynamic>? ??
                              const [])
                          .map(
                            (value) => _cryptoService.decodeRoomContent(
                              roomId: widget.chat.id,
                              senderId: senderId,
                              content: value.toString(),
                            ),
                          ),
                    )
                  : const <String>[];

              if (isGift) {
                decryptedContent =
                    payload.newRecord['encrypted_content']?.toString() ??
                    'Подарок';
              } else if (isPoll) {
                decryptedContent = await _cryptoService.decodeRoomContent(
                  roomId: widget.chat.id,
                  senderId: senderId,
                  content:
                      payload.newRecord['encrypted_content']?.toString() ?? '',
                );
              } else if (isImage) {
                final imageContent =
                    payload.newRecord['encrypted_content']?.toString() ?? '';
                decryptedContent =
                    await _chatService.resolveChatStorageUrl(
                      'chat_media',
                      normalizeStorageUrl(imageContent),
                    ) ??
                    imageContent;
                if (payload.newRecord['image_caption'] != null &&
                    payload.newRecord['image_caption'].toString().isNotEmpty) {
                  try {
                    decryptedCaption = await _cryptoService.decodeRoomContent(
                      roomId: widget.chat.id,
                      senderId: senderId,
                      content: payload.newRecord['image_caption'].toString(),
                    );
                  } catch (e) {
                    debugPrint('Не удалось расшифровать подпись: $e');
                    decryptedCaption = '[Не удалось расшифровать подпись]';
                  }
                }
              } else if (isFile) {
                final fileName =
                    payload.newRecord['file_name'] as String? ?? 'Файл';
                decryptedContent = 'Файл: $fileName';
              } else if (!isVoice) {
                final encryptedContent =
                    payload.newRecord['encrypted_content'] ?? '';
                try {
                  decryptedContent = await _cryptoService.decodeRoomContent(
                    roomId: widget.chat.id,
                    senderId: senderId,
                    content: encryptedContent.toString(),
                  );
                } catch (e) {
                  debugPrint('Не удалось расшифровать сообщение: $e');
                  decryptedContent = '[Не удалось расшифровать сообщение]';
                }
              } else {
                decryptedContent = 'Голосовое сообщение';
              }

              final legacyGiftName = Message.giftNameFromContent(
                decryptedContent,
              );
              if (legacyGiftName != null) {
                isGift = true;
                giftName ??= legacyGiftName;
              }

              app.User? sender;
              if (payload.newRecord['sender_is_channel'] == true) {
                sender = app.User(
                  id: senderId,
                  name: payload.newRecord['sender_name'] ?? widget.chat.name,
                  tag: payload.newRecord['sender_tag'] ?? '',
                  avatarUrl: payload.newRecord['sender_avatar'],
                );
              } else if (isMe) {
                sender = widget.currentUser;
              } else {
                sender = app.User(
                  id: senderId,
                  name: payload.newRecord['sender_name'] ?? 'Пользователь',
                  tag: payload.newRecord['sender_tag'] ?? '',
                  avatarUrl: payload.newRecord['sender_avatar'],
                );
              }

              final replyToId = payload.newRecord['reply_to_id'] as String?;
              final replyToContent =
                  payload.newRecord['reply_to_content'] as String?;
              final replyToSender =
                  payload.newRecord['reply_to_sender'] as String?;

              final newMessage = Message(
                id: newMessageId,
                chatId: payload.newRecord['room_id'],
                senderId: senderId,
                senderIsChannel: payload.newRecord['sender_is_channel'] == true,
                forwardedFromUserId:
                    payload.newRecord['forwarded_from_user_id'] as String?,
                forwardedFromName:
                    payload.newRecord['forwarded_from_name'] as String?,
                content: decryptedContent,
                createdAt: parseDateTimeSafely(payload.newRecord['created_at']),
                isMe: isMe,
                sender: sender,
                isVoice: isVoice,
                isImage: isImage,
                isPoll: isPoll,
                pollOptions: pollOptions,
                pollAllowMultiple:
                    payload.newRecord['poll_allow_multiple'] == true,
                pollClosed: payload.newRecord['poll_closed'] == true,
                isSticker: isSticker,
                isGift: isGift,
                giftName: giftName,
                giftEmoji: payload.newRecord['gift_emoji'] as String?,
                giftPriceEnc: (payload.newRecord['gift_price_enc'] as num?)
                    ?.toInt(),
                giftCaption: payload.newRecord['gift_caption'] as String?,
                imageCaption: decryptedCaption,
                voiceUrl: await _chatService.resolveChatStorageUrl(
                  'voice_messages',
                  payload.newRecord['voice_url'],
                ),
                voiceDuration: payload.newRecord['voice_duration'] != null
                    ? Duration(
                        seconds: payload.newRecord['voice_duration'] as int,
                      )
                    : null,
                replyToId: replyToId,
                replyToContent: replyToContent,
                replyToSender: replyToSender,
                isFile: isFile,
                fileName: payload.newRecord['file_name'] as String?,
                fileUrl: await _chatService.resolveChatStorageUrl(
                  payload.newRecord['encrypted_content_type'] == 'video_note'
                      ? 'chat_media'
                      : 'chat_files',
                  payload.newRecord['file_url'],
                ),
                fileSize: payload.newRecord['file_size'] as int?,
                fileMimeType: payload.newRecord['file_mime_type'] as String?,
                isVideoNote:
                    payload.newRecord['encrypted_content_type'] == 'video_note',
                isPinned: isPinned,
                readByOthers: widget.chat.type == 'saved' && isMe,
              );

              setState(() {
                if (!_messages.any((m) => m.id == newMessage.id)) {
                  _messages.add(newMessage);
                }
              });
              final latestObserved = _latestObservedMessageAt;
              if (latestObserved == null ||
                  newMessage.createdAt.isAfter(latestObserved)) {
                _latestObservedMessageAt = newMessage.createdAt;
              }

              if (!isMe) {
                unawaited(_playIncomingSound());
                _vibrateIfEnabled();
              }

              final wasAtBottom =
                  _scrollController.hasClients &&
                  _scrollController.position.pixels < 100;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (wasAtBottom && _scrollController.hasClients) {
                  _scrollController.jumpTo(0);
                }
                _scheduleVisibleMessagesRead();
              });
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'room_id',
              value: widget.chat.id,
            ),
            callback: (payload) async {
              if (!mounted) return;

              final messageId = payload.newRecord['id']?.toString();
              if (messageId == null) return;
              final updatedIsPinned = payload.newRecord['is_pinned'] == true;

              final index = _messages.indexWhere((m) => m.id == messageId);
              if (index != -1) {
                final existingMessage = _messages[index];
                var updatedContent = existingMessage.content;
                var updatedCaption = existingMessage.imageCaption;
                if (payload.newRecord['is_edited'] == true) {
                  try {
                    if (existingMessage.isImage &&
                        payload.newRecord['image_caption'] != null) {
                      updatedCaption = await _cryptoService.decodeRoomContent(
                        roomId: widget.chat.id,
                        senderId: payload.newRecord['profile_id'] as String,
                        content: payload.newRecord['image_caption'].toString(),
                      );
                    } else if (!existingMessage.isImage &&
                        !existingMessage.isVoice &&
                        !existingMessage.isFile &&
                        !existingMessage.isPoll) {
                      updatedContent = await _cryptoService.decodeRoomContent(
                        roomId: widget.chat.id,
                        senderId: payload.newRecord['profile_id'] as String,
                        content:
                            payload.newRecord['encrypted_content']
                                ?.toString() ??
                            '',
                      );
                    }
                  } catch (error) {
                    debugPrint(
                      'Не удалось расшифровать отредактированное сообщение: '
                      '$error',
                    );
                    if (existingMessage.isImage) {
                      updatedCaption = '[Не удалось расшифровать подпись]';
                    } else {
                      updatedContent = '[Не удалось расшифровать сообщение]';
                    }
                  }
                }

                if (!mounted) return;
                setState(() {
                  _messages[index] = existingMessage.copyWith(
                    content: updatedContent,
                    imageCaption: updatedCaption,
                    isEdited: payload.newRecord['is_edited'] == true,
                    isPinned: updatedIsPinned,
                    giftNftSerial:
                        (payload.newRecord['gift_nft_serial'] as num?)?.toInt(),
                    giftNftSkinName:
                        payload.newRecord['gift_nft_skin_name'] as String?,
                    giftNftSkinEmoji:
                        payload.newRecord['gift_nft_skin_emoji'] as String?,
                    giftNftBackgroundColor:
                        payload.newRecord['gift_nft_background_color']
                            as String?,
                    giftNftPattern:
                        payload.newRecord['gift_nft_pattern'] as String?,
                    giftNftAnimationUrl:
                        payload.newRecord['gift_nft_animation_url'] as String?,
                  );
                });
              }

              if (updatedIsPinned ||
                  _pinnedMessages.any((m) => m.id == messageId)) {
                _loadPinnedMessages();
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.delete,
            schema: 'public',
            table: 'messages',
            callback: (payload) {
              final deletedRoomId = payload.oldRecord['room_id']?.toString();
              if (deletedRoomId != null && deletedRoomId != widget.chat.id) {
                return;
              }
              final messageId = payload.oldRecord['id']?.toString();
              if (!mounted) return;
              if (messageId == null) return;
              setState(() {
                _messages.removeWhere((message) => message.id == messageId);
                _selectedMessageIds.remove(messageId);
                if (_selectedMessageIds.isEmpty) {
                  _isSelectingMessages = false;
                }
              });
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'message_reads',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'room_id',
              value: widget.chat.id,
            ),
            callback: (payload) {
              if (!mounted || !_supportsReadReceipts) return;
              if (payload.newRecord['user_id'] == widget.currentUser.id) {
                return;
              }

              final messageId = payload.newRecord['message_id'];
              final index = _messages.indexWhere(
                (message) => message.id == messageId && message.isMe,
              );
              if (index == -1 || _messages[index].readByOthers) return;

              setState(() {
                _messages[index] = _messages[index].copyWith(
                  readByOthers: true,
                );
              });
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'message_reactions',
            callback: (payload) {
              unawaited(
                _refreshMessageReactions(payload.newRecord['message_id']),
              );
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'message_reactions',
            callback: (payload) {
              unawaited(
                _refreshMessageReactions(payload.newRecord['message_id']),
              );
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.delete,
            schema: 'public',
            table: 'message_reactions',
            callback: (payload) {
              unawaited(
                _refreshMessageReactions(payload.oldRecord['message_id']),
              );
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'message_poll_votes',
            callback: (payload) {
              unawaited(
                _refreshPollVoteSummary(payload.newRecord['message_id']),
              );
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'message_poll_votes',
            callback: (payload) {
              unawaited(
                _refreshPollVoteSummary(payload.newRecord['message_id']),
              );
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.delete,
            schema: 'public',
            table: 'message_poll_votes',
            callback: (payload) {
              unawaited(
                _refreshPollVoteSummary(payload.oldRecord['message_id']),
              );
            },
          )
          .subscribe((status, err) {
            final state = status.toString().toLowerCase();
            if (err != null ||
                state.contains('channelerror') ||
                state.contains('timedout') ||
                state.contains('closed')) {
              _startPolling();
            } else if (state.contains('subscribed')) {
              _stopPolling();
            }
          });
    } catch (e) {
      _startPolling();
    }
  }

  void _startPolling() {
    _stopPolling();
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      try {
        final newMessages = await _chatService.getMessagesPaginated(
          widget.chat.id,
          limit: _messagesPageSize,
          currentUser: widget.currentUser,
          cryptoService: _cryptoService,
        );
        _applyPollSummaries(newMessages);

        final existingIds = _messages.map((message) => message.id).toSet();
        final latestObserved = _latestObservedMessageAt;
        final newMessagesList =
            newMessages
                .where(
                  (message) =>
                      !existingIds.contains(message.id) &&
                      (latestObserved == null ||
                          message.createdAt.isAfter(latestObserved)),
                )
                .toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        if (newMessagesList.isNotEmpty) {
          if (newMessagesList.any((msg) => !msg.isMe)) {
            unawaited(_playIncomingSound());
            _vibrateIfEnabled();
          }

          final messagesToAdd = newMessagesList.map((msg) {
            return msg.copyWith(
              sender: msg.isMe ? widget.currentUser : msg.sender,
              readByOthers: widget.chat.type == 'saved' && msg.isMe
                  ? true
                  : msg.readByOthers,
            );
          }).toList();
          for (final message in messagesToAdd) {
            final latest = _latestObservedMessageAt;
            if (latest == null || message.createdAt.isAfter(latest)) {
              _latestObservedMessageAt = message.createdAt;
            }
          }

          if (mounted) {
            setState(() {
              for (final message in messagesToAdd) {
                final index = _messages.indexWhere((m) => m.id == message.id);
                if (index == -1) {
                  _messages.add(message);
                } else {
                  _messages[index] = message;
                }
              }
              _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
            });

            final wasAtBottom =
                _scrollController.hasClients &&
                _scrollController.position.pixels < 100;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (wasAtBottom && _scrollController.hasClients) {
                _scrollController.jumpTo(0);
              }
              _scheduleVisibleMessagesRead();
            });
          }
        }

        if (_supportsReadReceipts) {
          final unreadOwnMessages = _messages
              .where((message) => message.isMe && !message.readByOthers)
              .take(100)
              .toList();
          if (unreadOwnMessages.isNotEmpty) {
            final readMessageIds = await _chatService.getReadMessageIds(
              unreadOwnMessages.map((message) => message.id).toList(),
              widget.currentUser.id,
            );
            if (mounted && readMessageIds.isNotEmpty) {
              setState(() {
                for (var index = 0; index < _messages.length; index++) {
                  final message = _messages[index];
                  if (readMessageIds.contains(message.id)) {
                    _messages[index] = message.copyWith(readByOthers: true);
                  }
                }
              });
            }
          }
        }

        await _refreshAllMessageReactions();
      } catch (_) {}
    });
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  Future<void> _sendGif(String gifUrl) async {
    if (_isBlocked) {
      if (mounted) {
        Toast.warning(
          context,
          'Вы не можете отправлять сообщения этому пользователю',
        );
      }
      return;
    }

    try {
      await _chatService.sendStickerMessage(widget.chat.id, gifUrl);

      if (mounted) {
        await _loadMessages(loadMore: false);
      }
    } catch (e) {
      if (mounted) {
        Toast.error(context, 'Ошибка отправки GIF: $e');
      }
    }
  }

  void _addPendingUpload(
    Message message, {
    required String label,
    String? previewPath,
    int totalBytes = 0,
    bool isPreparing = false,
  }) {
    if (!mounted) return;
    setState(() {
      _messages.add(message);
      _pendingUploads[message.id] = _PendingUpload(
        label: label,
        previewPath: previewPath,
        totalBytes: totalBytes,
        isPreparing: isPreparing,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    });
  }

  void _updatePendingUpload(
    String messageId, {
    int? uploadedBytes,
    int? totalBytes,
    bool? isPreparing,
  }) {
    final upload = _pendingUploads[messageId];
    if (!mounted || upload == null) return;
    setState(() {
      if (uploadedBytes != null) upload.uploadedBytes = uploadedBytes;
      if (totalBytes != null) upload.totalBytes = totalBytes;
      if (isPreparing != null) upload.isPreparing = isPreparing;
    });
  }

  void _removePendingUpload(String messageId) {
    if (!mounted) return;
    setState(() {
      _pendingUploads.remove(messageId);
      _messages.removeWhere((message) => message.id == messageId);
    });
  }

  String _formatPendingMegabytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';

  Widget _buildPendingUploadBubble(Message message) {
    final upload = _pendingUploads[message.id]!;
    final progress = upload.totalBytes > 0
        ? (upload.uploadedBytes / upload.totalBytes).clamp(0.0, 1.0)
        : null;
    final remainingBytes = (upload.totalBytes - upload.uploadedBytes).clamp(
      0,
      upload.totalBytes,
    );
    final hasPreview = !kIsWeb && message.isImage && upload.previewPath != null;

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: message.isImage ? 268 : 248,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF202830),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (message.isImage)
              SizedBox(
                height: 190,
                child: Stack(
                  fit: StackFit.expand,
                  alignment: Alignment.center,
                  children: [
                    if (hasPreview)
                      Image.file(
                        File(upload.previewPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: Color(0xFF303943),
                          child: Icon(
                            Icons.image_outlined,
                            color: Colors.white54,
                            size: 42,
                          ),
                        ),
                      )
                    else
                      const ColoredBox(
                        color: Color(0xFF303943),
                        child: Icon(
                          Icons.image_outlined,
                          color: Colors.white54,
                          size: 42,
                        ),
                      ),
                    ColoredBox(color: Colors.black.withValues(alpha: 0.38)),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox.square(
                          dimension: 48,
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 3,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          upload.isPreparing
                              ? upload.label
                              : progress == 1
                              ? 'Завершаем отправку...'
                              : 'Осталось ${_formatPendingMegabytes(remainingBytes)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                child: Row(
                  children: [
                    Icon(
                      message.isVoice
                          ? Icons.mic_rounded
                          : message.isVideoNote
                          ? Icons.video_camera_front_rounded
                          : Icons.insert_drive_file_rounded,
                      color: const Color(0xFF9ABDE9),
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        message.isVoice ? 'Голосовое сообщение' : upload.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox.square(
                      dimension: 32,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 2.5,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (!message.isImage)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Text(
                  upload.isPreparing
                      ? upload.label
                      : progress == 1
                      ? 'Завершаем отправку...'
                      : 'Осталось ${_formatPendingMegabytes(remainingBytes)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendFile() async {
    String? pendingMessageId;
    try {
      final file = await FileUploadService.pickFile();
      if (file == null) return;

      final fileName = file.name;
      final reportedFileSize = await file.length();
      if (!await _checkUploadSize(reportedFileSize)) return;
      final bytes = await file.readAsBytes();
      final fileSize = bytes.length;
      if (fileSize != reportedFileSize && !await _checkUploadSize(fileSize)) {
        return;
      }

      final tempMessage = Message(
        id: 'temp_file_${DateTime.now().millisecondsSinceEpoch}',
        chatId: widget.chat.id,
        senderId: widget.currentUser.id,
        content: 'Файл: $fileName',
        createdAt: DateTime.now(),
        isMe: true,
        sender: widget.currentUser,
        isFile: true,
        fileName: fileName,
        fileSize: fileSize,
      );
      pendingMessageId = tempMessage.id;
      _addPendingUpload(tempMessage, label: fileName, totalBytes: fileSize);

      final fileUrl = await FileUploadService().uploadFile(
        fileBytes: bytes,
        fileName: fileName,
        chatId: widget.chat.id,
        userId: widget.currentUser.id,
        onProgress: (uploadedBytes, totalBytes) => _updatePendingUpload(
          tempMessage.id,
          uploadedBytes: uploadedBytes,
          totalBytes: totalBytes,
        ),
      );

      await _chatService.sendFileMessage(
        widget.chat.id,
        fileUrl,
        fileName,
        fileSize,
      );

      if (mounted) {
        Toast.success(context, 'Файл отправлен!');
        await _loadMessages(loadMore: false);
      }
    } catch (e) {
      if (mounted) {
        Toast.error(context, 'Ошибка отправки файла: $e');
      }
    } finally {
      if (pendingMessageId != null) {
        _removePendingUpload(pendingMessageId);
      }
    }
  }

  Future<void> _sendPhoto() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) return;

    if (mounted) {
      _showPhotoCaptionDialog(image);
    }
  }

  Widget _buildVideoNoteRecorderOverlay() {
    final controller = _videoNoteCameraController;
    final isInitialized = controller?.value.isInitialized ?? false;
    final diameter = (MediaQuery.sizeOf(context).width - 48)
        .clamp(220.0, 320.0)
        .toDouble();
    final progress =
        (_videoNoteElapsed.inMilliseconds /
                const Duration(seconds: 60).inMilliseconds)
            .clamp(0.0, 1.0);
    final elapsedSeconds = _videoNoteElapsed.inSeconds;
    final elapsedLabel =
        '${(elapsedSeconds ~/ 60).toString().padLeft(1, '0')}:'
        '${(elapsedSeconds % 60).toString().padLeft(2, '0')}';

    return Container(
      width: diameter + 24,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xF0151923),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (_isRecordingVideoNote)
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF4B55),
                    shape: BoxShape.circle,
                  ),
                ),
              if (_isRecordingVideoNote) const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isPreparingVideoNote
                      ? 'Подключение камеры...'
                      : _isRecordingVideoNote
                      ? 'Запись видеокружка'
                      : 'Завершение записи...',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Отменить запись',
                visualDensity: VisualDensity.compact,
                onPressed: _isSendingVideoNote
                    ? null
                    : _cancelVideoNoteRecording,
                icon: const Icon(Icons.close, color: Colors.white70, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox.square(
            dimension: diameter,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ClipOval(
                  child: ColoredBox(
                    color: Colors.white,
                    child: SizedBox.expand(
                      child: isInitialized
                          ? CameraPreview(controller!)
                          : const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF9B5CFF),
                                strokeWidth: 2,
                              ),
                            ),
                    ),
                  ),
                ),
                SizedBox.square(
                  dimension: diameter,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 4,
                    backgroundColor: Colors.white.withValues(alpha: 0.25),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFFFF4B55),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: _cancelVideoNoteRecording,
                icon: const Icon(Icons.delete_outline, size: 19),
                label: const Text('Отмена'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
              Text(
                '$elapsedLabel / 1:00',
                style: const TextStyle(
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                  fontSize: 13,
                ),
              ),
              IconButton.filled(
                tooltip: 'Отправить видеокружок',
                onPressed: _isRecordingVideoNote
                    ? _finishVideoNoteRecording
                    : null,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFFF4B55),
                  disabledBackgroundColor: Colors.white12,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.stop_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _sendVideoNote() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      if (mounted) {
        Toast.error(context, 'Запись видеокружков доступна на телефоне');
      }
      return;
    }

    if (_isPreparingVideoNote ||
        _isRecordingVideoNote ||
        _isStoppingVideoNote ||
        _isSendingVideoNote) {
      return;
    }

    final session = ++_videoNoteSession;
    setState(() => _isPreparingVideoNote = true);
    try {
      final cameras = await availableCameras();
      if (!mounted || session != _videoNoteSession) return;
      if (cameras.isEmpty) {
        throw StateError('На устройстве не найдена камера');
      }

      final camera = cameras.firstWhere(
        (description) => description.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: true,
        fps: 30,
      );
      _videoNoteCameraController = controller;
      if (mounted) setState(() {});

      await controller.initialize();
      if (!mounted ||
          session != _videoNoteSession ||
          _videoNoteCameraController != controller) {
        return;
      }

      await controller.startVideoRecording();
      if (!mounted ||
          session != _videoNoteSession ||
          _videoNoteCameraController != controller) {
        if (_videoNoteCameraController == controller) {
          await _releaseVideoNoteCamera(discardRecording: true);
        }
        return;
      }

      _videoNoteRecordingStartedAt = DateTime.now();
      setState(() {
        _isPreparingVideoNote = false;
        _isRecordingVideoNote = true;
        _videoNoteElapsed = Duration.zero;
      });
      _videoNoteTimer = Timer.periodic(const Duration(milliseconds: 200), (
        timer,
      ) {
        final startedAt = _videoNoteRecordingStartedAt;
        if (startedAt == null || !mounted) {
          timer.cancel();
          return;
        }

        final elapsed = DateTime.now().difference(startedAt);
        if (elapsed >= const Duration(seconds: 60)) {
          unawaited(_finishVideoNoteRecording());
          return;
        }
        setState(() => _videoNoteElapsed = elapsed);
      });
    } catch (e, stackTrace) {
      if (session != _videoNoteSession) return;
      debugPrint('Не удалось запустить камеру видеокружка: $e\n$stackTrace');
      await _releaseVideoNoteCamera(discardRecording: true);
      if (mounted) {
        setState(() => _isPreparingVideoNote = false);
        Toast.error(context, 'Не удалось запустить камеру: $e');
      }
    }
  }

  Future<void> _finishVideoNoteRecording() async {
    final controller = _videoNoteCameraController;
    if (_isPreparingVideoNote && !_isRecordingVideoNote) {
      await _cancelVideoNoteRecording();
      return;
    }
    if (controller == null || !_isRecordingVideoNote || _isStoppingVideoNote) {
      return;
    }

    _videoNoteTimer?.cancel();
    setState(() {
      _isRecordingVideoNote = false;
      _isStoppingVideoNote = true;
    });

    try {
      final recording = await controller.stopVideoRecording();
      _videoNoteCameraController = null;
      await controller.dispose();
      _videoNoteRecordingStartedAt = null;
      if (mounted) {
        setState(() {
          _isStoppingVideoNote = false;
          _isSendingVideoNote = true;
        });
      }
      await _uploadVideoNote(File(recording.path));
    } catch (e, stackTrace) {
      debugPrint('Ошибка завершения записи видеокружка: $e\n$stackTrace');
      await _releaseVideoNoteCamera(discardRecording: true);
      if (mounted) {
        setState(() {
          _isStoppingVideoNote = false;
          _isSendingVideoNote = false;
        });
        Toast.error(context, 'Ошибка записи видеокружка: $e');
      }
    } finally {
      if (mounted) setState(() => _isSendingVideoNote = false);
    }
  }

  Future<void> _cancelVideoNoteRecording() async {
    _videoNoteSession++;
    _videoNoteTimer?.cancel();
    _videoNoteRecordingStartedAt = null;
    if (mounted) {
      setState(() {
        _isPreparingVideoNote = false;
        _isRecordingVideoNote = false;
        _isStoppingVideoNote = false;
      });
    }
    await _releaseVideoNoteCamera(discardRecording: true);
  }

  Future<void> _releaseVideoNoteCamera({required bool discardRecording}) async {
    final controller = _videoNoteCameraController;
    _videoNoteCameraController = null;
    if (controller == null) return;

    try {
      if (controller.value.isRecordingVideo) {
        final recording = await controller.stopVideoRecording();
        if (discardRecording) {
          final file = File(recording.path);
          if (await file.exists()) await file.delete();
        }
      }
    } catch (e) {
      debugPrint('Не удалось корректно остановить камеру видеокружка: $e');
    } finally {
      await controller.dispose();
    }
  }

  Future<void> _uploadVideoNote(File recordedVideo) async {
    File? roundVideo;
    String? uploadedFilePath;
    String? pendingMessageId;
    try {
      if (mounted) Toast.info(context, 'Обработка видеокружка...');
      final pendingMessage = Message(
        id: 'temp_video_note_${DateTime.now().millisecondsSinceEpoch}',
        chatId: widget.chat.id,
        senderId: widget.currentUser.id,
        content: 'Видеокружок',
        createdAt: DateTime.now(),
        isMe: true,
        sender: widget.currentUser,
        isVideoNote: true,
      );
      pendingMessageId = pendingMessage.id;
      _addPendingUpload(
        pendingMessage,
        label: 'Подготовка видеокружка...',
        isPreparing: true,
      );
      roundVideo = await _videoNoteService.makeRoundVideo(recordedVideo.path);
      final fileSize = await roundVideo.length();
      _updatePendingUpload(
        pendingMessage.id,
        totalBytes: fileSize,
        isPreparing: false,
      );
      if (!await _checkUploadSize(fileSize)) return;
      final bytes = await roundVideo.readAsBytes();
      if (bytes.length != fileSize && !await _checkUploadSize(bytes.length)) {
        return;
      }

      final fileName =
          'video_note_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final filePath = normalizeStoragePath('${widget.chat.id}/$fileName');
      await StorageUploadService.uploadBinary(
        bucket: 'chat_media',
        path: filePath,
        bytes: bytes,
        contentType: 'video/mp4',
        onProgress: (uploadedBytes, totalBytes) => _updatePendingUpload(
          pendingMessage.id,
          uploadedBytes: uploadedBytes,
          totalBytes: totalBytes,
        ),
      );
      uploadedFilePath = filePath;

      await _chatService.sendVideoNoteMessage(
        widget.chat.id,
        filePath,
        fileName,
        fileSize,
      );
      uploadedFilePath = null;

      if (mounted) {
        Toast.success(context, 'Видеокружок отправлен!');
        await _loadMessages(loadMore: false);
      }
    } catch (e, stackTrace) {
      debugPrint('Ошибка отправки видеокружка: $e\n$stackTrace');
      if (uploadedFilePath != null) {
        try {
          await StorageUploadService.remove(
            bucket: 'chat_media',
            path: uploadedFilePath,
          );
        } catch (cleanupError) {
          debugPrint('Не удалось удалить несвязанное видео: $cleanupError');
        }
      }
      if (mounted) {
        Toast.error(context, 'Ошибка отправки видеокружка: $e');
      }
    } finally {
      if (roundVideo != null) {
        try {
          if (await roundVideo.exists()) await roundVideo.delete();
        } catch (e) {
          debugPrint('Не удалось удалить временный видеокружок: $e');
        }
      }
      try {
        if (await recordedVideo.exists()) await recordedVideo.delete();
      } catch (e) {
        debugPrint('Не удалось удалить исходную запись видеокружка: $e');
      }
      if (pendingMessageId != null) {
        _removePendingUpload(pendingMessageId);
      }
    }
  }

  void _showPhotoCaptionDialog(XFile image) async {
    final captionController = TextEditingController();

    Uint8List? imageBytes;
    try {
      imageBytes = await image.readAsBytes();
    } catch (e) {
      debugPrint('Ошибка чтения изображения: $e');
      if (mounted) {
        Toast.error(context, 'Не удалось загрузить фото');
      }
      return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Фото', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: imageBytes != null
                    ? SizedBox(
                        width: MediaQuery.of(context).size.width * 0.7,
                        height: 200,
                        child: Image.memory(
                          imageBytes,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                height: 200,
                                color: Colors.grey[800],
                                child: const Center(
                                  child: Icon(
                                    Icons.broken_image,
                                    color: Colors.grey,
                                    size: 48,
                                  ),
                                ),
                              ),
                        ),
                      )
                    : Container(
                        height: 200,
                        color: Colors.grey[800],
                        child: const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.7,
                child: TextField(
                  controller: captionController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Добавить подпись...',
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    filled: true,
                    fillColor: const Color(0xFF282828),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  maxLines: 2,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _uploadAndSendPhoto(image, captionController.text.trim());
            },
            child: const Text(
              'Отправить',
              style: TextStyle(color: Color(0xFF1A73E8)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadAndSendPhoto(XFile image, String caption) async {
    String? pendingMessageId;
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        throw Exception('Нет активной Supabase-сессии');
      }

      final imageSize = await image.length();
      if (!await _checkUploadSize(imageSize)) return;
      final bytes = await image.readAsBytes();
      if (bytes.length != imageSize && !await _checkUploadSize(bytes.length)) {
        return;
      }
      if (mounted) Toast.info(context, 'Загрузка фото...');
      final extension = image.name.split('.').last.toLowerCase();
      final safeExtension = extension.isEmpty ? 'jpg' : extension;
      final mimeType = safeExtension == 'png' ? 'image/png' : 'image/jpeg';
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}.$safeExtension';
      final filePath = normalizeStoragePath('${widget.chat.id}/$fileName');
      final pendingMessage = Message(
        id: 'temp_photo_${DateTime.now().millisecondsSinceEpoch}',
        chatId: widget.chat.id,
        senderId: widget.currentUser.id,
        content: caption.isEmpty ? 'Фото' : caption,
        createdAt: DateTime.now(),
        isMe: true,
        sender: widget.currentUser,
        isImage: true,
        imageCaption: caption,
      );
      pendingMessageId = pendingMessage.id;
      _addPendingUpload(
        pendingMessage,
        label: 'Фото',
        previewPath: image.path,
        totalBytes: bytes.length,
      );

      await StorageUploadService.uploadBinary(
        bucket: 'chat_media',
        path: filePath,
        bytes: bytes,
        contentType: mimeType,
        onProgress: (uploadedBytes, totalBytes) => _updatePendingUpload(
          pendingMessage.id,
          uploadedBytes: uploadedBytes,
          totalBytes: totalBytes,
        ),
      );

      await _chatService.sendPhotoMessage(
        widget.chat.id,
        filePath,
        caption: caption,
      );

      if (mounted) {
        Toast.success(context, 'Фото отправлено!');
        await _loadMessages(loadMore: false);
      }
    } catch (e, st) {
      debugPrint('Ошибка отправки фото: $e\n$st');
      if (mounted) {
        if (e is UploadLimitException) {
          Toast.error(context, e.message);
          return;
        }
        final err = e.toString();
        String message;
        if (err.contains('bucket')) {
          message =
              'На сервере не настроен bucket chat_media или нет прав доступа';
        } else if (err.contains('401') ||
            err.contains('403') ||
            err.toLowerCase().contains('permission')) {
          message =
              'Ошибка доступа (401/403). Проверь права bucket в Supabase.';
        } else if (err.toLowerCase().contains('cors') ||
            err.toLowerCase().contains('network')) {
          message =
              'Проблема сети/CORS. Проверь URL Supabase и доступность хоста.';
        } else {
          message =
              'Ошибка отправки фото: ${err.length > 120 ? '${err.substring(0, 120)}...' : err}';
        }

        Toast.error(context, message);
      }
    } finally {
      if (pendingMessageId != null) {
        _removePendingUpload(pendingMessageId);
      }
    }
  }

  Future<void> _sendSticker(String stickerUrl) async {
    await _chatService.sendStickerMessage(widget.chat.id, stickerUrl);
  }

  Future<void> _showCreatePollDialog() async {
    final poll = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const CreatePollDialog(),
    );

    if (poll == null || !mounted) return;

    try {
      await _chatService.sendPollMessage(
        roomId: widget.chat.id,
        question: poll['question'] as String,
        options: (poll['options'] as List).cast<String>(),
        allowMultiple: poll['allowMultiple'] as bool,
      );
      if (mounted) await _loadMessages(loadMore: false);
    } catch (error) {
      if (mounted) Toast.error(context, 'Не удалось создать опрос');
    }
  }

  Future<void> _handlePollVote(Message message, List<int> optionIndices) async {
    try {
      await _chatService.voteOnPoll(
        messageId: message.id,
        optionIndices: optionIndices,
      );
      await _refreshPollVoteSummary(message.id);
    } catch (error) {
      if (mounted) Toast.error(context, 'Не удалось сохранить голос');
    }
  }

  Future<void> _refreshPollVoteSummary(dynamic rawMessageId) async {
    if (rawMessageId is! String) return;
    final index = _messages.indexWhere((message) => message.id == rawMessageId);
    if (index == -1) return;
    try {
      final summary = await _chatService.getPollVoteSummary(rawMessageId);
      if (!mounted) return;
      final currentIndex = _messages.indexWhere(
        (message) => message.id == rawMessageId,
      );
      if (currentIndex == -1) return;
      setState(() {
        _messages[currentIndex] = _messages[currentIndex].copyWith(
          pollVotes: Map<int, int>.from(summary['counts'] as Map),
          myPollVotes: (summary['my_votes'] as List).cast<int>(),
        );
      });
    } catch (error) {
      debugPrint('Не удалось обновить результаты опроса: $error');
    }
  }

  void _applyPollSummaries(List<Message> loadedMessages) {
    final freshPolls = {
      for (final message in loadedMessages)
        if (message.isPoll) message.id: message,
    };
    if (freshPolls.isEmpty) return;

    var changed = false;
    final updated = _messages.map((message) {
      final fresh = freshPolls[message.id];
      if (fresh == null || !message.isPoll) return message;
      changed = true;
      return message.copyWith(
        pollVotes: fresh.pollVotes,
        myPollVotes: fresh.myPollVotes,
      );
    }).toList();
    if (changed && mounted) setState(() => _messages = updated);
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Container(
          height: 318,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          decoration: BoxDecoration(
            color: const Color(0xFF151923),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Прикрепить',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.05,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildAttachmentItem(
                      icon: Icons.photo_library_outlined,
                      label: 'Фото',
                      color: const Color(0xFF70B7FF),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _sendPhoto();
                      },
                    ),
                    _buildAttachmentItem(
                      icon: Icons.video_camera_front_outlined,
                      label: 'Кружок',
                      color: const Color(0xFFB88CFF),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _sendVideoNote();
                      },
                    ),
                    _buildAttachmentItem(
                      icon: Icons.poll_outlined,
                      label: 'Опрос',
                      color: const Color(0xFF7BE0BD),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _showCreatePollDialog();
                        });
                      },
                    ),
                    _buildAttachmentItem(
                      icon: Icons.emoji_emotions_outlined,
                      label: 'Стикеры',
                      color: const Color(0xFFE4A7FF),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _toggleEmojiPicker();
                      },
                    ),
                    _buildAttachmentItem(
                      icon: Icons.insert_drive_file_outlined,
                      label: 'Файл',
                      color: const Color(0xFFFFBE72),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _sendFile();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: 0.28),
                  color.withValues(alpha: 0.10),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: color.withValues(alpha: 0.35)),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.12),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _clearChatHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Очистить историю?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Все сообщения в этом чате будут удалены без возможности восстановления',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              backgroundColor: Colors.red.withValues(alpha: 0.1),
            ),
            child: const Text('Очистить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      Toast.info(context, 'Очистка истории...');

      await _chatService.clearChatHistory(
        widget.chat.id,
        widget.currentUser.id,
      );

      setState(() {
        _messages.clear();
        _hasMoreMessages = true;
        _oldestMessageDate = null;
      });

      if (mounted) {
        Toast.success(context, 'История очищена');
        await _loadMessages(loadMore: false);
      }
    } catch (e) {
      if (mounted) {
        Toast.error(context, 'Ошибка очистки: ${e.toString()}');
      }
    }
  }

  Future<void> _sendVoiceMessage(File audioFile) async {
    String? pendingMessageId;
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        throw Exception('Нет сессии');
      }

      final fileSize = await audioFile.length();
      if (!await _checkUploadSize(fileSize)) return;
      final bytes = await audioFile.readAsBytes();
      if (bytes.length != fileSize && !await _checkUploadSize(bytes.length)) {
        return;
      }

      final tempMessage = Message(
        id: 'temp_voice_${DateTime.now().millisecondsSinceEpoch}',
        chatId: widget.chat.id,
        senderId: widget.currentUser.id,
        content: 'Голосовое сообщение',
        createdAt: DateTime.now(),
        isMe: true,
        sender: widget.currentUser,
        isVoice: true,
        voiceDuration: const Duration(seconds: 0),
      );
      pendingMessageId = tempMessage.id;
      _addPendingUpload(
        tempMessage,
        label: 'Голосовое сообщение',
        totalBytes: bytes.length,
      );

      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final filePath = '${widget.chat.id}/$fileName';

      await StorageUploadService.uploadBinary(
        bucket: 'voice_messages',
        path: filePath,
        bytes: bytes,
        contentType: 'audio/m4a',
        onProgress: (uploadedBytes, totalBytes) => _updatePendingUpload(
          tempMessage.id,
          uploadedBytes: uploadedBytes,
          totalBytes: totalBytes,
        ),
      );

      final voiceDuration = await _getAudioDuration(audioFile);

      final encryptedContent = _cryptoService.encodeCloudContent(
        'voice_message_${DateTime.now().millisecondsSinceEpoch}',
      );

      await _chatService.sendVoiceMessage(
        widget.chat.id,
        filePath,
        voiceDuration,
        encryptedContent,
      );

      if (mounted) {
        Toast.success(context, 'Голосовое отправлено');
        await _loadMessages(loadMore: false);
      }
    } catch (e) {
      if (mounted) {
        Toast.error(context, 'Ошибка отправки голосового: $e');
      }
    } finally {
      if (pendingMessageId != null) {
        _removePendingUpload(pendingMessageId);
      }
    }
  }

  Future<bool> _checkUploadSize(int sizeBytes) async {
    final role =
        widget.currentUser.role ?? AuthService().getUserRole() ?? 'user';
    try {
      await UploadLimitsService.ensureWithinLimit(
        sizeBytes: sizeBytes,
        role: role,
        isPremium:
            role.trim().toLowerCase() == 'premium' ||
            await SubscriptionService.isSubscriptionActive(),
      );
      return true;
    } on UploadSizeLimitExceeded catch (error) {
      if (mounted) Toast.warning(context, error.message);
      return false;
    } on UploadLimitException catch (error) {
      debugPrint('Не удалось проверить лимит отправки: $error');
      if (mounted) {
        Toast.error(context, 'Не удалось проверить лимит отправки: $error');
      }
      return false;
    }
  }

  Future<Duration> _getAudioDuration(File audioFile) async {
    try {
      final player = AudioPlayer();
      await player.setSourceDeviceFile(audioFile.path);
      final duration = await player.getDuration();
      await player.dispose();
      return duration ?? const Duration(seconds: 3);
    } catch (e) {
      return const Duration(seconds: 3);
    }
  }

  void _openAudioPlayer(String url) {
    setState(() {
      _currentAudioUrl = url;
      _showAudioPlayer = true;
    });
  }

  void _hideAudioPlayer() {
    setState(() {
      _showAudioPlayer = false;
      _currentAudioUrl = null;
    });
  }

  Future<void> _playMessageSound(String assetPath) async {
    final sound = SoundService();

    if (sound.settings.value.silentMode) return;

    final volume = sound.currentVolume;
    if (volume <= 0) return;

    try {
      await _soundPlayer.setVolume(volume);
      await _soundPlayer.play(AssetSource(assetPath));
    } catch (e) {
      debugPrint('Ошибка воспроизведения звука: $e');
    }
  }

  Future<void> _playIncomingSound() async {
    final sound = SoundService();

    if (sound.settings.value.silentMode) return;
    if (sound.currentVolume <= 0) return;
    if (widget.chat.type == 'channel' &&
        (!_isChannelSubscribed || !_channelSoundEnabled)) {
      return;
    }

    final isGroup =
        widget.chat.type == 'group' || widget.chat.type == 'channel';
    final enabled = isGroup
        ? sound.groupMessageEnabled
        : sound.incomingMessageEnabled;

    if (!enabled) return;

    await _playMessageSound('sounds/message_here.mp3');
  }

  Future<void> _playOutgoingSound() async {
    final sound = SoundService();

    if (sound.settings.value.silentMode) return;
    if (sound.currentVolume <= 0) return;
    if (!sound.outgoingMessageEnabled) return;

    await _playMessageSound('sounds/send_message.mp3');
  }

  void _vibrateIfEnabled() {
    final sound = SoundService();
    if (sound.settings.value.silentMode) return;
    if (!sound.vibrateEnabled) return;
    HapticFeedback.mediumImpact();
  }

  Future<void> _sendMessage({String? stickerUrl}) async {
    if (_editingMessage != null) {
      await _saveEditedMessage();
      return;
    }

    if (_isBlocked) {
      if (mounted) {
        Toast.warning(
          context,
          'Вы не можете отправлять сообщения этому пользователю',
        );
      }
      return;
    }

    String content = _messageController.text.trim();

    if (stickerUrl != null) {
      _sendSticker(stickerUrl);
      return;
    } else if (content.isEmpty) {
      _cancelReply();
      return;
    } else {
      _messageController.clear();
      _focusNode.unfocus();
    }

    final optimisticMessage = Message(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      chatId: widget.chat.id,
      senderId: widget.currentUser.id,
      content: content,
      createdAt: DateTime.now(),
      isMe: true,
      sender: widget.currentUser,
      replyToId: _replyingTo?.id,
      replyToContent: _replyingTo != null
          ? (_replyingTo!.isImage ? 'Фото' : _replyingTo!.content)
          : null,
      replyToSender: _replyingTo?.sender?.name ?? _replyingTo?.senderId,
    );

    if (mounted) {
      setState(() {
        _messages.add(optimisticMessage);
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }

    try {
      String? serverMessageId;
      if (_replyingTo != null) {
        serverMessageId = await _chatService.sendReplyMessage(
          widget.chat.id,
          content,
          _replyingTo!.id,
        );
        _cancelReply();
      } else {
        serverMessageId = await _chatService.sendMessage(
          widget.chat.id,
          content,
        );
      }

      if (serverMessageId == null) {
        throw StateError('Сервер не подтвердил отправку сообщения');
      }

      if (mounted) {
        setState(() {
          final optimisticIndex = _messages.indexWhere(
            (msg) => msg.id == optimisticMessage.id,
          );
          final persistedIndex = _messages.indexWhere(
            (msg) => msg.id == serverMessageId,
          );
          if (optimisticIndex != -1 && persistedIndex != -1) {
            _messages.removeAt(optimisticIndex);
          } else if (optimisticIndex != -1) {
            _messages[optimisticIndex] = optimisticMessage.copyWith(
              id: serverMessageId,
            );
          }
        });
        unawaited(_playOutgoingSound());
      }

      if (!kIsWeb &&
          (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focusNode.requestFocus();
        });
      }
    } catch (e) {
      if (mounted) {
        final errorText = e.toString();
        Toast.error(
          context,
          'Ошибка отправки: ${errorText.length > 180 ? '${errorText.substring(0, 180)}...' : errorText}',
        );
      }
      if (mounted) {
        setState(() {
          _messages.removeWhere((msg) => msg.id == optimisticMessage.id);
        });
      }
      if (!kIsWeb &&
          (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focusNode.requestFocus();
        });
      }
    }
  }

  Future<void> _showGiftPicker() async {
    if (widget.chat.type != 'direct' || _otherUserId == null) {
      Toast.info(context, 'Подарки доступны в личных чатах');
      return;
    }

    final sent = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => GiftShopScreen(
          roomId: widget.chat.id,
          recipientId: _otherUserId!,
          recipientName: _otherUserName?.isNotEmpty == true
              ? _otherUserName!
              : _otherUserTag?.isNotEmpty == true
              ? '@$_otherUserTag'
              : widget.chat.name,
          recipientAvatarUrl: _otherUserAvatar,
        ),
      ),
    );
    if (sent == true && mounted) {
      unawaited(_loadMessages(loadMore: false));
    }
  }

  void _toggleEmojiPicker() {
    setState(() {
      _showEmojiPicker = !_showEmojiPicker;
    });
    if (_showEmojiPicker) {
      _focusNode.unfocus();
    } else {
      _focusNode.requestFocus();
    }
  }

  void _onEmojiSelected(String emoji) {
    final text = _messageController.text;
    final selection = _messageController.selection;
    final newText = text.replaceRange(selection.start, selection.end, emoji);
    _messageController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selection.start + emoji.length,
      ),
    );
  }

  void _onStickerSelected(String stickerUrl) {
    setState(() {
      _showEmojiPicker = false;
    });
    _sendMessage(stickerUrl: stickerUrl);
  }

  Future<void> _loadStickers({bool initial = false}) async {
    if (_isLoadingStickers || !_hasMoreStickers) return;

    setState(() {
      _isLoadingStickers = true;
      _stickerError = '';
    });

    try {
      final limit = initial ? _stickerInitialLoadSize : _stickerPageSize;
      final uri = Uri.parse(_giphyBaseUrl).replace(
        queryParameters: {
          'api_key': _giphyApiKey,
          'q': _stickerSearchQuery,
          'limit': '$limit',
          'offset': '$_stickerOffset',
          'rating': 'g',
          'lang': 'ru',
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('Giphy API error: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final gifs = data['data'] as List<dynamic>? ?? [];

      final newStickers = <String>[];
      for (final gif in gifs) {
        final images = gif['images'] as Map<String, dynamic>?;
        final fixedHeight = images?['fixed_height'] as Map<String, dynamic>?;
        final url = fixedHeight?['url'] as String?;
        if (url != null) {
          newStickers.add(url);
        }
      }

      if (!mounted) return;

      setState(() {
        if (initial) {
          _stickers
            ..clear()
            ..addAll(newStickers);
          _stickerInitialLoaded = true;
        } else {
          _stickers.addAll(newStickers);
        }
        _stickerOffset += newStickers.length;
        _hasMoreStickers = newStickers.length == limit;
        _isLoadingStickers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingStickers = false;
        _stickerError = 'Не удалось загрузить стикеры';
      });
    }
  }

  void _onStickerScroll() {
    if (!_stickerScrollController.hasClients) return;
    final position = _stickerScrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadStickers();
    }
  }

  void _onStickerSearchChanged(String query) {
    _stickerSearchDebounce?.cancel();
    _stickerSearchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final newQuery = query.trim().isEmpty ? 'funny' : query.trim();
      if (newQuery == _stickerSearchQuery) return;
      setState(() {
        _stickerSearchQuery = newQuery;
        _stickers.clear();
        _stickerOffset = 0;
        _hasMoreStickers = true;
        _stickerInitialLoaded = false;
      });
      _loadStickers(initial: true);
    });
  }

  Future<void> _blockUserFromMenu() async {
    if (_otherUserId == null) return;

    try {
      final now = DateTime.now().toIso8601String();
      await Supabase.instance.client.from('blocks').insert([
        {
          'blocker_id': widget.currentUser.id,
          'blocked_id': _otherUserId!,
          'created_at': now,
        },
        {
          'blocker_id': _otherUserId!,
          'blocked_id': widget.currentUser.id,
          'created_at': now,
        },
      ]);

      if (mounted) {
        setState(() {
          _isBlocked = true;
        });
        Toast.success(context, 'Пользователь заблокирован');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        Toast.error(context, 'Ошибка блокировки');
      }
    }
  }

  Future<void> _unblockUserFromMenu() async {
    if (_otherUserId == null) return;

    try {
      await Supabase.instance.client
          .from('blocks')
          .delete()
          .or(
            'and(blocker_id.eq.${widget.currentUser.id},blocked_id.eq.$_otherUserId),and(blocker_id.eq.$_otherUserId,blocked_id.eq.${widget.currentUser.id})',
          );

      if (mounted) {
        setState(() {
          _isBlocked = false;
        });
        Toast.success(context, 'Пользователь разблокирован');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        Toast.error(context, 'Ошибка разблокировки');
      }
    }
  }

  Future<void> _reportChatUser() async {
    final userId = _otherUserId;
    if (userId == null || userId == widget.currentUser.id) return;
    await _showReportDialog(
      reportedUserId: userId,
      reportedUserName: widget.chat.name,
    );
  }

  Future<void> _reportMessage(Message message) async {
    if (message.isMe ||
        message.senderIsChannel ||
        message.senderId.isEmpty ||
        message.senderId == widget.currentUser.id) {
      return;
    }
    await _showReportDialog(
      reportedUserId: message.senderId,
      reportedUserName: 'Пользователь ${message.senderId.substring(0, 8)}',
      message: message,
    );
  }

  Future<void> _showReportDialog({
    required String reportedUserId,
    required String reportedUserName,
    Message? message,
  }) async {
    var selectedReason = 'harassment';
    var details = '';
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text(
            'Пожаловаться',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message == null
                      ? 'Жалоба на ${reportedUserName}'
                      : 'Жалоба на сообщение пользователя',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: selectedReason,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF252525),
                  decoration: const InputDecoration(
                    labelText: 'Причина',
                    labelStyle: TextStyle(color: Colors.white60),
                  ),
                  style: const TextStyle(color: Colors.white),
                  items: const [
                    DropdownMenuItem(
                      value: 'spam',
                      child: Text('Спам или мошенничество'),
                    ),
                    DropdownMenuItem(
                      value: 'harassment',
                      child: Text('Оскорбления или травля'),
                    ),
                    DropdownMenuItem(
                      value: 'inappropriate',
                      child: Text('Неприемлемый контент'),
                    ),
                    DropdownMenuItem(
                      value: 'illegal',
                      child: Text('Незаконный или опасный контент'),
                    ),
                    DropdownMenuItem(value: 'other', child: Text('Другое')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedReason = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  maxLength: 1000,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (value) => details = value,
                  decoration: const InputDecoration(
                    labelText: 'Комментарий (необязательно)',
                    labelStyle: TextStyle(color: Colors.white60),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'reason': selectedReason,
                'details': details.trim(),
              }),
              child: const Text(
                'Отправить жалобу',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;

    final content = (message?.content ?? '');
    try {
      await Supabase.instance.client.from('moderation_reports').insert({
        'reporter_id': widget.currentUser.id,
        'reported_user_id': reportedUserId,
        'reported_user_name': reportedUserName,
        'target_type': message == null ? 'user' : 'message',
        'message_id': message?.id,
        'chat_id': message?.chatId,
        'content_snapshot': message == null
            ? ''
            : (content.length > 2000 ? content.substring(0, 2000) : content),
        'reason': result['reason'],
        'details': result['details'],
      });
      if (mounted) Toast.success(context, 'Жалоба отправлена модераторам');
    } catch (error) {
      debugPrint('Не удалось отправить жалобу: $error');
      if (mounted) {
        Toast.error(context, 'Не удалось отправить жалобу. Попробуйте позже.');
      }
    }
  }

  void _showFullScreenImage(String imageUrl, {String? caption}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.download, color: Colors.white),
                onPressed: () {
                  _downloadImage(imageUrl);
                },
                tooltip: 'Сохранить',
              ),
            ],
          ),
          body: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      width: MediaQuery.of(context).size.width,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                : null,
                            color: Colors.white,
                          ),
                        );
                      },
                      errorBuilder: (_, _, _) => const Center(
                        child: Icon(
                          Icons.broken_image,
                          color: Colors.grey,
                          size: 64,
                        ),
                      ),
                    ),
                  ),
                  if (caption != null && caption.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      color: Colors.black87,
                      child: Text(
                        caption,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyChatWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF211735),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF9B5CFF).withValues(alpha: 0.26),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.chat_bubble_outline,
                color: Color(0xFFD1C2EF),
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Нет сообщений',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.chat.type == 'channel' && !_canPostToChannel
                  ? 'В этом канале пока нет сообщений'
                  : 'Напишите первое сообщение,\nчтобы начать общение',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 15,
                height: 1.5,
              ),
            ),
            if (widget.chat.type != 'channel' || _canPostToChannel) ...[
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () {
                  _sendGif(
                    'https://gifs.obs.ru-moscow-1.hc.sbercloud.ru/c1e0638372ac770360b818bee27d842b1a71f6c15c1cf615f14b8fb253cc062e.gif',
                  );
                },
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF333333),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          'https://gifs.obs.ru-moscow-1.hc.sbercloud.ru/c1e0638372ac770360b818bee27d842b1a71f6c15c1cf615f14b8fb253cc062e.gif',
                          width: 200,
                          height: 200,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              width: 200,
                              height: 200,
                              color: const Color(0xFF171329),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFF9B5CFF),
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (_, _, _) => Container(
                            width: 200,
                            height: 200,
                            color: const Color(0xFF171329),
                            child: const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.gif_box,
                                    color: Colors.grey,
                                    size: 48,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Не удалось загрузить GIF',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF211735),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF9B5CFF),
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.touch_app,
                            color: Color(0xFFD1C2EF),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Нажмите, чтобы отправить',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.detached) &&
        (_isRecordingVideoNote ||
            (_videoNoteCameraController?.value.isInitialized ?? false))) {
      unawaited(_cancelVideoNoteRecording());
    }
  }

  @override
  void dispose() {
    _videoNoteSession++;
    WidgetsBinding.instance.removeObserver(this);
    _videoNoteTimer?.cancel();
    _floatingDateHideTimer?.cancel();
    unawaited(_releaseVideoNoteCamera(discardRecording: true));
    _replyHighlightTimer?.cancel();
    _readReceiptTimer?.cancel();
    _realtimeChannel?.unsubscribe();
    _statusChannel?.unsubscribe();
    _messageController.dispose();
    _scrollController.dispose();
    _scrollController.removeListener(_onScroll);
    _stickerScrollController.dispose();
    _stickerScrollController.removeListener(_onStickerScroll);
    _stickerSearchController.dispose();
    _stickerSearchDebounce?.cancel();
    _focusNode.dispose();
    _stopPolling();
    _statusPollingTimer?.cancel();
    unawaited(_soundPlayer.dispose());
    _webrtc.disconnectFromServer();
    super.dispose();
  }

  String _getStatusText(String? status) {
    final normalizedStatus = UserStatusService.normalizeStatus(status);
    return UserStatusService.getStatusText(normalizedStatus);
  }

  Color _getStatusColor(String? status) {
    final normalizedStatus = UserStatusService.normalizeStatus(status);
    return UserStatusService.getStatusColor(normalizedStatus);
  }

  String _subscriberCountWord(int count) {
    final lastTwoDigits = count % 100;
    if (lastTwoDigits >= 11 && lastTwoDigits <= 14) return 'подписчиков';
    return switch (count % 10) {
      1 => 'подписчик',
      2 || 3 || 4 => 'подписчика',
      _ => 'подписчиков',
    };
  }

  Widget _buildHeaderCircleButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color backgroundColor = const Color(0xFF171329),
    double size = 40,
  }) {
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFF9B5CFF).withValues(alpha: 0.3),
        ),
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: size, height: size),
        icon: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasAvatar =
        widget.chat.avatarUrl != null && widget.chat.avatarUrl!.isNotEmpty;
    final reportableSelectedMessage = _reportableSelectedMessage;

    return ColoredBox(
      color: Colors.transparent,
      child: WallpaperBackground(
        wallpaper: _wallpaper,
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            toolbarHeight: 64,
            titleSpacing: 4,
            leadingWidth: _isSelectingMessages || Navigator.canPop(context)
                ? 48
                : 0,
            leading: _isSelectingMessages
                ? _buildHeaderCircleButton(
                    icon: Icons.close,
                    tooltip: 'Отменить выбор',
                    onPressed: _clearMessageSelection,
                    backgroundColor: const Color(0xFF211735),
                  )
                : Navigator.canPop(context)
                ? _buildHeaderCircleButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Назад',
                    onPressed: () => Navigator.maybePop(context),
                    backgroundColor: const Color(0xFF211735),
                    size: 40,
                  )
                : null,
            title: _isSelectingMessages
                ? Text(
                    'Выбрано: ${_selectedMessageIds.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  )
                : GestureDetector(
                    onTap: _showChatHeaderAction,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: 54,
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF211735).withValues(alpha: 0.96),
                            const Color(0xFF100D1E).withValues(alpha: 0.94),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: const Color(
                            0xFF9B5CFF,
                          ).withValues(alpha: 0.28),
                        ),
                      ),
                      child: Row(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              GestureDetector(
                                onTap: hasAvatar
                                    ? () => showAvatarPreview(
                                        context,
                                        image: NetworkImage(
                                          widget.chat.avatarUrl!,
                                        ),
                                      )
                                    : null,
                                child: CircleAvatar(
                                  radius: 22,
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                  backgroundImage: hasAvatar
                                      ? NetworkImage(widget.chat.avatarUrl!)
                                      : null,
                                  child: !hasAvatar
                                      ? (widget.chat.type == 'saved'
                                            ? const Icon(
                                                Icons.bookmark,
                                                color: Colors.white,
                                                size: 22,
                                              )
                                            : Text(
                                                widget.chat.name.isNotEmpty
                                                    ? widget.chat.name[0]
                                                          .toUpperCase()
                                                    : '?',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ))
                                      : null,
                                ),
                              ),
                              // Звездочку убрали — этот блок удален
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        widget.chat.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.clip,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 19,
                                          fontWeight: FontWeight.w600,
                                          height: 1.12,
                                        ),
                                      ),
                                    ),
                                    if (widget.chat.type == 'channel' &&
                                        widget.chat.isVerified) ...[
                                      const SizedBox(width: 5),
                                      const Icon(
                                        Icons.verified,
                                        color: Color(0xFF1A73E8),
                                        size: 16,
                                      ),
                                    ],
                                  ],
                                ),
                                if (widget.chat.type == 'direct') ...[
                                  Row(
                                    children: [
                                      Container(
                                        width: 7,
                                        height: 7,
                                        decoration: BoxDecoration(
                                          color: _getStatusColor(
                                            _otherUserStatus,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Text(
                                          _getStatusText(_otherUserStatus),
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFFB7AEC9),
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ] else if (widget.chat.type == 'saved') ...[
                                  const Text(
                                    'Сообщения самому себе',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Color(0xFFB7AEC9),
                                      fontSize: 13,
                                    ),
                                  ),
                                ] else ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          widget.chat.type == 'channel'
                                              ? '$_participantsCount ${_subscriberCountWord(_participantsCount)}'
                                              : '$_participantsCount участников',
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFFB7AEC9),
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            actions: _isSelectingMessages
                ? [
                    IconButton(
                      tooltip: 'Переслать выбранные',
                      onPressed: _selectedMessages.isEmpty
                          ? null
                          : () => _forwardMessages(_selectedMessages),
                      icon: const Icon(Icons.forward, color: Colors.white),
                    ),
                    IconButton(
                      tooltip: 'Удалить выбранные сообщения',
                      onPressed: _deletableSelectedMessages.isEmpty
                          ? null
                          : _confirmDeleteSelectedMessages,
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                    ),
                    IconButton(
                      tooltip: 'Пожаловаться на сообщение',
                      onPressed: reportableSelectedMessage == null
                          ? null
                          : () => _reportMessage(reportableSelectedMessage),
                      icon: const Icon(
                        Icons.flag_outlined,
                        color: Colors.orangeAccent,
                      ),
                    ),
                  ]
                : [
                    if (widget.chat.type == 'channel' &&
                        _isChannelSubscribed &&
                        _canPostToChannel)
                      _buildHeaderCircleButton(
                        icon: _channelSoundEnabled
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_off_outlined,
                        tooltip: _channelSoundEnabled
                            ? 'Выключить звук канала'
                            : 'Включить звук канала',
                        onPressed: _toggleChannelSound,
                      ),
                    Container(
                      width: 40,
                      height: 40,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF171329).withValues(alpha: 0.95),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(
                            0xFF9B5CFF,
                          ).withValues(alpha: 0.24),
                        ),
                      ),
                      child: PopupMenuButton<String>(
                        onSelected: (value) async {
                          switch (value) {
                            case 'info_group':
                              _showChatInfo();
                              break;
                            case 'wallpaper':
                              final result = await Navigator.push<String>(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => WallpaperScreen(
                                    userId: widget.currentUser.id,
                                    currentWallpaper: _wallpaper,
                                  ),
                                ),
                              );
                              if (result != null && mounted) {
                                setState(() => _wallpaper = result);
                              }
                              break;
                            case 'mute_group':
                              break;
                            case 'clear_history':
                              await _clearChatHistory();
                              break;
                            case 'block_user':
                              if (widget.chat.type == 'direct') {
                                if (_isBlocked) {
                                  await _unblockUserFromMenu();
                                } else {
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      backgroundColor: const Color(0xFF2A2A2A),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      title: const Text(
                                        'Заблокировать пользователя?',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                      content: Text(
                                        'Вы больше не сможете писать @${_otherUserTag ?? 'пользователю'}',
                                        style: const TextStyle(
                                          color: Colors.grey,
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text(
                                            'Отмена',
                                            style: TextStyle(
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            Navigator.pop(context);
                                            _blockUserFromMenu();
                                          },
                                          style: TextButton.styleFrom(
                                            backgroundColor: Colors.red
                                                .withValues(alpha: 0.1),
                                          ),
                                          child: const Text(
                                            'Заблокировать',
                                            style: TextStyle(color: Colors.red),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              }
                              break;
                            case 'report_user':
                              await _reportChatUser();
                              break;
                            case 'leave_group':
                              if (widget.chat.type == 'channel') {
                                await _leaveChannel();
                              } else {
                                _showChatInfo();
                              }
                              break;
                          }
                        },
                        icon: const Icon(Icons.more_vert, color: Colors.white),
                        color: const Color(0xFF171329),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        itemBuilder: (context) {
                          final items = [
                            const PopupMenuItem(
                              value: 'info_group',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  SizedBox(width: 14),
                                  Text(
                                    'Информация',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'wallpaper',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.wallpaper,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  SizedBox(width: 14),
                                  Text(
                                    'Обои',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'mute_group',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.volume_off,
                                    color: Colors.red,
                                    size: 20,
                                  ),
                                  SizedBox(width: 14),
                                  Text(
                                    'Выключить звук',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'clear_history',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete_sweep,
                                    color: Colors.red,
                                    size: 20,
                                  ),
                                  SizedBox(width: 14),
                                  Text(
                                    'Очистить историю',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ];

                          if (widget.chat.type == 'group' ||
                              widget.chat.type == 'channel') {
                            items.add(
                              PopupMenuItem(
                                value: 'leave_group',
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.logout,
                                      color: Colors.red,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 14),
                                    Text(
                                      widget.chat.type == 'channel'
                                          ? 'Выйти из канала'
                                          : 'Управление группой',
                                      style: const TextStyle(color: Colors.red),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          } else if (widget.chat.type == 'direct') {
                            items.add(
                              PopupMenuItem(
                                value: 'block_user',
                                child: Row(
                                  children: [
                                    Icon(
                                      _isBlocked
                                          ? Icons.check_circle
                                          : Icons.block,
                                      color: _isBlocked
                                          ? Colors.green
                                          : Colors.red,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 14),
                                    Text(
                                      _isBlocked
                                          ? 'Разблокировать'
                                          : 'Заблокировать',
                                      style: TextStyle(
                                        color: _isBlocked
                                            ? Colors.green
                                            : Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                            items.add(
                              const PopupMenuItem(
                                value: 'report_user',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.flag_outlined,
                                      color: Colors.orangeAccent,
                                      size: 20,
                                    ),
                                    SizedBox(width: 14),
                                    Text(
                                      'Пожаловаться',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          return items;
                        },
                      ),
                    ),
                  ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) => Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth > 1200
                      ? 1120
                      : constraints.maxWidth,
                ),
                child: Column(
                  children: [
                    if (_showAudioPlayer && _currentAudioUrl != null)
                      AudioPlayerWidget(
                        url: _currentAudioUrl!,
                        onClose: _hideAudioPlayer,
                      ),
                    _buildPinnedMessageBanner(),
                    if (_isSearchingForMessage)
                      const LinearProgressIndicator(
                        minHeight: 2,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF9B5CFF),
                        ),
                      ),
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              child: _isLoading
                                  ? const ChatMessageLoading(
                                      key: ValueKey('message-loading'),
                                    )
                                  : _messages.isEmpty
                                  ? KeyedSubtree(
                                      key: const ValueKey('empty-chat'),
                                      child: _buildEmptyChatWidget(),
                                    )
                                  : ListView.builder(
                                      key: const ValueKey('loaded-messages'),
                                      controller: _scrollController,
                                      reverse: true,
                                      padding: const EdgeInsets.only(
                                        top: 8,
                                        bottom: 16,
                                      ),
                                      itemCount:
                                          _messages.length +
                                          (_isLoadingMore ? 1 : 0),
                                      itemBuilder: (context, index) {
                                        if (index == _messages.length) {
                                          return const Padding(
                                            padding: EdgeInsets.all(16.0),
                                            child: Center(
                                              child: CircularProgressIndicator(
                                                color: Color(0xFF1A73E8),
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          );
                                        }

                                        final messagesList = _messages.reversed
                                            .toList();
                                        final msg = messagesList[index];

                                        final prevMsg = index > 0
                                            ? messagesList[index - 1]
                                            : null;

                                        final showAvatar =
                                            (prevMsg == null ||
                                            prevMsg.senderId != msg.senderId ||
                                            prevMsg.senderIsChannel !=
                                                msg.senderIsChannel);

                                        return ChatMessageEntrance(
                                          key: ValueKey(msg.id),
                                          delay: Duration(
                                            milliseconds: (index * 24)
                                                .clamp(0, 240)
                                                .toInt(),
                                          ),
                                          child: Column(
                                            children: [
                                              if (_shouldShowDateHeader(
                                                index,
                                                messagesList,
                                              ))
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 12,
                                                      ),
                                                  child: Center(
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 12,
                                                            vertical: 5,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color:
                                                            const Color(
                                                              0xFF211735,
                                                            ).withValues(
                                                              alpha: 0.9,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              12,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        _formatMessageDate(
                                                          msg.createdAt,
                                                        ),
                                                        style: const TextStyle(
                                                          color: Colors.white70,
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              _HighlightGlow(
                                                active:
                                                    msg.id ==
                                                    _highlightedMessageId,
                                                token: _highlightToken,
                                                child: KeyedSubtree(
                                                  key: _messageKeys.putIfAbsent(
                                                    msg.id,
                                                    () => GlobalKey(),
                                                  ),
                                                  child: Stack(
                                                    children: [
                                                      AbsorbPointer(
                                                        absorbing:
                                                            _isSelectingMessages,
                                                        child:
                                                            _pendingUploads
                                                                .containsKey(
                                                                  msg.id,
                                                                )
                                                            ? _buildPendingUploadBubble(
                                                                msg,
                                                              )
                                                            : msg.isGift &&
                                                                  !msg.isDeleted
                                                            ? GiftChatItem(
                                                                message: msg,
                                                                onLongPress: () =>
                                                                    _toggleMessageSelection(
                                                                      msg,
                                                                    ),
                                                              )
                                                            : MessageBubble(
                                                                message: msg,
                                                                sender:
                                                                    msg.sender,
                                                                channelIsVerified:
                                                                    widget
                                                                        .chat
                                                                        .isVerified,
                                                                onChannelTap:
                                                                    _showChatInfo,
                                                                isMe: msg.isMe,
                                                                isGroup:
                                                                    widget
                                                                            .chat
                                                                            .type ==
                                                                        'group' ||
                                                                    widget
                                                                            .chat
                                                                            .type ==
                                                                        'channel',
                                                                showReadReceipt:
                                                                    _supportsReadReceipts,
                                                                assumeRead:
                                                                    widget
                                                                        .chat
                                                                        .type ==
                                                                    'saved',
                                                                senderBadge: msg
                                                                    .sender
                                                                    ?.badge,
                                                                showAvatar:
                                                                    showAvatar,
                                                                isHighlighted:
                                                                    msg.id ==
                                                                    _highlightedMessageId,
                                                                isPinned: msg
                                                                    .isPinned,
                                                                onPlayVoice: (url) {
                                                                  _openAudioPlayer(
                                                                    url,
                                                                  );
                                                                },
                                                                onOpenImage:
                                                                    (
                                                                      url, {
                                                                      caption,
                                                                    }) {
                                                                      _showFullScreenImage(
                                                                        url,
                                                                        caption:
                                                                            caption,
                                                                      );
                                                                    },
                                                                onUrlTap:
                                                                    (url) {
                                                                      _openUrl(
                                                                        url,
                                                                      );
                                                                    },
                                                                onUsernameTap:
                                                                    _openUsernameChat,
                                                                onCopy: (message) {
                                                                  Clipboard.setData(
                                                                    ClipboardData(
                                                                      text: message
                                                                          .content,
                                                                    ),
                                                                  );
                                                                },
                                                                onEdit: (message) {
                                                                  _showEditDialog(
                                                                    message,
                                                                  );
                                                                },
                                                                onReply: (message) {
                                                                  _replyToMessage(
                                                                    message,
                                                                  );
                                                                },
                                                                onReplyPreviewTap:
                                                                    (
                                                                      replyToId,
                                                                      replyToContent,
                                                                      replyToSender,
                                                                    ) {
                                                                      _handleReplyPreviewTap(
                                                                        replyToId,
                                                                        replyToContent,
                                                                        replyToSender,
                                                                      );
                                                                    },
                                                                onForward:
                                                                    _forwardMessage,
                                                                onSelect:
                                                                    _toggleMessageSelection,
                                                                onReaction:
                                                                    _handleMessageReaction,
                                                                doubleTapReaction:
                                                                    _doubleTapReaction,
                                                                onPollVote:
                                                                    _handlePollVote,
                                                                onDelete:
                                                                    (message) {
                                                                      _confirmDelete(
                                                                        message,
                                                                      );
                                                                    },
                                                                onDownloadFile:
                                                                    (
                                                                      url,
                                                                      fileName,
                                                                    ) {
                                                                      _downloadFileWithProgress(
                                                                        url,
                                                                        fileName,
                                                                      );
                                                                    },
                                                                onSaveVideoNote:
                                                                    (
                                                                      url,
                                                                      fileName,
                                                                    ) {
                                                                      _downloadFileWithProgress(
                                                                        url,
                                                                        fileName,
                                                                        saveToGallery:
                                                                            true,
                                                                      );
                                                                    },
                                                                onOpenFile:
                                                                    (filePath) {
                                                                      _openFile(
                                                                        filePath,
                                                                      );
                                                                    },
                                                                onOpenPdf:
                                                                    (
                                                                      url,
                                                                      fileName,
                                                                    ) {
                                                                      _openPdfViewer(
                                                                        url,
                                                                        fileName,
                                                                      );
                                                                    },
                                                                onPin:
                                                                    widget.chat.type !=
                                                                            'channel' ||
                                                                        _canPostToChannel
                                                                    ? _pinMessage
                                                                    : null,
                                                                onUnpin:
                                                                    widget.chat.type !=
                                                                            'channel' ||
                                                                        _canPostToChannel
                                                                    ? _unpinMessage
                                                                    : null,
                                                              ),
                                                      ),
                                                      if (_isSelectingMessages)
                                                        Positioned.fill(
                                                          child: Material(
                                                            color:
                                                                _selectedMessageIds
                                                                    .contains(
                                                                      msg.id,
                                                                    )
                                                                ? const Color(
                                                                    0xFF4080C0,
                                                                  ).withValues(
                                                                    alpha: 0.24,
                                                                  )
                                                                : Colors
                                                                      .transparent,
                                                            child: InkWell(
                                                              onTap: () =>
                                                                  _toggleMessageSelection(
                                                                    msg,
                                                                  ),
                                                              child: Align(
                                                                alignment:
                                                                    msg.isMe
                                                                    ? Alignment
                                                                          .centerRight
                                                                    : Alignment
                                                                          .centerLeft,
                                                                child: Padding(
                                                                  padding:
                                                                      const EdgeInsets.all(
                                                                        8,
                                                                      ),
                                                                  child: AnimatedContainer(
                                                                    duration: const Duration(
                                                                      milliseconds:
                                                                          140,
                                                                    ),
                                                                    width: 26,
                                                                    height: 26,
                                                                    decoration: BoxDecoration(
                                                                      color:
                                                                          _selectedMessageIds.contains(
                                                                            msg.id,
                                                                          )
                                                                          ? const Color(
                                                                              0xFF4F84C4,
                                                                            )
                                                                          : const Color(
                                                                              0xFF151923,
                                                                            ),
                                                                      shape: BoxShape
                                                                          .circle,
                                                                      border: Border.all(
                                                                        color: Colors
                                                                            .white70,
                                                                      ),
                                                                    ),
                                                                    child:
                                                                        _selectedMessageIds.contains(
                                                                          msg.id,
                                                                        )
                                                                        ? const Icon(
                                                                            Icons.check,
                                                                            color:
                                                                                Colors.white,
                                                                            size:
                                                                                17,
                                                                          )
                                                                        : null,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ),
                          if (_showFloatingDate && _floatingDate != null)
                            Positioned(
                              top: 8,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: AnimatedOpacity(
                                  opacity: _showFloatingDate ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 200),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF1A1A1A,
                                      ).withValues(alpha: 0.95),
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.4,
                                          ),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      _floatingDate!,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (_showScrollDownButton)
                            Positioned(
                              bottom: 20,
                              right: 20,
                              child: AnimatedOpacity(
                                opacity: _showScrollDownButton ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 200),
                                child: FloatingActionButton.small(
                                  onPressed: _scrollToBottom,
                                  backgroundColor: Colors.white,
                                  child: const Icon(
                                    Icons.arrow_downward,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ),
                          if (_videoNoteCameraController != null)
                            Positioned.fill(
                              child: Center(
                                child: _buildVideoNoteRecorderOverlay(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_editingMessage != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF26183B), Color(0xFF171329)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(
                            0xFF9B5CFF,
                          ).withValues(alpha: 0.45),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF9B5CFF,
                              ).withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Icon(
                              Icons.edit_outlined,
                              color: Color(0xFFD1C2EF),
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _isEditingCaption
                                      ? 'Изменение подписи'
                                      : 'Редактирование сообщения',
                                  style: const TextStyle(
                                    color: Color(0xFFD1C2EF),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _isEditingCaption
                                      ? _editingMessage!.imageCaption ?? ''
                                      : _editingMessage!.isImage
                                      ? (_editingMessage!.isSticker
                                            ? 'Стикер'
                                            : 'Фото')
                                      : _editingMessage!.isFile
                                      ? 'Файл: ${_editingMessage!.fileName ?? 'Документ'}'
                                      : _editingMessage!.isVoice
                                      ? 'Голосовое сообщение'
                                      : _editingMessage!.content,
                                  style: TextStyle(
                                    color: Colors.grey[300],
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Отменить редактирование',
                            onPressed: _isSavingEdit
                                ? null
                                : _cancelEditingMessage,
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 20,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_replyingTo != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: InkWell(
                      onTap: () {
                        _handleReplyPreviewTap(
                          _replyingTo!.id,
                          _replyingTo!.content,
                          _replyingTo!.sender?.name,
                        );
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF26183B), Color(0xFF171329)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(
                              0xFF9B5CFF,
                            ).withValues(alpha: 0.45),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF9B5CFF,
                                ).withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Icon(
                                Icons.reply,
                                color: Color(0xFFD1C2EF),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Ответ @${_replyingTo!.sender?.name ?? _replyingTo!.senderId}',
                                    style: const TextStyle(
                                      color: Color(0xFFD1C2EF),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _replyingTo!.content.length > 60
                                        ? '${_replyingTo!.content.substring(0, 60)}...'
                                        : _replyingTo!.content,
                                    style: TextStyle(
                                      color: Colors.grey[300],
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: _cancelReply,
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 20,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.only(
                    left: 8,
                    right: 8,
                    top: 8,
                    bottom: MediaQuery.of(context).viewInsets.bottom > 0
                        ? MediaQuery.of(context).viewInsets.bottom + 8
                        : 8,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF100D1E).withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: const Color(0xFF9B5CFF).withValues(alpha: 0.23),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF6B35D3,
                          ).withValues(alpha: 0.12),
                          blurRadius: 24,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: _isBlocked && widget.chat.type == 'direct'
                        ? SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                              onPressed: () async {
                                try {
                                  await Supabase.instance.client
                                      .from('blocks')
                                      .delete()
                                      .or(
                                        'and(blocker_id.eq.${widget.currentUser.id},blocked_id.eq.$_otherUserId),and(blocker_id.eq.$_otherUserId,blocked_id.eq.${widget.currentUser.id})',
                                      );

                                  if (!mounted) return;
                                  setState(() {
                                    _isBlocked = false;
                                  });

                                  Toast.success(
                                    context,
                                    'Пользователь разблокирован',
                                  );
                                } catch (e) {
                                  if (!mounted) return;
                                  Toast.error(context, 'Ошибка разблокировки');
                                }
                              },
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Разблокировать',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : widget.chat.type == 'channel' && !_canPostToChannel
                        ? _isChannelSubscribed
                              ? Center(
                                  child: OutlinedButton.icon(
                                    onPressed: _toggleChannelSound,
                                    icon: Icon(
                                      _channelSoundEnabled
                                          ? Icons.notifications_active_outlined
                                          : Icons.notifications_off_outlined,
                                    ),
                                    label: Text(
                                      _channelSoundEnabled
                                          ? 'Выключить звук'
                                          : 'Включить звук',
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: BorderSide(
                                        color: Colors.white.withValues(
                                          alpha: 0.18,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : Center(
                                  child: FilledButton.icon(
                                    onPressed: _isSubscribing
                                        ? null
                                        : _subscribeToChannel,
                                    icon: _isSubscribing
                                        ? const SizedBox.square(
                                            dimension: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.notifications_active,
                                          ),
                                    label: const Text('Подписаться'),
                                  ),
                                )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF211735,
                                  ).withValues(alpha: 0.9),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(
                                      0xFF9B5CFF,
                                    ).withValues(alpha: 0.2),
                                    width: 1,
                                  ),
                                ),
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  onPressed: _editingMessage == null
                                      ? _showAttachmentMenu
                                      : null,
                                  icon: const Icon(
                                    Icons.attach_file,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                              ),
                              if (widget.chat.type == 'direct') ...[
                                const SizedBox(width: 4),
                                SizedBox(
                                  width: 40,
                                  height: 44,
                                  child: IconButton(
                                    tooltip: 'Подарить за Encoins',
                                    onPressed: _editingMessage == null
                                        ? _showGiftPicker
                                        : null,
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(
                                      Icons.redeem,
                                      color: Color(0xFFFFC86B),
                                      size: 23,
                                    ),
                                  ),
                                ),
                              ],
                              if (widget.chat.type == 'channel') ...[
                                const SizedBox(width: 4),
                                SizedBox(
                                  width: 42,
                                  height: 44,
                                  child: IconButton(
                                    tooltip: _sendAsChannel
                                        ? 'Отправить от имени канала'
                                        : 'Отправить от своего имени',
                                    onPressed: () {
                                      setState(
                                        () => _sendAsChannel = !_sendAsChannel,
                                      );
                                      _updateMessageAuthor();
                                    },
                                    icon: Icon(
                                      _sendAsChannel
                                          ? Icons.campaign_outlined
                                          : Icons.person_outline,
                                      color: _sendAsChannel
                                          ? Colors.white
                                          : Colors.white54,
                                      size: 21,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(width: 6),
                              Expanded(
                                child: Container(
                                  constraints: const BoxConstraints(
                                    minHeight: 44,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF171329,
                                    ).withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: const Color(
                                        0xFF9B5CFF,
                                      ).withValues(alpha: 0.23),
                                      width: 1,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: TextField(
                                    controller: _messageController,
                                    focusNode: _focusNode,
                                    onChanged: (value) {
                                      if (value.isNotEmpty &&
                                          _showSendAfterEdit) {
                                        setState(
                                          () => _showSendAfterEdit = false,
                                        );
                                      }
                                    },
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                    ),
                                    minLines: 1,
                                    maxLines: 5,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    decoration: InputDecoration(
                                      hintText: _editingMessage != null
                                          ? (_isEditingCaption
                                                ? 'Изменить подпись...'
                                                : 'Изменить сообщение...')
                                          : _replyingTo != null
                                          ? 'Напишите ответ...'
                                          : 'Сообщение',
                                      hintStyle: const TextStyle(
                                        color: Color(0xFFAAA0BF),
                                        fontSize: 15,
                                      ),
                                      filled: false,
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                    ),
                                    onSubmitted: (_) {
                                      if (_editingMessage != null ||
                                          _messageController.text
                                              .trim()
                                              .isNotEmpty) {
                                        _sendMessage();
                                      }
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              ValueListenableBuilder<TextEditingValue>(
                                valueListenable: _messageController,
                                builder: (context, value, child) {
                                  final hasText = value.text.trim().isNotEmpty;
                                  final isEditing = _editingMessage != null;
                                  final showSend =
                                      hasText ||
                                      isEditing ||
                                      _showSendAfterEdit;

                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFF211735,
                                          ).withValues(alpha: 0.9),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: const Color(
                                              0xFF9B5CFF,
                                            ).withValues(alpha: 0.2),
                                            width: 1,
                                          ),
                                        ),
                                        child: IconButton(
                                          padding: EdgeInsets.zero,
                                          onPressed: _toggleEmojiPicker,
                                          icon: Icon(
                                            _showEmojiPicker
                                                ? Icons.keyboard
                                                : Icons.emoji_emotions_outlined,
                                            color: _showEmojiPicker
                                                ? const Color(0xFFD4B4FF)
                                                : Colors.white,
                                            size: 22,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      if (showSend)
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Color(0xFF9B5CFF),
                                                Color(0xFF6728E8),
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                          child: IconButton(
                                            padding: EdgeInsets.zero,
                                            tooltip: isEditing
                                                ? 'Сохранить изменения'
                                                : 'Отправить',
                                            icon: _isSavingEdit
                                                ? const SizedBox.square(
                                                    dimension: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Colors.white,
                                                        ),
                                                  )
                                                : Icon(
                                                    isEditing
                                                        ? Icons.check_rounded
                                                        : Icons.send_rounded,
                                                    color: Colors.white,
                                                    size: 22,
                                                  ),
                                            onPressed: _isSavingEdit
                                                ? null
                                                : _sendMessage,
                                          ),
                                        )
                                      else
                                        VoiceRecorder(
                                          onSend: _sendVoiceMessage,
                                          onStartVideoNote: _sendVideoNote,
                                          onStopVideoNote:
                                              _finishVideoNoteRecording,
                                          isVideoNoteActive:
                                              _isPreparingVideoNote ||
                                              _isRecordingVideoNote ||
                                              _isStoppingVideoNote ||
                                              _isSendingVideoNote,
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                  ),
                ),
                if (_showEmojiPicker)
                  Container(
                    height: 280,
                    color: const Color(0xFF110D1C),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              _buildTabButton('Эмоджи', _emojiTab == 0, () {
                                setState(() => _emojiTab = 0);
                              }),
                              const SizedBox(width: 16),
                              _buildTabButton('Стикеры', _emojiTab == 1, () {
                                setState(() => _emojiTab = 1);
                                if (!_stickerInitialLoaded) {
                                  _loadStickers(initial: true);
                                }
                              }),
                              const Spacer(),
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _showEmojiPicker = false;
                                    _focusNode.requestFocus();
                                  });
                                },
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ),
                        Container(height: 1, color: Colors.grey[800]),
                        Expanded(
                          child: IndexedStack(
                            index: _emojiTab,
                            children: [
                              GridView.builder(
                                padding: const EdgeInsets.all(10),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 8,
                                      crossAxisSpacing: 4,
                                      mainAxisSpacing: 4,
                                      childAspectRatio: 1.0,
                                    ),
                                itemCount: _emojis.length,
                                itemBuilder: (context, index) {
                                  return InkWell(
                                    onTap: () =>
                                        _onEmojiSelected(_emojis[index]),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Center(
                                      child: Text(
                                        _emojis[index],
                                        style: const TextStyle(fontSize: 26),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      8,
                                      12,
                                      4,
                                    ),
                                    child: TextField(
                                      controller: _stickerSearchController,
                                      onChanged: _onStickerSearchChanged,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: 'Поиск стикеров...',
                                        hintStyle: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 14,
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.search,
                                          color: Colors.grey,
                                          size: 20,
                                        ),
                                        suffixIcon:
                                            _stickerSearchController
                                                .text
                                                .isNotEmpty
                                            ? IconButton(
                                                icon: const Icon(
                                                  Icons.clear,
                                                  color: Colors.grey,
                                                  size: 18,
                                                ),
                                                onPressed: () {
                                                  _stickerSearchController
                                                      .clear();
                                                  _onStickerSearchChanged('');
                                                },
                                              )
                                            : null,
                                        filled: true,
                                        fillColor: const Color(0xFF282828),
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child:
                                        _stickers.isEmpty && _isLoadingStickers
                                        ? const Center(
                                            child: CircularProgressIndicator(
                                              color: Color(0xFF9B5CFF),
                                            ),
                                          )
                                        : _stickers.isEmpty &&
                                              _stickerError.isNotEmpty
                                        ? Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.error_outline,
                                                  color: Colors.grey,
                                                  size: 40,
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  _stickerError,
                                                  style: const TextStyle(
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                TextButton(
                                                  onPressed: () =>
                                                      _loadStickers(
                                                        initial: true,
                                                      ),
                                                  child: const Text(
                                                    'Повторить',
                                                    style: TextStyle(
                                                      color: Color(0xFF1A73E8),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                        : GridView.builder(
                                            controller:
                                                _stickerScrollController,
                                            gridDelegate:
                                                const SliverGridDelegateWithFixedCrossAxisCount(
                                                  crossAxisCount: 4,
                                                  crossAxisSpacing: 8,
                                                  mainAxisSpacing: 8,
                                                ),
                                            padding: const EdgeInsets.all(16),
                                            itemCount:
                                                _stickers.length +
                                                (_isLoadingStickers ? 1 : 0),
                                            itemBuilder: (context, index) {
                                              if (index >= _stickers.length) {
                                                return const Center(
                                                  child:
                                                      CircularProgressIndicator(
                                                        color: Color(
                                                          0xFF1A73E8,
                                                        ),
                                                      ),
                                                );
                                              }
                                              return GestureDetector(
                                                onTap: () => _onStickerSelected(
                                                  _stickers[index],
                                                ),
                                                child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  child: Image.network(
                                                    _stickers[index],
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (_, _, _) =>
                                                        Container(
                                                          color: const Color(
                                                            0xFF282828,
                                                          ),
                                                          child: const Icon(
                                                            Icons.error,
                                                            color: Colors.grey,
                                                          ),
                                                        ),
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton(String title, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF1A73E8) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.grey,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _HighlightGlow extends StatefulWidget {
  final Widget child;
  final bool active;
  final int token;

  const _HighlightGlow({
    required this.child,
    required this.active,
    required this.token,
  });

  @override
  State<_HighlightGlow> createState() => _HighlightGlowState();
}

class _HighlightGlowState extends State<_HighlightGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 55),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    if (widget.active) _controller.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant _HighlightGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active &&
        (oldWidget.token != widget.token || !oldWidget.active)) {
      _controller.forward(from: 0);
    } else if (!widget.active) {
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, child) {
        final t = widget.active ? _opacity.value : 0.0;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Color.lerp(
              Colors.transparent,
              const Color(0xFF1A73E8).withValues(alpha: 0.16),
              t,
            ),
            boxShadow: t > 0
                ? [
                    BoxShadow(
                      color: const Color(
                        0xFF1A73E8,
                      ).withValues(alpha: 0.35 * t),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _DownloadProgressDialog extends StatefulWidget {
  final String url;
  final String localPath;
  final String fileName;
  final void Function(String filePath) onComplete;
  final void Function(String error) onError;

  const _DownloadProgressDialog({
    required this.url,
    required this.localPath,
    required this.fileName,
    required this.onComplete,
    required this.onError,
  });

  @override
  State<_DownloadProgressDialog> createState() =>
      _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  double _progress = 0.0;
  bool _isComplete = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(widget.url));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final contentLength = response.contentLength;
      final file = File(widget.localPath);
      final sink = file.openWrite();
      int bytesReceived = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        bytesReceived += chunk.length;
        if (contentLength != null && contentLength > 0) {
          setState(() {
            _progress = bytesReceived / contentLength;
          });
        } else {
          setState(() {
            _progress =
                double.tryParse(
                  (bytesReceived / 1024 / 1024).toStringAsFixed(1),
                ) ??
                0.0;
          });
        }
      }

      await sink.flush();
      await sink.close();
      client.close();

      if (mounted) {
        setState(() {
          _isComplete = true;
        });
        widget.onComplete(widget.localPath);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
        widget.onError(e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_download, color: Color(0xFF1A73E8), size: 48),
          const SizedBox(height: 16),
          const Text(
            'Скачивание файла',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.fileName,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 20),
          if (_error == null) ...[
            LinearProgressIndicator(
              value: _isComplete ? 1.0 : (_progress > 0 ? _progress : null),
              backgroundColor: Colors.grey[800],
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF1A73E8),
              ),
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 12),
            Text(
              _isComplete
                  ? 'Готово!'
                  : _progress < 1
                  ? '${(_progress * 100).toStringAsFixed(0)}%'
                  : 'Загрузка...',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ] else ...[
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 8),
            Text(
              'Ошибка: $_error',
              style: const TextStyle(color: Colors.red, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
