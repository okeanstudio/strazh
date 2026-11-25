import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/shared/domain/models/user.dart' as app;
import 'package:strazh/shared/presentation/widgets/toast.dart';
import 'package:strazh/core/utils/rpc_user.dart';
import 'package:strazh/core/utils/badges.dart';
import 'package:strazh/features/chat/data/services/user_status_service.dart';
import 'package:strazh/features/gifts/data/services/gift_service.dart';
import 'package:strazh/shared/presentation/widgets/avatar_preview.dart';
import 'package:strazh/shared/presentation/widgets/username_mention_text.dart';
import 'package:strazh/features/profile/data/services/profile_nft_decoration_service.dart';
import 'package:strazh/features/profile/presentation/widgets/profile_nft_decorations.dart';
import 'package:strazh/features/profile/presentation/widgets/profile_content_tabs.dart';
import 'package:strazh/features/stories/data/services/stories_service.dart';
import 'package:strazh/shared/domain/models/story.dart';
import 'package:strazh/features/chat/data/services/storage_upload_service.dart';
import 'package:strazh/features/profile/presentation/widgets/profile_music_card.dart';

Future<void> showUserProfile(
  BuildContext context, {
  required app.User user,
  VoidCallback? onAudioCall,
  VoidCallback? onVideoCall,
  ValueChanged<String>? onUsernameTap,
}) {
  final profile = ProfileDialog(
    user: user,
    onAudioCall: onAudioCall,
    onVideoCall: onVideoCall,
    onUsernameTap: onUsernameTap,
    fullScreen: MediaQuery.sizeOf(context).width < 600,
  );
  if (MediaQuery.sizeOf(context).width < 600) {
    return Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => profile));
  }
  return showDialog<void>(context: context, builder: (_) => profile);
}

class ProfileDialog extends StatefulWidget {
  final app.User user;
  final VoidCallback? onAudioCall;
  final VoidCallback? onVideoCall;
  final ValueChanged<String>? onUsernameTap;
  final bool fullScreen;

  const ProfileDialog({
    super.key,
    required this.user,
    this.onAudioCall,
    this.onVideoCall,
    this.onUsernameTap,
    this.fullScreen = false,
  });

  @override
  State<ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<ProfileDialog>
    with TickerProviderStateMixin {
  String? _currentStatus;
  RealtimeChannel? _statusChannel;
  Timer? _statusPollingTimer;
  String? _role;
  String? _badge;
  bool _isLoading = true;
  bool _isBot = false;
  bool _botVerified = false;

  // Полные данные пользователя
  String _name = '';
  String _tag = '';
  List<String> _additionalUsernames = [];
  String _bio = '';
  String _avatarUrl = '';
  String _email = '';
  String? _phone;
  String? _birthDate;
  String? _inviteCode;
  bool _hasSubscription = false;
  String? _profileMusicUrl;
  String? _profileMusicName;

  // Данные о пригласившем
  // ignore: unused_field
  String _invitedByCode = '';
  String _invitedByUserId = '';
  String _invitedByName = '';
  String _invitedByTag = '';
  bool _isLoadingInviter = false;

  // Подарки и статистика
  List<Map<String, dynamic>> _userGifts = [];
  Map<String, Map<int, String>> _profileDecorations = {
    'avatar': {},
    'name': {},
  };
  bool _isLoadingGifts = true;
  int _giftsCount = 0;
  List<Story> _userStories = [];
  bool _isLoadingStories = true;
  String? _storiesError;
  int _messagesCount = 0;

  late AnimationController _rainbowController;

  @override
  void initState() {
    super.initState();
    StoriesService.storiesRevision.addListener(_onStoriesChanged);
    _rainbowController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    _currentStatus = widget.user.status;
    _name = widget.user.name;
    _tag = widget.user.tag;
    _avatarUrl = widget.user.avatarUrl ?? '';
    _phone = widget.user.phone;
    _birthDate = widget.user.birthDate?.toIso8601String();
    _badge = widget.user.badge;
    _role = widget.user.role;
    _isBot = widget.user.isBot;
    _botVerified = widget.user.botVerified;
    _loadFullUserData();
    _subscribeToUserStatus();
  }

  @override
  void dispose() {
    StoriesService.storiesRevision.removeListener(_onStoriesChanged);
    _statusChannel?.unsubscribe();
    _statusPollingTimer?.cancel();
    _rainbowController.dispose();
    super.dispose();
  }

  void _onStoriesChanged() {
    _loadStories();
  }

  Map<String, dynamic>? _firstRow(dynamic response) {
    if (response == null) return null;
    if (response is List && response.isNotEmpty) {
      final first = response[0];
      if (first is Map) return Map<String, dynamic>.from(first);
    }
    if (response is Map<String, dynamic>) return response;
    if (response is Map) return Map<String, dynamic>.from(response);
    return null;
  }

  String _formatBirthDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return 'Не указан';
    final date = DateTime.tryParse(isoDate);
    if (date == null) return 'Не указан';
    const months = [
      '',
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
    final day = date.day;
    final month = months[date.month];
    final year = date.year;
    final now = DateTime.now();
    int age = now.year - date.year;
    if (now.month < date.month ||
        (now.month == date.month && now.day < date.day)) {
      age--;
    }
    String yearsWord;
    if (age % 10 == 1 && age % 100 != 11) {
      yearsWord = 'год';
    } else if ([2, 3, 4].contains(age % 10) &&
        ![12, 13, 14].contains(age % 100)) {
      yearsWord = 'года';
    } else {
      yearsWord = 'лет';
    }
    return '$day $month $year года ($age $yearsWord)';
  }

  String _formatPhoneForDisplay(String? phone) {
    if (phone == null || phone.isEmpty) return 'Не указан';
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length < 11) return phone;
    if (digits.length == 11 && digits.startsWith('7')) {
      return '+7 (${digits.substring(1, 4)}) ${digits.substring(4, 7)}-${digits.substring(7, 9)}-${digits.substring(9, 11)}';
    }
    return '+$digits';
  }

