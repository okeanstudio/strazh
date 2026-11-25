import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

enum ChatAttachmentAction {
  gallery,
  gift,
  file,
  music,
  location,
  poll,
  videoNote,
  stickers,
}

class ChatAttachmentPickerSheet extends StatefulWidget {
  final ValueChanged<ChatAttachmentAction> onAction;
  final bool canToggleViewOnce;
  final bool sendViewOnce;
  final ValueChanged<bool> onViewOnceChanged;

  const ChatAttachmentPickerSheet({
    super.key,
    required this.onAction,
    required this.canToggleViewOnce,
    required this.sendViewOnce,
    required this.onViewOnceChanged,
  });

  @override
  State<ChatAttachmentPickerSheet> createState() =>
      _ChatAttachmentPickerSheetState();
}

class _ChatAttachmentPickerSheetState extends State<ChatAttachmentPickerSheet> {
  final Set<String> _selectedIds = {};
  List<AssetEntity> _assets = [];
  bool _isLoading = true;
  bool _hasPermission = true;
  late bool _sendViewOnce = widget.sendViewOnce;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _loadRecentPhotos();
  }

  Future<void> _loadRecentPhotos() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      setState(() {
        _isLoading = false;
        _assets = [];
      });
      return;
    }

    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!mounted) return;
      if (permission != PermissionState.authorized &&
          permission != PermissionState.limited) {
        setState(() {
          _hasPermission = false;
          _isLoading = false;
        });
        return;
      }

      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        onlyAll: true,
      );
      final assets = albums.isEmpty
          ? <AssetEntity>[]
          : await albums.first.getAssetListPaged(page: 0, size: 60);
      if (!mounted) return;
      setState(() {
        _assets = assets;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
    }
  }

  void _handleAction(ChatAttachmentAction action) {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onAction(action);
    });
  }

  void _sendSelected() {
    final selected = _assets
        .where((asset) => _selectedIds.contains(asset.id))
        .toList();
    Navigator.of(context).pop(selected);
  }

  @override
  Widget build(BuildContext context) {
    final sheetHeight = (MediaQuery.sizeOf(context).height * 0.72)
        .clamp(300.0, 680.0)
        .toDouble();

    return SafeArea(
      top: false,
      child: Container(
        height: sheetHeight,
        decoration: const BoxDecoration(
          color: Color(0xFF171717),
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 9, 18, 8),
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 48,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Недавние',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: 5),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: Colors.white70,
                              size: 24,
                            ),
                          ],
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            tooltip: 'Закрыть',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.08,
                              ),
                              shape: const CircleBorder(),
                            ),
                          ),
                        ),
                        if (_selectedIds.isNotEmpty)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _sendSelected,
                              child: Text(
                                'Отправить ${_selectedIds.length}',
                                style: const TextStyle(
                                  color: Color(0xFF78A9FF),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildGallery()),
            _buildActionBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildGallery() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF78A9FF),
          strokeWidth: 2,
        ),
      );
    }

    if (!_hasPermission) {
      return _buildMessage(
        icon: Icons.photo_library_outlined,
        message: 'Разрешите доступ к фото, чтобы видеть недавние снимки',
        action: TextButton(
          onPressed: PhotoManager.openSetting,
          child: const Text('Открыть настройки'),
        ),
      );
    }

    if (_loadError != null) {
      return _buildMessage(
        icon: Icons.error_outline,
        message: 'Не удалось загрузить фотографии',
        action: TextButton(
          onPressed: () {
            setState(() {
              _loadError = null;
              _isLoading = true;
            });
            _loadRecentPhotos();
          },
          child: const Text('Повторить'),
        ),
      );
    }

    if (_assets.isEmpty) {
      return _buildMessage(
        icon: Icons.photo_library_outlined,
        message: 'Здесь появятся недавние фото и видео',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: 0.82,
      ),
      itemCount: _assets.length,
      itemBuilder: (context, index) {
        final asset = _assets[index];
        final isSelected = _selectedIds.contains(asset.id);
        return GestureDetector(
          onTap: () => setState(() {
            if (isSelected) {
              _selectedIds.remove(asset.id);
            } else {
              _selectedIds.add(asset.id);
            }
          }),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _AssetThumbnail(asset: asset),
              if (asset.type == AssetType.video)
                const Center(
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    color: Colors.white,
                    size: 38,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                  ),
                ),
              if (asset.type == AssetType.video)
                Positioned(
                  left: 7,
                  bottom: 7,
                  child: Text(
                    _formatDuration(asset.duration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                    ),
                  ),
                ),
              Positioned(
                top: 8,
                right: 8,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 25,
                  height: 25,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF75A8F8)
                        : Colors.black.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.9),
                      width: 1.5,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 17,
                        )
                      : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remainingSeconds = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainingSeconds';
  }

  Widget _buildMessage({
    required IconData icon,
    required String message,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white38, size: 38),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
            ?action,
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    const actions = [
      (ChatAttachmentAction.gallery, Icons.photo_library, 'Галерея', true),
      (ChatAttachmentAction.gift, Icons.card_giftcard, 'Подарок', false),
      (ChatAttachmentAction.file, Icons.insert_drive_file, 'Файл', false),
      (ChatAttachmentAction.music, Icons.music_note_rounded, 'Музыка', false),
      (ChatAttachmentAction.location, Icons.location_on, 'Геопозиция', false),
      (ChatAttachmentAction.poll, Icons.poll, 'Опрос', false),
      (
        ChatAttachmentAction.videoNote,
        Icons.video_camera_front,
        'Кружок',
        false,
      ),
      (
        ChatAttachmentAction.stickers,
        Icons.emoji_emotions_outlined,
        'Стикеры',
        false,
      ),
    ];

    final itemWidth = ((MediaQuery.sizeOf(context).width - 24) / 5)
        .clamp(64.0, 86.0)
        .toDouble();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF353535),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          if (widget.canToggleViewOnce)
            SizedBox(
              width: 68,
              child: InkWell(
                onTap: () {
                  final enabled = !_sendViewOnce;
                  setState(() => _sendViewOnce = enabled);
                  widget.onViewOnceChanged(enabled);
                },
                borderRadius: BorderRadius.circular(22),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 30,
                        color: _sendViewOnce
                            ? const Color(0xFFD4B4FF)
                            : Colors.white,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _sendViewOnce ? '1 просмотр' : 'Без повтора',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _sendViewOnce
                              ? const Color(0xFFD4B4FF)
                              : Colors.white,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (action, icon, label, active) in actions)
                    SizedBox(
                      width: itemWidth,
                      child: InkWell(
                        onTap: () => _handleAction(action),
                        borderRadius: BorderRadius.circular(22),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                icon,
                                size: 30,
                                color: active
                                    ? const Color(0xFF78A9FF)
                                    : Colors.white,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: active
                                      ? const Color(0xFF78A9FF)
                                      : Colors.white,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
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
  }
}

class _AssetThumbnail extends StatelessWidget {
  final AssetEntity asset;

  const _AssetThumbnail({required this.asset});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: asset.thumbnailDataWithSize(const ThumbnailSize.square(240)),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return const ColoredBox(color: Color(0xFF282828));
        }
        return Image.memory(bytes, fit: BoxFit.cover);
      },
    );
  }
}
