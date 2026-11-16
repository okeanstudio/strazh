// d:math нужен для sin и pi
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/shared/presentation/widgets/bottom_nav_bar.dart';
import 'package:strazh/features/chat/presentation/widgets/chat_tile.dart';
import 'package:strazh/features/chat/data/services/chat_service.dart';
import 'package:strazh/features/chat/data/services/chat_list_preferences.dart';
import 'package:strazh/shared/domain/models/chat.dart';
import 'package:strazh/features/chat/presentation/widgets/chat_actions_sheet.dart';
import 'package:strazh/features/chat/presentation/widgets/create_chat/create_group.dart';
import 'package:strazh/features/chat/presentation/widgets/create_chat/create_channel.dart';
import 'package:strazh/features/auth/data/services/auth_service.dart';
import 'package:strazh/features/auth/presentation/screens/auth.dart';
import 'package:strazh/features/auth/presentation/screens/login_codes_chat_screen.dart';
import 'package:strazh/features/legal/presentation/screens/usage_policy_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strazh/shared/domain/models/user.dart' as app;
import 'package:strazh/features/chat/presentation/screens/chat.dart';
import 'package:strazh/features/settings/presentation/screens/settings.dart';
import 'package:strazh/features/profile/presentation/screens/profile.dart';
import 'package:strazh/features/chat/data/services/notification_service.dart';
import 'package:strazh/features/stories/presentation/screens/stories_screen.dart';
import 'package:strazh/features/home/presentation/screens/home_desktop.dart';
import 'package:strazh/shared/presentation/widgets/strzh_s_loader.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _policyVersion = '2026-10-22';
  bool _isCheckingPolicy = true;
  String? _policyCheckError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPolicyAcceptance();
    });
  }

  Future<void> _checkPolicyAcceptance() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isCheckingPolicy = false);
        return;
      }

      final preferences = await SharedPreferences.getInstance();
      final acceptanceKey = 'usage_policy_accepted_${user.id}_$_policyVersion';
      if (preferences.getBool(acceptanceKey) == true) {
        if (mounted) setState(() => _isCheckingPolicy = false);
        return;
      }

      if (!mounted) return;
      final accepted = await showUsagePolicyDialog(context);
      if (!mounted) return;

      if (accepted == true) {
        await preferences.setBool(acceptanceKey, true);
        if (mounted) {
          setState(() {
            _policyCheckError = null;
            _isCheckingPolicy = false;
          });
        }
        return;
      }

      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (_) => false,
      );
    } catch (error) {
      debugPrint('Не удалось проверить принятие правил: $error');
      if (!mounted) return;
      setState(() {
        _policyCheckError = error.toString();
        _isCheckingPolicy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingPolicy) {
      return const Scaffold(
        backgroundColor: Color(0xFF080712),
        body: Center(child: StrazhSLoader(size: 96)),
      );
    }

    if (_policyCheckError != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF080712),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.redAccent,
                  size: 40,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Не удалось проверить согласие с правилами.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  _policyCheckError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _policyCheckError = null;
                      _isCheckingPolicy = true;
                    });
                    _checkPolicyAcceptance();
                  },
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isDesktop = _isDesktop(context);

    if (isDesktop) {
      return const HomeDesktopScreen();
    } else {
      return const HomeMobileScreen();
    }
  }

  bool _isDesktop(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (kIsWeb) {
      return width > 800;
    }
    return width > 800 ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }
}

// ===== МОБИЛЬНАЯ ВЕРСИЯ =====

class HomeMobileScreen extends StatefulWidget {
  const HomeMobileScreen({super.key});

  @override
  State<HomeMobileScreen> createState() => _HomeMobileScreenState();
}

