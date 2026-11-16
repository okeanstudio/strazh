import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:strazh/features/profile/data/services/avatar_service.dart';
import 'package:strazh/shared/presentation/widgets/avatar_preview.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

class AvatarPicker extends StatefulWidget {
  final String userId;
  final String? currentAvatarUrl;
  final Function(String? newAvatarUrl)? onAvatarUpdated;

  const AvatarPicker({
    super.key,
    required this.userId,
    this.currentAvatarUrl,
    this.onAvatarUpdated,
  });

  @override
  State<AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends State<AvatarPicker> {
  bool _isLoading = false;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _avatarUrl = widget.currentAvatarUrl;
  }

  Future<void> _pickImage(ImageSource source) async {
    final image = await AvatarService.pickImage(
      context: context,
      source: source,
    );
    if (image == null) return;

    if (!mounted) return;
    setState(() => _isLoading = true);

    final url = await AvatarService.uploadAvatar(
      image: image,
      userId: widget.userId,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (url != null) {
      setState(() => _avatarUrl = url);
      widget.onAvatarUpdated?.call(url);
      Toast.success(context, 'Аватарка обновлена');
      Navigator.pop(context);
    } else {
      Toast.error(context, 'Ошибка загрузки аватарки');
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
              backgroundColor: Colors.red.withOpacity(0.1),
            ),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    final success = await AvatarService.deleteAvatar(widget.userId);
    setState(() => _isLoading = false);

    if (success) {
      setState(() => _avatarUrl = null);
      widget.onAvatarUpdated?.call(null);
      Toast.success(context, 'Аватарка удалена');
      Navigator.pop(context);
    } else {
      Toast.error(context, 'Ошибка удаления аватарки');
    }
  }

  void _showPickerDialog() {
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
                      onTap: () => _pickImage(ImageSource.gallery),
                    ),
                    _buildPickerOption(
                      icon: Icons.photo_camera,
                      label: 'Камера',
                      onTap: () => _pickImage(ImageSource.camera),
                    ),
                    if (_avatarUrl != null)
                      _buildPickerOption(
                        icon: Icons.delete_outline,
                        label: 'Удалить',
                        onTap: _deleteAvatar,
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
                  ? Colors.red.withOpacity(0.15)
                  : Colors.white.withOpacity(0.08),
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
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: () {
            final url = _avatarUrl;
            if (url != null && url.isNotEmpty) {
              showAvatarPreview(context, image: NetworkImage(url));
            } else {
              _showPickerDialog();
            }
          },
          child: CircleAvatar(
            radius: 45,
            backgroundColor: Colors.grey[800],
            backgroundImage: _avatarUrl != null && _avatarUrl!.isNotEmpty
                ? NetworkImage(_avatarUrl!)
                : null,
            child: _avatarUrl == null || _avatarUrl!.isEmpty
                ? const Icon(Icons.person, color: Colors.white, size: 40)
                : null,
          ),
        ),
        if (_isLoading)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
          ),
        // Иконка карандаша для изменения
        Positioned(
          bottom: 0,
          right: 0,
          child: GestureDetector(
            onTap: _showPickerDialog,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: Color(0xFF1A73E8),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.edit, color: Colors.white, size: 16),
            ),
          ),
        ),
      ],
    );
  }
}
