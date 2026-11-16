import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:strazh/features/profile/data/services/avatar_service.dart';
import 'package:strazh/shared/presentation/widgets/avatar_preview.dart';
import 'package:strazh/features/chat/data/services/storage_upload_service.dart';

class ChatInfoWidget extends StatefulWidget {
  final String chatId;
  final String currentUserId;

  const ChatInfoWidget({
    super.key,
    required this.chatId,
    required this.currentUserId,
  });

  @override
  State<ChatInfoWidget> createState() => _ChatInfoWidgetState();
}

class _ChatInfoWidgetState extends State<ChatInfoWidget> {
  Map<String, dynamic>? _chatData;
  List<Map<String, dynamic>> _participants = [];
  List<Map<String, dynamic>> _availableUsers = [];
  bool _isLoading = true;
  bool _isOwner = false;
  bool _isAdmin = false;
  bool _isEditing = false;
  bool _isPrivate = false;
  bool _isActionLoading = false;
  Uint8List? _avatarBytes;

  bool get _isChannel => _chatData?['type'] == 'channel';

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  static const Color _bg = Color(0xFF0D0A0A);
  static const Color _card = Color(0xFF1A1A1A);
  static const Color _cardLight = Color(0xFF2A2A2A);
  static const Color _border = Color(0xFF333333);
  static const Color _textPrimary = Colors.white;
  static const Color _textSecondary = Color(0xFF9E9E9E);
  static const Color _textMuted = Color(0xFF6E6E6E);

  @override
  void initState() {
    super.initState();
    _loadChatInfo();
  }