class _HomeMobileScreenState extends State<HomeMobileScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  app.User? _currentUser;

  final ChatService _chatService = ChatService();
  final AuthService _authService = AuthService();
  List<Chat> _chats = [];
  List<Map<String, dynamic>> _userResults = [];
  List<Chat> _groupResults = [];
  bool _isLoading = true;
  String? _currentUserId;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _homeScrollController = ScrollController();
  final Map<String, double> _scrollOffsetByView = {};
  List<Chat> _filteredChats = [];
  bool _isSearchingUsers = false;
  ChatListPreferences? _chatListPreferences;
  bool _showArchivedChats = false;
  String? _selectedFolder;

  // Realtime каналы
  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _roomsChannel;
  RealtimeChannel? _participantsChannel;

  // Таймер для поллинга (запасной вариант)
  Timer? _pollingTimer;
  Timer? _readStatusRefreshTimer;
  bool _isPolling = false;
  bool _isRefreshingChatList = false;
  final Set<String> _failedRealtimeChannels = {};
  final Set<String> _readyRealtimeChannels = {};

  String _currentScreen = 'home';

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut),
    );

    final supabase = Supabase.instance.client;
    debugPrint('Подключено к Supabase: ${supabase.rest.url}');

    _initData();
    _searchController.addListener(_onSearchChanged);
    _homeScrollController.addListener(_saveCurrentScrollOffset);
  }

  String get _scrollViewKey =>
      _showArchivedChats ? 'archive' : 'folder:${_selectedFolder ?? ''}';

  void _saveCurrentScrollOffset() {
    if (_homeScrollController.hasClients) {
      _scrollOffsetByView[_scrollViewKey] =
          _homeScrollController.position.pixels;
    }
  }

  void _restoreScrollOffset(String viewKey, double offset) {
    _scrollOffsetByView[viewKey] = offset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_homeScrollController.hasClients) return;
      final position = _homeScrollController.position;
      final restoredOffset = offset
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      _homeScrollController.jumpTo(restoredOffset);
      _scrollOffsetByView[viewKey] = restoredOffset;
    });
  }

  Future<void> _initData() async {
    _currentUserId = _authService.currentUserId;
    _currentUser = _authService.getCurrentUserFromMetadata();
    try {
      _chatListPreferences = await ChatListPreferences.load(_currentUserId);
    } catch (error) {
      debugPrint('Не удалось загрузить настройки списка чатов: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось загрузить настройки чатов')),
        );
      }
    }
    await _loadChats();
    if (mounted) {
      NotificationService().onChatSelected = _openNotificationChat;
      _subscribeToRealtimeUpdates();
      setState(() {});
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query.length >= 2) {
      _filterChats();
      _searchUsers(query);
      _searchGroups(query);
    } else {
      setState(() {
        _filteredChats = _filteredChatsForCurrentView();
        _userResults = [];
        _groupResults = [];
        _isSearchingUsers = false;
      });
    }
  }

  void _filterChats() {
    final query = _searchController.text.toLowerCase().trim();
    if (!mounted) return;
    setState(() {
      if (query.isEmpty) {
        _filteredChats = _filteredChatsForCurrentView();
      } else {
        _filteredChats = _filteredChatsForCurrentView(query);
      }
    });
  }

  List<Chat> _sortChatsByPin(Iterable<Chat> chats) {
    final sorted = ChatService.sortChats(chats.toList());
    final pinned = _chatListPreferences?.pinnedChatIds ?? const <String>{};
    return [
      ...sorted.where((chat) => pinned.contains(chat.id)),
      ...sorted.where((chat) => !pinned.contains(chat.id)),
    ];
  }

  List<Chat> _filteredChatsForCurrentView([String query = '']) {
    final preferences = _chatListPreferences;
    final visible = _chats.where((chat) {
      final isArchived =
          preferences?.archivedChatIds.contains(chat.id) ?? false;
      if (isArchived != _showArchivedChats) return false;
      if (_showArchivedChats || _selectedFolder == null) return true;
      return preferences?.folderByChatId[chat.id] == _selectedFolder;
    });
    final normalizedQuery = query.toLowerCase().trim();
    return _sortChatsByPin(
      normalizedQuery.isEmpty
          ? visible
          : visible.where(
              (chat) => chat.name.toLowerCase().contains(normalizedQuery),
            ),
    );
  }

  Future<void> _showChatActions(Chat chat) async {
    final preferences = _chatListPreferences;
    if (preferences == null) return;

    final result = await showChatActionsSheet(
      context: context,
      chat: chat,
      isPinned: preferences.pinnedChatIds.contains(chat.id),
      isArchived: preferences.archivedChatIds.contains(chat.id),
      isMuted: preferences.mutedChatIds.contains(chat.id),
    );
    if (result == null || !mounted) return;

    try {
      String message;
      switch (result) {
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
          final folderName = await _chooseChatFolder(chat);
          if (folderName == null || !mounted) return;
          await preferences.setChatFolder(
            chat.id,
            folderName.isEmpty ? null : folderName,
          );
          message = folderName.isEmpty
              ? 'Чат убран из папки'
              : 'Чат перемещён в «$folderName»';
      }
      if (!mounted) return;
      setState(() {
        _chats = _sortChatsByPin(_chats);
        _filteredChats = _filteredChatsForCurrentView(
          _searchController.text.trim().length >= 2
              ? _searchController.text
              : '',
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    } catch (error) {
      debugPrint('Не удалось изменить настройки чата ${chat.id}: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить действие')),
        );
      }
    }
  }

  static const _createFolderPickerResult = '\u0000create-folder';

  Future<String?> _chooseChatFolder(Chat chat) async {
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
                    if (preferences.folderNames.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(14),
                        child: Text(
                          'Сначала создай папку кнопкой «+» над списком чатов',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
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
    final previousFolders = Set<String>.from(preferences.folderNames);
    await _createChatFolder();
    if (!mounted) return null;
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

  Future<void> _createChatFolder() async {
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
    if (name == null || !mounted) return;

    try {
      await preferences.createFolder(name);
      if (!mounted) return;
      setState(() {
        _selectedFolder = name.trim();
        _filteredChats = _filteredChatsForCurrentView();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Папка «${name.trim()}» создана'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      debugPrint('Не удалось создать папку чатов: $error');
      if (!mounted) return;
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
        _filteredChats = _filteredChatsForCurrentView();
      });
    } catch (error) {
      debugPrint('Не удалось удалить папку чатов: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Не удалось удалить папку')));
    }
  }

  void _toggleArchivedChats() {
    _saveCurrentScrollOffset();
    final nextIsArchived = !_showArchivedChats;
    final nextViewKey = nextIsArchived ? 'archive' : 'folder:';
    final currentOffset = _homeScrollController.hasClients
        ? _homeScrollController.position.pixels
        : 0.0;
    final nextOffset = _scrollOffsetByView[nextViewKey] ?? currentOffset;
    setState(() {
      _showArchivedChats = nextIsArchived;
      _selectedFolder = null;
      _filteredChats = _filteredChatsForCurrentView(
        _searchController.text.trim().length >= 2 ? _searchController.text : '',
      );
    });
    _restoreScrollOffset(nextViewKey, nextOffset);
  }

  Future<void> _searchUsers(String query) async {
    if (_currentUser == null) return;
    setState(() => _isSearchingUsers = true);
    try {
      final results = await _authService.searchUsers(query);
      if (mounted && query == _searchController.text.trim()) {
        setState(() {
          _userResults = results;
          _isSearchingUsers = false;
        });
      }
    } catch (e) {
      debugPrint('Ошибка поиска пользователей: $e');
      if (mounted && query == _searchController.text.trim()) {
        setState(() {
          _userResults = [];
          _isSearchingUsers = false;
        });
      }
    }
  }

  Future<void> _searchGroups(String query) async {
    try {
      final groups = await _chatService.searchGroups(query);
      if (mounted && query == _searchController.text.trim()) {
        setState(() => _groupResults = groups);
      }
    } catch (error) {
      debugPrint('Ошибка поиска групп: $error');
      if (mounted) setState(() => _groupResults = []);
    }
  }

  Future<void> _joinGroup(Chat group) async {
    try {
      await _chatService.joinGroup(group.id);
      await _loadChats();
      if (mounted) {
        setState(() {
          _searchController.clear();
          _groupResults.removeWhere((item) => item.id == group.id);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Вы вступили в группу «${group.name}»')),
          );
        }
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
    final user = _currentUser;
    if (user == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chat: channel,
          currentUser: user,
          onMembershipChanged: () => unawaited(_loadChats()),
        ),
      ),
    );
  }

  Future<String?> _getOrCreateDirectChat(String otherUserId) async {
    final supabase = Supabase.instance.client;
    final currentUserId = _currentUserId;
    if (currentUserId == null) return null;

    final existingChats = await supabase
        .from('room_participants')
        .select('room_id')
        .eq('user_id', currentUserId); // ✅ ИСПРАВЛЕНО: profile_id → user_id

    final List<String> roomIds = existingChats
        .map((e) => e['room_id'] as String)
        .toList();

    if (roomIds.isNotEmpty) {
      final sharedChats = await supabase
          .from('room_participants')
          .select('room_id')
          .eq('user_id', otherUserId) // ✅ ИСПРАВЛЕНО: profile_id → user_id
          .inFilter('room_id', roomIds);

      final sharedRoomIds = sharedChats
          .map((chat) => chat['room_id'] as String)
          .toSet()
          .toList();
      if (sharedRoomIds.isNotEmpty) {
        final directRooms = await supabase
            .from('rooms')
            .select('id')
            .inFilter('id', sharedRoomIds)
            .eq('type', 'direct');
        final directRoomIds = directRooms
            .map((room) => room['id'] as String)
            .toList();

        if (directRoomIds.isNotEmpty) {
          final latestMessage = await supabase
              .from('messages')
              .select('room_id')
              .inFilter('room_id', directRoomIds)
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
          if (latestMessage != null) {
            return latestMessage['room_id'] as String;
          }
          return directRoomIds.first;
        }
      }
    }

    final newRoom = await supabase
        .from('rooms')
        .insert({
          'type': 'direct',
          'created_by': currentUserId,
          'created_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();

    final roomId = newRoom['id'];

    await supabase.from('room_participants').insert([
      {
        'room_id': roomId,
        'user_id': currentUserId, // ✅ ИСПРАВЛЕНО: profile_id → user_id
        'joined_at': DateTime.now().toIso8601String(),
      },
      {
        'room_id': roomId,
        'user_id': otherUserId, // ✅ ИСПРАВЛЕНО: profile_id → user_id
        'joined_at': DateTime.now().toIso8601String(),
      },
    ]);
    return roomId;
  }

  Future<void> _openChatWithUser(
    String userId,
    String userName,
    String? avatarUrl,
  ) async {
    try {
      final roomId = await _getOrCreateDirectChat(userId);
      if (roomId != null && mounted && _currentUser != null) {
        final existingChat = _chats
            .where((chat) => chat.id == roomId)
            .firstOrNull;
        final chat =
            existingChat ??
            Chat(
              id: roomId,
              name: userName,
              avatarUrl: avatarUrl,
              type: 'direct',
            );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                ChatScreen(chat: chat, currentUser: _currentUser!),
          ),
        );
      }
    } catch (error) {
      debugPrint('Ошибка открытия чата: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось открыть чат: $error')),
        );
      }
    }
  }

  Future<void> _openNotificationChat(String chatId) async {
    if (!mounted || _currentUser == null) return;

    var chat = _chats.where((item) => item.id == chatId).firstOrNull;
    if (chat == null) {
      try {
        final chats = await _chatService.getMyChats();
        if (!mounted) return;
        setState(() {
          _chats = _sortChatsByPin(ChatService.mergeChats(_chats, chats));
          _filteredChats = _filteredChatsForCurrentView();
        });
        chat = _chats.where((item) => item.id == chatId).firstOrNull;
      } catch (error) {
        debugPrint('Не удалось загрузить чат из уведомления: $error');
        return;
      }
    }

    final selectedChat = chat;
    if (!mounted || selectedChat == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => selectedChat.type == 'login_codes'
            ? const LoginCodesChatScreen()
            : ChatScreen(chat: selectedChat, currentUser: _currentUser!),
      ),
    );
  }

  void _handleNavigation(String screenName) {
    setState(() {
      _currentScreen = screenName;
    });
  }

  @override
  void dispose() {
    NotificationService().onChatSelected = null;
    _messagesChannel?.unsubscribe();
    _roomsChannel?.unsubscribe();
    _participantsChannel?.unsubscribe();
    _failedRealtimeChannels.clear();
    _pollingTimer?.cancel();
    _readStatusRefreshTimer?.cancel();
    _shakeController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _homeScrollController.removeListener(_saveCurrentScrollOffset);
    _homeScrollController.dispose();
    super.dispose();
  }

  // ===== РАСШИРЕННАЯ ПОДПИСКА НА REALTIME =====
  void _subscribeToRealtimeUpdates() {
    if (_currentUserId == null) return;

    // Отписываемся от старых каналов
    _messagesChannel?.unsubscribe();
    _roomsChannel?.unsubscribe();
    _participantsChannel?.unsubscribe();

    final supabase = Supabase.instance.client;

    // 1. Подписка на новые сообщения
    _messagesChannel = supabase
        .channel('home_messages_${_currentUserId!}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) async {
            if (!mounted) return;
            debugPrint(
              'Home Realtime: новое сообщение для комнаты ${payload.newRecord['room_id']}',
            );
            await _refreshChatLastMessage(
              payload.newRecord['room_id']?.toString(),
              messageRecord: payload.newRecord,
            );
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          callback: (payload) async {
            if (!mounted) return;
            await _loadChats(showLoading: false);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'messages',
          callback: (payload) async {
            if (!mounted) return;
            await _loadChats(showLoading: false);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'message_reads',
          callback: (payload) async {
            if (!mounted) return;
            _readStatusRefreshTimer?.cancel();
            _readStatusRefreshTimer = Timer(
              const Duration(milliseconds: 250),
              () => unawaited(_loadChats(showLoading: false)),
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
            value: _currentUserId!,
          ),
          callback: (payload) async {
            if (!mounted) return;
            await _loadChats(showLoading: false);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'phone_login_challenges',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: _currentUserId!,
          ),
          callback: (payload) async {
            if (!mounted) return;
            await _loadChats(showLoading: false);
          },
        )
        .subscribe(
          (status, error) => _handleRealtimeStatus('messages', status, error),
        );

    // 2. Подписка на новые комнаты (чаты)
    _roomsChannel = supabase
        .channel('home_rooms_${_currentUserId!}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'rooms',
          callback: (payload) async {
            if (!mounted) return;
            final newRecord = payload.newRecord;
            final newRoomId = newRecord['id'] as String?;
            if (newRoomId != null) {
              final participant = await supabase
                  .from('room_participants')
                  .select()
                  .eq('room_id', newRoomId)
                  .eq('user_id', _currentUserId!) // ✅ ИСПРАВЛЕНО
                  .maybeSingle();

              if (participant != null && mounted) {
                await _loadChats(showLoading: false);
              }
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'rooms',
          callback: (payload) async {
            if (!mounted) return;
            await _loadChats(showLoading: false);
          },
        )
        .subscribe(
          (status, error) => _handleRealtimeStatus('rooms', status, error),
        );

    // 3. Подписка на изменения участников (добавление в группы)
    _participantsChannel = supabase
        .channel('home_participants_${_currentUserId!}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'room_participants',
          callback: (payload) async {
            if (!mounted) return;
            final newParticipant = payload.newRecord;
            if (newParticipant['user_id'] == _currentUserId) {
              // ✅ ИСПРАВЛЕНО
              await _loadChats(showLoading: false);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'room_participants',
          callback: (payload) async {
            if (!mounted) return;
            await _loadChats(showLoading: false);
          },
        )
        .subscribe(
          (status, error) =>
              _handleRealtimeStatus('participants', status, error),
        );
  }

  Future<void> _refreshChatLastMessage(
    String? roomId, {
    Map<String, dynamic>? messageRecord,
  }) async {
    if (roomId == null) {
      await _loadChats(showLoading: false);
      return;
    }

    final chatIndex = _chats.indexWhere((chat) => chat.id == roomId);
    if (chatIndex == -1) {
      await _loadChats(showLoading: false);
      return;
    }

    try {
      final refreshedChat = await _chatService.refreshChatLastMessage(
        _chats[chatIndex],
        messageRecord: messageRecord,
      );
      if (!mounted) return;
      if (refreshedChat == null) {
        await _loadChats(showLoading: false);
        return;
      }

      final updatedChats = List<Chat>.from(_chats);
      final currentIndex = updatedChats.indexWhere((chat) => chat.id == roomId);
      if (currentIndex == -1) {
        await _loadChats(showLoading: false);
        return;
      }
      updatedChats[currentIndex] = refreshedChat;
      final sortedChats = _sortChatsByPin(updatedChats);
      final query = _searchController.text.toLowerCase().trim();

      setState(() {
        _chats = sortedChats;
        _filteredChats = _filteredChatsForCurrentView(query);
      });
    } catch (error) {
      debugPrint('Ошибка быстрого обновления чата: $error');
      await _loadChats(showLoading: false);
    }
  }

  void _handleRealtimeStatus(String channel, Object? status, Object? error) {
    final value = status.toString().toLowerCase();
    debugPrint(
      'Home Realtime [$channel]: $status${error == null ? '' : ' ($error)'}',
    );
    if (value.contains('subscribed')) {
      _failedRealtimeChannels.remove(channel);
      _readyRealtimeChannels.add(channel);
    } else if (error != null ||
        value.contains('error') ||
        value.contains('timeout') ||
        value.contains('closed')) {
      _failedRealtimeChannels.add(channel);
      _readyRealtimeChannels.remove(channel);
    }

    if (_failedRealtimeChannels.isNotEmpty) {
      _startPolling();
    } else if (_readyRealtimeChannels.containsAll([
      'messages',
      'rooms',
      'participants',
    ])) {
      _stopPolling();
    }
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  // ===== ЗАПАСНОЙ ПОЛЛИНГ =====
  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (!mounted || _isPolling) return;

      _isPolling = true;
      try {
        await _loadChats(showLoading: false);
      } catch (e) {
        debugPrint('⚠️ Ошибка поллинга чатов: $e');
      } finally {
        _isPolling = false;
      }
    });
  }

  Future<void> _loadChats({bool showLoading = true}) async {
    if (!mounted || _isRefreshingChatList) return;
    _isRefreshingChatList = true;
    if (showLoading) setState(() => _isLoading = true);
    try {
      final chats = await _chatService.getMyChats();
      if (mounted) {
        final mergedChats = _sortChatsByPin(
          ChatService.mergeChats(_chats, chats),
        );
        final query = _searchController.text.toLowerCase().trim();

        setState(() {
          _chats = mergedChats;
          _filteredChats = _filteredChatsForCurrentView(query);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки чатов: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } finally {
      _isRefreshingChatList = false;
    }
  }

  void _shake() {
    _shakeController.forward(from: 0);
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    Widget bodyContent;
    switch (_currentScreen) {
      case 'settings':
        bodyContent = const SettingsScreen();
        break;
      case 'profile':
        bodyContent = const ProfileScreen();
        break;
      case 'home':
      default:
        bodyContent = _buildHomeContent();
        break;
    }

    final isHomeScreen = _currentScreen == 'home';

    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        final shakeOffset = sin(_shakeAnimation.value * 4 * pi) * 6;
        return Transform.translate(
          offset: Offset(shakeOffset, 0),
          child: child,
        );
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF080712),
        appBar: isHomeScreen
            ? AppBar(
                backgroundColor: const Color(
                  0xFF080712,
                ).withValues(alpha: 0.72),
                elevation: 0,
                scrolledUnderElevation: 0,
                surfaceTintColor: Colors.transparent,
                title: Row(
                  children: [
                    const Text(
                      'Strazh',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 29,
                        letterSpacing: -0.8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF25104E),
                        fixedSize: const Size(46, 46),
                      ),
                      onPressed: () {
                        // Сохраняем контекст в переменную и проверяем mounted
                        final currentContext = context;
                        showMenu(
                          context: currentContext,
                          position: RelativeRect.fromLTRB(100, 100, 0, 0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(
                              color: Color(0xFF7050B5),
                              width: 1,
                            ),
                          ),
                          color: const Color(0xFF19172A),
                          items: const [
                            PopupMenuItem(
                              value: 'create_group',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.group_add,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  SizedBox(width: 14),
                                  Text(
                                    'Создать группу',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'create_channel',
                              child: Row(
                                children: [
                                  Icon(
                                    LucideIcons.megaphone,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  SizedBox(width: 14),
                                  Text(
                                    'Создать канал',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ).then((value) {
                          // Проверяем mounted перед использованием контекста
                          if (currentContext.mounted) {
                            switch (value) {
                              case 'create_group':
                                if (_currentUserId != null) {
                                  showDialog(
                                    context: currentContext,
                                    builder: (dialogContext) =>
                                        CreateGroupWidget(
                                          currentUserId: _currentUserId!,
                                          existingMemberIds: [],
                                        ),
                                  ).then((groupId) {
                                    if (groupId != null && mounted) {
                                      _loadChats();
                                    }
                                  });
                                }
                              case 'create_channel':
                                if (_currentUserId != null) {
                                  showDialog<String>(
                                    context: currentContext,
                                    builder: (_) => CreateChannelWidget(
                                      currentUserId: _currentUserId!,
                                    ),
                                  ).then((channelId) {
                                    if (channelId != null && mounted) {
                                      _loadChats();
                                    }
                                  });
                                }
                            }
                          }
                        });
                      },
                      icon: const Icon(Icons.add_rounded, size: 28),
                    ),
                  ],
                ),
              )
            : null,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF111023),
                    Color(0xFF090812),
                    Color(0xFF0D0920),
                  ],
                ),
              ),
            ),
            Positioned(
              top: -150,
              right: -170,
              child: Container(
                width: 390,
                height: 390,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF712CFF).withValues(alpha: 0.22),
                      const Color(0xFF712CFF).withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 30,
              left: -230,
              child: Container(
                width: 440,
                height: 440,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF3D28BD).withValues(alpha: 0.16),
                      const Color(0xFF3D28BD).withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.025),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(_currentScreen),
                child: bodyContent,
              ),
            ),
          ],
        ),
        bottomNavigationBar: BottomNavBar(
          currentScreen: _currentScreen,
          onShake: _shake,
          onNavigate: _handleNavigation,
        ),
      ),
    );
  }

  Widget _buildHomeContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF8A4DFF)),
      );
    }
    final isSearching = _searchController.text.trim().length >= 2;
    return Column(
      children: [
        _buildSearchField(),
        if (isSearching) const SizedBox(height: 58) else _buildFolderFilters(),
        Expanded(
          child: CustomScrollView(
            controller: _homeScrollController,
            key: const PageStorageKey<String>('home-chat-list'),
            slivers: [
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    'Истории',
                    style: TextStyle(
                      color: Color(0xFFC9C0E8),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: StoriesBar(currentUserId: _currentUserId),
              ),
              if (!isSearching)
                SliverToBoxAdapter(child: _buildArchiveToggle()),
              if (isSearching)
                SliverToBoxAdapter(child: _buildSearchResults())
              else if (_filteredChats.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: const BoxDecoration(
                            color: Color(0xFF19172A),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.chat_bubble_outline,
                            color: Colors.grey,
                            size: 48,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _showArchivedChats
                              ? 'Архив пуст'
                              : _selectedFolder == null
                              ? 'Нет чатов'
                              : 'Папка пуста',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _showArchivedChats
                              ? 'Чаты, которые вы отправите в архив, появятся здесь'
                              : _selectedFolder == null
                              ? 'Начните новый чат или создайте группу'
                              : 'Зажмите чат и переместите его сюда',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      if (_currentUser == null) return const SizedBox.shrink();
                      final chat = _filteredChats[index];
                      return ChatTile(
                        key: ValueKey(chat.id),
                        chat: chat,
                        currentUser: _currentUser!,
                        animationIndex: index,
                        isPinned:
                            _chatListPreferences?.pinnedChatIds.contains(
                              chat.id,
                            ) ??
                            false,
                        isMuted:
                            _chatListPreferences?.mutedChatIds.contains(
                              chat.id,
                            ) ??
                            false,
                        onLongPress: () => _showChatActions(chat),
                      );
                    }, childCount: _filteredChats.length),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 88)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        decoration: InputDecoration(
          hintText: 'Поиск...',
          hintStyle: const TextStyle(color: Color(0xFFA9A4BD)),
          prefixIcon: const Icon(
            Icons.search,
            color: Color(0xFFB8A7E8),
            size: 22,
          ),
          filled: true,
          fillColor: const Color(0xFF19172A),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(color: Color(0xFF8A4DFF), width: 1.2),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 13),
        ),
      ),
    );
  }

  Widget _buildFolderFilters() {
    final preferences = _chatListPreferences;
    final folders = preferences?.folderNames.toList() ?? <String>[];
    folders.sort();
    return SizedBox(
      height: 58,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 5, 16, 9),
        children: [
          _folderFilterChip(
            title: 'Все',
            icon: Icons.chat_bubble_outline_rounded,
            selected: _selectedFolder == null,
            onTap: () => _selectFolder(null),
          ),
          for (final folder in folders)
            GestureDetector(
              onLongPress: () => _deleteChatFolder(folder),
              child: _folderFilterChip(
                title: folder,
                icon: Icons.folder_rounded,
                selected: _selectedFolder == folder,
                onTap: () => _selectFolder(folder),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Tooltip(
              message: 'Создать папку',
              child: Material(
                color: const Color(0xFF1B1829),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _createChatFolder,
                  child: const SizedBox(
                    width: 38,
                    height: 38,
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
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: Material(
        color: selected ? const Color(0xFF6728E8) : const Color(0xFF171525),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? const Color(0xFFB88CFF).withValues(alpha: 0.7)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? Colors.white : const Color(0xFFA9A4BD),
                ),
                const SizedBox(width: 7),
                Text(
                  title,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _selectFolder(String? folderName) {
    _saveCurrentScrollOffset();
    final nextViewKey = 'folder:${folderName ?? ''}';
    final currentOffset = _homeScrollController.hasClients
        ? _homeScrollController.position.pixels
        : 0.0;
    final nextOffset = _scrollOffsetByView[nextViewKey] ?? currentOffset;
    setState(() {
      _selectedFolder = folderName;
      _filteredChats = _filteredChatsForCurrentView(
        _searchController.text.trim().length >= 2 ? _searchController.text : '',
      );
    });
    _restoreScrollOffset(nextViewKey, nextOffset);
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
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Material(
        color: const Color(0xFF171426),
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          onTap: _toggleArchivedChats,
          borderRadius: BorderRadius.circular(17),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: const Color(0xFFB49AFF).withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF16C7C4), Color(0xFF159A9F)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    isArchive
                        ? Icons.arrow_back_rounded
                        : Icons.archive_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isArchive ? 'Все чаты' : 'Архив',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isArchive
                            ? 'Вернуться к основному списку'
                            : 'Скрытые чаты · $archivedCount',
                        style: TextStyle(
                          color: const Color(0xFFA7A2BC),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.32),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchUserAvatar(Map<String, dynamic> user) {
    final name = user['name']?.toString() ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final avatarUrl = user['avatar_url']?.toString();

    Widget fallback() => Center(
      child: Text(initial, style: const TextStyle(color: Colors.white)),
    );

    if (avatarUrl == null || avatarUrl.isEmpty) {
      return CircleAvatar(
        backgroundColor: Colors.deepPurple,
        child: fallback(),
      );
    }

    return CircleAvatar(
      backgroundColor: Colors.deepPurple,
      child: ClipOval(
        child: Image.network(
          avatarUrl,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('Не удалось загрузить аватар пользователя: $error');
            return fallback();
          },
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_isSearchingUsers) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF8A4DFF)),
      );
    }
    if (_filteredChats.isEmpty &&
        _userResults.isEmpty &&
        _groupResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF19172A),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.search_off, color: Colors.grey, size: 48),
            ),
            const SizedBox(height: 16),
            const Text(
              'Ничего не найдено',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        if (_groupResults.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
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
            (group) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF19172A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.white,
                    child: group.type == 'channel'
                        ? const Icon(
                            Icons.campaign_outlined,
                            color: Colors.black,
                          )
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
                          color: Color(0xFF8A4DFF),
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
            ),
          ),
        ],
        if (_userResults.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Пользователи',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ..._userResults.map(
            (user) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF19172A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: ListTile(
                  leading: _buildSearchUserAvatar(user),
                  title: Text(
                    user['name'] ?? 'Без имени',
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    '@${user['tag']}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  onTap: () => _openChatWithUser(
                    user['id'].toString(),
                    user['name']?.toString() ?? user['tag']?.toString() ?? '',
                    user['avatar_url']?.toString(),
                  ),
                ),
              ),
            ),
          ),
        ],
        if (_filteredChats.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              _userResults.isNotEmpty ? 16 : 12,
              16,
              8,
            ),
            child: const Text(
              'Чаты',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ..._filteredChats.indexed.map((entry) {
            final (index, chat) = entry;
            if (_currentUser == null) return const SizedBox.shrink();
            return ChatTile(
              key: ValueKey(chat.id),
              chat: chat,
              currentUser: _currentUser!,
              animationIndex: index,
              isPinned:
                  _chatListPreferences?.pinnedChatIds.contains(chat.id) ??
                  false,
              isMuted:
                  _chatListPreferences?.mutedChatIds.contains(chat.id) ?? false,
              onLongPress: () => _showChatActions(chat),
            );
          }),
        ],
      ],
    );
  }
}
