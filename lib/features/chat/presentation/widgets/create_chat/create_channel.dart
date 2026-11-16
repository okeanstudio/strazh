import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:strazh/features/profile/data/services/avatar_service.dart';
import 'package:strazh/shared/presentation/widgets/avatar_preview.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/features/chat/data/services/storage_upload_service.dart';

class CreateChannelWidget extends StatefulWidget {
  final String currentUserId;
  final List<String> existingMemberIds;

  const CreateChannelWidget({
    super.key,
    required this.currentUserId,
    this.existingMemberIds = const [],
  });

  @override
  State<CreateChannelWidget> createState() => _CreateChannelWidgetState();
}

class _CreateChannelWidgetState extends State<CreateChannelWidget> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final List<String> _selectedMembers = [];
  Uint8List? _avatarBytes;
  bool _isLoading = false;
  bool _isPrivate = false;
  String? _error;

  Future<void> _pickAvatar() async {
    final image = await AvatarService.pickImage(
      context: context,
      source: ImageSource.gallery,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (mounted) setState(() => _avatarBytes = bytes);
  }

  Future<String?> _uploadAvatar() async {
    final bytes = _avatarBytes;
    if (bytes == null) return null;
    final filePath =
        '${widget.currentUserId}/channel_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await StorageUploadService.uploadBinary(
      bucket: 'channel_avatars',
      path: filePath,
      bytes: bytes,
      contentType: 'image/jpeg',
      onProgress: (_, _) {},
    );
    return StorageUploadService.getPublicUrl(
      bucket: 'channel_avatars',
      path: filePath,
    );
  }

  Future<String?> createChannel({
    required String channelName,
    required List<String> memberIds,
    required String currentUserId,
    String? avatarUrl,
    String? description,
    String? tag,
    required bool isPrivate,
  }) async {
    try {
      final roomResponse = await Supabase.instance.client
          .from('rooms')
          .insert({
            'type': 'channel',
            'name': channelName,
            'tag': isPrivate ? null : tag,
            'is_private': isPrivate,
            'avatar_url': avatarUrl,
            'description': description,
            'created_by': currentUserId,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      final String channelId = roomResponse['id'];

      final participants = [
        {
          'room_id': channelId,
          'user_id': currentUserId,
          'joined_at': DateTime.now().toIso8601String(),
        },
        ...memberIds.map(
          (memberId) => {
            'room_id': channelId,
            'user_id': memberId,
            'joined_at': DateTime.now().toIso8601String(),
          },
        ),
      ];

      await Supabase.instance.client
          .from('room_participants')
          .insert(participants);

      return channelId;
    } catch (e) {
      debugPrint('Ошибка создания канала: $e');
      return null;
    }
  }

  Future<void> _handleCreate() async {
    final channelName = _nameController.text.trim();
    final tag = _tagController.text.trim().replaceFirst('@', '');

    if (channelName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Введите название канала')));
      return;
    }
    if (!_isPrivate && tag.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Для открытого канала укажите тег')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    String? channelId;
    try {
      final avatarUrl = await _uploadAvatar();
      channelId = await createChannel(
        channelName: channelName,
        memberIds: _selectedMembers,
        currentUserId: widget.currentUserId,
        avatarUrl: avatarUrl,
        description: _descriptionController.text.trim(),
        tag: _isPrivate ? null : tag,
        isPrivate: _isPrivate,
      );
    } catch (error) {
      debugPrint('Ошибка загрузки аватара канала: $error');
      if (mounted) {
        setState(() => _error = 'Не удалось загрузить аватар канала');
      }
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (channelId != null && mounted) {
      Navigator.pop(context, channelId);
    } else if (mounted && _error == null) {
      setState(() => _error = 'Не удалось создать канал');
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
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color.fromARGB(255, 29, 29, 29),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.group_add, color: Colors.black, size: 40),
            ),
            const SizedBox(height: 20),
            const Text(
              'Создать канал',
              style: TextStyle(color: Colors.white, fontSize: 20),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _isLoading
                  ? null
                  : () {
                      final bytes = _avatarBytes;
                      if (bytes == null) {
                        _pickAvatar();
                      } else {
                        showAvatarPreview(
                          context,
                          image: MemoryImage(bytes),
                        );
                      }
                    },
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 42,
                        backgroundColor: const Color.fromARGB(255, 50, 50, 50),
                        backgroundImage: _avatarBytes == null
                            ? null
                            : MemoryImage(_avatarBytes!),
                        child: _avatarBytes == null
                            ? const Icon(
                                Icons.add_a_photo_outlined,
                                color: Colors.white70,
                                size: 28,
                              )
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _pickAvatar,
                          child: const CircleAvatar(
                            radius: 15,
                            backgroundColor: Color(0xFF1A73E8),
                            child: Icon(
                              Icons.edit,
                              color: Colors.white,
                              size: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'Добавить аватар канала',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Название канала',
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: const Color.fromARGB(255, 50, 50, 50),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  icon: Icon(Icons.public_rounded),
                  label: Text('Открытый'),
                ),
                ButtonSegment<bool>(
                  value: true,
                  icon: Icon(Icons.lock_outline_rounded),
                  label: Text('Приватный'),
                ),
              ],
              selected: {_isPrivate},
              onSelectionChanged: (selection) =>
                  setState(() => _isPrivate = selection.first),
            ),
            const SizedBox(height: 8),
            Text(
              _isPrivate
                  ? 'Приватный канал доступен только приглашённым.'
                  : 'Открытый канал можно найти по тегу.',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            if (!_isPrivate) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _tagController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Тег канала *',
                  hintStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: const Color.fromARGB(255, 50, 50, 50),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _descriptionController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Описание (необязательно)',
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: const Color.fromARGB(255, 50, 50, 50),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(backgroundColor: Colors.grey),
                    child: const Text(
                      'Отмена',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleCreate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Создать',
                            style: TextStyle(color: Colors.black),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
