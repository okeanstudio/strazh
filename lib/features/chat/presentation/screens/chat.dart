import 'dart:convert';
import 'dart:collection';
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
import 'package:strazh/features/chat/presentation/widgets/chat_attachment_picker_sheet.dart';
import 'package:strazh/features/chat/presentation/widgets/forward_chat_picker.dart';
import 'package:strazh/features/chat/data/services/chat_service.dart';
import 'package:strazh/features/bots/data/bot_service.dart';
import 'package:strazh/features/chat/data/services/username_chat_service.dart';
import 'package:strazh/features/gifts/data/services/gift_service.dart';
import 'package:strazh/features/chat/data/services/video_note_service.dart';
import 'package:strazh/features/settings/data/services/reaction_settings_service.dart';
import 'package:strazh/core/config/reactions.dart';
import 'package:strazh/features/chat/data/services/crypto_service.dart';
import 'package:strazh/features/chat/data/services/chat_message_cache.dart';
import 'package:strazh/features/chat/data/services/file_upload_service.dart';
import 'package:strazh/features/chat/data/services/storage_upload_service.dart';
import 'package:strazh/features/chat/presentation/widgets/chat_manage/group_info.dart';
import 'package:strazh/features/profile/presentation/widgets/profile.dart';
import 'package:strazh/features/chat/presentation/widgets/create_poll_dialog.dart';
import 'package:strazh/features/chat/presentation/widgets/media/voice_recorder.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:desktop_drop/desktop_drop.dart';
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
import 'package:photo_manager/photo_manager.dart';

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

enum _DesktopAttachmentAction { pickFile, toggleViewOnce }

class _ChatMessageSearchDialog extends StatefulWidget {
  final List<Message> Function(String) getMatches;
  final bool Function() hasMoreMessages;
  final bool Function() isLoadingMore;
  final Future<void> Function(
    String query,
    VoidCallback refresh,
    bool Function() shouldContinue,
  )
  onLoadMore;
  final Future<void> Function(String messageId) onSelect;

  const _ChatMessageSearchDialog({
    required this.getMatches,
    required this.hasMoreMessages,
    required this.isLoadingMore,
    required this.onLoadMore,
    required this.onSelect,
  });

  @override
  State<_ChatMessageSearchDialog> createState() =>
      _ChatMessageSearchDialogState();
}

class _ChatMessageSearchDialogState extends State<_ChatMessageSearchDialog> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOlderMessages() async {
    final query = _searchController.text.trim();
    if (query.isEmpty || widget.isLoadingMore() || !widget.hasMoreMessages()) {
      return;
    }

