import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/shared/domain/models/chat.dart';
import 'package:strazh/shared/domain/models/user.dart' as app;
import 'package:strazh/features/chat/presentation/screens/chat.dart';
import 'package:strazh/features/auth/presentation/screens/login_codes_chat_screen.dart';
import 'package:strazh/features/profile/presentation/screens/profile.dart';
import 'package:strazh/features/settings/presentation/screens/settings.dart';
import 'package:strazh/features/chat/data/services/chat_service.dart';
import 'package:strazh/features/chat/data/services/chat_list_preferences.dart';
import 'package:strazh/features/chat/presentation/widgets/chat_actions_sheet.dart';
import 'package:strazh/core/utils/date_time_utils.dart';
import 'package:strazh/features/auth/data/services/auth_service.dart';
import 'package:strazh/features/chat/data/services/notification_service.dart';
import 'package:strazh/features/chat/presentation/widgets/create_chat/create_group.dart';
import 'package:strazh/features/chat/presentation/widgets/create_chat/create_channel.dart';
import 'package:strazh/features/stories/presentation/screens/stories_screen.dart'
    show StoriesBar;

class HomeDesktopScreen extends StatefulWidget {
  const HomeDesktopScreen({super.key});

  @override
  State<HomeDesktopScreen> createState() => _HomeDesktopScreenState();
}

class _HomeDesktopScreenState extends State<HomeDesktopScreen> {
  final ChatService _chatService = ChatService();
  final AuthService _authService = AuthService();
  List<Chat> _chats = [];
  bool _isLoading = true;
  Chat? _selectedChat;
  app.User? _currentUser;

  bool _showSettings = false;
  bool _showProfile = false;

  RealtimeChannel? _realtimeChannel;
  RealtimeChannel? _notificationChannel;
  Timer? _pollingTimer;
  Timer? _readStatusRefreshTimer;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<Chat> _groupResults = [];
  bool _isSearchingGroups = false;

  String? _lastNotifiedMessageId;
  bool _chatRealtimeReady = false;
  bool _notificationRealtimeReady = false;
  bool _chatRealtimeFailed = false;
  bool _notificationRealtimeFailed = false;
  bool _isRefreshingChats = false;
  ChatListPreferences? _chatListPreferences;
  bool _showArchivedChats = false;
  String? _selectedFolder;

