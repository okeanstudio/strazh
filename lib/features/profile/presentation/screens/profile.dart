import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:strazh/features/auth/presentation/screens/auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';
import 'package:strazh/features/auth/data/services/auth_service.dart';
import 'package:strazh/features/gifts/data/services/gift_service.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';
import 'package:strazh/shared/presentation/widgets/avatar_preview.dart';
import 'package:strazh/features/profile/data/services/avatar_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:strazh/core/utils/badges.dart';
import 'package:strazh/features/profile/presentation/screens/edit_profile.dart';
import 'package:strazh/features/profile/presentation/screens/manage_usernames_screen.dart';
import 'package:strazh/features/profile/data/services/profile_nft_decoration_service.dart';
import 'package:strazh/features/profile/presentation/widgets/profile_nft_decorations.dart';
import 'package:strazh/features/profile/presentation/widgets/profile_content_tabs.dart';
import 'package:strazh/features/stories/data/services/stories_service.dart';
import 'package:strazh/shared/domain/models/story.dart';
import 'package:strazh/features/chat/data/services/storage_upload_service.dart';
import 'package:strazh/features/chat/data/services/username_chat_service.dart';
import 'package:strazh/features/chat/presentation/screens/chat.dart';
import 'package:strazh/shared/presentation/widgets/username_mention_text.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  late AnimationController _loadingAnimationController;

  final AuthService _authService = AuthService();

  String? _userName;
  String? _tag;
  List<String> _additionalUsernames = [];
  String? _phone;
  String? _birthDate;
  String? _inviteCode;
  String? _invitedBy;
  String? _invitedByTag;
  String? _role;
  String? _bio;
  String? _avatarUrl;
  String? _badge;
  bool _hasSubscription = false;
  bool _isLoading = true;
  bool _isUploadingAvatar = false;

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

  String _formatBirthDate(String? isoDate) {
    if (isoDate == null) return 'Не указан';
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

  String _formatPhoneForDisplay(String phone) {
    if (phone.isEmpty) return 'Не указан';
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length < 11) return phone;
    if (digits.length == 11 && digits.startsWith('7')) {
      return '+7 (${digits.substring(1, 4)}) ${digits.substring(4, 7)}-${digits.substring(7, 9)}-${digits.substring(9, 11)}';
    }
    return '+$digits';
  }

  Map<String, dynamic>? _firstRow(dynamic response) {
    if (response == null) return null;
    if (response is List && response.isNotEmpty) {
      final first = response[0];
      if (first is Map) {
        return Map<String, dynamic>.from(first);
      }
    }

    if (response is Map<String, dynamic>) {
      return response;
    }
    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }
    return null;
  }

  Future<void> _loadProfile() async {
    String? tag = _authService.getUserTag();

    if (tag == null || tag.isEmpty) {
      try {
        const storage = FlutterSecureStorage();
        tag = await storage.read(key: 'user_tag');
      } catch (e) {
        debugPrint('⚠️ Ошибка чтения user_tag: $e');
      }
    }

    debugPrint('🔍 Загрузка профиля, tag = $tag');

    if (tag == null || tag.isEmpty) {
      debugPrint('⚠️ Тег не найден — профиль не может быть загружен');
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

    try {
      final response = await Supabase.instance.client.rpc(
        'get_user_by_tag',
        params: {'p_tag': tag},
      );

      final userData = _firstRow(response);

      if (userData == null) {
        debugPrint('⚠️ Пользователь не найден по тегу: $tag');
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      debugPrint('🔎 RAW userData: $userData');

      final metadata =
          userData['raw_user_meta_data'] as Map<String, dynamic>? ?? {};
      final userId = userData['id'] as String?;

      debugPrint('🔎 RAW metadata: $metadata');

      var additionalUsernames = <String>[];
      if (userId != null) {
        try {
          final response = await Supabase.instance.client
              .from('user_additional_usernames')
              .select('username')
              .eq('user_id', userId)
              .order('created_at');
          additionalUsernames = response
              .map((row) => row['username'] as String)
              .toList();
        } catch (e) {
          debugPrint('⚠️ Не удалось загрузить дополнительные юзернеймы: $e');
        }
      }

      String? invitedByName;
      String? invitedByTag;
      final invitedByUserId = metadata['invited_by_user_id'] as String?;

      debugPrint('🔍 invited_by_user_id: $invitedByUserId');

      if (invitedByUserId != null && invitedByUserId.isNotEmpty) {
        try {
          final inviterResponse = await Supabase.instance.client.rpc(
            'get_my_inviter_profile',
          );
          final inviter = _firstRow(inviterResponse);
          if (inviter != null) {
            invitedByName = inviter['name'] as String?;
            invitedByTag = inviter['tag'] as String?;
          }
        } catch (e) {
          debugPrint('⚠️ Ошибка загрузки профиля пригласившего: $e');
        }
      }

      if (invitedByName == null || invitedByName.isEmpty) {
        final inviteCode = metadata['invited_by_code'] as String?;
        if (inviteCode != null && inviteCode.isNotEmpty) {
          try {
            final inviterByCodeResponse = await Supabase.instance.client.rpc(
              'get_user_by_invite_code',
              params: {'p_code': inviteCode},
            );
            final inviter = _firstRow(inviterByCodeResponse);
            if (inviter != null) {
              final inviterMetadata =
                  inviter['raw_user_meta_data'] as Map<String, dynamic>? ?? {};
              invitedByName = inviterMetadata['name'] as String?;
              invitedByTag = inviterMetadata['tag'] as String?;
            }
          } catch (e) {
            debugPrint('⚠️ Ошибка поиска пригласившего по коду: $e');
          }
        }
      }

      debugPrint('✅ Пригласивший: $invitedByName (@$invitedByTag)');

      int messagesCount = 0;
      if (userId != null) {
        try {
          final messagesResponse = await Supabase.instance.client
              .from('messages')
              .select('id')
              .eq('profile_id', userId);
          messagesCount = messagesResponse.length;
        } catch (e) {
          debugPrint('⚠️ Не удалось загрузить сообщения: $e');
        }
      }

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

      if (mounted) {
        setState(() {
          _userName = metadata['name'] as String?;
          _tag = metadata['tag'] as String? ?? tag;
          _additionalUsernames = additionalUsernames;
          _phone = userData['phone'] as String? ?? metadata['phone'] as String?;
          _inviteCode = metadata['invite_code'] as String?;
          _invitedBy = invitedByName;
          _invitedByTag = invitedByTag;
          _birthDate = metadata['birth_date'] as String?;
          _role = metadata['role'] as String? ?? 'user';
          _bio = metadata['bio'] as String?;
          _avatarUrl = metadata['avatar_url'] as String?;
          _badge = metadata['badge'] as String?;
          _hasSubscription = subValid;
          _messagesCount = messagesCount;
          _isLoading = false;
        });
      }

      await _loadUserGifts();
      await _loadUserStories(userId ?? _authService.currentUserId);
    } catch (e, stack) {
      debugPrint('❌ Ошибка загрузки профиля: $e');
      debugPrint('$stack');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadUserStories(String? userId) async {
    if (userId == null) {
      if (mounted) setState(() => _isLoadingStories = false);
      return;
    }
    if (mounted) {
      setState(() {
        _isLoadingStories = true;
        _storiesError = null;
      });
    }
    try {
      final stories = await StoriesService.getProfileStories(userId);
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

  Future<void> _loadUserGifts() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) {
        if (mounted) setState(() => _isLoadingGifts = false);
        return;
      }

      final response = await GiftService.getReceivedGifts(userId);
      if (mounted) {
        setState(() {
          _userGifts = List<Map<String, dynamic>>.from(response);
          _giftsCount = _userGifts.length;
          _isLoadingGifts = false;
        });
      }
      try {
        final decorations = await ProfileNftDecorationService.getForUser(
          userId,
        );
        if (mounted) setState(() => _profileDecorations = decorations);
      } catch (error) {
        debugPrint('Не удалось загрузить NFT-украшения профиля: $error');
      }
    } catch (e) {
      debugPrint('⚠️ Ошибка загрузки подарков: $e');
      if (mounted) {
        setState(() => _isLoadingGifts = false);
      }
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
    final userId = _authService.currentUserId;
    if (userId == null) return;
    try {
      final decorations = await ProfileNftDecorationService.getForUser(userId);
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

  Future<void> _pickAvatar(ImageSource source) async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      Toast.error(context, 'Вы не авторизованы! Войдите заново');
      return;
    }

    final image = await AvatarService.pickImage(
      context: context,
      source: source,
    );

    if (image == null) return;

    if (!mounted) return;
    setState(() => _isUploadingAvatar = true);

    try {
      final userId = _authService.currentUserId;
      if (userId == null) {
        Toast.error(context, 'Ошибка: пользователь не найден');
        setState(() => _isUploadingAvatar = false);
        return;
      }

      final bytes = await image.readAsBytes();
      final extension = image.path.split('.').last.toLowerCase();
      final safeExtension = extension.isEmpty ? 'jpg' : extension;
      final fileName =
          '$userId/${DateTime.now().millisecondsSinceEpoch}.$safeExtension';
      await StorageUploadService.uploadBinary(
        bucket: 'avatars',
        path: fileName,
        bytes: bytes,
        contentType: safeExtension == 'png' ? 'image/png' : 'image/jpeg',
        onProgress: (_, _) {},
      );

      final publicUrl = await StorageUploadService.getPublicUrl(
        bucket: 'avatars',
        path: fileName,
      );

      final currentMetadata = session.user.userMetadata ?? {};
      currentMetadata['avatar_url'] = publicUrl;

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: currentMetadata),
      );

      if (mounted) {
        setState(() {
          _avatarUrl = publicUrl;
          _isUploadingAvatar = false;
        });
        Toast.success(context, 'Аватарка обновлена');
      }
    } catch (e) {
      debugPrint('❌ Ошибка загрузки аватарки: $e');
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
        Toast.error(context, 'Ошибка загрузки аватарки: $e');
      }
    }
  }

  Future<void> _deleteAvatar() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1428),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Удалить аватарку?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Аватарка будет сброшена на стандартную',
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
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isUploadingAvatar = true);

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return;

      final currentMetadata = session.user.userMetadata ?? {};
      currentMetadata['avatar_url'] = null;

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: currentMetadata),
      );

      if (mounted) {
        setState(() {
          _avatarUrl = null;
          _isUploadingAvatar = false;
        });
        Toast.success(context, 'Аватарка удалена');
      }
    } catch (e) {
      debugPrint('Ошибка удаления аватарки: $e');
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
        Toast.error(context, 'Ошибка удаления аватарки');
      }
    }
  }

  void _showAvatarPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Фото профиля',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildPickerOption(
                      icon: Icons.photo_library,
                      label: 'Галерея',
                      onTap: () {
                        Navigator.pop(context);
                        _pickAvatar(ImageSource.gallery);
                      },
                    ),
                    _buildPickerOption(
                      icon: Icons.photo_camera,
                      label: 'Камера',
                      onTap: () {
                        Navigator.pop(context);
                        _pickAvatar(ImageSource.camera);
                      },
                    ),
                    if (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                      _buildPickerOption(
                        icon: Icons.delete_outline,
                        label: 'Удалить',
                        onTap: () {
                          Navigator.pop(context);
                          _deleteAvatar();
                        },
                        isDestructive: true,
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPickerOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isDestructive
                  ? Colors.red.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isDestructive ? Colors.red : Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: isDestructive ? Colors.red : Colors.grey[400],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();

    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut),
    );

    _loadingAnimationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _loadingAnimationController.dispose();
    super.dispose();
  }

  Future<void> _openEditProfile() async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EditProfileScreen(
          initialName: _userName ?? '',
          initialTag: _tag ?? '',
          initialPhone: _phone ?? '',
          initialEmail: _authService.getCurrentUser()?.email ?? '',
          initialBio: _bio ?? '',
          initialBirthDate: _birthDate,
        ),
      ),
    );
    if (updated == true && mounted) await _loadProfile();
  }

  Future<void> _openUsernameManager() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const ManageUsernamesScreen()),
    );
    if (mounted) await _loadProfile();
  }

  Future<void> _openUsernameChat(String username) async {
    try {
      final currentUser = _authService.getCurrentUserFromMetadata();
      if (currentUser == null) {
        if (!mounted) return;
        Toast.error(context, 'Не удалось определить текущего пользователя');
        return;
      }

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
              ChatScreen(chat: result.chat, currentUser: currentUser),
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

  Widget _buildRainbowIcon() {
    return AnimatedBuilder(
      animation: _loadingAnimationController,
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
            transform: GradientRotation(
              _loadingAnimationController.value * 2 * pi,
            ),
          ).createShader(bounds),
          child: const Icon(Icons.verified, size: 20, color: Colors.white),
        );
      },
    );
  }

  Widget _buildRoleIcon(String? role) {
    final badge = Badges.byId(_badge);
    if (badge != null) {
      return BadgeIcon(badgeId: _badge, size: 20);
    }

    switch (role) {
      case 'owner':
        return _buildRainbowIcon();
      case 'admin':
        return const Icon(Icons.verified, color: Colors.red, size: 20);
      case 'official':
        return const Icon(Icons.verified, color: Colors.blue, size: 20);
      case 'moderator':
        return const Icon(Icons.verified, color: Colors.green, size: 20);
      case 'banned':
        return const Icon(Icons.block, color: Colors.red, size: 20);
    }

    if (role == 'premium' || _hasSubscription) {
      return const Icon(Icons.verified, color: Color(0xFFFFD700), size: 20);
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = viewportWidth >= 900;
    final avatarOrbitSize = (viewportWidth - 48).clamp(260.0, 310.0);
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
        backgroundColor: const Color(0xFF090515),
        appBar: isDesktop
            ? null
            : AppBar(
                backgroundColor: const Color(0xFF090515),
                elevation: 0,
                centerTitle: true,
                title: const Text(
                  'Профиль',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                actions: [
                  IconButton(
                    onPressed: _openEditProfile,
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: Colors.white,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(
                        0xFF171329,
                      ).withValues(alpha: 0.9),
                      side: BorderSide(
                        color: const Color(0xFF9B5CFF).withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ],
              ),
        body: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF090515),
                      Color(0xFF100725),
                      Color(0xFF080512),
                    ],
                    stops: [0, 0.52, 1],
                  ),
                ),
                child: CustomPaint(painter: _ProfileBackdropPainter()),
              ),
            ),
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(color: Color(0xFF9B5CFF)),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final contentMaxWidth = constraints.maxWidth >= 900
                      ? 920.0
                      : constraints.maxWidth;
                  return SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: constraints.maxWidth >= 900 ? 32 : 20,
                      vertical: 18,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: contentMaxWidth),
                        child: Column(
                          children: [
                            if (isDesktop)
                              Align(
                                alignment: Alignment.centerRight,
                                child: IconButton(
                                  tooltip: 'Редактировать профиль',
                                  onPressed: _openEditProfile,
                                  icon: const Icon(
                                    Icons.settings_outlined,
                                    color: Colors.white,
                                  ),
                                  style: IconButton.styleFrom(
                                    backgroundColor: const Color(
                                      0xFF171329,
                                    ).withValues(alpha: 0.9),
                                    side: BorderSide(
                                      color: const Color(
                                        0xFF9B5CFF,
                                      ).withValues(alpha: 0.3),
                                    ),
                                  ),
                                ),
                              ),
                            Center(
                              child: GestureDetector(
                                onTap: () {
                                  final url = _avatarUrl;
                                  if (url != null && url.isNotEmpty) {
                                    showAvatarPreview(
                                      context,
                                      image: NetworkImage(url),
                                    );
                                  } else {
                                    _showAvatarPicker();
                                  }
                                },
                                child: ProfileNftAvatarOrbit(
                                  size: avatarOrbitSize,
                                  gifts: [
                                    for (var slot = 0; slot < 4; slot++)
                                      if (_decorationGift('avatar', slot)
                                          case final gift?)
                                        gift,
                                  ],
                                  child: Stack(
                                    alignment: Alignment.bottomRight,
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFFD8B5FF),
                                              Color(0xFF8A35FF),
                                              Color(0xFF4A14B8),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(
                                                0xFF9B5CFF,
                                              ).withValues(alpha: 0.5),
                                              blurRadius: 34,
                                              spreadRadius: 2,
                                            ),
                                          ],
                                        ),
                                        padding: const EdgeInsets.all(5),
                                        child: CircleAvatar(
                                          radius: 71,
                                          backgroundColor: const Color(
                                            0xFF100B1D,
                                          ),
                                          backgroundImage:
                                              _avatarUrl != null &&
                                                  _avatarUrl!.isNotEmpty
                                              ? NetworkImage(_avatarUrl!)
                                              : null,
                                          child:
                                              _avatarUrl == null ||
                                                  _avatarUrl!.isEmpty
                                              ? Text(
                                                  _userName != null &&
                                                          _userName!.isNotEmpty
                                                      ? _userName![0]
                                                            .toUpperCase()
                                                      : '?',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 52,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                )
                                              : null,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF090515),
                                          shape: BoxShape.circle,
                                        ),
                                        child: GestureDetector(
                                          onTap: _showAvatarPicker,
                                          child: Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: const BoxDecoration(
                                              color: Color(0xFF7442F5),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.edit,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (_isUploadingAvatar)
                                        Positioned.fill(
                                          child: Container(
                                            decoration: const BoxDecoration(
                                              color: Colors.black54,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Center(
                                              child: SizedBox(
                                                width: 30,
                                                height: 30,
                                                child:
                                                    CircularProgressIndicator(
                                                      color: Colors.white,
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: ProfileNftNameDecoration(
                                    gift: _decorationGift('name', 0),
                                    child: Text(
                                      _userName ?? 'Имя',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 30,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                _buildRoleIcon(_role),
                              ],
                            ),

                            TextButton.icon(
                              onPressed: _openDecorationPicker,
                              icon: const Icon(Icons.auto_awesome, size: 17),
                              label: const Text('Украшения профиля'),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFFB974FF),
                                textStyle: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),

                            const SizedBox(height: 4),

                            GestureDetector(
                              onTap: () {
                                final usernames = [
                                  if (_tag?.isNotEmpty == true) _tag!,
                                  ..._additionalUsernames,
                                ];
                                final copiedUsernames = usernames.isEmpty
                                    ? ''
                                    : formatUsernameList(
                                        usernames.first,
                                        usernames.skip(1),
                                      );
                                Clipboard.setData(
                                  ClipboardData(text: copiedUsernames),
                                );
                                if (mounted) {
                                  Toast.success(
                                    context,
                                    'Юзернеймы скопированы',
                                  );
                                }
                              },
                              child: Container(
                                width: double.infinity,
                                constraints: const BoxConstraints(
                                  maxWidth: 420,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF171329),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: const Color(
                                      0xFF9B5CFF,
                                    ).withValues(alpha: 0.24),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Expanded(
                                          child: Text(
                                            'ЮЗЕРНЕЙМ',
                                            style: TextStyle(
                                              color: Color(0xFF9B8CB8),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 1.1,
                                            ),
                                          ),
                                        ),
                                        TextButton.icon(
                                          onPressed: _openUsernameManager,
                                          icon: const Icon(
                                            Icons.add_circle_outline,
                                            size: 16,
                                          ),
                                          label: const Text('Управлять'),
                                          style: TextButton.styleFrom(
                                            foregroundColor: const Color(
                                              0xFFBDA4FF,
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                            textStyle: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    UsernameMentionText(
                                      text: formatUsernameList(
                                        _tag ?? 'username',
                                        _additionalUsernames,
                                      ),
                                      style: const TextStyle(
                                        color: Color(0xFFD1C2EF),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        height: 1.5,
                                      ),
                                      linkColor: const Color(0xFFD1C2EF),
                                      onUsernameTap: _openUsernameChat,
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            if (_bio != null && _bio!.isNotEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF171329,
                                  ).withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(
                                      0xFF9B5CFF,
                                    ).withValues(alpha: 0.2),
                                    width: 1,
                                  ),
                                ),
                                child: UsernameMentionText(
                                  text: _bio!,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 15,
                                    height: 1.5,
                                  ),
                                  linkColor: const Color(0xFF91B9FF),
                                  onUsernameTap: _openUsernameChat,
                                  textAlign: TextAlign.center,
                                ),
                              ),

                            if (_bio != null && _bio!.isNotEmpty)
                              const SizedBox(height: 16),

                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF171329,
                                ).withValues(alpha: 0.94),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(
                                    0xFF9B5CFF,
                                  ).withValues(alpha: 0.24),
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.pink.withValues(
                                            alpha: 0.2,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.cake,
                                          color: Colors.pink,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'День рождения',
                                              style: TextStyle(
                                                color: const Color(0xFFAAA0BF),
                                                fontSize: 12,
                                              ),
                                            ),
                                            Text(
                                              _formatBirthDate(_birthDate),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withValues(
                                            alpha: 0.2,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.phone,
                                          color: Colors.green,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Номер телефона',
                                              style: TextStyle(
                                                color: const Color(0xFFAAA0BF),
                                                fontSize: 12,
                                              ),
                                            ),
                                            Text(
                                              _phone != null &&
                                                      _phone!.isNotEmpty
                                                  ? _formatPhoneForDisplay(
                                                      _phone!,
                                                    )
                                                  : 'Не указан',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withValues(
                                            alpha: 0.2,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.link,
                                          color: Colors.blue,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Код приглашения',
                                              style: TextStyle(
                                                color: const Color(0xFFAAA0BF),
                                                fontSize: 12,
                                              ),
                                            ),
                                            Row(
                                              children: [
                                                Text(
                                                  _inviteCode ?? 'Не указан',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                if (_inviteCode != null)
                                                  IconButton(
                                                    onPressed: () {
                                                      Clipboard.setData(
                                                        ClipboardData(
                                                          text: _inviteCode!,
                                                        ),
                                                      );
                                                      if (mounted) {
                                                        Toast.success(
                                                          context,
                                                          'Код приглашения скопирован',
                                                        );
                                                      }
                                                    },
                                                    icon: const Icon(
                                                      Icons.copy,
                                                      color: const Color(
                                                        0xFFAAA0BF,
                                                      ),
                                                      size: 18,
                                                    ),
                                                    padding: EdgeInsets.zero,
                                                    constraints:
                                                        const BoxConstraints(),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.purple.withValues(
                                            alpha: 0.2,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.person_add,
                                          color: Colors.purple,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Пригласил',
                                              style: TextStyle(
                                                color: Colors.grey,
                                                fontSize: 12,
                                              ),
                                            ),
                                            Text(
                                              _invitedBy != null &&
                                                      _invitedBy!.isNotEmpty
                                                  ? '$_invitedBy (@${_invitedByTag ?? ''})'
                                                  : 'Сам зарегистрировался',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF171329,
                                      ).withValues(alpha: 0.94),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: const Color(
                                          0xFF9B5CFF,
                                        ).withValues(alpha: 0.24),
                                        width: 1,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFFFFD700,
                                            ).withValues(alpha: 0.15),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.card_giftcard,
                                            color: Color(0xFFFFD700),
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '$_giftsCount',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const Text(
                                          'Подарков',
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF171329,
                                      ).withValues(alpha: 0.94),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: const Color(
                                          0xFF9B5CFF,
                                        ).withValues(alpha: 0.24),
                                        width: 1,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFF9B5CFF,
                                            ).withValues(alpha: 0.15),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.message,
                                            color: const Color(0xFFB974FF),
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '$_messagesCount',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const Text(
                                          'Сообщений',
                                          style: TextStyle(
                                            color: const Color(0xFFAAA0BF),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),
                            ProfileContentTabs(
                              stories: _userStories,
                              isLoadingStories: _isLoadingStories,
                              storiesError: _storiesError,
                              onRetryStories: () =>
                                  _loadUserStories(_authService.currentUserId),
                              gifts: _userGifts,
                              isLoadingGifts: _isLoadingGifts,
                              canManageGifts: true,
                              onGiftUpgraded: _updateGiftAfterUpgrade,
                              onGiftPinned: _updateGiftPin,
                              ownerId: _authService.currentUserId ?? '',
                              ownerName: _userName ?? '',
                              ownerTag: _tag ?? '',
                              ownerAvatarUrl: _avatarUrl ?? '',
                            ),

                            const SizedBox(height: 24),

                            SizedBox(
                              width: double.infinity,
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  backgroundColor: Colors.red.withValues(
                                    alpha: 0.1,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(
                                      color: Colors.red.withValues(alpha: 0.2),
                                      width: 1,
                                    ),
                                  ),
                                ),
                                onPressed: () async {
                                  await _authService.logout();
                                  if (mounted) {
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const AuthScreen(),
                                      ),
                                    );
                                  }
                                },
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.logout,
                                      color: Colors.red,
                                      size: 22,
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      'Выйти из аккаунта',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.red,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ProfileBackdropPainter extends CustomPainter {
  const _ProfileBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final ribbonPaint = Paint()
      ..color = const Color(0xFF7027E8).withValues(alpha: 0.13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 34
      ..strokeCap = StrokeCap.round;
    final glowPaint = Paint()
      ..color = const Color(0xFFB05CFF).withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final upperRibbon = Path()
      ..moveTo(-size.width * 0.2, size.height * 0.28)
      ..cubicTo(
        size.width * 0.2,
        size.height * 0.04,
        size.width * 0.48,
        size.height * 0.48,
        size.width * 0.76,
        size.height * 0.22,
      )
      ..cubicTo(
        size.width * 0.94,
        size.height * 0.06,
        size.width * 1.05,
        size.height * 0.36,
        size.width * 1.2,
        size.height * 0.24,
      );
    final lowerRibbon = Path()
      ..moveTo(-size.width * 0.2, size.height * 0.83)
      ..cubicTo(
        size.width * 0.18,
        size.height * 0.7,
        size.width * 0.55,
        size.height * 1.04,
        size.width * 0.82,
        size.height * 0.79,
      )
      ..cubicTo(
        size.width * 1.02,
        size.height * 0.62,
        size.width * 1.08,
        size.height * 0.94,
        size.width * 1.2,
        size.height * 0.78,
      );

    canvas.drawPath(upperRibbon, ribbonPaint);
    canvas.drawPath(lowerRibbon, ribbonPaint);
    canvas.drawPath(upperRibbon, glowPaint);
    canvas.drawPath(lowerRibbon, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _ProfileBackdropPainter oldDelegate) => false;
}