    await widget.onLoadMore(query, () {
      if (mounted) setState(() {});
    }, () => mounted);
    if (mounted) setState(() {});
  }

  String _formatDate(DateTime date) {
    final localDate = date.toLocal();
    return '${localDate.day.toString().padLeft(2, '0')}.'
        '${localDate.month.toString().padLeft(2, '0')}.'
        '${localDate.year} '
        '${localDate.hour.toString().padLeft(2, '0')}:'
        '${localDate.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim();
    final matches = widget.getMatches(query);
    final isLoading = widget.isLoadingMore();
    final hasMore = widget.hasMoreMessages();
    final screenSize = MediaQuery.sizeOf(context);

    return Dialog(
      backgroundColor: const Color(0xFF171329),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: SizedBox(
        width: screenSize.width > 560 ? 520 : screenSize.width - 40,
        height: screenSize.height * 0.72,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF9B5CFF), Color(0xFF5B6CFF)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.search, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Поиск по чату',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Найдите нужное сообщение',
                          style: TextStyle(
                            color: Color(0xFFAAA4BD),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: isLoading ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _searchController,
                autofocus: true,
                enabled: !isLoading,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Введите текст сообщения',
                  hintStyle: const TextStyle(color: Color(0xFF89839B)),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Color(0xFFB7AEC9),
                  ),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Очистить',
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(
                            Icons.close,
                            color: Color(0xFFB7AEC9),
                          ),
                        ),
                  filled: true,
                  fillColor: const Color(0xFF211C35),
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(
                      color: Color(0xFF9B5CFF),
                      width: 1.4,
                    ),
                  ),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _loadOlderMessages(),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    query.isEmpty
                        ? 'Введите запрос'
                        : '${matches.length} ${_resultCountWord(matches.length)}',
                    style: const TextStyle(
                      color: Color(0xFFAAA4BD),
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  if (query.isNotEmpty && hasMore)
                    TextButton.icon(
                      onPressed: isLoading ? null : _loadOlderMessages,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFC9A7FF),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: isLoading
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.history, size: 18),
                      label: Text(isLoading ? 'Ищем...' : 'Искать раньше'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: query.isEmpty
                    ? _buildEmptyState(
                        icon: Icons.manage_search,
                        message: 'Ищите по тексту, подписям и названиям файлов',
                      )
                    : matches.isEmpty
                    ? _buildEmptyState(
                        icon: hasMore
                            ? Icons.history
                            : Icons.search_off_outlined,
                        message: hasMore
                            ? 'Здесь пока нет совпадений.\nПоищите в более ранних сообщениях.'
                            : 'Совпадений не найдено',
                      )
                    : ListView.separated(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: matches.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 7),
                        itemBuilder: (context, index) {
                          final message = matches[index];
                          final preview = message.content.trim().isNotEmpty
                              ? message.content.trim()
                              : message.imageCaption ??
                                    message.fileName ??
                                    message.giftCaption ??
                                    'Сообщение';
                          final senderName =
                              message.sender?.name ??
                              message.forwardedFromName ??
                              (message.isMe ? 'Вы' : 'Сообщение');

                          return Material(
                            color: const Color(0xFF211C35),
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: isLoading
                                  ? null
                                  : () {
                                      final navigator = Navigator.of(context);
                                      final selectedId = message.id;
                                      FocusScope.of(context).unfocus();
                                      navigator.pop();
                                      unawaited(widget.onSelect(selectedId));
                                    },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 13,
                                  vertical: 11,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF9B5CFF,
                                        ).withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        message.isImage
                                            ? Icons.image_outlined
                                            : message.isFile
                                            ? Icons.attach_file
                                            : message.isVoice
                                            ? Icons.mic_none
                                            : Icons.chat_bubble_outline,
                                        color: const Color(0xFFC9A7FF),
                                        size: 19,
                                      ),
                                    ),
                                    const SizedBox(width: 11),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            senderName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            preview,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFFB7AEC9),
                                              fontSize: 12,
                                              height: 1.35,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _formatDate(message.createdAt),
                                      style: const TextStyle(
                                        color: Color(0xFF89839B),
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (isLoading) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation(Color(0xFF9B5CFF)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({required IconData icon, required String message}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: const Color(0xFF777087)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFAAA4BD),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _resultCountWord(int count) {
    final remainder = count % 10;
    final lastTwo = count % 100;
    if (remainder == 1 && lastTwo != 11) return 'результат';
    if (remainder >= 2 && remainder <= 4 && (lastTwo < 12 || lastTwo > 14)) {
      return 'результата';
    }
    return 'результатов';
  }
}

class ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  static const int _cachedMessageCount = 15;
  static const int _cachedChatCount = 10;
  static final LinkedHashMap<String, List<Message>> _recentMessageCache =
      LinkedHashMap<String, List<Message>>();

  final TextEditingController _messageController = TextEditingController();
  final ChatService _chatService = ChatService();
  final BotService _botService = BotService();
  final VideoNoteService _videoNoteService = VideoNoteService();
  final CryptoService _cryptoService = CryptoService();
  final FocusNode _focusNode = FocusNode();
  int _participantsCount = 0;

  final WebRTCService _webrtc = WebRTCService();
  final String _signalingServerUrl = 'http://81.19.136.44:3000';

  Message? _replyingTo;
  String? _botFatherWizardStep;
  String? _botFatherNewBotName;
  String? _botFatherSelectedBotId;
  Message? _editingMessage;
  bool _isEditingCaption = false;
  bool _isSavingEdit = false;
  bool _showSendAfterEdit = false;
  String? _highlightedMessageId;
  bool _centerOldestMessage = false;
  bool _centerNewestMessage = false;
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
  bool _videoNoteViewOnce = false;
  final Set<String> _openingViewOnceMessageIds = {};
  bool _sendViewOnce = false;
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
  RealtimeChannel? _activityChannel;
  final Map<String, ({String name, String state, DateTime updatedAt})>
  _remoteActivities = {};
  Timer? _localActivityHeartbeat;
  Timer? _activityExpiryTimer;
  String? _localActivity;
  DateTime? _lastActivitySentAt;
  Timer? _pollingTimer;
  bool _isPolling = false;
  Timer? _statusPollingTimer;
  Timer? _replyHighlightTimer;
  Timer? _readReceiptTimer;
  bool _isMarkingReadReceipts = false;
  final Set<String> _markedAsReadMessageIds = {};
  final Set<String> _shownBotCallbackAnswers = {};

  final AudioPlayer _soundPlayer = AudioPlayer();

  bool _isSearchingForMessage = false;
  bool _isNavigatingToMessage = false;
  String? _navigationTargetMessageId;
  bool _isSearchingChatHistory = false;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  DateTime? _oldestMessageDate;
  DateTime? _latestObservedMessageAt;
  DateTime? _lastFloatingDateUpdateAt;
  bool _isRefreshingInitialMessages = false;
  int _chatLoadGeneration = 0;
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
      _onMessageTextChanged(_messageController.text);
      setState(() {});
    });
    _focusNode.addListener(() {
      _onMessageTextChanged(_messageController.text);
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
        await _restoreCachedMessages(widget.chat.id);
        if (!mounted) return;
        await _initializeChat();
        if (widget.chat.type == 'channel') await _loadChannelPermission();
      }
    });
  }

  String _messageCacheKey(String roomId) => '${widget.currentUser.id}:$roomId';

  Future<void> _restoreCachedMessages(String roomId) async {
    final key = _messageCacheKey(roomId);
    List<Message> cachedMessages;
    try {
      cachedMessages =
          _recentMessageCache.remove(key) ??
          await ChatMessageCache.instance.loadMessages(
            userId: widget.currentUser.id,
            roomId: roomId,
          );
    } catch (error) {
      debugPrint('Не удалось восстановить кэш сообщений: $error');
      return;
    }
    if (!mounted || widget.chat.id != roomId) return;
    if (cachedMessages.isEmpty) return;

    final sortedMessages = List<Message>.from(cachedMessages)
      ..sort((first, second) => first.createdAt.compareTo(second.createdAt));
    _recentMessageCache[key] = sortedMessages.length > _cachedMessageCount
        ? sortedMessages.sublist(sortedMessages.length - _cachedMessageCount)
        : sortedMessages;
    setState(() {
      _messages = sortedMessages;
      _isLoading = false;
      _isInitialLoadComplete = true;
      _isRefreshingInitialMessages = true;
      _hasMoreMessages = true;
      _oldestMessageDate = sortedMessages.first.createdAt;
      _latestObservedMessageAt = sortedMessages.last.createdAt;
    });
  }

  void _cacheCurrentMessages({String? roomId}) {
    final persistentMessages =
        _messages
            .where(
              (message) =>
                  !_pendingUploads.containsKey(message.id) &&
                  !message.id.startsWith('temp_'),
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final key = _messageCacheKey(roomId ?? widget.chat.id);
    unawaited(
      ChatMessageCache.instance
          .saveMessages(
            userId: widget.currentUser.id,
            roomId: roomId ?? widget.chat.id,
            messages: persistentMessages,
          )
          .catchError((Object error, StackTrace stackTrace) {
            debugPrint('Не удалось сохранить кэш сообщений: $error');
          }),
    );
    _recentMessageCache.remove(key);
    if (persistentMessages.isEmpty) return;

    _recentMessageCache[key] = persistentMessages.length > _cachedMessageCount
        ? persistentMessages.sublist(
            persistentMessages.length - _cachedMessageCount,
          )
        : persistentMessages;

    while (_recentMessageCache.length > _cachedChatCount) {
      _recentMessageCache.remove(_recentMessageCache.keys.first);
    }
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

    _cacheCurrentMessages(roomId: oldWidget.chat.id);
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
    _latestObservedMessageAt = null;
    _isRefreshingInitialMessages = false;
    _chatLoadGeneration++;
    _isInitialLoadComplete = false;
    final newRoomId = widget.chat.id;
    unawaited(() async {
      await _restoreCachedMessages(newRoomId);
      if (mounted && widget.chat.id == newRoomId) {
        await _initializeChat();
      }
    }());
  }

  void focusMessageInput() {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      _focusNode.requestFocus();
    }
  }

  Future<void> _startCall({required bool isVideo}) async {
    if (widget.chat.isBot) {
      Toast.info(context, 'Звонки с ботами недоступны');
      return;
    }
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
      if (!widget.chat.isBot) {
        await _syncChatKeysForCurrentDevice();
        try {
          await _cryptoService.ensureCurrentDevice();
        } catch (error) {
          debugPrint(
            'Не удалось зарегистрировать ключ этого устройства: $error',
          );
          if (mounted) {
            Toast.error(
              context,
              'Не удалось подготовить сквозное шифрование. '
              'Проверьте подключение и обновление сервера.',
            );
          }
        }
      }
      await _checkBlockStatus();
      await _subscribeToOtherUserStatus();
      await _loadPinnedMessages();
      await _loadMessages(loadMore: false);
      _loadParticipantsCount();
      _subscribeToRealtime();
      _subscribeToActivity();
    } catch (e) {
      if (mounted) {
        Toast.error(context, 'Ошибка инициализации: $e');
      }
    }
  }

  Future<void> _syncChatKeysForCurrentDevice() async {
    Object? recoveryError;
    try {
      await _cryptoService.syncKeyVaultWithServerEscrow();
    } catch (error) {
      debugPrint('Не удалось восстановить серверную копию E2EE: $error');
      recoveryError = error;
    }
    try {
      if (await _cryptoService.isKeyVaultUnlocked()) {
        await _cryptoService.syncKeyVaultWithStoredKey();
      }
    } catch (error) {
      debugPrint('Не удалось обновить резервную копию E2EE: $error');
      recoveryError ??= error;
    }
    if (recoveryError != null && mounted) {
      Toast.warning(
        context,
        'Не удалось восстановить ключи чата. Проверьте, что миграции '
        'E2EE применены на сервере.',
      );
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
      _cacheCurrentMessages();

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
      _cacheCurrentMessages();

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
    return !_sameCalendarDay(
      messagesList[index].createdAt,
      messagesList[index + 1].createdAt,
    );
  }

  bool _sameCalendarDay(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  List<Message> _matchingMessages(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return const [];

    final matches = _messages.where((message) {
      if (message.isDeleted) return false;
      final searchableText = [
        message.content,
        message.imageCaption,
        message.giftName,
        message.giftCaption,
        message.fileName,
        message.replyToContent,
        ...message.pollOptions,
      ].whereType<String>().join('\n').toLowerCase();
      return searchableText.contains(normalizedQuery);
    }).toList();
    matches.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return matches;
  }

  Future<void> _searchOlderMessages(
    String query,
    VoidCallback refreshDialog,
    bool Function() shouldContinue,
  ) async {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty ||
        _isSearchingChatHistory ||
        !_hasMoreMessages) {
      return;
    }

    final existingMatches = _matchingMessages(
      normalizedQuery,
    ).map((message) => message.id).toSet();
    setState(() => _isSearchingChatHistory = true);
    try {
      while (mounted && shouldContinue() && _hasMoreMessages) {
        final previousOldestMessageDate = _oldestMessageDate;
        await _loadMessages(loadMore: true);
        if (!mounted) return;
        refreshDialog();

        final hasNewMatch = _matchingMessages(
          normalizedQuery,
        ).any((message) => !existingMatches.contains(message.id));
        if (hasNewMatch ||
            !_hasMoreMessages ||
            _oldestMessageDate == previousOldestMessageDate) {
          break;
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isSearchingChatHistory = false);
        refreshDialog();
      }
    }
  }

  Future<void> _showMessageSearch() => showDialog<void>(
    context: context,
    builder: (_) => _ChatMessageSearchDialog(
      getMatches: _matchingMessages,
      hasMoreMessages: () => _hasMoreMessages,
      isLoadingMore: () => _isSearchingChatHistory,
      onLoadMore: (query, refresh, shouldContinue) =>
          _searchOlderMessages(query, refresh, shouldContinue),
      onSelect: (messageId) async {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (mounted) await _scrollToMessageWithCenter(messageId);
      },
    ),
  );

  Future<void> _scrollToMessageWithCenter(
    String messageId, {
    bool highlight = true,
  }) async {
    if (_isNavigatingToMessage) return;
    setState(() {
      _isNavigatingToMessage = true;
      _navigationTargetMessageId = messageId;
    });
    try {
      await _scrollToMessageWithCenterInternal(messageId, highlight: highlight);
    } finally {
      if (mounted) {
        setState(() {
          _isNavigatingToMessage = false;
          _navigationTargetMessageId = null;
        });
      }
    }
  }

  Future<void> _scrollToMessageWithCenterInternal(
    String messageId, {
    required bool highlight,
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

    setState(() {
      _centerOldestMessage = messageIndex == 0 && !_hasMoreMessages;
      _centerNewestMessage = messageIndex == _messages.length - 1;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scrollController.hasClients) return;

    final targetDisplayIndex = _messages.length - 1 - messageIndex;
    for (var attempt = 0; attempt < 12; attempt++) {
      if (!mounted || !_scrollController.hasClients) return;
      await WidgetsBinding.instance.endOfFrame;

      final targetContext = _messageKeys[messageId]?.currentContext;
      if (targetContext != null) {
        final targetRender = targetContext.findRenderObject();
        if (targetRender is RenderBox && targetRender.attached) {
          final scrollable = Scrollable.of(targetContext);
          final viewportRender = scrollable.position.context.storageContext
              .findRenderObject();
          if (viewportRender is RenderBox) {
            final targetTop = targetRender.localToGlobal(
              Offset.zero,
              ancestor: viewportRender,
            );
            final targetCenter = targetTop.dy + targetRender.size.height / 2;
            final delta =
                targetCenter - scrollable.position.viewportDimension / 2;
            if (delta.abs() <= 2) break;

            final isReversed = scrollable.axisDirection == AxisDirection.up;
            final requestedOffset =
                scrollable.position.pixels + (isReversed ? -delta : delta);
            final targetOffset = requestedOffset.clamp(
              0.0,
              scrollable.position.maxScrollExtent,
            );
            if ((targetOffset - scrollable.position.pixels).abs() <= 1) {
              break;
            }
            await scrollable.position.animateTo(
              targetOffset,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
            );
            continue;
          }
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

    if (!await _alignMessageToCenter(messageId)) {
      Toast.info(context, 'Не удалось показать сообщение');
      return;
    }

    if (highlight) _highlightMessage(messageId);
  }

  Future<bool> _alignMessageToCenter(String messageId) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scrollController.hasClients) return false;

      final targetContext = _messageKeys[messageId]?.currentContext;
      final targetRender = targetContext?.findRenderObject();
      if (targetContext == null ||
          targetRender is! RenderBox ||
          !targetRender.attached) {
        continue;
      }

      final scrollable = Scrollable.of(targetContext);
      final viewportRender = scrollable.position.context.storageContext
          .findRenderObject();
      if (viewportRender is! RenderBox) continue;

      final targetTop = targetRender.localToGlobal(
        Offset.zero,
        ancestor: viewportRender,
      );
      final targetCenter = targetTop.dy + targetRender.size.height / 2;
      final delta = targetCenter - scrollable.position.viewportDimension / 2;
      if (delta.abs() <= 2) return true;

      final reversed = scrollable.axisDirection == AxisDirection.up;
      final desiredOffset =
          scrollable.position.pixels + (reversed ? -delta : delta);
      final targetOffset = desiredOffset.clamp(
        0.0,
        scrollable.position.maxScrollExtent,
      );
      if ((targetOffset - scrollable.position.pixels).abs() <= 1) {
        return true;
      }

      await scrollable.position.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }

    return mounted && _scrollController.hasClients;
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

    if (!_isNavigatingToMessage &&
        position.pixels >= position.maxScrollExtent - 200) {
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
      _cacheCurrentMessages();
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
      if (changed) _cacheCurrentMessages();
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
    if (kIsWeb && fromScroll) {
      final now = DateTime.now();
      final lastUpdate = _lastFloatingDateUpdateAt;
      if (lastUpdate != null &&
          now.difference(lastUpdate) < const Duration(milliseconds: 100)) {
        return;
      }
      _lastFloatingDateUpdateAt = now;
    }

    if (!_scrollController.hasClients || _messages.isEmpty) {
      _floatingDateHideTimer?.cancel();
      if (_showFloatingDate) {
        setState(() => _showFloatingDate = false);
      }
      return;
    }

    final viewportHeight = _scrollController.position.viewportDimension;
    final centerY = viewportHeight / 2;
    final scrollableRender = _scrollController.position.context.storageContext
        .findRenderObject();
    if (scrollableRender is! RenderBox) return;

    Message? centerMsg;
    double bestDistance = double.infinity;

    for (final msg in _messages) {
      final key = _messageKeys[msg.id];
      final ctx = key?.currentContext;
      if (ctx == null) continue;

      final render = ctx.findRenderObject();
      if (render is! RenderBox) continue;
      if (!render.attached) continue;

      final top = render
          .localToGlobal(Offset.zero, ancestor: scrollableRender)
          .dy;
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

    final chronologicalIndex = _messages.indexOf(centerMsg);
    if (chronologicalIndex == -1) return;
    final msgDate = _formatMessageDate(centerMsg.createdAt);
    final isHeaderVisible =
        chronologicalIndex == 0 ||
        !_sameCalendarDay(
          centerMsg.createdAt,
          _messages[chronologicalIndex - 1].createdAt,
        );

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
        Toast.success(context, 'Видео сохранено в галерею');
      } else {
        Toast.error(
          context,
          'Не удалось сохранить видео: ${result.errorMessage ?? 'неизвестная ошибка'}',
        );
      }
    } catch (error) {
      debugPrint('Ошибка сохранения видео в галерею: $error');
      if (mounted) {
        Toast.error(context, 'Не удалось сохранить видео в галерею');
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
      if (widget.chat.isBot) {
        final bot = await _loadDirectChatBot();
        if (bot != null) {
          _otherUserId = bot['id']?.toString();
          _otherUserName = bot['name']?.toString();
          _otherUserTag = bot['tag']?.toString();
          _otherUserAvatar = bot['avatar_url']?.toString();
          _otherUserStatus = 'bot';
        }
        if (mounted) setState(() => _isBlocked = false);
        return;
      }

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

  Future<Map<String, dynamic>?> _loadDirectChatBot() async {
    final participant = await Supabase.instance.client
        .from('bot_chat_participants')
        .select('bot_id')
        .eq('room_id', widget.chat.id)
        .maybeSingle();
    final botId = participant?['bot_id']?.toString();
    if (botId == null) return null;

    final bot = await Supabase.instance.client
        .from('bots')
        .select('id, name, tag, description, avatar_url, is_verified')
        .eq('id', botId)
        .maybeSingle();
    return bot;
  }

  Future<void> _subscribeToOtherUserStatus() async {
    if (widget.chat.type != 'direct' || widget.chat.isBot) return;
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
    if (widget.chat.isBot) return;
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
    _cacheCurrentMessages();
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
                _cacheCurrentMessages();
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
    _cacheCurrentMessages();
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
    _cacheCurrentMessages();

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
    if (widget.chat.isBot) {
      unawaited(_showBotProfile());
      return;
    }

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

    unawaited(_showChatHeaderAction());
  }

  Future<void> _showChatHeaderAction() async {
    if (widget.chat.type != 'direct') {
      _showChatInfo();
      return;
    }

    if (widget.chat.isBot) {
      await _showBotProfile();
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

    showUserProfile(
      context,
      user: app.User(
        id: userId,
        name: widget.chat.name,
        tag: _otherUserTag ?? '',
        avatarUrl: _otherUserAvatar,
        status: _otherUserStatus,
        badge: _otherUserBadge,
      ),
      onAudioCall: () => _startCall(isVideo: false),
      onVideoCall: () => _startCall(isVideo: true),
      onUsernameTap: _openUsernameChat,
    );
  }

  Future<void> _showBotProfile() async {
    try {
      final bot = await _loadDirectChatBot();
      if (!mounted) return;
      if (bot == null) {
        Toast.error(context, 'Не удалось загрузить информацию о боте');
        return;
      }

      showUserProfile(
        context,
        user: app.User(
          id: bot['id'].toString(),
          name: bot['name']?.toString() ?? widget.chat.name,
          tag: bot['tag']?.toString() ?? '',
          bio: bot['description']?.toString(),
          avatarUrl: bot['avatar_url']?.toString(),
          isBot: true,
          botVerified: bot['is_verified'] == true,
        ),
        onUsernameTap: _openUsernameChat,
      );
    } catch (error) {
      if (mounted) {
        Toast.error(context, 'Не удалось загрузить информацию о боте: $error');
      }
    }
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

  Future<void> _loadMessages({bool loadMore = false}) async {
    if (loadMore && _isRefreshingInitialMessages) return;

    final loadGeneration = _chatLoadGeneration;
    final roomId = widget.chat.id;
    final messageIdsAtRequestStart = loadMore
        ? const <String>{}
        : _messages.map((message) => message.id).toSet();

    if (loadMore) {
      if (_isLoadingMore || !_hasMoreMessages) return;
      setState(() {
        _isLoadingMore = true;
      });
    } else {
      _isRefreshingInitialMessages = true;
      setState(() {
        if (!_isInitialLoadComplete) _isLoading = true;
        _hasMoreMessages = true;
        _oldestMessageDate = null;
      });
    }

    try {
      final messages = await _chatService.getMessagesPaginated(
        roomId,
        limit: _messagesPageSize,
        before: loadMore ? _oldestMessageDate : null,
        currentUser: widget.currentUser,
        cryptoService: _cryptoService,
      );

      if (!mounted || loadGeneration != _chatLoadGeneration) return;

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
      if (!mounted || loadGeneration != _chatLoadGeneration) return;

      setState(() {
        final existingIds = <String>{};
        final pendingMessages = _messages
            .where((message) => _pendingUploads.containsKey(message.id))
            .toList();
        final cachedMessages = _messages
            .where(
              (message) =>
                  messageIdsAtRequestStart.contains(message.id) &&
                  !_pendingUploads.containsKey(message.id),
            )
            .toList();
        final messagesReceivedWhileLoading = loadMore
            ? <Message>[]
            : _messages
                  .where(
                    (message) =>
                        !messageIdsAtRequestStart.contains(message.id) &&
                        !_pendingUploads.containsKey(message.id),
                  )
                  .toList();
        final combinedMessages = loadMore
            ? [...orderedPage, ..._messages]
            : [
                ...messagesReceivedWhileLoading,
                ...orderedPage,
                ...cachedMessages,
                ...pendingMessages,
              ];
        _messages = combinedMessages
            .where((message) => existingIds.add(message.id))
            .toList();
        _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

        _isLoading = false;
        _isLoadingMore = false;
        if (!loadMore) _isRefreshingInitialMessages = false;
        _isInitialLoadComplete = true;

        if (loadedMessages.isNotEmpty) {
          _oldestMessageDate = loadedMessages.first.createdAt;
          _hasMoreMessages = loadedMessages.length >= _messagesPageSize;
        } else {
          _hasMoreMessages = false;
        }
      });
      _cacheCurrentMessages();

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
      if (!mounted || loadGeneration != _chatLoadGeneration) return;
      if (mounted) {
        Toast.error(context, 'Ошибка загрузки сообщений');
      }
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        if (!loadMore) _isRefreshingInitialMessages = false;
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
              final botId = payload.newRecord['bot_id'];
              final isMe = botId == null && senderId == widget.currentUser.id;
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

              if (payload.newRecord['bot_plaintext'] == true) {
                decryptedContent =
                    payload.newRecord['encrypted_content']?.toString() ?? '';
              } else if (isGift) {
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
              if (botId != null) {
                final isBotFather = botId == BotService.botFatherId;
                var botAvatarUrl = payload.newRecord['sender_avatar']
                    ?.toString();
                if (!isBotFather && botAvatarUrl == null) {
                  if (widget.chat.isBot && botId == widget.chat.id) {
                    botAvatarUrl = widget.chat.avatarUrl;
                  } else {
                    try {
                      final botRecord = await Supabase.instance.client
                          .from('bots')
                          .select('avatar_url')
                          .eq('id', botId)
                          .maybeSingle();
                      botAvatarUrl = botRecord?['avatar_url']?.toString();
                    } catch (error) {
                      debugPrint('Не удалось загрузить аватар бота: $error');
                    }
                  }
                }
                sender = app.User(
                  id: botId,
                  name: isBotFather
                      ? 'BotFather'
                      : payload.newRecord['sender_name'] ?? 'Бот',
                  tag: isBotFather
                      ? 'BotFather'
                      : payload.newRecord['sender_tag'] ?? '',
                  avatarUrl: botAvatarUrl,
                  isBot: true,
                  botVerified: isBotFather || widget.chat.botVerified,
                );
              } else if (payload.newRecord['sender_is_channel'] == true) {
                sender = app.User(
                  id: senderId,
                  name: payload.newRecord['sender_name'] ?? widget.chat.name,
                  tag: payload.newRecord['sender_tag'] ?? '',
                  avatarUrl:
                      payload.newRecord['sender_avatar'] ??
                      widget.chat.avatarUrl,
                );
              } else if (isMe) {
                sender = widget.currentUser;
              } else {
                sender = app.User(
                  id: senderId,
                  name: payload.newRecord['sender_name'] ?? 'Пользователь',
                  tag: payload.newRecord['sender_tag'] ?? '',
                  avatarUrl: payload.newRecord['sender_avatar'],
                  isBot: widget.chat.isBot,
                  botVerified: widget.chat.botVerified,
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
                senderId: botId ?? senderId,
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
                botInlineKeyboard: Message.parseBotInlineKeyboard(
                  payload.newRecord['bot_inline_keyboard'],
                ),
                isPinned: isPinned,
                readByOthers: widget.chat.type == 'saved' && isMe,
              );

              setState(() {
                if (!_messages.any((m) => m.id == newMessage.id)) {
                  _messages.add(newMessage);
                }
              });
              _cacheCurrentMessages();
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
                  if (payload.newRecord['bot_plaintext'] == true) {
                    updatedContent =
                        payload.newRecord['encrypted_content']?.toString() ??
                        '';
                  } else {
                    try {
                      if (existingMessage.isImage &&
                          payload.newRecord['image_caption'] != null) {
                        updatedCaption = await _cryptoService.decodeRoomContent(
                          roomId: widget.chat.id,
                          senderId: payload.newRecord['profile_id'] as String,
                          content: payload.newRecord['image_caption']
                              .toString(),
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
                }

                if (!mounted) return;
                setState(() {
                  _messages[index] = existingMessage.copyWith(
                    content: updatedContent,
                    imageCaption: updatedCaption,
                    isEdited: payload.newRecord['is_edited'] == true,
                    isPinned: updatedIsPinned,
                    botInlineKeyboard: Message.parseBotInlineKeyboard(
                      payload.newRecord['bot_inline_keyboard'],
                    ),
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
                _cacheCurrentMessages();
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
              _cacheCurrentMessages();
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
              _cacheCurrentMessages();
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
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'bot_updates',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'chat_id',
              value: widget.chat.id,
            ),
            callback: (payload) {
              _showBotCallbackAnswer(payload.newRecord);
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

  bool get _supportsActivity =>
      !widget.chat.isBot &&
      (widget.chat.type == 'direct' || widget.chat.type == 'group');

  void _subscribeToActivity() {
    if (!_supportsActivity ||
        Supabase.instance.client.auth.currentSession == null) {
      return;
    }

    _activityChannel = Supabase.instance.client
        .channel(
          'typing:${widget.chat.id}',
          opts: const RealtimeChannelConfig(private: true),
        )
        .onBroadcast(event: 'activity', callback: _handleActivityBroadcast)
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            debugPrint('Chat activity Realtime error: $status ($error)');
          }
        });

    _activityExpiryTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final cutoff = DateTime.now().subtract(const Duration(seconds: 6));
      final expired = _remoteActivities.keys
          .where(
            (userId) => _remoteActivities[userId]!.updatedAt.isBefore(cutoff),
          )
          .toList();
      if (expired.isNotEmpty && mounted) {
        setState(() {
          for (final userId in expired) {
            _remoteActivities.remove(userId);
          }
        });
      }
    });
  }

  void _handleActivityBroadcast(Map<String, dynamic> payload) {
    final userId = payload['user_id']?.toString();
    final state = payload['state']?.toString();
    if (!mounted ||
        userId == null ||
        userId.isEmpty ||
        userId == widget.currentUser.id ||
        (state != 'typing' && state != 'recording' && state != 'idle')) {
      return;
    }
    final String activityState = state!;

    setState(() {
      if (activityState == 'idle') {
        _remoteActivities.remove(userId);
      } else {
        final name = payload['name']?.toString().trim() ?? '';
        _remoteActivities[userId] = (
          name: name.isEmpty ? 'Участник' : name,
          state: activityState,
          updatedAt: DateTime.now(),
        );
      }
    });
  }

  void _onMessageTextChanged(String value) {
    if (!_supportsActivity) return;
    final isTyping = value.trim().isNotEmpty && _focusNode.hasFocus;
    if (!isTyping) {
      _setLocalActivity(null);
      return;
    }

    final lastSent = _lastActivitySentAt;
    if (_localActivity != 'typing' ||
        lastSent == null ||
        DateTime.now().difference(lastSent) >= const Duration(seconds: 2)) {
      _setLocalActivity('typing');
    }
  }

  void _setLocalActivity(String? state) {
    if (!_supportsActivity || state == _localActivity) return;

    _localActivityHeartbeat?.cancel();
    _localActivity = state;
    if (state == null) {
      _sendActivity('idle');
      return;
    }

    _sendActivity(state);
    _localActivityHeartbeat = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _sendActivity(state),
    );
  }

  void _sendActivity(String state) {
    final channel = _activityChannel;
    if (channel == null) return;
    _lastActivitySentAt = DateTime.now();
    unawaited(
      channel
          .sendBroadcastMessage(
            event: 'activity',
            payload: {
              'user_id': widget.currentUser.id,
              'name': widget.currentUser.name,
              'state': state,
            },
          )
          .then((response) {
            if (response != ChannelResponse.ok) {
              debugPrint('Не удалось отправить статус активности: $response');
            }
          })
          .catchError((Object error) {
            debugPrint('Ошибка отправки статуса активности: $error');
          }),
    );
  }

  String? get _remoteActivityLabel {
    if (_remoteActivities.isEmpty) return null;
    final activities = _remoteActivities.values.toList();
    final recording = activities
        .where((activity) => activity.state == 'recording')
        .toList();
    final active = recording.isNotEmpty ? recording : activities;
    final names = active.map((activity) => activity.name).toList();

    if (names.length > 1) {
      return recording.isNotEmpty
          ? '${names.length} участника записывают голосовое...'
          : '${names.length} участника печатают...';
    }
    return recording.isNotEmpty
        ? '${names.first} записывает голосовое...'
        : '${names.first} печатает...';
  }

  void _showBotCallbackAnswer(Map<String, dynamic> record) {
    if (!mounted ||
        record['update_type'] != 'callback_query' ||
        record['actor_id'] != widget.currentUser.id) {
      return;
    }

    final text = record['callback_answer_text']?.toString().trim() ?? '';
    if (text.isEmpty) return;

    final updateId = record['id']?.toString();
    if (updateId == null || !_shownBotCallbackAnswers.add(updateId)) return;
    if (_shownBotCallbackAnswers.length > 500) {
      _shownBotCallbackAnswers.clear();
      _shownBotCallbackAnswers.add(updateId);
    }

    if (record['callback_answer_show_alert'] == true) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Бот'),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ОК'),
            ),
          ],
        ),
      );
    } else {
      Toast.info(context, text);
    }
  }

  void _startPolling() {
    _stopPolling();
    final pollInterval = kIsWeb
        ? const Duration(seconds: 10)
        : const Duration(seconds: 2);
    _pollingTimer = Timer.periodic(pollInterval, (timer) async {
      if (!mounted || _isPolling) {
        if (!mounted) timer.cancel();
        return;
      }

      _isPolling = true;
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
            _cacheCurrentMessages();

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
              _cacheCurrentMessages();
            }
          }
        }

        await _refreshAllMessageReactions();
      } catch (error) {
        debugPrint('Ошибка резервного обновления чата: $error');
      } finally {
        _isPolling = false;
      }
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
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (message.isImage)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
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

  Future<void> _openDesktopFilePicker() async {
    final files = await FileUploadService.pickFiles();
    if (files.isEmpty || !mounted) return;
    await _sendDroppedFiles(files);
  }

  Future<void> _sendDroppedFiles(List<XFile> files) async {
    for (final file in files) {
      await _sendFile(selectedFile: file);
    }
  }

  Future<void> _sendFile({XFile? selectedFile}) async {
    String? pendingMessageId;
    try {
      final file = selectedFile ?? await FileUploadService.pickFile();
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
        fileMimeType: FileUploadService.getMimeType(fileName),
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
        fileMimeType: FileUploadService.getMimeType(fileName),
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

  Future<void> _sendMusic() async {
    String? pendingMessageId;
    try {
      final file = await FileUploadService.pickMusic();
      if (file == null) return;

      final fileName = file.name;
      final reportedFileSize = await file.length();
      if (!await _checkUploadSize(reportedFileSize)) return;
      final bytes = await file.readAsBytes();
      final fileSize = bytes.length;
      if (fileSize != reportedFileSize && !await _checkUploadSize(fileSize)) {
        return;
      }

      final mimeType = FileUploadService.getMimeType(fileName);
      final tempMessage = Message(
        id: 'temp_music_${DateTime.now().millisecondsSinceEpoch}',
        chatId: widget.chat.id,
        senderId: widget.currentUser.id,
        content: 'Музыка: $fileName',
        createdAt: DateTime.now(),
        isMe: true,
        sender: widget.currentUser,
        isFile: true,
        fileName: fileName,
        fileSize: fileSize,
        fileMimeType: mimeType,
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
        fileMimeType: mimeType,
      );

      if (mounted) {
        Toast.success(context, 'Музыка отправлена');
        await _loadMessages(loadMore: false);
      }
    } catch (e) {
      if (mounted) {
        Toast.error(context, 'Ошибка отправки музыки: $e');
      }
    } finally {
      if (pendingMessageId != null) {
        _removePendingUpload(pendingMessageId);
      }
    }
  }

  Future<void> _sendPhoto() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickMedia();

    if (image == null) return;

    if (_videoMimeType(image.mimeType, image.name) != null) {
      await _uploadAndSendVideo(image, viewOnce: _sendViewOnce);
    } else if (mounted) {
      _showPhotoCaptionDialog(image, viewOnce: _sendViewOnce);
    }
  }

  String? _videoMimeType(String? mimeType, String fileName) {
    if (mimeType?.toLowerCase().startsWith('video/') == true) {
      return mimeType!.toLowerCase();
    }

    final extension = fileName.split('.').last.toLowerCase();
    return switch (extension) {
      'mp4' || 'm4v' => 'video/mp4',
      'mov' => 'video/quicktime',
      '3gp' => 'video/3gpp',
      'mkv' => 'video/x-matroska',
      'webm' => 'video/webm',
      'avi' => 'video/x-msvideo',
      _ => null,
    };
  }

  Future<void> _uploadAndSendVideo(XFile video, {bool viewOnce = false}) async {
    String? pendingMessageId;
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        throw StateError('Нет активной Supabase-сессии');
      }

      final mimeType = _videoMimeType(video.mimeType, video.name);
      if (mimeType == null) {
        throw StateError('Не удалось определить формат видео');
      }

      final videoSize = await video.length();
      if (!await _checkUploadSize(videoSize)) return;
      final bytes = await video.readAsBytes();
      if (bytes.length != videoSize && !await _checkUploadSize(bytes.length)) {
        return;
      }

      final extension = video.name.contains('.')
          ? video.name.split('.').last.toLowerCase()
          : 'mp4';
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$extension';
      final filePath = normalizeStoragePath('${widget.chat.id}/$fileName');
      final pendingMessage = Message(
        id: 'temp_video_${DateTime.now().millisecondsSinceEpoch}',
        chatId: widget.chat.id,
        senderId: widget.currentUser.id,
        content: 'Видео',
        createdAt: DateTime.now(),
        isMe: true,
        sender: widget.currentUser,
        isFile: true,
        fileName: fileName,
        fileSize: bytes.length,
        fileMimeType: mimeType,
      );
      pendingMessageId = pendingMessage.id;
      _addPendingUpload(
        pendingMessage,
        label: 'Видео',
        totalBytes: bytes.length,
      );

      await StorageUploadService.uploadBinary(
        bucket: 'chat_files',
        path: filePath,
        bytes: bytes,
        contentType: mimeType,
        onProgress: (uploadedBytes, totalBytes) => _updatePendingUpload(
          pendingMessage.id,
          uploadedBytes: uploadedBytes,
          totalBytes: totalBytes,
        ),
      );

      await _chatService.sendFileMessage(
        widget.chat.id,
        filePath,
        fileName,
        bytes.length,
        fileMimeType: mimeType,
        viewOnce: viewOnce,
      );

      if (mounted) {
        if (viewOnce) setState(() => _sendViewOnce = false);
        Toast.success(context, 'Видео отправлено!');
        await _loadMessages(loadMore: false);
      }
    } catch (error, stackTrace) {
      debugPrint('Ошибка отправки видео: $error\n$stackTrace');
      if (mounted) {
        if (error is UploadLimitException) {
          Toast.error(context, error.message);
        } else {
          Toast.error(context, 'Ошибка отправки видео: $error');
        }
      }
    } finally {
      if (pendingMessageId != null) {
        _removePendingUpload(pendingMessageId);
      }
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
    _videoNoteViewOnce = _sendViewOnce;
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
      await _uploadVideoNote(
        File(recording.path),
        viewOnce: _videoNoteViewOnce,
      );
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

  Future<void> _uploadVideoNote(
    File recordedVideo, {
    bool viewOnce = false,
  }) async {
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
        viewOnce: viewOnce,
      );
      uploadedFilePath = null;

      if (mounted) {
        if (viewOnce) setState(() => _sendViewOnce = false);
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

  void _showPhotoCaptionDialog(XFile image, {bool viewOnce = false}) async {
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
              _uploadAndSendPhoto(
                image,
                captionController.text.trim(),
                viewOnce: viewOnce,
              );
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

  Future<void> _uploadAndSendPhoto(
    XFile image,
    String caption, {
    bool viewOnce = false,
  }) async {
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
        viewOnce: viewOnce,
      );

      if (mounted) {
        if (viewOnce) setState(() => _sendViewOnce = false);
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
      _cacheCurrentMessages();
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
    if (changed && mounted) {
      setState(() => _messages = updated);
      _cacheCurrentMessages();
    }
  }

  bool get _isDesktopAttachmentPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  void _showAttachmentMenu() {
    if (_isDesktopAttachmentPlatform) {
      unawaited(_openDesktopFilePicker());
      return;
    }
    showModalBottomSheet<List<AssetEntity>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ChatAttachmentPickerSheet(
        canToggleViewOnce: !widget.chat.isBot && _editingMessage == null,
        sendViewOnce: _sendViewOnce,
        onViewOnceChanged: (enabled) {
          if (mounted) setState(() => _sendViewOnce = enabled);
        },
        onAction: (action) {
          switch (action) {
            case ChatAttachmentAction.gallery:
              _sendPhoto();
            case ChatAttachmentAction.gift:
              _showGiftPicker();
            case ChatAttachmentAction.file:
              _sendFile();
            case ChatAttachmentAction.music:
              _sendMusic();
            case ChatAttachmentAction.location:
              Toast.info(context, 'Отправка геопозиции пока недоступна');
            case ChatAttachmentAction.poll:
              _showCreatePollDialog();
            case ChatAttachmentAction.videoNote:
              _sendVideoNote();
            case ChatAttachmentAction.stickers:
              _toggleEmojiPicker();
          }
        },
      ),
    ).then((assets) {
      if (assets == null || assets.isEmpty || !mounted) return;
      unawaited(_sendSelectedMedia(assets));
    });
  }

  Future<void> _sendSelectedMedia(List<AssetEntity> assets) async {
    final viewOnce = _sendViewOnce;
    for (final asset in assets) {
      try {
        final file = await asset.file;
        if (file == null) {
          throw StateError('Не удалось получить выбранный файл');
        }
        if (asset.type == AssetType.video) {
          await _uploadAndSendVideo(XFile(file.path), viewOnce: viewOnce);
        } else {
          await _uploadAndSendPhoto(XFile(file.path), '', viewOnce: viewOnce);
        }
      } catch (error) {
        if (mounted) {
          Toast.error(context, 'Не удалось прикрепить медиафайл: $error');
        }
      }
      if (viewOnce && mounted) setState(() => _sendViewOnce = false);
    }
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
      _cacheCurrentMessages();

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
    final viewOnce = _sendViewOnce;
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
        viewOnce: viewOnce,
      );

      if (mounted) {
        if (viewOnce) setState(() => _sendViewOnce = false);
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

  Future<void> _openViewOnceMedia(Message message) async {
    if (!_openingViewOnceMessageIds.add(message.id)) return;
    try {
      final claimed = await _chatService.claimViewOnceMessage(message.id);
      if (!claimed) {
        if (mounted) {
          setState(() {
            _messages = _messages
                .map(
                  (item) => item.id == message.id
                      ? item.copyWith(viewOnceViewed: true)
                      : item,
                )
                .toList();
          });
          Toast.info(context, 'Это сообщение уже просмотрено');
        }
        return;
      }

      final bucket = message.isImage
          ? 'chat_media'
          : message.isVoice
          ? 'voice_messages'
          : message.isVideoNote
          ? 'chat_media'
          : 'chat_files';
      final rawUrl = message.isImage
          ? message.content
          : message.isVoice
          ? message.voiceUrl
          : message.fileUrl;
      final path = storageObjectPath(bucket, rawUrl);
      if (path == null) {
        throw StateError('Не удалось определить путь к одноразовому медиа');
      }
      final signedUrl = await StorageUploadService.createSignedUrl(
        bucket: bucket,
        path: path,
        expiresIn: 60,
      );
      if (!mounted) return;

      setState(() {
        _messages = _messages
            .map(
              (item) => item.id == message.id
                  ? item.copyWith(viewOnceViewed: true)
                  : item,
            )
            .toList();
      });

      if (message.isImage) {
        _showFullScreenImage(signedUrl, caption: message.imageCaption);
      } else {
        await launchUrl(
          Uri.parse(signedUrl),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Не удалось открыть одноразовое медиа: $error\n$stackTrace');
      if (mounted) {
        Toast.error(context, 'Не удалось открыть медиа: $error');
      }
    } finally {
      _openingViewOnceMessageIds.remove(message.id);
    }
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

  Future<void> _sendStartCommand() async {
    if (!widget.chat.isBot) return;
    _messageController.text = '/start';
    await _sendMessage();
  }

  Future<void> _sendBotCallback(Message message, String callbackData) async {
    if (!widget.chat.isBot) return;
    try {
      await Supabase.instance.client.from('bot_updates').insert({
        'bot_id': message.senderId,
        'actor_id': widget.currentUser.id,
        'update_type': 'callback_query',
        'chat_id': widget.chat.id,
        'message_id': message.id,
        'callback_data': callbackData,
        'text': callbackData,
        'payload': {
          'callback_query': {
            'id': message.id,
            'chat_id': widget.chat.id,
            'message_id': message.id,
            'data': callbackData,
            'from': {
              'id': widget.currentUser.id,
              'name': widget.currentUser.name,
              'tag': widget.currentUser.tag,
            },
          },
        },
      });
    } catch (error) {
      if (mounted) {
        Toast.error(context, 'Не удалось отправить callback: $error');
      }
    }
  }

  Future<void> _handleBotFatherMessage(String text) async {
    try {
      final userMessageId = await _chatService.sendMessage(
        widget.chat.id,
        text,
        isBotChat: true,
      );
      if (userMessageId == null) {
        throw StateError('Не удалось сохранить команду BotFather');
      }

      final userMessage = Message(
        id: userMessageId,
        chatId: widget.chat.id,
        senderId: widget.currentUser.id,
        content: text,
        createdAt: DateTime.now(),
        isMe: true,
        sender: widget.currentUser,
      );
      if (mounted && !_messages.any((message) => message.id == userMessageId)) {
        setState(() => _messages.add(userMessage));
      }

      final command = text.trim();
      final lowerCommand = command.toLowerCase();
      final setCommandMatch = RegExp(
        r'^/(setname|setdescription|setusername)(?:@\w+)?(?:\s+@?([a-z0-9_]+))?$',
        caseSensitive: false,
      ).firstMatch(command);
      final revokeCommandMatch = RegExp(
        r'^/revoke(?:@\w+)?(?:\s+@?([a-z0-9_]+))?$',
        caseSensitive: false,
      ).firstMatch(command);
      var response = 'Команда не распознана. Отправьте /help.';

      if (lowerCommand == '/cancel') {
        _botFatherWizardStep = null;
        _botFatherNewBotName = null;
        _botFatherSelectedBotId = null;
        response = 'Создание бота отменено.';
      } else if (_botFatherWizardStep == 'name' &&
          !lowerCommand.startsWith('/')) {
        _botFatherNewBotName = command;
        _botFatherWizardStep = 'username';
        response =
            'Теперь отправьте username бота. Он должен заканчиваться на bot '
            '(например, weather_bot).';
      } else if (_botFatherWizardStep == 'username' &&
          !lowerCommand.startsWith('/')) {
        final tag = command.replaceFirst(RegExp(r'^@+'), '');
        final name = _botFatherNewBotName!;
        final token = _botService.createToken();
        _botFatherWizardStep = null;
        _botFatherNewBotName = null;
        try {
          await _botService.createBot(
            name: name,
            tag: tag,
            description: '',
            avatarUrl: null,
            token: token,
          );
          response =
              'Готово! Бот @$tag создан.\n'
              'Токен: $token\n\n'
              'Его можно снова получить командой /token @$tag.';
        } catch (error) {
          response = 'Не удалось создать бота: $error';
        }
      } else if (_botFatherWizardStep?.startsWith('set_') == true &&
          _botFatherSelectedBotId != null &&
          !lowerCommand.startsWith('/')) {
        final field = _botFatherWizardStep!.substring('set_'.length);
        final botId = _botFatherSelectedBotId!;
        _botFatherWizardStep = null;
        _botFatherSelectedBotId = null;
        try {
          await _botService.updateMyBot(
            botId: botId,
            field: field,
            value: command,
          );
          response = switch (field) {
            'name' => 'Имя бота обновлено.',
            'description' => 'Описание бота обновлено.',
            'tag' => 'Username бота обновлён.',
            _ => 'Настройки бота обновлены.',
          };
        } catch (error) {
          response = 'Не удалось изменить настройку: $error';
        }
      } else if (setCommandMatch != null) {
        final commandName = setCommandMatch.group(1)!.toLowerCase();
        final requestedTag = setCommandMatch.group(2)?.toLowerCase();
        if (requestedTag == null) {
          response = 'Укажите своего бота: /$commandName @username';
        } else {
          final bots = await _botService.getMyBots();
          final bot = bots
              .where(
                (item) => item['tag']?.toString().toLowerCase() == requestedTag,
              )
              .firstOrNull;
          if (bot == null) {
            response = 'Бот @$requestedTag не найден среди ваших ботов.';
          } else {
            _botFatherWizardStep = switch (commandName) {
              'setname' => 'set_name',
              'setdescription' => 'set_description',
              'setusername' => 'set_tag',
              _ => null,
            };
            _botFatherSelectedBotId = bot['id'].toString();
            response = switch (commandName) {
              'setname' => 'Отправьте новое имя для бота @$requestedTag.',
              'setdescription' =>
                'Отправьте новое описание для бота @$requestedTag.',
              'setusername' =>
                'Отправьте новый username для бота @$requestedTag. Он должен заканчиваться на bot.',
              _ => 'Неизвестная настройка.',
            };
          }
        }
      } else if (revokeCommandMatch != null) {
        final requestedTag = revokeCommandMatch.group(1)?.toLowerCase();
        if (requestedTag == null) {
          response = 'Укажите своего бота: /revoke @username';
        } else {
          final bots = await _botService.getMyBots();
          final bot = bots
              .where(
                (item) => item['tag']?.toString().toLowerCase() == requestedTag,
              )
              .firstOrNull;
          if (bot == null) {
            response = 'Бот @$requestedTag не найден среди ваших ботов.';
          } else {
            try {
              final token = await _botService.rotateMyBotToken(
                bot['id'].toString(),
              );
              response =
                  'Старый токен бота @$requestedTag отозван. '
                  'Новый токен:\n$token';
            } catch (error) {
              response = 'Не удалось перевыпустить токен: $error';
            }
          }
        }
      } else if (lowerCommand == '/start' || lowerCommand == '/help') {
        _botFatherWizardStep = null;
        _botFatherNewBotName = null;
        _botFatherSelectedBotId = null;
        response =
            'Я BotFather. Здесь можно создавать ботов и управлять ими.'
            '\n\n/newbot — создать бота\n/mybots — список ваших ботов\n'
            '/token @username — показать токен\n'
            '/revoke @username — отозвать токен и выпустить новый\n'
            '/setname @username — изменить имя\n'
            '/setdescription @username — изменить описание\n'
            '/setusername @username — изменить username\n'
            '/cancel — отменить действие';
      } else if (lowerCommand == '/newbot') {
        _botFatherWizardStep = 'name';
        _botFatherNewBotName = null;
        response = 'Как назвать нового бота?';
      } else if (lowerCommand == '/mybots') {
        final bots = await _botService.getMyBots();
        response = bots.isEmpty
            ? 'У вас пока нет ботов. Создайте первого командой /newbot.'
            : 'Ваши боты:\n${bots.map((bot) => '• ${bot['name']} — @${bot['tag']}').join('\n')}\n\n'
                  'Настройки: /setname @username, /setdescription @username, '
                  '/setusername @username\nТокен: /token @username\n'
                  'Перевыпуск: /revoke @username';
      } else if (lowerCommand.startsWith('/token')) {
        final requestedTag = command
            .replaceFirst(
              RegExp(r'^/token(?:@\w+)?\s*', caseSensitive: false),
              '',
            )
            .replaceFirst(RegExp(r'^@+'), '')
            .trim()
            .toLowerCase();
        if (requestedTag.isEmpty) {
          response = 'Укажите бота: /token @username';
        } else {
          final bots = await _botService.getMyBots();
          final bot = bots
              .where(
                (item) => item['tag']?.toString().toLowerCase() == requestedTag,
              )
              .firstOrNull;
          if (bot == null) {
            response = 'Бот @$requestedTag не найден среди ваших ботов.';
          } else {
            final token = await _botService.getBotToken(bot['id'].toString());
            response = token == null
                ? 'Токен для @$requestedTag недоступен.'
                : 'Токен бота @$requestedTag:\n$token';
          }
        }
      } else if (_botFatherWizardStep == 'username') {
        response = 'Отправьте username бота или /cancel для отмены.';
      }

      final replyId = await _botService.sendBotFatherMessage(
        roomId: widget.chat.id,
        text: response,
      );
      if (replyId == null) {
        throw StateError('BotFather не вернул ID ответа');
      }
      if (mounted) {
        setState(() {
          if (!_messages.any((message) => message.id == replyId)) {
            _messages.add(
              Message(
                id: replyId,
                chatId: widget.chat.id,
                senderId: BotService.botFatherId,
                content: response,
                createdAt: DateTime.now(),
                isMe: false,
                sender: const app.User(
                  id: BotService.botFatherId,
                  name: 'BotFather',
                  tag: 'BotFather',
                  isBot: true,
                  botVerified: true,
                ),
              ),
            );
          }
        });
        _cacheCurrentMessages();
      }
    } catch (error) {
      if (mounted) Toast.error(context, 'Ошибка BotFather: $error');
    }
  }

  Future<void> _sendMessage({String? stickerUrl, String? commandText}) async {
    if (_editingMessage != null && commandText == null) {
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

    final content = commandText ?? _messageController.text.trim();

    if (widget.chat.isBot &&
        widget.chat.name.toLowerCase() == 'botfather' &&
        stickerUrl == null &&
        content.isNotEmpty) {
      if (commandText == null) {
        _messageController.clear();
        _focusNode.unfocus();
      }
      await _handleBotFatherMessage(content);
      return;
    }

    if (stickerUrl != null) {
      _sendSticker(stickerUrl);
      return;
    } else if (content.isEmpty) {
      _cancelReply();
      return;
    } else if (commandText == null) {
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
      replyToId: commandText == null ? _replyingTo?.id : null,
      replyToContent: commandText == null && _replyingTo != null
          ? (_replyingTo!.isImage ? 'Фото' : _replyingTo!.content)
          : null,
      replyToSender: commandText == null
          ? _replyingTo?.sender?.name ?? _replyingTo?.senderId
          : null,
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
      if (_replyingTo != null && commandText == null) {
        serverMessageId = await _chatService.sendReplyMessage(
          widget.chat.id,
          content,
          _replyingTo!.id,
          isBotChat: widget.chat.isBot,
        );
        _cancelReply();
      } else {
        serverMessageId = await _chatService.sendMessage(
          widget.chat.id,
          content,
          isBotChat: widget.chat.isBot,
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
        _cacheCurrentMessages();
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
        _cacheCurrentMessages();
      }
      if (!kIsWeb &&
          (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focusNode.requestFocus();
        });
      }
    }
  }

  Future<void> _scheduleTextMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || widget.chat.isBot || _editingMessage != null) return;
    if (_isBlocked) {
      Toast.warning(
        context,
        'Вы не можете отправлять сообщения этому пользователю',
      );
      return;
    }

    final now = DateTime.now();
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF9B5CFF),
            surface: Color(0xFF211735),
          ),
        ),
        child: child!,
      ),
    );
    if (selectedDate == null || !mounted) return;

    final initialTime = TimeOfDay.fromDateTime(
      selectedDate.year == now.year &&
              selectedDate.month == now.month &&
              selectedDate.day == now.day
          ? now.add(const Duration(minutes: 5))
          : now,
    );
    final selectedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF9B5CFF),
            surface: Color(0xFF211735),
          ),
        ),
        child: child!,
      ),
    );
    if (selectedTime == null || !mounted) return;

    final scheduledFor = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );
    if (scheduledFor.isBefore(
      DateTime.now().add(const Duration(seconds: 30)),
    )) {
      Toast.warning(context, 'Выберите время хотя бы на минуту позже');
      return;
    }

    try {
      await _chatService.scheduleTextMessage(
        widget.chat.id,
        text,
        scheduledFor,
        replyToId: _replyingTo?.id,
        replyToContent: _replyingTo == null
            ? null
            : _replyingTo!.isImage
            ? 'Фото'
            : _replyingTo!.content,
        replyToSender: _replyingTo?.sender?.name ?? _replyingTo?.senderId,
      );
      if (!mounted) return;
      _messageController.clear();
      _cancelReply();
      Toast.success(
        context,
        'Сообщение запланировано на ${selectedTime.format(context)}',
      );
    } catch (error) {
      if (mounted)
        Toast.error(context, 'Не удалось запланировать сообщение: $error');
    }
  }

  Future<void> _showGiftPicker() async {
    if (widget.chat.isBot ||
        widget.chat.type != 'direct' ||
        _otherUserId == null) {
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
    if (widget.chat.isBot || _otherUserId == null) return;

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
    if (widget.chat.isBot || _otherUserId == null) return;

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
    if (widget.chat.isBot) return;
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
        message.sender?.isBot == true ||
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
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      clipBehavior: Clip.antiAlias,
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
    if (state == AppLifecycleState.resumed) {
      _onMessageTextChanged(_messageController.text);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _cacheCurrentMessages();
      _setLocalActivity(null);
    }

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
    _cacheCurrentMessages();
    _videoNoteSession++;
    WidgetsBinding.instance.removeObserver(this);
    _videoNoteTimer?.cancel();
    _floatingDateHideTimer?.cancel();
    _activityExpiryTimer?.cancel();
    _localActivityHeartbeat?.cancel();
    if (_localActivity != null) _sendActivity('idle');
    unawaited(_releaseVideoNoteCamera(discardRecording: true));
    _replyHighlightTimer?.cancel();
    _readReceiptTimer?.cancel();
    _activityChannel?.unsubscribe();
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

  Widget _buildChatSubtitle(String text, {required bool showOnlineDot}) {
    return Row(
      children: [
        if (showOnlineDot) ...[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: _getStatusColor(_otherUserStatus),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
        ],
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFB7AEC9), fontSize: 13),
          ),
        ),
      ],
    );
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
    final displayMessages = _messages.reversed.toList(growable: false);
    final isBotFather =
        widget.chat.isBot && widget.chat.name.toLowerCase() == 'botfather';
    final hasAvatar =
        isBotFather ||
        (widget.chat.avatarUrl != null && widget.chat.avatarUrl!.isNotEmpty);
    final ImageProvider? avatarImage = isBotFather
        ? const AssetImage('assets/icon/bots/botfather_strazh.jpg')
        : hasAvatar
        ? NetworkImage(widget.chat.avatarUrl!)
        : null;
    final reportableSelectedMessage = _reportableSelectedMessage;

    return ColoredBox(
      color: Colors.transparent,
      child: WallpaperBackground(
        wallpaper: _wallpaper,
        child: DropTarget(
          onDragDone: (details) {
            if (!kIsWeb && details.files.isNotEmpty && mounted) {
              unawaited(_sendDroppedFiles(details.files));
            }
          },
          child: Scaffold(
            resizeToAvoidBottomInset: true,
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              toolbarHeight: widget.chat.isBot ? 76 : 64,
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
                        height: widget.chat.isBot ? 66 : 54,
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
                                          image: avatarImage!,
                                        )
                                      : null,
                                  child: CircleAvatar(
                                    radius: 22,
                                    backgroundColor: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    backgroundImage: avatarImage,
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
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
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
                                      if (widget.chat.isBot) ...[
                                        const SizedBox(width: 5),
                                        const Icon(
                                          Icons.smart_toy,
                                          color: Color(0xFFB89AFF),
                                          size: 16,
                                        ),
                                        if (widget.chat.botVerified) ...[
                                          const SizedBox(width: 3),
                                          const Icon(
                                            Icons.verified,
                                            color: Color(0xFF1A73E8),
                                            size: 16,
                                          ),
                                        ],
                                      ],
                                    ],
                                  ),
                                  if (widget.chat.type == 'direct') ...[
                                    if (!widget.chat.isBot)
                                      _buildChatSubtitle(
                                        _remoteActivityLabel ??
                                            _getStatusText(_otherUserStatus),
                                        showOnlineDot:
                                            _remoteActivityLabel == null,
                                      ),
                                    if (widget.chat.isBot)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 1),
                                        child: Row(
                                          children: [
                                            const Expanded(
                                              child: Text(
                                                'Бот · без сквозного шифрования',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: Color(0xFFB7AEC9),
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ),
                                            TextButton.icon(
                                              onPressed: _sendStartCommand,
                                              style: TextButton.styleFrom(
                                                minimumSize: Size.zero,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 2,
                                                    ),
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                backgroundColor: const Color(
                                                  0xFF1A73E8,
                                                ),
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                              ),
                                              icon: const Icon(
                                                Icons.play_arrow,
                                                size: 14,
                                              ),
                                              label: const Text(
                                                'Старт',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
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
                                            _remoteActivityLabel ??
                                                (widget.chat.type == 'channel'
                                                    ? '$_participantsCount ${_subscriberCountWord(_participantsCount)}'
                                                    : '$_participantsCount участников'),
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
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
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
                          color: const Color(
                            0xFF171329,
                          ).withValues(alpha: 0.95),
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
                              case 'search':
                                await _showMessageSearch();
                                break;
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
                                        backgroundColor: const Color(
                                          0xFF2A2A2A,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
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
                                              style: TextStyle(
                                                color: Colors.red,
                                              ),
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
                          icon: const Icon(
                            Icons.more_vert,
                            color: Colors.white,
                          ),
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
                                value: 'search',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.search,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    SizedBox(width: 14),
                                    Text(
                                      'Поиск',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
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
                                        style: const TextStyle(
                                          color: Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            } else if (widget.chat.type == 'direct' &&
                                !widget.chat.isBot) {
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
                      _buildPinnedMessageBanner(),
                      if (_isSearchingForMessage || _isSearchingChatHistory)
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
                                        padding: EdgeInsets.only(
                                          top: _centerOldestMessage
                                              ? constraints.maxHeight / 2
                                              : 8,
                                          bottom: _centerNewestMessage
                                              ? constraints.maxHeight / 2
                                              : 16,
                                        ),
                                        itemCount: displayMessages.length,
                                        itemBuilder: (context, index) {
                                          final msg = displayMessages[index];

                                          final prevMsg = index > 0
                                              ? displayMessages[index - 1]
                                              : null;

                                          final showAvatar =
                                              (prevMsg == null ||
                                              prevMsg.senderId !=
                                                  msg.senderId ||
                                              prevMsg.senderIsChannel !=
                                                  msg.senderIsChannel);

                                          return ChatMessageEntrance(
                                            key: ValueKey(msg.id),
                                            animate:
                                                !_isNavigatingToMessage ||
                                                msg.id !=
                                                    _navigationTargetMessageId,
                                            delay: Duration(
                                              milliseconds: (index * 24)
                                                  .clamp(0, 240)
                                                  .toInt(),
                                            ),
                                            child: Column(
                                              children: [
                                                if (_shouldShowDateHeader(
                                                  index,
                                                  displayMessages,
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
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .white70,
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
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
                                                    key: _messageKeys
                                                        .putIfAbsent(
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
                                                                  sender: msg
                                                                      .sender,
                                                                  channelIsVerified:
                                                                      widget
                                                                          .chat
                                                                          .isVerified,
                                                                  channelAvatarUrl:
                                                                      widget
                                                                          .chat
                                                                          .avatarUrl,
                                                                  onChannelTap:
                                                                      _showChatInfo,
                                                                  isMe:
                                                                      msg.isMe,
                                                                  isGroup:
                                                                      widget.chat.type ==
                                                                          'group' ||
                                                                      widget.chat.type ==
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
                                                                  onOpenViewOnce:
                                                                      _openViewOnceMedia,
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
                                                                  onCommandTap:
                                                                      (
                                                                        command,
                                                                      ) => _sendMessage(
                                                                        commandText:
                                                                            command,
                                                                      ),
                                                                  onBotCallback:
                                                                      _sendBotCallback,
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
                                                                      (
                                                                        message,
                                                                      ) {
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
                                                                      (
                                                                        filePath,
                                                                      ) {
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
                                                                      alpha:
                                                                          0.24,
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
                                                                      height:
                                                                          26,
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
                                                                          color:
                                                                              Colors.white70,
                                                                        ),
                                                                      ),
                                                                      child:
                                                                          _selectedMessageIds.contains(
                                                                            msg.id,
                                                                          )
                                                                          ? const Icon(
                                                                              Icons.check,
                                                                              color: Colors.white,
                                                                              size: 17,
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
                            if (_isLoadingMore && !_isNavigatingToMessage)
                              const Positioned(
                                top: 12,
                                left: 0,
                                right: 0,
                                child: IgnorePointer(
                                  child: Center(
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        color: Color(0xFF9B5CFF),
                                        strokeWidth: 2,
                                      ),
                                    ),
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
                          color: const Color(
                            0xFF9B5CFF,
                          ).withValues(alpha: 0.23),
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
                      child: widget.chat.isBot && _messages.isEmpty
                          ? SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _sendStartCommand,
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('Начать'),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                ),
                              ),
                            )
                          : _isBlocked && widget.chat.type == 'direct'
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
                                    Toast.error(
                                      context,
                                      'Ошибка разблокировки',
                                    );
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
                                            ? Icons
                                                  .notifications_active_outlined
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
                                  child: _isDesktopAttachmentPlatform
                                      ? PopupMenuButton<
                                          _DesktopAttachmentAction
                                        >(
                                          enabled: _editingMessage == null,
                                          tooltip: 'Вложения',
                                          padding: EdgeInsets.zero,
                                          icon: const Icon(
                                            Icons.attach_file,
                                            color: Colors.white,
                                            size: 22,
                                          ),
                                          onSelected: (action) {
                                            switch (action) {
                                              case _DesktopAttachmentAction
                                                  .pickFile:
                                                unawaited(
                                                  _openDesktopFilePicker(),
                                                );
                                              case _DesktopAttachmentAction
                                                  .toggleViewOnce:
                                                final enabled = !_sendViewOnce;
                                                setState(
                                                  () => _sendViewOnce = enabled,
                                                );
                                                Toast.info(
                                                  context,
                                                  enabled
                                                      ? 'Режим «1 просмотр» включён'
                                                      : 'Режим «1 просмотр» выключен',
                                                );
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            const PopupMenuItem(
                                              value: _DesktopAttachmentAction
                                                  .pickFile,
                                              child: Text('Прикрепить файл'),
                                            ),
                                            if (!widget.chat.isBot &&
                                                _editingMessage == null)
                                              PopupMenuItem(
                                                value: _DesktopAttachmentAction
                                                    .toggleViewOnce,
                                                child: Text(
                                                  _sendViewOnce
                                                      ? 'Отключить 1 просмотр'
                                                      : 'Включить 1 просмотр',
                                                ),
                                              ),
                                          ],
                                        )
                                      : IconButton(
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
                                          () =>
                                              _sendAsChannel = !_sendAsChannel,
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
                                        _onMessageTextChanged(value);
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
                                    final hasText = value.text
                                        .trim()
                                        .isNotEmpty;
                                    final isEditing = _editingMessage != null;
                                    final showSend =
                                        hasText ||
                                        isEditing ||
                                        _showSendAfterEdit;

                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        if (showSend)
                                          GestureDetector(
                                            onLongPress:
                                                hasText &&
                                                    !isEditing &&
                                                    !widget.chat.isBot
                                                ? _scheduleTextMessage
                                                : null,
                                            child: Container(
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
                                                    : hasText &&
                                                          !widget.chat.isBot
                                                    ? 'Отправить · удерживайте для отправки позже'
                                                    : 'Отправить',
                                                icon: _isSavingEdit
                                                    ? const SizedBox.square(
                                                        dimension: 20,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                      )
                                                    : Icon(
                                                        isEditing
                                                            ? Icons
                                                                  .check_rounded
                                                            : Icons
                                                                  .send_rounded,
                                                        color: Colors.white,
                                                        size: 22,
                                                      ),
                                                onPressed: _isSavingEdit
                                                    ? null
                                                    : _sendMessage,
                                              ),
                                            ),
                                          )
                                        else
                                          VoiceRecorder(
                                            onSend: _sendVoiceMessage,
                                            onAudioRecordingChanged:
                                                (recording) {
                                                  _setLocalActivity(
                                                    recording
                                                        ? 'recording'
                                                        : null,
                                                  );
                                                },
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
                                          _stickers.isEmpty &&
                                              _isLoadingStickers
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
                                                        color: Color(
                                                          0xFF1A73E8,
                                                        ),
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
                                                  onTap: () =>
                                                      _onStickerSelected(
                                                        _stickers[index],
                                                      ),
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
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
                                                              color:
                                                                  Colors.grey,
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
