import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:strazh/features/profile/data/services/avatar_service.dart';
import 'package:strazh/shared/presentation/widgets/avatar_preview.dart';
import 'package:strazh/features/chat/data/services/storage_upload_service.dart';

class CreateGroupWidget extends StatefulWidget {
  final String currentUserId;
  final List<String> existingMemberIds;

  const CreateGroupWidget({
    super.key,
    required this.currentUserId,
    this.existingMemberIds = const [],
  });

  @override
  State<CreateGroupWidget> createState() => _CreateGroupWidgetState();
}

class _CreateGroupWidgetState extends State<CreateGroupWidget> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final List<String> _selectedMembers = [];

  // Аватарка
  XFile? _avatarFile;

  // Участники
  List<Map<String, dynamic>> _availableUsers = [];
  bool _isLoadingUsers = false;

  bool _isLoading = false;
  bool _isPrivate = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAvailableUsers();
  }

  Future<void> _loadAvailableUsers() async {
    setState(() => _isLoadingUsers = true);
    try {
      final supabase = Supabase.instance.client;
      final currentUserRooms = await supabase
          .from('room_participants')
          .select('room_id')
          .eq('user_id', widget.currentUserId);
      final roomIds = currentUserRooms
          .map((row) => row['room_id'] as String)
          .toList();

      if (roomIds.isEmpty) {
        if (mounted) setState(() => _isLoadingUsers = false);
        return;
      }

      final directRooms = await supabase
          .from('rooms')
          .select('id')
          .eq('type', 'direct')
          .inFilter('id', roomIds);
      final directRoomIds = directRooms
          .map((room) => room['id'] as String)
          .toList();

      if (directRoomIds.isEmpty) {
        if (mounted) setState(() => _isLoadingUsers = false);
        return;
      }

      final directChatParticipants = await supabase
          .from('room_participants')
          .select('user_id')
          .inFilter('room_id', directRoomIds)
          .neq('user_id', widget.currentUserId);
      final directChatUserIds = directChatParticipants
          .map((row) => row['user_id'] as String)
          .toSet();

      // Load profile data only for users with an existing direct chat.
      final allUsers = await Supabase.instance.client.rpc('get_all_users');

      if (mounted) {
        if (allUsers is List) {
          final filtered = allUsers
              .where((user) => directChatUserIds.contains(user['id']))
              .toList();
          setState(() {
            _availableUsers = List<Map<String, dynamic>>.from(
              filtered.map((u) => Map<String, dynamic>.from(u as Map)),
            );
            _isLoadingUsers = false;
          });
        } else {
          setState(() => _isLoadingUsers = false);
        }
      }
    } catch (e) {
      debugPrint('Ошибка загрузки пользователей: $e');
      if (mounted) setState(() => _isLoadingUsers = false);
    }
  }

  Future<void> _pickAvatar() async {
    final file = await AvatarService.pickImage(
      context: context,
      source: ImageSource.gallery,
    );

    if (file != null) {
      if (!mounted) return;
      setState(() {
        _avatarFile = file;
      });
    }
  }

  Future<String?> _uploadAvatar() async {
    if (_avatarFile == null) return null;

    try {
      final bytes = await _avatarFile!.readAsBytes();
      final fileName =
          '${widget.currentUserId}/group_avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await StorageUploadService.uploadBinary(
        bucket: 'group_avatars',
        path: fileName,
        bytes: bytes,
        contentType: 'image/jpeg',
        onProgress: (_, _) {},
      );

      return await StorageUploadService.getPublicUrl(
        bucket: 'group_avatars',
        path: fileName,
      );
    } catch (e) {
      debugPrint('Ошибка загрузки аватарки: $e');
      return null;
    }
  }

  Future<String?> createGroup({
    required String groupName,
    required List<String> memberIds,
    required String currentUserId,
    String? avatarUrl,
    String? description,
    String? tag,
    bool isPrivate = false,
  }) async {
    final ownerId =
        Supabase.instance.client.auth.currentUser?.id ?? currentUserId;
    final roomResponse = await Supabase.instance.client
        .from('rooms')
        .insert({
          'type': 'group',
          'name': groupName,
          'tag': tag,
          'is_private': isPrivate,
          'avatar_url': avatarUrl,
          'description': description,
          'created_by': ownerId,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();
    final groupId = roomResponse['id'] as String;
    final memberIdsWithOwner = <String>{ownerId, ...memberIds};
    await Supabase.instance.client
        .from('room_participants')
        .insert(
          memberIdsWithOwner
              .map(
                (memberId) => {
                  'room_id': groupId,
                  'user_id': memberId,
                  'joined_at': DateTime.now().toIso8601String(),
                },
              )
              .toList(),
        );
    return groupId;
  }

  Future<void> _handleCreate() async {
    final groupName = _nameController.text.trim();
    final tag = _tagController.text.trim().replaceFirst('@', '');
    if (groupName.length < 2) return;
    if (!_isPrivate && tag.isEmpty) {
      setState(() => _error = 'Для открытой группы укажите тег');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Загружаем аватарку если она есть
      final avatarUrl = await _uploadAvatar();

      final groupId = await createGroup(
        groupName: groupName,
        memberIds: _selectedMembers,
        currentUserId: widget.currentUserId,
        description: _descriptionController.text.trim(),
        tag: _isPrivate ? null : tag,
        isPrivate: _isPrivate,
        avatarUrl: avatarUrl,
      );

      if (mounted && groupId != null) Navigator.pop(context, groupId);
    } catch (error) {
      debugPrint('Ошибка создания группы: $error');
      if (mounted) setState(() => _error = 'Не удалось создать группу');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
    InputDecoration fieldDecoration(String label, IconData icon, String hint) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.white54),
        labelStyle: const TextStyle(color: Colors.white70),
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: const Color(0xFF252525),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white54),
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.sizeOf(context).height * .9,
        ),
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF171717),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white12),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(
                          Icons.groups_rounded,
                          color: Colors.black,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Новая группа',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Создайте пространство для общения',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white54),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // АВАТАРКА ГРУППЫ
                  Center(
                    child: GestureDetector(
                      onTap: () {
                        final image = _avatarFile;
                        if (image == null) {
                          _pickAvatar();
                        } else {
                          showAvatarPreview(
                            context,
                            image: FileImage(File(image.path)),
                          );
                        }
                      },
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: const Color(0xFF252525),
                            backgroundImage: _avatarFile != null
                                ? FileImage(File(_avatarFile!.path))
                                : null,
                            child: _avatarFile == null
                                ? const Icon(
                                    Icons.add_a_photo,
                                    color: Colors.white54,
                                    size: 32,
                                  )
                                : null,
                          ),
                          GestureDetector(
                            onTap: _pickAvatar,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                color: Colors.black,
                                size: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      _avatarFile == null
                          ? 'Нажмите, чтобы добавить аватарку'
                          : 'Нажмите, чтобы изменить аватарку',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  TextFormField(
                    controller: _nameController,
                    maxLength: 60,
                    style: const TextStyle(color: Colors.white),
                    decoration: fieldDecoration(
                      'Название группы',
                      Icons.groups_outlined,
                      'Например, Команда проекта',
                    ),
                    validator: (value) =>
                        value == null || value.trim().length < 2
                        ? 'Введите название группы'
                        : null,
                  ),
                  const SizedBox(height: 12),
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
                    onSelectionChanged: (selection) {
                      setState(() {
                        _isPrivate = selection.first;
                        _error = null;
                      });
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isPrivate
                        ? 'Приватную группу можно открыть только по приглашению.'
                        : 'Открытая группа будет доступна в поиске по тегу.',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  if (!_isPrivate) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _tagController,
                      style: const TextStyle(color: Colors.white),
                      decoration: fieldDecoration(
                        'Тег группы *',
                        Icons.alternate_email,
                        'project_team',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: fieldDecoration(
                      'Описание',
                      Icons.notes_outlined,
                      'О чем эта группа?',
                    ),
                  ),

                  // УЧАСТНИКИ
                  const SizedBox(height: 20),
                  const Text(
                    'Участники (необязательно)',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  if (_isLoadingUsers)
                    const Center(child: CircularProgressIndicator())
                  else if (_availableUsers.isEmpty)
                    const Text(
                      'Нет доступных пользователей',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    )
                  else
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F1F1F),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _availableUsers.length,
                        itemBuilder: (context, index) {
                          final user = _availableUsers[index];
                          final isSelected = _selectedMembers.contains(
                            user['id'],
                          );

                          return Material(
                            color: Colors.transparent,
                            child: CheckboxListTile(
                              value: isSelected,
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedMembers.add(user['id'] as String);
                                  } else {
                                    _selectedMembers.remove(user['id']);
                                  }
                                });
                              },
                              title: Text(
                                user['name'] ?? 'Пользователь',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                '@${user['tag'] ?? ''}',
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                              secondary: CircleAvatar(
                                radius: 20,
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
                              controlAffinity: ListTileControlAffinity.trailing,
                              activeColor: Colors.white,
                              checkColor: Colors.black,
                              dense: true,
                            ),
                          );
                        },
                      ),
                    ),

                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isLoading
                              ? null
                              : () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            side: const BorderSide(color: Colors.white24),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Отмена'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleCreate,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Text(
                                  'Создать группу',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