  Future<void> _loadFullUserData() async {
    try {
      final botRecord = await Supabase.instance.client
          .from('bots')
          .select('name, tag, description, avatar_url, is_verified')
          .eq('id', widget.user.id)
          .maybeSingle();
      if (botRecord != null) {
        if (!mounted) return;
        setState(() {
          _isBot = true;
          _botVerified = botRecord['is_verified'] == true;
          _name = botRecord['name'] as String? ?? widget.user.name;
          _tag = botRecord['tag'] as String? ?? widget.user.tag;
          _bio = botRecord['description'] as String? ?? '';
          _avatarUrl = botRecord['avatar_url'] as String? ?? '';
          _currentStatus = 'bot';
          _email = '';
          _role = 'bot';
          _isLoading = false;
        });
        return;
      }

      if (widget.user.isBot) {
        if (!mounted) return;
        setState(() {
          _isBot = true;
          _botVerified = widget.user.botVerified;
          _name = widget.user.name;
          _tag = widget.user.tag;
          _bio = widget.user.bio ?? '';
          _avatarUrl = widget.user.avatarUrl ?? '';
          _currentStatus = 'bot';
          _email = '';
          _role = 'bot';
          _isLoading = false;
        });
        return;
      }

      final response = await Supabase.instance.client.rpc(
        'get_user_by_id',
        params: {'p_id': widget.user.id},
      );

      debugPrint('📊 Данные пользователя (preview): $response');
      final userRecord = _firstRow(response);
      // fallback через старый хелпер если вдруг формат иной
      final normalized = userRecord ?? rpcUserRecord(response);
      if (normalized == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final rawMeta =
          (userRecord?['raw_user_meta_data'] as Map?) ??
          (normalized['raw_user_meta_data'] as Map?);
      final metadata = rawMeta != null
          ? Map<String, dynamic>.from(rawMeta)
          : Map<String, dynamic>.from(normalized);

      // Если _firstRow дал нам уже развернутый record, берем из него напрямую,
      // иначе из metadata
      final dynamic name =
          userRecord?['name'] ?? normalized['name'] ?? metadata['name'];
      final dynamic tag =
          userRecord?['tag'] ?? normalized['tag'] ?? metadata['tag'];
      final dynamic bio = metadata['bio'];
      final dynamic avatar = metadata['avatar_url'] ?? normalized['avatar_url'];
      final dynamic status = metadata['status'] ?? normalized['status'];
      final dynamic role = metadata['role'] ?? normalized['role'];
      final dynamic badge = metadata['badge'] ?? normalized['badge'];
      final dynamic email =
          userRecord?['email'] ?? metadata['email'] ?? normalized['email'];
      final dynamic phone =
          metadata['phone'] ?? normalized['phone'] ?? userRecord?['phone'];
      final dynamic birthDate =
          metadata['birth_date'] ??
          userRecord?['birth_date'] ??
          normalized['birth_date'];
      final dynamic inviteCode = metadata['invite_code'];
      final dynamic invitedByUserId = metadata['invited_by_user_id'];
      final dynamic invitedByCode = metadata['invited_by_code'];

      var additionalUsernames = <String>[];
      try {
        final rows = await Supabase.instance.client
            .from('user_additional_usernames')
            .select('username')
            .eq('user_id', widget.user.id)
            .order('created_at');
        additionalUsernames = rows
            .map((row) => row['username'] as String)
            .toList();
      } catch (error) {
        debugPrint('⚠️ Не удалось загрузить дополнительные юзернеймы: $error');
      }

      // Подписка как в ProfileScreen
      final subActive = metadata['subscription_active'] == true;
      final subExpiresRaw = metadata['subscription_expires_at'];
      bool subValid = false;
      if (subActive && subExpiresRaw != null) {
        if (subExpiresRaw.toString() == 'forever') {
          subValid = true;
        } else {
          final d = DateTime.tryParse(subExpiresRaw.toString());
          subValid = d != null && d.isAfter(DateTime.now());
        }
      }

      // Инвайтер - пробуем каноничный метод как в ProfileScreen
      String? inviterName;
      String? inviterTag;
      if (invitedByUserId != null && invitedByUserId.toString().isNotEmpty) {
        try {
          final inviterResp = await Supabase.instance.client.rpc(
            'get_my_inviter_profile',
          );
          final inviter = _firstRow(inviterResp);
          if (inviter != null) {
            inviterName = inviter['name'] as String?;
            inviterTag = inviter['tag'] as String?;
          }
        } catch (_) {}
        // fallback: прямой get_user_by_id если get_my_inviter_profile вернул пусто
        if ((inviterName == null || inviterName.isEmpty) &&
            invitedByUserId.toString() != widget.user.id) {
          try {
            final r = await Supabase.instance.client.rpc(
              'get_user_by_id',
              params: {'p_id': invitedByUserId.toString()},
            );
            final rec = _firstRow(r) ?? rpcUserRecord(r);
            if (rec != null) {
              inviterName = rec['name'] as String?;
              inviterTag = rec['tag'] as String?;
            }
          } catch (_) {}
        }
      }
      if ((inviterName == null || inviterName.isEmpty) &&
          invitedByCode != null &&
          invitedByCode.toString().isNotEmpty) {
        try {
          final r = await Supabase.instance.client.rpc(
            'get_user_by_invite_code',
            params: {'p_code': invitedByCode.toString()},
          );
          final rec = _firstRow(r);
          if (rec != null) {
            final m = rec['raw_user_meta_data'] as Map?;
            final mm = m != null
                ? Map<String, dynamic>.from(m)
                : <String, dynamic>{};
            inviterName = mm['name'] as String? ?? rec['name'] as String?;
            inviterTag = mm['tag'] as String? ?? rec['tag'] as String?;
          }
        } catch (_) {}
      }

      final storedMusicPath =
          metadata['profile_music_path'] as String? ??
          StorageUploadService.objectPathFromStorageUrl(
            'chat_files',
            metadata['profile_music_url'],
          );
      final storedMusicUrl = metadata['profile_music_url'] as String?;
      String? profileMusicUrl;
      var canViewProfileMusic =
          Supabase.instance.client.auth.currentUser?.id == widget.user.id;
      if (!canViewProfileMusic) {
        try {
          final result = await Supabase.instance.client.rpc(
            'can_view_profile_music',
            params: {'p_user_id': widget.user.id},
          );
          canViewProfileMusic = result == true;
        } catch (error) {
          debugPrint('Не удалось проверить видимость музыки профиля: $error');
        }
      }

      if (canViewProfileMusic) {
        if (storedMusicPath != null) {
          try {
            profileMusicUrl = await StorageUploadService.createSignedUrl(
              bucket: 'chat_files',
              path: storedMusicPath,
              expiresIn: 3600,
            );
          } catch (error) {
            debugPrint('Не удалось обновить ссылку на музыку профиля: $error');
            profileMusicUrl = storedMusicUrl;
          }
        } else {
          profileMusicUrl = storedMusicUrl;
        }
      }

      if (mounted) {
        setState(() {
          _name = (name as String?)?.isNotEmpty == true
              ? name as String
              : widget.user.name;
          _tag = (tag as String?)?.isNotEmpty == true
              ? tag as String
              : widget.user.tag;
          _additionalUsernames = additionalUsernames;
          _bio = (bio as String?) ?? '';
          _avatarUrl = (avatar as String?) ?? '';
          _currentStatus = (status as String?) ?? 'offline';
          _role = (role as String?) ?? widget.user.role ?? 'user';
          _badge = (badge as String?) ?? widget.user.badge;
          _email = (email as String?) ?? '';
          _phone = (phone as String?);
          _birthDate = birthDate?.toString();
          _inviteCode = (inviteCode as String?);
          _invitedByUserId = invitedByUserId?.toString() ?? '';
          _profileMusicUrl = profileMusicUrl?.trim();
          _profileMusicName = canViewProfileMusic
              ? (metadata['profile_music_name'] as String?)?.trim()
              : null;
          _invitedByCode = invitedByCode?.toString() ?? '';
          _invitedByName = inviterName ?? '';
          _invitedByTag = inviterTag ?? '';
          _hasSubscription = subValid;
          _isLoading = false;
        });
      }

      // Грузим подарки/сообщения параллельно
      _loadGifts();
      _loadStories();
      _loadMessagesCount();
    } catch (e) {
      debugPrint('⚠️ Ошибка загрузки данных пользователя (preview): $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStories() async {
    if (!mounted) return;
    setState(() {
      _isLoadingStories = true;
      _storiesError = null;
    });
    try {
      final stories = await StoriesService.getProfileStories(widget.user.id);
      if (!mounted) return;
      setState(() {
        _userStories = stories
          ..sort(
            (first, second) => second.createdAt.compareTo(first.createdAt),
          );
        _isLoadingStories = false;
      });
    } catch (error) {
      debugPrint('Не удалось загрузить истории профиля: $error');
      if (!mounted) return;
      setState(() {
        _storiesError = error.toString();
        _isLoadingStories = false;
      });
    }
  }

  Future<void> _loadGifts() async {
    try {
      final rows = await GiftService.getReceivedGifts(widget.user.id);
      if (!mounted) return;
      setState(() {
        _userGifts = List<Map<String, dynamic>>.from(rows);
        _giftsCount = _userGifts.length;
        _isLoadingGifts = false;
      });
      try {
        final decorations = await ProfileNftDecorationService.getForUser(
          widget.user.id,
        );
        if (mounted) setState(() => _profileDecorations = decorations);
      } catch (error) {
        debugPrint('Не удалось загрузить NFT-украшения профиля: $error');
      }
    } catch (e) {
      debugPrint('⚠️ Ошибка загрузки подарков preview: $e');
      if (mounted) setState(() => _isLoadingGifts = false);
    }
  }

  Map<String, dynamic>? _decorationGift(String placement, int slot) {
    final inventoryId = _profileDecorations[placement]?[slot];
    if (inventoryId == null) return null;
    for (final gift in _userGifts) {
      if (gift['id']?.toString() == inventoryId && gift['nft_serial'] != null) {
        return gift;
      }
    }
    return null;
  }

  Future<void> _openDecorationPicker() async {
    try {
      final decorations = await ProfileNftDecorationService.getForUser(
        widget.user.id,
      );
      if (!mounted) return;
      setState(() => _profileDecorations = decorations);
      await ProfileNftDecorationPicker.show(
        context: context,
        gifts: _userGifts,
        decorations: _profileDecorations,
        onChanged: (decorations) {
          if (mounted) setState(() => _profileDecorations = decorations);
        },
      );
    } catch (error) {
      debugPrint('Не удалось открыть украшения профиля: $error');
      if (mounted) Toast.error(context, 'Не удалось загрузить украшения');
    }
  }

  void _updateGiftAfterUpgrade(Map<String, dynamic> nft) {
    final inventoryId = nft['inventory_id']?.toString();
    if (inventoryId == null) return;
    final index = _userGifts.indexWhere(
      (gift) => gift['id']?.toString() == inventoryId,
    );
    if (index < 0) return;
    setState(() {
      _userGifts[index] = {..._userGifts[index], ...nft};
    });
  }

  void _updateGiftPin(Map<String, dynamic> pin) {
    final inventoryId = pin['inventory_id']?.toString();
    if (inventoryId == null) return;
    final index = _userGifts.indexWhere(
      (gift) => gift['id']?.toString() == inventoryId,
    );
    if (index < 0) return;
    setState(() {
      _userGifts[index] = {..._userGifts[index], ...pin};
      _userGifts.sort(_comparePinnedGifts);
    });
  }

  void _openMentionedUsername(String username) {
    final onUsernameTap = widget.onUsernameTap;
    if (onUsernameTap == null) return;
    Navigator.of(context).pop();
    onUsernameTap(username);
  }

  int _comparePinnedGifts(
    Map<String, dynamic> first,
    Map<String, dynamic> second,
  ) {
    final pinOrder = (second['is_pinned'] == true ? 1 : 0).compareTo(
      first['is_pinned'] == true ? 1 : 0,
    );
    if (pinOrder != 0) return pinOrder;
    final firstPinnedAt = DateTime.tryParse(
      first['pinned_at']?.toString() ?? '',
    );
    final secondPinnedAt = DateTime.tryParse(
      second['pinned_at']?.toString() ?? '',
    );
    if (firstPinnedAt != null && secondPinnedAt != null) {
      final pinDateOrder = secondPinnedAt.compareTo(firstPinnedAt);
      if (pinDateOrder != 0) return pinDateOrder;
    }
    final firstCreatedAt = DateTime.tryParse(
      first['created_at']?.toString() ?? '',
    );
    final secondCreatedAt = DateTime.tryParse(
      second['created_at']?.toString() ?? '',
    );
    if (firstCreatedAt == null || secondCreatedAt == null) return 0;
    return secondCreatedAt.compareTo(firstCreatedAt);
  }

  Future<void> _loadMessagesCount() async {
    try {
      final rows = await Supabase.instance.client
          .from('messages')
          .select('id')
          .eq('profile_id', widget.user.id);
      if (!mounted) return;
      setState(() => _messagesCount = rows.length);
    } catch (e) {
      debugPrint('⚠️ Не удалось загрузить счетчик сообщений preview: $e');
    }
  }

  // Резервный загрузчик инвайтера (используется внутри _loadFullUserData fallback)
  // ignore: unused_element
  Future<void> _loadInviterData() async {
    if (_invitedByUserId.isEmpty || _invitedByUserId == widget.user.id) return;
    setState(() => _isLoadingInviter = true);
    try {
      final response = await Supabase.instance.client.rpc(
        'get_user_by_id',
        params: {'p_id': _invitedByUserId},
      );
      final inviter = _firstRow(response) ?? rpcUserRecord(response);
      if (mounted && inviter != null) {
        final n = inviter['name'] as String? ?? 'Неизвестный';
        final t = inviter['tag'] as String? ?? '';
        if (n != _name || t != _tag) {
          setState(() {
            _invitedByName = n;
            _invitedByTag = t;
            _isLoadingInviter = false;
          });
        } else {
          setState(() {
            _invitedByUserId = '';
            _invitedByCode = '';
            _isLoadingInviter = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingInviter = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingInviter = false);
    }
  }

  Future<void> _subscribeToUserStatus() async {
    if (_isBot || widget.user.isBot || widget.user.id.isEmpty) return;
    try {
      _statusChannel?.unsubscribe();
      _startStatusPolling();
    } catch (e) {
      debugPrint('⚠️ Ошибка подписки на статус профиля: $e');
    }
  }

  void _startStatusPolling() {
    if (_isBot || widget.user.isBot) return;
    _statusPollingTimer?.cancel();
    _statusPollingTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted) return;
      try {
        final response = await Supabase.instance.client.rpc(
          'get_user_by_id',
          params: {'p_id': widget.user.id},
        );
        final rec = _firstRow(response) ?? rpcUserRecord(response);
        if (mounted && rec != null) {
          final meta = rec['raw_user_meta_data'] is Map
              ? Map<String, dynamic>.from(rec['raw_user_meta_data'] as Map)
              : <String, dynamic>{};
          setState(() {
            _name =
                (rec['name'] as String?) ?? meta['name'] as String? ?? _name;
            _tag = (rec['tag'] as String?) ?? meta['tag'] as String? ?? _tag;
            _bio = (meta['bio'] as String?) ?? _bio;
            _avatarUrl =
                (meta['avatar_url'] as String?) ??
                rec['avatar_url'] as String? ??
                _avatarUrl;
            _currentStatus =
                (meta['status'] as String?) ??
                rec['status'] as String? ??
                _currentStatus;
            _role =
                (meta['role'] as String?) ?? rec['role'] as String? ?? _role;
            _badge =
                (meta['badge'] as String?) ?? rec['badge'] as String? ?? _badge;
            _phone =
                (meta['phone'] as String?) ?? rec['phone'] as String? ?? _phone;
            _birthDate =
                (meta['birth_date'] ?? rec['birth_date'])?.toString() ??
                _birthDate;
            _email =
                (rec['email'] as String?) ?? meta['email'] as String? ?? _email;
          });
        }
      } catch (e) {
        debugPrint('⚠️ Ошибка опроса данных профиля: $e');
      }
    });
  }

  String _getStatusText(String? status) {
    return UserStatusService.getStatusText(
      UserStatusService.normalizeStatus(status),
    );
  }

  // —— Галочки/бейджи как в ProfileScreen ——
  Widget _buildRainbowIcon({double size = 22}) {
    return AnimatedBuilder(
      animation: _rainbowController,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: const [
              Colors.red,
              Colors.orange,
              Colors.yellow,
              Colors.green,
              Colors.blue,
              Colors.indigo,
              Colors.purple,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            transform: GradientRotation(_rainbowController.value * 2 * pi),
          ).createShader(bounds),
          child: Icon(Icons.verified, size: size, color: Colors.white),
        );
      },
    );
  }

  Widget _buildRoleIcon(String? role) {
    if (Badges.byId(_badge) != null) {
      return BadgeIcon(badgeId: _badge, size: 22);
    }
    switch (role) {
      case 'owner':
        return _buildRainbowIcon();
      case 'admin':
        return const Icon(Icons.verified, color: Colors.red, size: 22);
      case 'official':
        return const Icon(Icons.verified, color: Colors.blue, size: 22);
      case 'moderator':
        return const Icon(Icons.verified, color: Colors.green, size: 22);
      case 'banned':
        return const Icon(Icons.block, color: Colors.red, size: 22);
    }
    if (role == 'premium' || _hasSubscription) {
      return const Icon(Icons.verified, color: Color(0xFFFFD700), size: 22);
    }
    return const SizedBox.shrink();
  }

  bool _shouldShowVerification(String? role) {
    if (Badges.byId(_badge) != null) return true;
    return role == 'admin' ||
        role == 'official' ||
        role == 'moderator' ||
        role == 'owner' ||
        role == 'poop' ||
        role == 'premium' ||
        role == 'banned' ||
        _hasSubscription;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final isPhone = screenSize.width < 600;
    final screenPadding = MediaQuery.paddingOf(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final profileContent = Container(
      width: double.infinity,
      constraints: BoxConstraints(
        maxWidth: isPhone ? double.infinity : 420,
        maxHeight: isPhone ? screenSize.height : screenSize.height * 0.88,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF181818), Color(0xFF090909), Color(0xFF111111)],
        ),
        borderRadius: BorderRadius.circular(isPhone ? 0 : 28),
        border: isPhone ? null : Border.all(color: const Color(0xFF343434)),
        boxShadow: isPhone
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.7),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isPhone ? 0 : 28),
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                isPhone ? 20 : 24,
                (isPhone ? screenPadding.top : 0) + 30,
                isPhone ? 20 : 24,
                24 + bottomInset + (isPhone ? screenPadding.bottom : 0),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Аватарка с обводкой по роли
                  GestureDetector(
                    onTap: _avatarUrl.isEmpty
                        ? null
                        : () => showAvatarPreview(
                            context,
                            image: NetworkImage(_avatarUrl),
                          ),
                    child: ProfileNftAvatarOrbit(
                      gifts: [
                        for (var slot = 0; slot < 4; slot++)
                          ?_decorationGift('avatar', slot),
                      ],
                      child: Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              Colors.white,
                              Colors.white.withValues(alpha: 0.35),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.16),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(3),
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF090909),
                          ),
                          child: ClipOval(
                            child: _avatarUrl.isNotEmpty
                                ? Image.network(
                                    _avatarUrl,
                                    width: 106,
                                    height: 106,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => _buildInitials(),
                                  )
                                : _buildInitials(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Имя + галочка/бейдж как в profile_screen
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: ProfileNftNameDecoration(
                          gift: _decorationGift('name', 0),
                          child: Text(
                            _name.isNotEmpty ? _name : widget.user.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (!_isLoading && _shouldShowVerification(_role)) ...[
                        const SizedBox(width: 6),
                        _buildRoleIcon(_role),
                      ],
                      if (_isBot) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.smart_toy,
                          color: Colors.white70,
                          size: 20,
                        ),
                        if (_botVerified) ...[
                          const SizedBox(width: 3),
                          const Icon(
                            Icons.verified,
                            color: Color(0xFF1A73E8),
                            size: 20,
                          ),
                        ],
                      ],
                    ],
                  ),
                  if (Supabase.instance.client.auth.currentUser?.id ==
                      widget.user.id)
                    TextButton.icon(
                      onPressed: _openDecorationPicker,
                      icon: const Icon(Icons.auto_awesome, size: 17),
                      label: const Text('Украшения профиля'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                    ),
                  if (_profileMusicUrl != null &&
                      _profileMusicUrl!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ProfileMusicCard(
                      url: _profileMusicUrl!,
                      title: _profileMusicName?.isNotEmpty == true
                          ? _profileMusicName!
                          : 'Музыка профиля',
                    ),
                  ],
                  const SizedBox(height: 4),

                  // Тэг
                  GestureDetector(
                    onTap: () {
                      final tagToCopy = _tag.isNotEmpty
                          ? _tag
                          : widget.user.tag;
                      final usernames = [
                        if (tagToCopy.isNotEmpty) tagToCopy,
                        ..._additionalUsernames,
                      ];
                      final copiedUsernames = usernames.isEmpty
                          ? ''
                          : formatUsernameList(
                              usernames.first,
                              usernames.skip(1),
                            );
                      Clipboard.setData(ClipboardData(text: copiedUsernames));
                      Toast.success(context, 'Юзернеймы скопированы');
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF171717),
                        border: Border.all(color: const Color(0xFF393939)),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ЮЗЕРНЕЙМ',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          UsernameMentionText(
                            text: formatUsernameList(
                              _tag.isNotEmpty ? _tag : widget.user.tag,
                              _additionalUsernames,
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              height: 1.5,
                            ),
                            linkColor: Colors.white,
                            onUsernameTap: _openMentionedUsername,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Статус
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1C),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isBot ? Icons.smart_toy : Icons.circle,
                          color: Colors.white70,
                          size: _isBot ? 14 : 8,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isBot ? 'Чат-бот' : _getStatusText(_currentStatus),
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  if (!_isBot &&
                      (widget.onAudioCall != null ||
                          widget.onVideoCall != null)) ...[
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.onAudioCall != null)
                          _buildCallAction(
                            icon: Icons.call_rounded,
                            tooltip: 'Аудиозвонок',
                            onPressed: widget.onAudioCall!,
                          ),
                        if (widget.onAudioCall != null &&
                            widget.onVideoCall != null)
                          const SizedBox(width: 14),
                        if (widget.onVideoCall != null)
                          _buildCallAction(
                            icon: Icons.videocam_rounded,
                            tooltip: 'Видеозвонок',
                            onPressed: widget.onVideoCall!,
                          ),
                      ],
                    ),
                  ],

                  // Бейдж строкой если есть
                  if (Badges.byId(_badge) case final badge?) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: badge.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: badge.color.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          BadgeIcon(badgeId: _badge, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            Badges.byId(_badge)!.name,
                            style: TextStyle(
                              color: badge.color,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),
                  const Divider(color: Color(0xFF343434)),
                  const SizedBox(height: 14),

                  // Био
                  if (!_isBot && _bio.isNotEmpty) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'О себе',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF151515),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF343434)),
                      ),
                      child: UsernameMentionText(
                        text: _bio,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.4,
                        ),
                        linkColor: Colors.white,
                        onUsernameTap: _openMentionedUsername,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Инфо блок как в profile screen
                  _buildInfoBlock(),
                  const SizedBox(height: 14),

                  if (!_isBot) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            icon: Icons.card_giftcard,
                            color: Colors.white,
                            value: '$_giftsCount',
                            label: 'Подарков',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildStatCard(
                            icon: Icons.message,
                            color: Colors.white70,
                            value: '$_messagesCount',
                            label: 'Сообщений',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ProfileContentTabs(
                      stories: _userStories,
                      isLoadingStories: _isLoadingStories,
                      storiesError: _storiesError,
                      onRetryStories: _loadStories,
                      gifts: _userGifts,
                      isLoadingGifts: _isLoadingGifts,
                      canManageGifts:
                          Supabase.instance.client.auth.currentUser?.id ==
                          widget.user.id,
                      onGiftUpgraded: _updateGiftAfterUpgrade,
                      onGiftPinned: _updateGiftPin,
                      ownerId: widget.user.id,
                      ownerName: _name.isNotEmpty ? _name : widget.user.name,
                      ownerTag: _tag.isNotEmpty ? _tag : widget.user.tag,
                      ownerAvatarUrl: _avatarUrl,
                      canDeleteStories:
                          Supabase.instance.client.auth.currentUser?.id ==
                          widget.user.id,
                    ),
                  ],

                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFF242424),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Закрыть'),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: screenPadding.top + 6,
              right: 6,
              child: IconButton(
                tooltip: 'Закрыть профиль',
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF242424),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(42, 42),
                ),
                icon: const Icon(Icons.close_rounded, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
    if (widget.fullScreen) {
      return Scaffold(
        backgroundColor: const Color(0xFF090909),
        body: SafeArea(child: SizedBox.expand(child: profileContent)),
      );
    }
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: profileContent,
    );
  }

  Widget _buildCallAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton.filled(
      tooltip: tooltip,
      onPressed: () {
        Navigator.pop(context);
        onPressed();
      },
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xFF242424),
        foregroundColor: Colors.white,
        fixedSize: const Size(54, 54),
        shape: const CircleBorder(),
        side: const BorderSide(color: Color(0xFF505050)),
      ),
      icon: Icon(icon, size: 23),
    );
  }

  Widget _buildInfoBlock() {
    if (_isBot) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF151515),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF343434), width: 1),
        ),
        child: Column(
          children: [
            _buildInfoRow(
              icon: Icons.smart_toy_outlined,
              label: 'Тип',
              value: 'Чат-бот',
              iconBg: Colors.white10,
              iconColor: Colors.white70,
            ),
            const SizedBox(height: 10),
            _buildInfoRow(
              icon: Icons.description_outlined,
              label: 'Описание',
              value: _bio.isEmpty ? 'Описание не указано' : _bio,
              iconBg: Colors.white10,
              iconColor: Colors.white70,
            ),
            const SizedBox(height: 10),
            _buildInfoRow(
              icon: Icons.fingerprint,
              label: 'ID бота',
              value: widget.user.id,
              iconBg: Colors.white10,
              iconColor: Colors.white70,
              trailing: IconButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.user.id));
                  Toast.success(context, 'ID бота скопирован');
                },
                icon: const Icon(Icons.copy, color: Colors.grey, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ],
        ),
      );
    }

    final birth = _birthDate != null && _birthDate!.isNotEmpty
        ? _formatBirthDate(_birthDate)
        : (widget.user.birthDate != null
              ? _formatBirthDate(widget.user.birthDate!.toIso8601String())
              : 'Не указан');
    final phone = _formatPhoneForDisplay(_phone ?? widget.user.phone);
    final email = _email.isNotEmpty
        ? _email
        : (widget.user.email ?? 'Не указан');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF343434), width: 1),
      ),
      child: Column(
        children: [
          _buildInfoRow(
            icon: Icons.cake,
            label: 'День рождения',
            value: birth,
            iconBg: Colors.white10,
            iconColor: Colors.white70,
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            icon: Icons.phone,
            label: 'Телефон',
            value: phone,
            iconBg: Colors.white10,
            iconColor: Colors.white70,
          ),
          const SizedBox(height: 10),
          if (!_isBot)
            _buildInfoRow(
              icon: Icons.email,
              label: 'Email',
              value: email,
              iconBg: Colors.white10,
              iconColor: Colors.white70,
            ),
          if (_inviteCode != null && _inviteCode!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildInfoRow(
              icon: Icons.link,
              label: 'Код приглашения',
              value: _inviteCode!,
              iconBg: Colors.white10,
              iconColor: Colors.white70,
              trailing: IconButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _inviteCode!));
                  Toast.success(context, 'Код скопирован');
                },
                icon: const Icon(Icons.copy, color: Colors.grey, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ],
          if (_invitedByName.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildInfoRow(
              icon: Icons.person_add,
              label: 'Пригласил',
              value: '$_invitedByName (@$_invitedByTag)',
              iconBg: Colors.white10,
              iconColor: Colors.white70,
            ),
          ] else if (_invitedByUserId.isNotEmpty && _isLoadingInviter) ...[
            const SizedBox(height: 10),
            _buildInfoRow(
              icon: Icons.person_add,
              label: 'Пригласил',
              value: 'Загрузка...',
              iconBg: Colors.white10,
              iconColor: Colors.white70,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color color,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF343434), width: 1),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildInitials() {
    final initial = _name.isNotEmpty ? _name[0].toUpperCase() : '?';
    return Center(
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 36,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color iconBg = const Color(0xFF2A2A2A),
    Color iconColor = Colors.grey,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 1),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (trailing != null) ...[const SizedBox(width: 6), trailing],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