  Future<void> _loadChatInfo() async {
    try {
      final chatResponse = await Supabase.instance.client
          .from('rooms')
          .select()
          .eq('id', widget.chatId)
          .maybeSingle();

      final isOwner = chatResponse?['created_by'] == widget.currentUserId;

      final participantRows = await Supabase.instance.client
          .from('room_participants')
          .select('user_id, role')
          .eq('room_id', widget.chatId);
      final profileIds = participantRows
          .map((row) => row['user_id'] as String)
          .toList();

      final allUsers = await Supabase.instance.client.rpc('get_all_users');
      final profilesById = <String, Map<String, dynamic>>{};
      if (allUsers is List) {
        for (final user in allUsers) {
          if (profileIds.contains(user['id'])) {
            profilesById[user['id'] as String] = Map<String, dynamic>.from(
              user as Map,
            );
          }
        }
      }

      final participantsResponse = participantRows
          .map(
            (row) => {
              'user_id': row['user_id'],
              'role': row['role'] ?? 'member',
              'users': profilesById[row['user_id']],
            },
          )
          .where((participant) => participant['users'] != null)
          .toList();

      if (mounted) {
        setState(() {
          _chatData = chatResponse;
          _participants = List.from(participantsResponse);
          _isOwner = isOwner;
          _isAdmin =
              isOwner ||
              participantRows.any(
                (row) =>
                    row['user_id'] == widget.currentUserId &&
                    row['role'] == 'admin',
              );
          _isPrivate = chatResponse?['is_private'] == true;
          _isLoading = false;
          _nameController.text = chatResponse?['name'] ?? '';
          _tagController.text = chatResponse?['tag'] ?? '';
          _descriptionController.text = chatResponse?['description'] ?? '';
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAvailableUsers() async {
    try {
      final allUsers = await Supabase.instance.client.rpc('get_all_users');
      if (mounted && allUsers is List) {
        final filtered = allUsers
            .where((user) => user['id'] != widget.currentUserId)
            .toList();
        setState(() {
          _availableUsers = List<Map<String, dynamic>>.from(
            filtered.map((u) => Map<String, dynamic>.from(u as Map)),
          );
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки пользователей: $e');
    }
  }

  Future<void> _pickAvatar() async {
    final file = await AvatarService.pickImage(
      context: context,
      source: ImageSource.gallery,
    );
    if (file != null) {
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _avatarBytes = bytes);
    }
  }

  Future<String?> _uploadAvatar() async {
    if (_avatarBytes == null) return _chatData?['avatar_url'] as String?;
    try {
      final fileName =
          'group_avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final bucket = _isChannel ? 'channel_avatars' : 'group_avatars';
      final filePath = '${widget.currentUserId}/$fileName';
      await StorageUploadService.uploadBinary(
        bucket: bucket,
        path: filePath,
        bytes: _avatarBytes!,
        contentType: 'image/jpeg',
        onProgress: (_, _) {},
      );

      return await StorageUploadService.getPublicUrl(
        bucket: bucket,
        path: filePath,
      );
    } catch (e) {
      debugPrint('Ошибка загрузки аватарки: $e');
      return _chatData?['avatar_url'] as String?;
    }
  }

  Future<void> _updateGroupInfo() async {
    final name = _nameController.text.trim();
    final tag = _isPrivate
        ? ''
        : _tagController.text.trim().replaceFirst('@', '');
    final description = _descriptionController.text.trim();

    if (name.length < 2) return;
    if (!_isPrivate && tag.isEmpty) {
      _showError(
        'Для открытого ${_isChannel ? 'канала' : 'группы'} укажите тег',
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final avatarUrl = await _uploadAvatar();
      await Supabase.instance.client.rpc(
        'update_room_settings',
        params: {
          'p_room_id': widget.chatId,
          'p_name': name,
          'p_tag': _isPrivate ? null : tag,
          'p_description': description,
          'p_is_private': _isPrivate,
          'p_avatar_url': avatarUrl,
        },
      );

      if (mounted) {
        setState(() {
          _chatData?['name'] = name;
          _chatData?['tag'] = _isPrivate ? null : tag;
          _chatData?['description'] = description;
          _chatData?['is_private'] = _isPrivate;
          _chatData?['avatar_url'] = avatarUrl;
          _avatarBytes = null;
          _isLoading = false;
          _isEditing = false;
        });
      }
    } catch (e) {
      debugPrint('Ошибка обновления: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _removeParticipant(String profileId) async {
    try {
      await Supabase.instance.client.rpc(
        'remove_room_member',
        params: {'p_room_id': widget.chatId, 'p_user_id': profileId},
      );

      if (mounted) {
        setState(() {
          _participants.removeWhere((p) => p['user_id'] == profileId);
        });
      }
      return true;
    } catch (e) {
      debugPrint('Ошибка удаления участника: $e');
      if (mounted) _showError('Не удалось удалить участника');
      return false;
    }
  }

  Future<void> _addParticipant(String profileId) async {
    try {
      await Supabase.instance.client.rpc(
        'add_room_member',
        params: {'p_room_id': widget.chatId, 'p_user_id': profileId},
      );

      if (mounted) {
        setState(() {
          _participants.add({
            'user_id': profileId,
            'role': 'member',
            'users': _availableUsers.firstWhere((u) => u['id'] == profileId),
          });
        });
      }
    } catch (e) {
      debugPrint('Ошибка добавления участника: $e');
      if (mounted) _showError('Не удалось добавить участника');
    }
  }

  Future<bool> _setParticipantRole(String profileId, String role) async {
    try {
      await Supabase.instance.client.rpc(
        'set_room_member_role',
        params: {
          'p_room_id': widget.chatId,
          'p_user_id': profileId,
          'p_role': role,
        },
      );
      if (mounted) {
        setState(() {
          final index = _participants.indexWhere(
            (participant) => participant['user_id'] == profileId,
          );
          if (index != -1) _participants[index]['role'] = role;
        });
      }
      return true;
    } catch (error) {
      debugPrint('Ошибка изменения роли: $error');
      if (mounted) _showError('Не удалось изменить роль участника');
      return false;
    }
  }

  Future<void> _deleteGroup() async {
    if (_isActionLoading) return;
    setState(() => _isActionLoading = true);
    try {
      await Supabase.instance.client
          .from('rooms')
          .delete()
          .eq('id', widget.chatId);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Ошибка удаления группы: $e');
      if (mounted) {
        setState(() => _isActionLoading = false);
        _showError('Не удалось удалить группу');
      }
    }
  }

  Future<void> _leaveGroup() async {
    try {
      await Supabase.instance.client.rpc(
        'remove_room_member',
        params: {'p_room_id': widget.chatId, 'p_user_id': widget.currentUserId},
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Ошибка выхода: $e');
      if (mounted) _showError('Не удалось выйти из комнаты');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: _cardLight),
    );
  }

  void _cancelGroupEdit() {
    final chat = _chatData;
    if (chat != null) {
      _nameController.text = chat['name']?.toString() ?? '';
      _tagController.text = chat['tag']?.toString() ?? '';
      _descriptionController.text = chat['description']?.toString() ?? '';
      _isPrivate = chat['is_private'] == true;
    }
    setState(() => _isEditing = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tagController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final dialogHeight = screenHeight * 0.85;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 500,
        height: dialogHeight,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _border, width: 1),
        ),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ===== АВАТАР =====
                    Center(
                      child: GestureDetector(
                        onTap: () {
                          if (_isAdmin && _isEditing) {
                            _pickAvatar();
                            return;
                          }
                          final bytes = _avatarBytes;
                          final url = _chatData?['avatar_url'] as String?;
                          if (bytes != null) {
                            showAvatarPreview(
                              context,
                              image: MemoryImage(bytes),
                            );
                          } else if (url != null && url.isNotEmpty) {
                            showAvatarPreview(
                              context,
                              image: NetworkImage(url),
                            );
                          }
                        },
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: _border, width: 1),
                              ),
                              child: CircleAvatar(
                                radius: 48,
                                backgroundColor: _cardLight,
                                backgroundImage: _avatarBytes != null
                                    ? MemoryImage(_avatarBytes!)
                                    : (_chatData?['avatar_url'] != null
                                          ? NetworkImage(
                                              _chatData!['avatar_url']
                                                  as String,
                                            )
                                          : null),
                                child:
                                    _avatarBytes == null &&
                                        _chatData?['avatar_url'] == null
                                    ? Text(
                                        _chatData?['name']?.isNotEmpty == true
                                            ? _chatData!['name'][0]
                                                  .toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          color: _textPrimary,
                                          fontSize: 32,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                            if (_isAdmin && _isEditing)
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.camera_alt,
                                  color: Colors.black,
                                  size: 16,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ===== НАЗВАНИЕ =====
                    if (_isAdmin && _isEditing)
                      Container(
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _border, width: 0.5),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: TextField(
                          controller: _nameController,
                          style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            hintText: _isChannel
                                ? 'Название канала'
                                : 'Название группы',
                            hintStyle: TextStyle(color: _textMuted),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      Text(
                        _chatData?['name'] ?? 'Без названия',
                        style: const TextStyle(
                          color: _textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),

                    const SizedBox(height: 8),

                    // ===== ОПИСАНИЕ =====
                    if (_isAdmin && _isEditing)
                      Container(
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _border, width: 0.5),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: TextField(
                          controller: _descriptionController,
                          style: const TextStyle(
                            color: _textSecondary,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: _isChannel
                                ? 'Описание канала'
                                : 'Описание группы',
                            hintStyle: TextStyle(color: _textMuted),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 3,
                        ),
                      )
                    else if (_chatData?['description'] != null &&
                        _chatData!['description'].toString().isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          _chatData!['description'],
                          style: const TextStyle(
                            color: _textSecondary,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                    const SizedBox(height: 14),

                    // ===== ДОСТУП К КОМНАТЕ =====
                    if (_isAdmin && _isEditing)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SegmentedButton<bool>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment<bool>(
                                value: false,
                                icon: Icon(Icons.public_rounded),
                                label: Text('Открытая'),
                              ),
                              ButtonSegment<bool>(
                                value: true,
                                icon: Icon(Icons.lock_outline_rounded),
                                label: Text('Приватная'),
                              ),
                            ],
                            selected: {_isPrivate},
                            onSelectionChanged: (selection) =>
                                setState(() => _isPrivate = selection.first),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _isPrivate
                                ? 'Вступление — только для приглашённых.'
                                : '${_isChannel ? 'Канал' : 'Группа'} отображается в поиске по тегу.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isPrivate
                                  ? Icons.lock_outline_rounded
                                  : Icons.public_rounded,
                              color: _textSecondary,
                              size: 17,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isPrivate
                                  ? 'Приватный ${_isChannel ? 'канал' : 'группа'}'
                                  : 'Открытый ${_isChannel ? 'канал' : 'группа'}',
                              style: const TextStyle(
                                color: _textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 14),

                    // ===== ТЕГ =====
                    if (_isAdmin && _isEditing && !_isPrivate)
                      Container(
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _border, width: 0.5),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        child: TextField(
                          controller: _tagController,
                          style: const TextStyle(
                            color: _textSecondary,
                            fontSize: 14,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'тег',
                            hintStyle: TextStyle(color: _textMuted),
                            prefixText: '@ ',
                            prefixStyle: TextStyle(color: _textMuted),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else if (!_isPrivate &&
                        _chatData?['tag']?.toString().isNotEmpty == true)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '@${_chatData!['tag']}',
                          style: const TextStyle(
                            color: _textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ),

                    const SizedBox(height: 18),

                    // ===== КНОПКА УЧАСТНИКИ =====
                    if (!_isChannel || _isAdmin)
                      SizedBox(
                        width: double.infinity,
                        child: InkWell(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (context) => _ParticipantsDialog(
                                participants: _participants,
                                currentUserId: widget.currentUserId,
                                isOwner: _isOwner,
                                isAdmin: _isAdmin,
                                isEditing: _isEditing,
                                onRemove: _removeParticipant,
                                onSetRole: _setParticipantRole,
                                onAddTap: () async {
                                  await _loadAvailableUsers();
                                  if (!mounted) return;
                                  showDialog(
                                    context: context,
                                    builder: (context) => _AddParticipantDialog(
                                      availableUsers: _availableUsers,
                                      participants: _participants,
                                      onAdd: _addParticipant,
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: _card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _border, width: 0.5),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.people_outline,
                                  color: _textPrimary,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Участники',
                                    style: TextStyle(
                                      color: _textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _cardLight,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${_participants.length}',
                                    style: const TextStyle(
                                      color: _textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.chevron_right,
                                  color: _textMuted,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    const SizedBox(height: 20),

                    // ===== КНОПКИ =====
                    if (_isAdmin && !_isEditing)
                      SizedBox(
                        width: double.infinity,
                        child: _ActionButton(
                          label: 'Редактировать',
                          bg: Colors.white,
                          fg: Colors.black,
                          onTap: () => setState(() => _isEditing = true),
                        ),
                      ),

                    if (_isAdmin && _isEditing) ...[
                      Row(
                        children: [
                          Expanded(
                            child: _ActionButton(
                              label: 'Отмена',
                              bg: _cardLight,
                              fg: _textPrimary,
                              onTap: _cancelGroupEdit,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ActionButton(
                              label: 'Сохранить',
                              bg: Colors.white,
                              fg: Colors.black,
                              onTap: _updateGroupInfo,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: _ActionButton(
                          label: _chatData?['type'] == 'channel'
                              ? 'Удалить канал'
                              : 'Удалить группу',
                          bg: _card,
                          fg: const Color(0xFFEF5350),
                          bordered: true,
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: _card,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                title: Text(
                                  _isChannel
                                      ? 'Удалить канал?'
                                      : 'Удалить группу?',
                                  style: const TextStyle(color: _textPrimary),
                                ),
                                content: const Text(
                                  'Это действие нельзя отменить. Все сообщения будут удалены.',
                                  style: TextStyle(color: _textSecondary),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text(
                                      'Отмена',
                                      style: TextStyle(color: _textSecondary),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _deleteGroup();
                                    },
                                    child: const Text(
                                      'Удалить',
                                      style: TextStyle(
                                        color: Color(0xFFEF5350),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],

                    const SizedBox(height: 4),

                    // Выйти из комнаты
                    TextButton(
                      onPressed: _leaveGroup,
                      child: Text(
                        _isChannel ? 'Выйти из канала' : 'Выйти из группы',
                        style: const TextStyle(
                          color: Color(0xFFEF5350),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                    // Закрыть
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Закрыть',
                        style: TextStyle(color: _textMuted, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

// ===== Кнопка в едином стиле =====
class _ActionButton extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;
  final bool bordered;

  const _ActionButton({
    required this.label,
    required this.bg,
    required this.fg,
    required this.onTap,
    this.bordered = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: bg,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: bordered
              ? const BorderSide(color: Color(0xFF333333), width: 1)
              : BorderSide.none,
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ====== ОКНО УЧАСТНИКОВ ======
class _ParticipantsDialog extends StatefulWidget {
  final List<Map<String, dynamic>> participants;
  final String currentUserId;
  final bool isOwner;
  final bool isAdmin;
  final bool isEditing;
  final Future<bool> Function(String profileId) onRemove;
  final Future<bool> Function(String profileId, String role) onSetRole;
  final VoidCallback onAddTap;

  const _ParticipantsDialog({
    required this.participants,
    required this.currentUserId,
    required this.isOwner,
    required this.isAdmin,
    required this.isEditing,
    required this.onRemove,
    required this.onSetRole,
    required this.onAddTap,
  });

  @override
  State<_ParticipantsDialog> createState() => _ParticipantsDialogState();
}

class _ParticipantsDialogState extends State<_ParticipantsDialog> {
  final TextEditingController _searchController = TextEditingController();
  late List<Map<String, dynamic>> _filtered;

  static const Color _bg = Color(0xFF0D0A0A);
  static const Color _card = Color(0xFF1A1A1A);
  static const Color _cardLight = Color(0xFF2A2A2A);
  static const Color _border = Color(0xFF333333);
  static const Color _textPrimary = Colors.white;
  static const Color _textSecondary = Color(0xFF9E9E9E);
  static const Color _textMuted = Color(0xFF6E6E6E);

  @override
  void initState() {
    super.initState();
    _filtered = List.from(widget.participants);
    _searchController.addListener(_applyFilter);
  }

  void _applyFilter() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      _filtered = widget.participants.where((p) {
        final user = p['users'] as Map<String, dynamic>;
        final name = (user['name'] ?? '').toString().toLowerCase();
        final tag = (user['tag'] ?? '').toString().toLowerCase();
        return name.contains(q) || tag.contains(q);
      }).toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 500,
        height: screenHeight * 0.85,
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _border, width: 1),
        ),
        child: Column(
          children: [
            // ===== ШАПКА =====
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
              child: Row(
                children: [
                  const Text(
                    'Участники',
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${widget.participants.length}',
                      style: const TextStyle(
                        color: _textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (widget.isAdmin && widget.isEditing)
                    IconButton(
                      onPressed: widget.onAddTap,
                      icon: const Icon(
                        Icons.person_add_alt_1,
                        color: _textPrimary,
                        size: 22,
                      ),
                      tooltip: 'Добавить участника',
                    ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close,
                      color: _textSecondary,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),

            // ===== ПОИСК =====
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border, width: 0.5),
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: _textPrimary, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Поиск участников...',
                    hintStyle: TextStyle(color: _textMuted, fontSize: 14),
                    prefixIcon: Icon(Icons.search, color: _textMuted, size: 20),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 4,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ===== СПИСОК =====
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'Никого не найдено',
                        style: TextStyle(color: _textMuted),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final participant = _filtered[index];
                        final user =
                            participant['users'] as Map<String, dynamic>;
                        final isCurrentUser =
                            participant['user_id'] == widget.currentUserId;
                        final role = participant['role'] as String? ?? 'member';

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _border.withValues(alpha: 0.5),
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: _cardLight,
                                backgroundImage: user['avatar_url'] != null
                                    ? NetworkImage(user['avatar_url'] as String)
                                    : null,
                                child: user['avatar_url'] == null
                                    ? Text(
                                        user['name']?.isNotEmpty == true
                                            ? user['name'][0].toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          color: _textPrimary,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      user['name'] ?? 'Пользователь',
                                      style: const TextStyle(
                                        color: _textPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (user['tag'] != null &&
                                        user['tag'].toString().isNotEmpty)
                                      Text(
                                        '@${user['tag']}',
                                        style: const TextStyle(
                                          color: _textMuted,
                                          fontSize: 12,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              if (isCurrentUser)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    'Вы',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              if (role == 'owner' || role == 'admin')
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: role == 'owner'
                                        ? const Color(
                                            0xFF9C7D3B,
                                          ).withValues(alpha: 0.18)
                                        : const Color(
                                            0xFF4D8B83,
                                          ).withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Text(
                                    role == 'owner' ? 'Владелец' : 'Админ',
                                    style: TextStyle(
                                      color: role == 'owner'
                                          ? const Color(0xFFE0BC70)
                                          : const Color(0xFF82CEC1),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              if (widget.isOwner &&
                                  widget.isEditing &&
                                  !isCurrentUser &&
                                  role != 'owner')
                                PopupMenuButton<String>(
                                  tooltip: 'Изменить роль',
                                  onSelected: (newRole) async {
                                    final updated = await widget.onSetRole(
                                      participant['user_id'] as String,
                                      newRole,
                                    );
                                    if (!mounted || !updated) return;
                                    setState(
                                      () => participant['role'] = newRole,
                                    );
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'admin',
                                      child: Text(
                                        role == 'admin'
                                            ? 'Администратор ✓'
                                            : 'Назначить админом',
                                      ),
                                    ),
                                    if (role == 'admin')
                                      const PopupMenuItem(
                                        value: 'member',
                                        child: Text('Снять админа'),
                                      ),
                                  ],
                                  icon: const Icon(
                                    Icons.more_vert,
                                    color: _textSecondary,
                                    size: 20,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 36,
                                    minHeight: 36,
                                  ),
                                ),
                              if (widget.isAdmin &&
                                  widget.isEditing &&
                                  !isCurrentUser)
                                IconButton(
                                  onPressed: () async {
                                    final removed = await widget.onRemove(
                                      participant['user_id'] as String,
                                    );
                                    if (!mounted || !removed) return;
                                    setState(() {
                                      _filtered.removeWhere(
                                        (p) =>
                                            p['user_id'] ==
                                            participant['user_id'],
                                      );
                                    });
                                  },
                                  icon: const Icon(
                                    Icons.remove_circle_outline,
                                    color: _textSecondary,
                                    size: 20,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  tooltip: 'Удалить участника',
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ====== ДИАЛОГ ДОБАВЛЕНИЯ УЧАСТНИКОВ ======
class _AddParticipantDialog extends StatefulWidget {
  final List<Map<String, dynamic>> availableUsers;
  final List<Map<String, dynamic>> participants;
  final void Function(String profileId) onAdd;

  const _AddParticipantDialog({
    required this.availableUsers,
    required this.participants,
    required this.onAdd,
  });

  @override
  State<_AddParticipantDialog> createState() => _AddParticipantDialogState();
}

class _AddParticipantDialogState extends State<_AddParticipantDialog> {
  final List<String> _selected = [];

  @override
  Widget build(BuildContext context) {
    final available = widget.availableUsers
        .where(
          (user) => !widget.participants.any((p) => p['user_id'] == user['id']),
        )
        .toList();

    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Добавить участников',
        style: TextStyle(color: Colors.white, fontSize: 18),
      ),
      content: SizedBox(
        width: 400,
        height: 400,
        child: available.isEmpty
            ? const Center(
                child: Text(
                  'Нет доступных пользователей',
                  style: TextStyle(color: Color(0xFF6E6E6E)),
                ),
              )
            : ListView.builder(
                itemCount: available.length,
                itemBuilder: (context, index) {
                  final user = available[index];
                  final isSelected = _selected.contains(user['id']);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selected.remove(user['id']);
                          } else {
                            _selected.add(user['id'] as String);
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: const Color(0xFF3A3A3A),
                              backgroundImage: user['avatar_url'] != null
                                  ? NetworkImage(user['avatar_url'] as String)
                                  : null,
                              child: user['avatar_url'] == null
                                  ? Text(
                                      (user['name'] ?? '?')[0].toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    user['name'] ?? 'Пользователь',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (user['tag'] != null)
                                    Text(
                                      '@${user['tag']}',
                                      style: const TextStyle(
                                        color: Color(0xFF6E6E6E),
                                        fontSize: 12,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.transparent,
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0xFF4A4A4A),
                                  width: 1.5,
                                ),
                              ),
                              child: isSelected
                                  ? const Icon(
                                      Icons.check,
                                      color: Colors.black,
                                      size: 14,
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Отмена',
            style: TextStyle(color: Color(0xFF6E6E6E)),
          ),
        ),
        TextButton(
          onPressed: () {
            for (final id in _selected) {
              widget.onAdd(id);
            }
            Navigator.pop(context);
          },
          child: const Text('Добавить', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