  final GlobalKey<ChatScreenState> _chatScreenKey =
      GlobalKey<ChatScreenState>();

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_onSearchChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestMessageFocus();
    });
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    final query = _searchController.text.trim();
    if (query.length < 2) {
      setState(() => _groupResults = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() => _isSearchingGroups = true);
      try {
        final results = await _chatService.searchGroups(query);
        if (mounted && query == _searchController.text.trim()) {
          setState(() {
            _groupResults = results;
            _isSearchingGroups = false;
          });
        }
      } catch (error) {
        debugPrint('Ошибка поиска групп: $error');
        if (mounted) {
          setState(() {
            _groupResults = [];
            _isSearchingGroups = false;
          });
        }
      }
    });
  }

  Future<void> _joinGroup(Chat group) async {
    try {
      final joinedChat = await _chatService.joinGroup(group.id);
      await _refreshChats();
      if (mounted && joinedChat != null) {
        setState(() {
          _selectedChat = joinedChat;
          _searchController.clear();
          _groupResults.removeWhere((item) => item.id == group.id);
        });
      }
    } catch (error) {
      debugPrint('Ошибка вступления в группу: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось вступить в группу')),
        );
      }
    }
  }

  void _previewChannel(Chat channel) {
    setState(() {
      _selectedChat = channel;
      _searchController.clear();
      _groupResults.removeWhere((item) => item.id == channel.id);
    });
  }

  Future<void> _openCreateGroup() async {
    final groupId = await showDialog<String>(
      context: context,
      builder: (context) => CreateGroupWidget(currentUserId: _currentUser!.id),
    );
    if (!mounted || groupId == null) return;
    await _refreshChats();
    final created = _chats.where((chat) => chat.id == groupId).firstOrNull;
    if (created != null) setState(() => _selectedChat = created);
  }

  Future<void> _openCreateChannel() async {
    final user = _currentUser;
    if (user == null) return;
    final channelId = await showDialog<String>(
      context: context,
      builder: (_) => CreateChannelWidget(currentUserId: user.id),
    );
    if (!mounted || channelId == null) return;
    await _refreshChats();
    final created = _chats.where((chat) => chat.id == channelId).firstOrNull;
    if (created != null) setState(() => _selectedChat = created);
  }

  Future<void> _loadData() async {
    try {
      _currentUser = _authService.getCurrentUserFromMetadata();
      _chatListPreferences = await ChatListPreferences.load(
        _authService.currentUserId,
      );

      final chats = await _chatService.getMyChats();

      if (mounted) {
        setState(() {
          _chats = _sortChatsByPin(chats);
          _isLoading = false;
          if (_visibleChats.isNotEmpty) {
            _selectedChat = _visibleChats.first;
          }
        });

        NotificationService().onChatSelected = _openChatById;
        _subscribeToChatUpdates();
        _subscribeToNotifications();
        _requestMessageFocus();
      }
    } catch (e) {
      debugPrint('Ошибка загрузки данных: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _refreshChats() async {
    if (_isRefreshingChats) return;
    _isRefreshingChats = true;
    try {
      final chats = await _chatService.getMyChats();
      if (mounted) {
        setState(() {
          _chats = _sortChatsByPin(chats);
          if (_selectedChat != null) {
            final refreshedSelection = _chats
                .where((chat) => chat.id == _selectedChat!.id)
                .firstOrNull;
            if (refreshedSelection == null) {
              _selectedChat = _visibleChats.isNotEmpty
                  ? _visibleChats.first
                  : null;
            } else {
              _selectedChat = refreshedSelection;
            }
          }
        });
      }
    } catch (error) {
      debugPrint('Ошибка обновления списка чатов: $error');
    } finally {
      _isRefreshingChats = false;
    }
  }

  void _requestMessageFocus() {
    if (_selectedChat != null && !_showSettings && !_showProfile) {
      _chatScreenKey.currentState?.focusMessageInput();
    }
  }

  void _updateRealtimeFallback(String channel, Object? status, Object? error) {
    final statusText = status.toString().toLowerCase();
    debugPrint(
      'Home desktop Realtime [$channel]: $status${error == null ? '' : ' ($error)'}',
    );
    final isConnected = statusText.contains('subscribed');
    final hasFailed =
        error != null ||
        statusText.contains('error') ||
        statusText.contains('timeout') ||
        statusText.contains('closed');

    if (channel == 'chats') {
      _chatRealtimeReady = isConnected;
      _chatRealtimeFailed = hasFailed;
    } else {
      _notificationRealtimeReady = isConnected;
      _notificationRealtimeFailed = hasFailed;
    }

    if (_chatRealtimeFailed || _notificationRealtimeFailed) {
      _startPolling();
    } else if (_chatRealtimeReady && _notificationRealtimeReady) {
      _stopPolling();
    }
  }

  void _subscribeToNotifications() {
    _notificationChannel?.unsubscribe();

    final userId = _currentUser?.id;
    if (userId == null) return;

    debugPrint('📢 Подписка на уведомления для пользователя $userId');

    _notificationChannel = Supabase.instance.client
        .channel('notifications_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final message = payload.newRecord;
            debugPrint(
              'Home desktop Realtime: новое сообщение для комнаты ${message['room_id']}',
            );
            if (message['profile_id'] != userId) {
              unawaited(
                _refreshChatLastMessage(
                  message['room_id']?.toString(),
                  messageRecord: message,
                ),
              );
            }
            debugPrint('📢 Получено новое сообщение: $message');
            final senderId = message['profile_id'];

            if (senderId == userId) return;

            _handleIncomingMessage(message);
          },
        )
        .subscribe((status, error) {
          debugPrint('📢 Статус подписки: $status');
          if (error != null) {
            debugPrint('📢 Ошибка подписки: $error');
          }
          _updateRealtimeFallback('notifications', status, error);
        });
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  void _startPolling() {
    _pollingTimer?.cancel();

    final userId = _currentUser?.id;
    if (userId == null) return;

    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final response = await Supabase.instance.client
            .from('messages')
            .select('*')
            .order('created_at', ascending: false)
            .limit(1);

        if (response.isNotEmpty) {
          final lastMessage = response.first;
          final messageId = lastMessage['id'] as String;
          final lastMessageTime = parseDateTimeSafely(
            lastMessage['created_at'],
          );
          final now = DateTime.now();

          if (_lastNotifiedMessageId == messageId) return;

          if (now.difference(lastMessageTime).inSeconds < 5) {
            final senderId = lastMessage['profile_id'];
            _lastNotifiedMessageId = messageId;
            if (_chatRealtimeFailed) {
              unawaited(_refreshChats());
            }

            if (senderId == userId) return;

            _handleIncomingMessage(lastMessage);
          }
        }
      } catch (e) {
        debugPrint('Ошибка polling: $e');
      }
    });
  }

  void _handleIncomingMessage(Map<String, dynamic> data) async {
    try {
      final chatId = data['room_id'] as String;
      if (_lastNotifiedMessageId == data['id']) return;
      _lastNotifiedMessageId = data['id'] as String?;

      final chat = _chats.firstWhere(
        (c) => c.id == chatId,
        orElse: () => Chat(id: chatId, name: 'Чат', type: 'direct'),
      );

      await NotificationService().showChatNotification(chat: chat);
    } catch (e) {
      debugPrint('Не удалось показать уведомление о новом сообщении: $e');
    }
  }

  void _openChatById(String chatId) {
    final chat = _chats.firstWhere(
      (c) => c.id == chatId,
      orElse: () => Chat(id: chatId, name: 'Чат', type: 'direct'),
    );

    if (_chats.any((c) => c.id == chatId)) {
      _onChatSelected(chat);
    }
  }

  void _subscribeToChatUpdates() {
    _realtimeChannel?.unsubscribe();

    final userId = _currentUser?.id;
    if (userId == null) return;

    _realtimeChannel = Supabase.instance.client
        .channel('home_chats_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            unawaited(
              _refreshChatLastMessage(
                payload.newRecord['room_id']?.toString(),
                messageRecord: payload.newRecord,
              ),
            );
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            _refreshChats();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            _refreshChats();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'room_participants',
          callback: (payload) {
            if (payload.oldRecord['user_id'] == userId) _refreshChats();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'message_reads',
          callback: (payload) {
            _readStatusRefreshTimer?.cancel();
            _readStatusRefreshTimer = Timer(
              const Duration(milliseconds: 250),
              () => _refreshChats(),
            );
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'phone_login_challenges',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) => _refreshChats(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'phone_login_challenges',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) => _refreshChats(),
        )
        .subscribe(
          (status, error) => _updateRealtimeFallback('chats', status, error),
        );
  }

  Future<void> _refreshChatLastMessage(
    String? roomId, {
    Map<String, dynamic>? messageRecord,
  }) async {
    if (!mounted) return;
    if (roomId == null) {
      await _refreshChats();
      return;
    }

    final currentChat = _chats.where((chat) => chat.id == roomId).firstOrNull;
    if (currentChat == null) {
      await _refreshChats();
      return;
    }

    try {
      final refreshedChat = await _chatService.refreshChatLastMessage(
        currentChat,
        messageRecord: messageRecord,
      );
      if (!mounted) return;
      if (refreshedChat == null) {
        await _refreshChats();
        return;
      }

      final updatedChats = List<Chat>.from(_chats);
      final currentIndex = updatedChats.indexWhere((chat) => chat.id == roomId);
      if (currentIndex == -1) {
        await _refreshChats();
        return;
      }
      updatedChats[currentIndex] = refreshedChat;
      final sortedChats = _sortChatsByPin(updatedChats);
      final selectedChatId = _selectedChat?.id;

      setState(() {
        _chats = sortedChats;
        if (selectedChatId != null) {
          _selectedChat = sortedChats
              .where((chat) => chat.id == selectedChatId)
              .firstOrNull;
        }
      });
    } catch (error) {
      debugPrint('Ошибка быстрого обновления чата: $error');
      await _refreshChats();
    }
  }

  void _onChatSelected(Chat chat) {
    setState(() {
      _selectedChat = chat;
      _showSettings = false;
      _showProfile = false;
    });
    _refreshChats();

    _requestMessageFocus();
  }

  void _openSettings() {
    setState(() {
      _showSettings = true;
      _showProfile = false;
    });
  }

  void _openProfile() {
    setState(() {
      _showProfile = true;
      _showSettings = false;
    });
  }

  void _goBackToChats() {
    setState(() {
      _showSettings = false;
      _showProfile = false;
    });

    _requestMessageFocus();
  }

  List<Chat> get _visibleChats {
    final archivedChatIds =
        _chatListPreferences?.archivedChatIds ?? const <String>{};
    final visible = _chats.where((chat) {
      if (archivedChatIds.contains(chat.id) != _showArchivedChats) {
        return false;
      }
      if (_showArchivedChats || _selectedFolder == null) return true;
      return _chatListPreferences?.folderByChatId[chat.id] == _selectedFolder;
    });
    return _sortChatsByPin(visible);
  }

  List<Chat> _sortChatsByPin(Iterable<Chat> chats) {
    final sorted = ChatService.sortChats(chats.toList());
    final pinnedChatIds =
        _chatListPreferences?.pinnedChatIds ?? const <String>{};
    return [
      ...sorted.where((chat) => pinnedChatIds.contains(chat.id)),
      ...sorted.where((chat) => !pinnedChatIds.contains(chat.id)),
    ];
  }

  void _toggleArchivedChats() {
    setState(() {
      _showArchivedChats = !_showArchivedChats;
      _selectedFolder = null;
      if (_selectedChat != null &&
          !_visibleChats.any((chat) => chat.id == _selectedChat!.id)) {
        _selectedChat = _visibleChats.isEmpty ? null : _visibleChats.first;
      }
    });
  }

  Future<void> _showChatContextMenu(BuildContext context, Chat chat) async {
    final preferences = _chatListPreferences;
    if (preferences == null) return;
    final selectedAction = await showChatActionsSheet(
      context: context,
      chat: chat,
      isPinned: preferences.pinnedChatIds.contains(chat.id),
      isArchived: preferences.archivedChatIds.contains(chat.id),
      isMuted: preferences.mutedChatIds.contains(chat.id),
    );
    if (selectedAction == null || !mounted || !context.mounted) return;

    try {
      String message;
      switch (selectedAction) {
        case ChatListAction.togglePin:
          final isPinned = !preferences.pinnedChatIds.contains(chat.id);
          await preferences.setPinned(chat.id, isPinned);
          message = isPinned ? 'Чат закреплён' : 'Чат откреплён';
        case ChatListAction.toggleArchive:
          final isArchived = !preferences.archivedChatIds.contains(chat.id);
          await preferences.setArchived(chat.id, isArchived);
          message = isArchived
              ? 'Чат перемещён в архив'
              : 'Чат возвращён из архива';
        case ChatListAction.toggleMute:
          final isMuted = !preferences.mutedChatIds.contains(chat.id);
          await preferences.setMuted(chat.id, isMuted);
          message = isMuted ? 'Уведомления отключены' : 'Уведомления включены';
        case ChatListAction.moveToFolder:
          final folderName = await _chooseChatFolder(context, chat);
          if (folderName == null || !mounted || !context.mounted) return;
          await preferences.setChatFolder(
            chat.id,
            folderName.isEmpty ? null : folderName,
          );
          message = folderName.isEmpty
              ? 'Чат убран из папки'
              : 'Чат перемещён в «$folderName»';
      }

      if (!mounted || !context.mounted) return;
      setState(() {
        _chats = _sortChatsByPin(_chats);
        if (_selectedChat != null &&
            !_visibleChats.any((item) => item.id == _selectedChat!.id)) {
          _selectedChat = _visibleChats.isEmpty ? null : _visibleChats.first;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    } catch (error) {
      debugPrint('Не удалось изменить настройки чата ${chat.id}: $error');
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить действие')),
        );
      }
    }
  }

  static const _createFolderPickerResult = '\u0000create-folder';

  Future<String?> _chooseChatFolder(BuildContext context, Chat chat) async {
    final preferences = _chatListPreferences;
    if (preferences == null) return null;
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          decoration: BoxDecoration(
            color: const Color(0xFF191820),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Папка для «${chat.name}»',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    _folderPickerOption(
                      context,
                      title: 'Без папки',
                      icon: Icons.inbox_outlined,
                      selected: !preferences.folderByChatId.containsKey(
                        chat.id,
                      ),
                      value: '',
                    ),
                    for (final folder
                        in preferences.folderNames.toList()..sort())
                      _folderPickerOption(
                        context,
                        title: folder,
                        icon: Icons.folder_rounded,
                        selected: preferences.folderByChatId[chat.id] == folder,
                        value: folder,
                      ),
                    _folderPickerOption(
                      context,
                      title: 'Создать папку',
                      icon: Icons.create_new_folder_outlined,
                      selected: false,
                      value: _createFolderPickerResult,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (result != _createFolderPickerResult) return result;
    if (!mounted || !context.mounted) return null;
    final previousFolders = Set<String>.from(preferences.folderNames);
    await _createChatFolder(context);
    if (!mounted || !context.mounted) return null;
    final createdFolders = preferences.folderNames.difference(previousFolders);
    return createdFolders.isEmpty ? null : createdFolders.first;
  }

  Widget _folderPickerOption(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool selected,
    required String value,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(
        icon,
        color: selected ? const Color(0xFF8F8BFF) : Colors.white60,
      ),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      trailing: selected
          ? const Icon(Icons.check_rounded, color: Color(0xFF8F8BFF))
          : null,
      onTap: () => Navigator.pop(context, value),
    );
  }

  Future<void> _createChatFolder(BuildContext context) async {
    final preferences = _chatListPreferences;
    if (preferences == null) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF191820),
        title: const Text('Новая папка', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Например, Работа',
            hintStyle: const TextStyle(color: Colors.white38),
            counterStyle: const TextStyle(color: Colors.white38),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF8F8BFF)),
            ),
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted || !context.mounted) return;
    try {
      await preferences.createFolder(name);
      if (!mounted || !context.mounted) return;
      setState(() {
        _selectedFolder = name.trim();
        if (_selectedChat != null &&
            !_visibleChats.any((chat) => chat.id == _selectedChat!.id)) {
          _selectedChat = _visibleChats.isEmpty ? null : _visibleChats.first;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Папка «${name.trim()}» создана'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      debugPrint('Не удалось создать папку чатов: $error');
      if (!mounted || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is StateError
                ? error.message.toString()
                : 'Не удалось создать папку. Проверь подключение и повтори.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    NotificationService().onChatSelected = null;
    _realtimeChannel?.unsubscribe();
    _notificationChannel?.unsubscribe();
    _pollingTimer?.cancel();
    _readStatusRefreshTimer?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF080712),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF8A4DFF)),
        ),
      );
    }

    final currentUser = _currentUser;
    if (currentUser == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF080712),
        body: Center(
          child: Text(
            'Пользователь не найден',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final userAvatarUrl = currentUser.avatarUrl;
    final userName = currentUser.name;

    if (_showSettings) {
      return Scaffold(
        backgroundColor: const Color(0xFF080712),
        body: Row(
          children: [
            Container(
              width: 320,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF111023), Color(0xFF090812)],
                ),
                border: Border(
                  right: BorderSide(
                    color: Colors.white.withValues(alpha: 0.06),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF171426),
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.06),
                          width: 1,
                        ),
                      ),
                    ),
                    child: InkWell(
                      onTap: _goBackToChats,
                      borderRadius: BorderRadius.circular(12),
                      child: Row(
                        children: [
                          Icon(Icons.arrow_back, color: Colors.grey[400]),
                          const SizedBox(width: 12),
                          Text(
                            'Назад к чатам',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Expanded(child: SettingsScreen()),
          ],
        ),
      );
    }

    if (_showProfile) {
      return Scaffold(
        backgroundColor: const Color(0xFF080712),
        body: Row(
          children: [
            Container(
              width: 320,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF111023), Color(0xFF090812)],
                ),
                border: Border(
                  right: BorderSide(
                    color: Colors.white.withValues(alpha: 0.06),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF171426),
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.06),
                          width: 1,
                        ),
                      ),
                    ),
                    child: InkWell(
                      onTap: _goBackToChats,
                      borderRadius: BorderRadius.circular(12),
                      child: Row(
                        children: [
                          Icon(Icons.arrow_back, color: Colors.grey[400]),
                          const SizedBox(width: 12),
                          Text(
                            'Назад к чатам',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Профиль',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Expanded(child: ProfileScreen()),
          ],
        ),
      );
    }

    // ===== ОСНОВНОЙ ЭКРАН С ЧАТАМИ =====
    return Scaffold(
      backgroundColor: const Color(0xFF080712),
      body: Row(
        children: [
          Container(
            width: 320,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF111023), Color(0xFF090812)],
              ),
              border: Border(
                right: BorderSide(
                  color: Colors.white.withValues(alpha: 0.06),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF9B5CFF), Color(0xFF5424D8)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF8547FF,
                              ).withValues(alpha: 0.3),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.bubble_chart_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 11),
                      const Text(
                        'Strazh',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF8A4DFF,
                          ).withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(
                              0xFFB88CFF,
                            ).withValues(alpha: 0.15),
                          ),
                        ),
                        child: const Text(
                          'MESSENGER',
                          style: TextStyle(
                            color: Color(0xFFCAB6FF),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: _openProfile,
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: const Color(0xFF19172A),
                      borderRadius: BorderRadius.circular(18),
                      border: Border(
                        top: BorderSide(
                          color: Colors.white.withValues(alpha: 0.06),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: Colors.grey[800],
                          backgroundImage:
                              userAvatarUrl != null && userAvatarUrl.isNotEmpty
                              ? NetworkImage(userAvatarUrl)
                              : null,
                          child: userAvatarUrl == null || userAvatarUrl.isEmpty
                              ? Text(
                                  userName.isNotEmpty
                                      ? userName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _currentUser?.name ?? 'Пользователь',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '@${_currentUser?.tag ?? ''}',
                                style: TextStyle(
                                  color: const Color(0xFF9D96B3),
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _openSettings,
                          icon: Icon(
                            Icons.settings_outlined,
                            color: const Color(0xFFC2B5E4),
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  height: 104,
                  child: StoriesBar(currentUserId: _currentUser!.id),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF19172A),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.07),
                            ),
                          ),
                          child: TextField(
                            controller: _searchController,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              hintText: 'Поиск групп и чатов...',
                              hintStyle: const TextStyle(
                                color: Color(0xFFA9A4BD),
                              ),
                              prefixIcon: Icon(
                                Icons.search,
                                color: const Color(0xFFB8A7E8),
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF271C43),
                          foregroundColor: const Color(0xFFD8C7FF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        tooltip: 'Создать группу',
                        onPressed: _openCreateGroup,
                        icon: const Icon(
                          Icons.group_add_outlined,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF271C43),
                          foregroundColor: const Color(0xFFD8C7FF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        tooltip: 'Создать канал',
                        onPressed: _openCreateChannel,
                        icon: const Icon(
                          Icons.campaign_outlined,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      if (!_showArchivedChats) _buildFolderFilters(),
                      _buildArchiveToggle(),
                      Expanded(child: _buildChatList()),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: _selectedChat != null
                ? (_selectedChat!.type == 'login_codes'
                      ? const LoginCodesChatScreen()
                      : ChatScreen(
                          key: _chatScreenKey,
                          chat: _selectedChat!,
                          currentUser: _currentUser!,
                          onMembershipChanged: () => unawaited(_refreshChats()),
                        ))
                : _buildEmptyState(),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderFilters() {
    final folders = _chatListPreferences?.folderNames.toList() ?? <String>[];
    folders.sort();
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        children: [
          _folderFilterChip(
            title: 'Все',
            selected: _selectedFolder == null,
            onTap: () => _selectFolder(null),
          ),
          for (final folder in folders)
            GestureDetector(
              onLongPress: () => _deleteChatFolder(folder),
              child: _folderFilterChip(
                title: folder,
                selected: _selectedFolder == folder,
                onTap: () => _selectFolder(folder),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 5),
            child: Tooltip(
              message: 'Создать папку',
              child: Material(
                color: const Color(0xFF19172A),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _createChatFolder(context),
                  child: const SizedBox(
                    width: 34,
                    height: 34,
                    child: Icon(Icons.add_rounded, color: Colors.white70),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _folderFilterChip({
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: selected ? const Color(0xFF6728E8) : const Color(0xFF171525),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 34),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? const Color(0xFFB88CFF).withValues(alpha: 0.7)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Center(
              child: Text(
                title,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _selectFolder(String? folderName) {
    setState(() {
      _selectedFolder = folderName;
      if (_selectedChat != null &&
          !_visibleChats.any((chat) => chat.id == _selectedChat!.id)) {
        _selectedChat = _visibleChats.isEmpty ? null : _visibleChats.first;
      }
    });
  }

  Future<void> _deleteChatFolder(String name) async {
    final preferences = _chatListPreferences;
    if (preferences == null) return;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF191820),
        title: const Text(
          'Удалить папку?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Чаты из «$name» останутся в общем списке.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (shouldDelete != true || !mounted) return;
    try {
      await preferences.deleteFolder(name);
      if (!mounted) return;
      setState(() {
        if (_selectedFolder == name) _selectedFolder = null;
        if (_selectedChat != null &&
            !_visibleChats.any((chat) => chat.id == _selectedChat!.id)) {
          _selectedChat = _visibleChats.isEmpty ? null : _visibleChats.first;
        }
      });
    } catch (error) {
      debugPrint('Не удалось удалить папку чатов: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Не удалось удалить папку')));
    }
  }

  Widget _buildChatList() {
    final query = _searchController.text.trim();
    if (query.length >= 2) {
      if (_isSearchingGroups) {
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      }
      final chatResults = _visibleChats
          .where(
            (chat) => chat.name.toLowerCase().contains(query.toLowerCase()),
          )
          .toList();
      if (_groupResults.isEmpty && chatResults.isEmpty) {
        return const Center(
          child: Text(
            'Ничего не найдено',
            style: TextStyle(color: Colors.grey),
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (chatResults.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Text(
                'Мои чаты',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ...chatResults.map(
              (chat) => _buildChatTile(chat, _selectedChat?.id == chat.id),
            ),
          ],
          if (_groupResults.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Text(
                'Открытые группы и каналы',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ..._groupResults.map(
              (group) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.white,
                  child: group.type == 'channel'
                      ? const Icon(Icons.campaign_outlined, color: Colors.black)
                      : Text(
                          group.name[0].toUpperCase(),
                          style: const TextStyle(color: Colors.black),
                        ),
                ),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        group.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    if (group.type == 'channel' && group.isVerified) ...[
                      const SizedBox(width: 5),
                      const Icon(
                        Icons.verified,
                        color: Color(0xFF1A73E8),
                        size: 16,
                      ),
                    ],
                  ],
                ),
                subtitle: Text(
                  group.type == 'channel'
                      ? 'Открытый канал'
                      : 'Открытая группа',
                  style: TextStyle(color: Colors.grey),
                ),
                trailing: TextButton(
                  onPressed: group.type == 'channel'
                      ? () => _previewChannel(group)
                      : () => _joinGroup(group),
                  child: Text(
                    group.type == 'channel' ? 'Предпросмотр' : 'Вступить',
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    }
    if (_visibleChats.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _showArchivedChats
                    ? Icons.archive_outlined
                    : Icons.chat_bubble_outline,
                color: Colors.white.withValues(alpha: 0.28),
                size: 32,
              ),
              const SizedBox(height: 10),
              Text(
                _showArchivedChats ? 'Архив пуст' : 'Нет чатов',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.48),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _visibleChats.length,
      itemBuilder: (context, index) {
        final chat = _visibleChats[index];
        return _buildChatTile(chat, _selectedChat?.id == chat.id);
      },
    );
  }

  Widget _buildArchiveToggle() {
    final archivedCount = _chats
        .where(
          (chat) =>
              _chatListPreferences?.archivedChatIds.contains(chat.id) ?? false,
        )
        .length;
    final isArchive = _showArchivedChats;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Material(
        color: const Color(0xFF171426),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: _toggleArchivedChats,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFB49AFF).withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isArchive ? Icons.arrow_back_rounded : Icons.archive_outlined,
                  color: const Color(0xFF38D3CA),
                  size: 19,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isArchive ? 'Все чаты' : 'Архив',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!isArchive && archivedCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38D3CA).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      archivedCount.toString(),
                      style: const TextStyle(
                        color: Color(0xFF38D3CA),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(width: 5),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.3),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatTile(Chat chat, bool isSelected) {
    final hasAvatar = chat.avatarUrl != null && chat.avatarUrl!.isNotEmpty;
    const accentColor = Color(0xFF7442F5);

    return GestureDetector(
      onSecondaryTapDown: (_) => _showChatContextMenu(context, chat),
      onLongPress: () => _showChatContextMenu(context, chat),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _onChatSelected(chat),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: isSelected
                ? Border.all(color: accentColor.withValues(alpha: 0.2))
                : null,
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.grey[800],
                    backgroundImage: hasAvatar
                        ? NetworkImage(chat.avatarUrl!)
                        : null,
                    child: !hasAvatar
                        ? chat.type == 'login_codes'
                              ? const Icon(
                                  Icons.shield_outlined,
                                  color: Color(0xFF568AF2),
                                )
                              : Text(
                                  chat.name.isNotEmpty
                                      ? chat.name[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                        : null,
                  ),
                  if (chat.type == 'saved')
                    Positioned(
                      right: -3,
                      bottom: -3,
                      child: Container(
                        width: 19,
                        height: 19,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFC857),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF090812)),
                        ),
                        child: const Icon(
                          Icons.star_rounded,
                          color: Color(0xFF30230A),
                          size: 14,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            chat.name,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontSize: 15,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (chat.type == 'channel' && chat.isVerified) ...[
                          const SizedBox(width: 5),
                          const Icon(
                            Icons.verified,
                            color: Color(0xFF1A73E8),
                            size: 15,
                          ),
                        ],
                        if (_chatListPreferences?.pinnedChatIds.contains(
                              chat.id,
                            ) ??
                            false) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.push_pin_rounded,
                            color: Color(0xFF8F8BFF),
                            size: 13,
                          ),
                        ],
                        if (_chatListPreferences?.mutedChatIds.contains(
                              chat.id,
                            ) ??
                            false) ...[
                          const SizedBox(width: 5),
                          Icon(
                            Icons.notifications_off_outlined,
                            color: Colors.grey[500],
                            size: 14,
                          ),
                        ],
                      ],
                    ),
                    Row(
                      children: [
                        if (chat.lastMessageIsMe) ...[
                          Icon(
                            chat.lastMessageReadByOthers
                                ? Icons.done_all
                                : Icons.done,
                            color: chat.lastMessageReadByOthers
                                ? const Color(0xFF64B5F6)
                                : Colors.grey[500],
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            chat.lastMessage ?? 'Нет сообщений',
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white54
                                  : Colors.grey[500],
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  Text(
                    _formatTime(chat.lastMessageTime),
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                  if (chat.unreadCount > 0)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7442F5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        chat.unreadCount > 99 ? '99+' : '${chat.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              IconButton(
                tooltip: 'Действия с чатом',
                icon: Icon(Icons.more_vert, color: Colors.grey[500], size: 18),
                onPressed: () => _showChatContextMenu(context, chat),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF19172A),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF333333), width: 1),
            ),
            child: const Icon(
              Icons.chat_bubble_outline,
              color: Colors.grey,
              size: 40,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Выберите чат',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Выберите чат из списка слева,\nчтобы начать общение',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 15,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(time.year, time.month, time.day);

    if (messageDate == today) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Вчера';
    } else {
      return '${time.day}.${time.month}';
    }
  }
}
