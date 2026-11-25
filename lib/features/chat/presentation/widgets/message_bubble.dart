import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:strazh/shared/domain/models/message.dart';
import 'package:strazh/shared/domain/models/user.dart' as app;
import 'package:strazh/features/chat/data/services/file_upload_service.dart';
import 'package:strazh/features/gifts/data/services/gift_service.dart';
import 'package:strazh/features/settings/data/services/theme_service.dart';
import 'package:strazh/core/utils/badges.dart';
import 'package:strazh/features/profile/presentation/widgets/profile.dart';
import 'package:strazh/features/bots/data/bot_service.dart';
import 'package:strazh/features/gifts/presentation/widgets/gift_nft_link_preview.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';
import 'package:strazh/shared/presentation/widgets/username_mention_text.dart';
import 'package:strazh/core/config/reactions.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/features/chat/data/services/storage_upload_service.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final app.User? sender;
  final bool isMe;
  final bool isGroup;
  final bool showReadReceipt;
  final bool assumeRead;
  final List<String> quickReactions;
  final String doubleTapReaction;
  final void Function(Message message, String reaction)? onReaction;
  final Future<void> Function(Message message, List<int> optionIndices)?
  onPollVote;
  final String? senderBadge;
  final void Function(String url)? onPlayVoice;
  final void Function(Message message)? onCopy;
  final void Function(Message message)? onEdit;
  final void Function(Message message)? onReply;
  final void Function(Message message)? onForward;
  final void Function(Message message)? onSelect;
  final void Function(Message message)? onPin;
  final void Function(Message message)? onDelete;
  final void Function(String url, {String? caption})? onOpenImage;
  final void Function(String url)? onUrlTap;
  final ValueChanged<String>? onUsernameTap;
  final ValueChanged<String>? onCommandTap;
  final void Function(Message message, String callbackData)? onBotCallback;
  final void Function(String url, String fileName)? onDownloadFile;
  final void Function(String url, String fileName)? onSaveVideoNote;
  final void Function(String filePath)? onOpenFile;
  final void Function(String url, String fileName)? onOpenPdf;
  final Future<void> Function(Message message)? onOpenViewOnce;
  final void Function(Message message)? onUnpin;
  final bool isPinned;
  final void Function(
    String? replyToId,
    String? replyToContent,
    String? replyToSender,
  )?
  onReplyPreviewTap;
  final bool isHighlighted;
  final bool showAvatar;
  final bool channelIsVerified;
  final String? channelAvatarUrl;
  final VoidCallback? onChannelTap;

  const MessageBubble({
    super.key,
    required this.message,
    this.sender,
    required this.isMe,
    this.isGroup = false,
    this.showReadReceipt = false,
    this.assumeRead = false,
    this.quickReactions = quickReactionEmojis,
    this.doubleTapReaction = defaultDoubleTapReaction,
    this.onReaction,
    this.onPollVote,
    this.senderBadge,
    this.onPlayVoice,
    this.onCopy,
    this.onEdit,
    this.onReply,
    this.onForward,
    this.onSelect,
    this.onPin,
    this.onDelete,
    this.onOpenImage,
    this.onUrlTap,
    this.onUsernameTap,
    this.onCommandTap,
    this.onBotCallback,
    this.onReplyPreviewTap,
    this.isHighlighted = false,
    this.onDownloadFile,
    this.onSaveVideoNote,
    this.onOpenFile,
    this.onOpenPdf,
    this.onOpenViewOnce,
    this.showAvatar = true,
    this.channelIsVerified = false,
    this.channelAvatarUrl,
    this.onChannelTap,
    this.onUnpin,
    required this.isPinned,
  });

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Widget _buildReadReceipt() {
    final isRead = assumeRead || message.readByOthers;
    return Icon(
      isRead ? Icons.done_all : Icons.done,
      size: 14,
      color: isRead ? const Color(0xFF64B5F6) : Colors.white54,
    );
  }

  Widget _buildViewOnceMessage(BuildContext context) {
    final label = message.isImage
        ? 'Фото'
        : message.isVoice
        ? 'Голосовое сообщение'
        : 'Видео';
    final viewed = message.viewOnceViewed;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: viewed || onOpenViewOnce == null
            ? null
            : () => onOpenViewOnce!(message),
        child: Container(
          constraints: const BoxConstraints(minWidth: 210, maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF251B36),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF9B5CFF).withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                viewed ? Icons.visibility_off_rounded : Icons.timer_outlined,
                color: const Color(0xFFD4B4FF),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    viewed ? 'Уже просмотрено' : '$label · один просмотр',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!viewed) ...[
                    const SizedBox(height: 3),
                    const Text(
                      'Нажмите, чтобы открыть',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getFileIcon(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return '📄';
      case 'doc':
      case 'docx':
        return '📝';
      case 'xls':
      case 'xlsx':
        return '📊';
      case 'ppt':
      case 'pptx':
        return '📑';
      case 'zip':
      case 'rar':
      case '7z':
        return '📦';
      case 'txt':
        return '📃';
      case 'json':
      case 'xml':
      case 'csv':
        return '📋';
      case 'mp3':
      case 'm4a':
      case 'aac':
      case 'wav':
      case 'ogg':
      case 'flac':
      case 'opus':
        return '🎵';
      default:
        return '📎';
    }
  }

  Color _getFileColor(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return Colors.red;
      case 'doc':
      case 'docx':
        return Colors.blue;
      case 'xls':
      case 'xlsx':
        return Colors.green;
      case 'ppt':
      case 'pptx':
        return Colors.orange;
      case 'zip':
      case 'rar':
      case '7z':
        return Colors.purple;
      case 'txt':
        return Colors.grey;
      case 'json':
      case 'xml':
      case 'csv':
        return Colors.cyan;
      case 'mp3':
      case 'm4a':
      case 'aac':
      case 'wav':
      case 'ogg':
      case 'flac':
      case 'opus':
        return Colors.purpleAccent;
      default:
        return Colors.grey;
    }
  }

  Future<void> _addTrackToProfile({
    required BuildContext context,
    required String url,
    required String title,
  }) async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) throw StateError('Нет авторизации');
      final objectPath = StorageUploadService.objectPathFromStorageUrl(
        'chat_files',
        url,
      );
      if (objectPath == null) {
        throw StateError('Не удалось определить путь к музыкальному файлу');
      }
      final metadata = Map<String, dynamic>.from(user.userMetadata ?? {});
      metadata['profile_music_path'] = objectPath;
      metadata.remove('profile_music_url');
      metadata['profile_music_name'] = title;
      await supabase.auth.updateUser(UserAttributes(data: metadata));
      if (!context.mounted) return;
      Toast.success(context, 'Музыка добавлена в профиль');
    } catch (error) {
      if (!context.mounted) return;
      Toast.error(context, 'Не удалось добавить музыку: $error');
    }
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final items = <PopupMenuEntry>[];

    final isVideoFile =
        message.fileMimeType?.toLowerCase().startsWith('video/') == true;
    if ((message.isVideoNote || isVideoFile) &&
        message.fileUrl != null &&
        onSaveVideoNote != null) {
      items.add(
        PopupMenuItem(
          onTap: () => onSaveVideoNote!(
            message.fileUrl!,
            message.fileName ?? (isVideoFile ? 'video.mp4' : 'video_note.mp4'),
          ),
          child: const Row(
            children: [
              Icon(Icons.save_alt_rounded, color: Colors.lightBlue, size: 20),
              SizedBox(width: 12),
              Text(
                'Сохранить в галерею',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    if (onSelect != null) {
      items.add(
        PopupMenuItem(
          onTap: () => onSelect?.call(message),
          child: const Row(
            children: [
              Icon(Icons.checklist_rounded, color: Colors.lightBlue, size: 20),
              SizedBox(width: 12),
              Text('Выбрать', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }

    if (onReaction != null) {
      items.add(
        _QuickReactionsMenuEntry(
          reactions: quickReactions,
          onSelected: (reaction) {
            Navigator.of(context).pop();
            onReaction?.call(message, reaction);
          },
        ),
      );

      items.add(
        PopupMenuItem(
          onTap: () => _showReactionPicker(context),
          child: const Row(
            children: [
              Icon(Icons.add_reaction_outlined, color: Colors.amber, size: 20),
              SizedBox(width: 12),
              Text('Другие реакции', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }

    items.add(
      PopupMenuItem(
        onTap: () => onCopy?.call(message),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.copy, color: Colors.blue, size: 18),
            ),
            const SizedBox(width: 12),
            const Text(
              'Копировать',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );

    if (isMe && message.canEditText) {
      items.add(
        PopupMenuItem(
          onTap: () => onEdit?.call(message),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.edit, color: Colors.orange, size: 18),
              ),
              const SizedBox(width: 12),
              const Text(
                'Изменить',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    items.add(
      PopupMenuItem(
        onTap: () => onReply?.call(message),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.reply, color: Colors.green, size: 18),
            ),
            const SizedBox(width: 12),
            const Text(
              'Ответить',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );

    items.add(
      PopupMenuItem(
        onTap: () => onForward?.call(message),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.forward, color: Colors.purple, size: 18),
            ),
            const SizedBox(width: 12),
            const Text(
              'Переслать',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );

    if (isPinned ? onUnpin != null : onPin != null) {
      items.add(
        PopupMenuItem(
          onTap: () {
            if (isPinned) {
              onUnpin?.call(message);
            } else {
              onPin?.call(message);
            }
          },
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.push_pin,
                  color: Colors.redAccent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                isPinned ? 'Открепить' : 'Закрепить',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    if (isMe) {
      items.add(
        PopupMenuItem(
          onTap: () => onDelete?.call(message),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.delete, color: Colors.red, size: 18),
              ),
              const SizedBox(width: 12),
              const Text(
                'Удалить',
                style: TextStyle(color: Colors.red, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      color: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide.none,
      ),
      elevation: 8,
      items: items,
    );
  }

  void _showReactionPicker(BuildContext context) {
    if (onReaction == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1D24),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Реакции',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 240,
                child: GridView.builder(
                  itemCount: availableReactionEmojis.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  itemBuilder: (context, index) {
                    final reaction = availableReactionEmojis[index];
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        onReaction?.call(message, reaction);
                      },
                      child: Center(
                        child: Text(
                          reaction,
                          style: const TextStyle(fontSize: 25),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProfile(BuildContext context, app.User user) {
    showDialog(
      context: context,
      builder: (context) =>
          ProfileDialog(user: user, onUsernameTap: onUsernameTap),
    );
  }

  void _showSenderProfile(BuildContext context, app.User user) {
    if (message.senderIsChannel) {
      onChannelTap?.call();
      return;
    }
    _showProfile(context, user);
  }

  Widget _buildSenderAvatar(app.User user, {String? fallbackAvatarUrl}) {
    final isBotFather = user.isBot && user.id == BotService.botFatherId;
    final preferredAvatarUrl = fallbackAvatarUrl?.trim();
    final avatarUrl =
        preferredAvatarUrl != null && preferredAvatarUrl.isNotEmpty
        ? preferredAvatarUrl
        : user.avatarUrl;
    final initial = user.name.isNotEmpty
        ? user.name.substring(0, 1).toUpperCase()
        : '?';

    Widget image;
    if (isBotFather) {
      image = Image.asset(
        'assets/icon/bots/botfather_strazh.jpg',
        fit: BoxFit.cover,
      );
    } else if (avatarUrl != null && avatarUrl.trim().isNotEmpty) {
      image = Image.network(
        avatarUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('Не удалось загрузить аватар отправителя: $error');
          return _buildAvatarFallback(initial);
        },
      );
    } else {
      image = _buildAvatarFallback(initial);
    }

    return CircleAvatar(
      radius: 18,
      backgroundColor: Colors.grey[800],
      child: ClipOval(child: SizedBox.expand(child: image)),
    );
  }

  Widget _buildAvatarFallback(String initial) {
    return ColoredBox(
      color: Colors.grey.shade800,
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
    );
  }

  Future<void> _downloadFile(BuildContext context) async {
    if (message.fileUrl == null) return;
    try {
      await FileUploadService.downloadFile(
        message.fileUrl!,
        message.fileName ?? 'файл',
      );
      if (context.mounted) {
        Toast.success(context, 'Файл скачан');
      }
    } catch (e) {
      if (context.mounted) {
        Toast.error(context, 'Ошибка скачивания: $e');
      }
    }
  }

  Widget _buildSenderName() {
    final isChannelAuthor = message.senderIsChannel;
    final messageSender = sender;
    if (messageSender == null || (!isChannelAuthor && (isMe || !isGroup))) {
      return const SizedBox.shrink();
    }
    if (messageSender.name.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isChannelAuthor) ...[
            const Icon(
              Icons.campaign_outlined,
              color: Color(0xFF86B9FF),
              size: 14,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            messageSender.name,
            style: TextStyle(
              color: isChannelAuthor ? const Color(0xFF86B9FF) : Colors.grey,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (messageSender.isBot) ...[
            const SizedBox(width: 4),
            const Icon(Icons.smart_toy, color: Color(0xFFB89AFF), size: 14),
            if (messageSender.botVerified) ...[
              const SizedBox(width: 3),
              const Icon(Icons.verified, color: Color(0xFF1A73E8), size: 14),
            ],
          ],
          if (isChannelAuthor && channelIsVerified) ...[
            const SizedBox(width: 4),
            const Icon(Icons.verified, color: Color(0xFF1A73E8), size: 14),
          ],
          if (!isChannelAuthor &&
              senderBadge != null &&
              senderBadge!.isNotEmpty) ...[
            const SizedBox(width: 4),
            BadgeIcon(badgeId: senderBadge, size: 14),
          ],
        ],
      ),
    );
  }

  bool get _shouldShowSenderName =>
      !message.isDeleted &&
      (message.senderIsChannel ||
          (!isMe && isGroup && showAvatar && sender != null));

  Widget _buildForwardedFrom(BuildContext context) {
    final userId = message.forwardedFromUserId;
    final name = message.forwardedFromName?.trim();
    if (userId == null || userId.isEmpty || name == null || name.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.forward,
            size: 14,
            color: isMe ? Colors.white70 : const Color(0xFF9ABDE9),
          ),
          const SizedBox(width: 4),
          Text(
            'Переслано от',
            style: TextStyle(
              color: isMe ? Colors.white70 : const Color(0xFF9ABDE9),
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(width: 3),
          Flexible(
            child: TextButton(
              onPressed: () => _showProfile(
                context,
                app.User(id: userId, name: name, tag: ''),
              ),
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: isMe ? Colors.white : const Color(0xFF9ABDE9),
              ),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReactionBar() {
    final reactions = message.reactions.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (reactions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(top: 2, left: isMe ? 12 : 56, right: 12),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        alignment: isMe ? WrapAlignment.end : WrapAlignment.start,
        children: reactions.map((entry) {
          final isSelected = message.myReaction == entry.key;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onReaction == null
                  ? null
                  : () => onReaction!(message, entry.key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF24466D)
                      : const Color(0xFF252932),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF6FA8E8)
                        : Colors.white12,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(entry.key, style: const TextStyle(fontSize: 15)),
                    if (message.reactionUsers[entry.key]?.isNotEmpty == true)
                      const SizedBox(width: 5),
                    if (message.reactionUsers[entry.key]?.isNotEmpty == true)
                      _buildReactionAvatars(message.reactionUsers[entry.key]!),
                    const SizedBox(width: 4),
                    Text(
                      '${entry.value}',
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildReactionAvatars(List<app.User> users) {
    final visibleUsers = users.take(3).toList();
    const avatarSize = 16.0;
    const overlap = 5.0;

    return SizedBox(
      width: avatarSize + (visibleUsers.length - 1) * overlap,
      height: avatarSize,
      child: Stack(
        children: [
          for (var index = 0; index < visibleUsers.length; index++)
            Positioned(
              left: index * overlap,
              child: Container(
                width: avatarSize,
                height: avatarSize,
                padding: const EdgeInsets.all(1),
                decoration: const BoxDecoration(
                  color: Color(0xFF252932),
                  shape: BoxShape.circle,
                ),
                child: ClipOval(
                  child: _buildReactionAvatar(visibleUsers[index]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReactionAvatar(app.User user) {
    final initial = user.name.isNotEmpty ? user.name[0].toUpperCase() : '?';
    final avatarUrl = user.avatarUrl;

    if (avatarUrl == null || avatarUrl.isEmpty) {
      return _reactionAvatarFallback(initial);
    }

    return Image.network(
      avatarUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        debugPrint('Не удалось загрузить аватар участника реакции: $error');
        return _reactionAvatarFallback(initial);
      },
    );
  }

  Widget _reactionAvatarFallback(String initial) {
    return ColoredBox(
      color: Colors.blueGrey,
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(color: Colors.white, fontSize: 8),
        ),
      ),
    );
  }

  double _maxMessageBubbleWidth(BuildContext context, double fraction) {
    return (MediaQuery.sizeOf(context).width * fraction)
        .clamp(0.0, 720.0)
        .toDouble();
  }

  double _maxImageWidth(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    if (screenWidth >= 900) {
      return (screenWidth * 0.45).clamp(0.0, 460.0).toDouble();
    }
    return _maxMessageBubbleWidth(context, 0.65);
  }

  double _maxImageHeight(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= 900 ? 320 : 520;
  }

  String _pollVotesLabel(int count) {
    final lastTwo = count % 100;
    final last = count % 10;
    final noun = lastTwo >= 11 && lastTwo <= 14
        ? 'голосов'
        : last == 1
        ? 'голос'
        : last >= 2 && last <= 4
        ? 'голоса'
        : 'голосов';
    return '$count $noun';
  }

  Widget _buildPollMessage(BuildContext context) {
    final totalVotes = message.pollVotes.values.fold<int>(
      0,
      (sum, count) => sum + count,
    );
    final theme = ThemeService().currentTheme.value;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxWidth: _maxMessageBubbleWidth(context, 0.76),
          ),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isMe ? theme.myBubble : theme.otherBubble,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_shouldShowSenderName) _buildSenderName(),
              Row(
                children: [
                  const Icon(
                    Icons.poll_outlined,
                    color: Color(0xFF9ABDE9),
                    size: 18,
                  ),
                  const SizedBox(width: 7),
                  const Text(
                    'ОПРОС',
                    style: TextStyle(
                      color: Color(0xFF9ABDE9),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (message.pollClosed)
                    const Text(
                      'Завершён',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (message.forwardedFromUserId != null)
                _buildForwardedFrom(context),
              Text(
                message.content,
                style: TextStyle(
                  color: isMe ? theme.myText : Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              if (message.pollAllowMultiple)
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Можно выбрать несколько вариантов',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
              for (
                var optionIndex = 0;
                optionIndex < message.pollOptions.length;
                optionIndex++
              )
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: message.pollClosed || onPollVote == null
                          ? null
                          : () {
                              final selected = message.myPollVotes.toSet();
                              if (message.pollAllowMultiple) {
                                if (!selected.add(optionIndex)) {
                                  selected.remove(optionIndex);
                                }
                              } else if (!selected.add(optionIndex)) {
                                selected.clear();
                              } else {
                                selected
                                  ..clear()
                                  ..add(optionIndex);
                              }
                              onPollVote!(message, selected.toList()..sort());
                            },
                      borderRadius: BorderRadius.circular(11),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF11151C,
                          ).withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: message.myPollVotes.contains(optionIndex)
                                ? const Color(0xFF73A9E2)
                                : Colors.white12,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  message.myPollVotes.contains(optionIndex)
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color:
                                      message.myPollVotes.contains(optionIndex)
                                      ? const Color(0xFF9ABDE9)
                                      : Colors.white38,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    message.pollOptions[optionIndex],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                if (totalVotes > 0)
                                  Text(
                                    '${message.pollVotes[optionIndex] ?? 0}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                            if (totalVotes > 0) ...[
                              const SizedBox(height: 7),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  minHeight: 4,
                                  value:
                                      (message.pollVotes[optionIndex] ?? 0) /
                                      totalVotes,
                                  backgroundColor: Colors.white12,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                        Color(0xFF5C91C9),
                                      ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    _pollVotesLabel(totalVotes),
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const Spacer(),
                  Text(
                    _formatTime(message.createdAt),
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                  if (showReadReceipt && isMe) ...[
                    const SizedBox(width: 3),
                    _buildReadReceipt(),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget bubble;
    if (message.isDeleted) {
      bubble = _buildDeletedMessage(context);
    } else if (message.viewOnce && !isMe) {
      bubble = _buildViewOnceMessage(context);
    } else if (message.isPoll) {
      bubble = _buildPollMessage(context);
    } else if (message.isVideoNote) {
      bubble = _buildVideoNoteMessage(context);
    } else if (message.isFile) {
      bubble = _buildFileMessage(context);
    } else if (message.isVoice) {
      bubble = _buildVoiceMessage(context);
    } else {
      bubble = _buildTextMessage(context);
    }
    final hasInnerDoubleTapAction =
        message.isFile ||
        message.isVideoNote ||
        message.isVoice ||
        (message.isImage && !message.isSticker);
    return GestureDetector(
      onDoubleTap: onReaction == null || hasInnerDoubleTapAction
          ? null
          : () => onReaction!(message, doubleTapReaction),
      child: _MessageSwipeGesture(
        onSwipeLeft: onReply == null ? null : () => onReply!(message),
        onSwipeRight: onForward == null ? null : () => onForward!(message),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [bubble, _buildReactionBar()],
        ),
      ),
    );
  }

  Widget _buildRichText(String text, bool isMe) {
    final theme = ThemeService().currentTheme.value;
    final bubbleColor = isMe ? theme.myBubble : theme.otherBubble;
    final linkColor = _linkColorFor(bubbleColor);

    return UsernameMentionText(
      text: text,
      style: TextStyle(
        color: isMe ? theme.myText : theme.otherText,
        fontSize: 16,
      ),
      linkColor: linkColor,
      onUrlTap: onUrlTap,
      onUsernameTap: onUsernameTap,
      onCommandTap: onCommandTap,
    );
  }

  Color _linkColorFor(Color background) {
    const lightLink = Colors.white;
    const darkLink = Color(0xFF000714);
    final lightContrast = _contrastRatio(lightLink, background);
    final darkContrast = _contrastRatio(darkLink, background);
    return lightContrast >= darkContrast ? lightLink : darkLink;
  }

  double _contrastRatio(Color first, Color second) {
    final firstLuminance = first.computeLuminance();
    final secondLuminance = second.computeLuminance();
    final lighter = firstLuminance > secondLuminance
        ? firstLuminance
        : secondLuminance;
    final darker = firstLuminance > secondLuminance
        ? secondLuminance
        : firstLuminance;
    return (lighter + 0.05) / (darker + 0.05);
  }

  Widget _buildDeletedMessage(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: GestureDetector(
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, details.globalPosition),
        onLongPressStart: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: Row(
          mainAxisAlignment: isMe
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe && sender != null && showAvatar)
              GestureDetector(
                onTap: () => _showSenderProfile(context, sender!),
                onLongPress: () => _showSenderProfile(context, sender!),
                child: _buildSenderAvatar(
                  sender!,
                  fallbackAvatarUrl: message.senderIsChannel
                      ? channelAvatarUrl
                      : null,
                ),
              ),
            if (!isMe && !showAvatar) const SizedBox(width: 44),
            if (!isMe) const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(12),
                constraints: BoxConstraints(
                  maxWidth: _maxMessageBubbleWidth(context, 0.65),
                ),
                decoration: BoxDecoration(
                  color: isMe ? Colors.grey[300] : const Color(0xFF3A3A3A),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isMe ? 16 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 16),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline,
                      color: isMe ? Colors.grey[600] : Colors.grey[500],
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Сообщение удалено',
                      style: TextStyle(
                        color: isMe ? Colors.grey[600] : Colors.grey[500],
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isMe) const SizedBox(width: 8),
            if (isMe && message.sender != null && showAvatar)
              GestureDetector(
                onTap: () => _showSenderProfile(context, message.sender!),
                onLongPress: () => _showSenderProfile(context, message.sender!),
                child: _buildSenderAvatar(
                  message.sender!,
                  fallbackAvatarUrl: message.senderIsChannel
                      ? channelAvatarUrl
                      : null,
                ),
              ),
            if (isMe && !showAvatar) const SizedBox(width: 44),
          ],
        ),
      ),
    );
  }

  Widget _buildFileMessage(BuildContext context) {
    final fileName = message.fileName ?? 'Файл';
    final fileSize = message.fileSize;
    final theme = ThemeService().currentTheme.value;
    if (message.fileMimeType?.toLowerCase().startsWith('video/') == true &&
        message.fileUrl != null) {
      return _buildVideoFileMessage(context, fileName, fileSize);
    }
    final extension = fileName.split('.').last.toLowerCase();
    const audioExtensions = {'mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac', 'opus'};
    final isAudio =
        message.fileMimeType?.toLowerCase().startsWith('audio/') == true ||
        audioExtensions.contains(extension);
    if (isAudio && message.fileUrl != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        child: Row(
          mainAxisAlignment: isMe
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            if (!isMe && sender != null && showAvatar)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _buildSenderAvatar(sender!),
              ),
            if (!isMe && !showAvatar) const SizedBox(width: 44),
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: _maxMessageBubbleWidth(context, 0.72),
                ),
                decoration: BoxDecoration(
                  color: isMe ? theme.myBubble : theme.otherBubble,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _InlineAudioPlayer(
                  url: message.fileUrl!,
                  title: fileName,
                  isMe: isMe,
                  sizeLabel: _formatFileSize(fileSize),
                  onAddToProfile: () => _addTrackToProfile(
                    context: context,
                    url: message.fileUrl!,
                    title: fileName,
                  ),
                ),
              ),
            ),
            if (isMe && message.sender != null && showAvatar)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: GestureDetector(
                  onTap: () => _showSenderProfile(context, message.sender!),
                  onLongPress: () =>
                      _showSenderProfile(context, message.sender!),
                  child: _buildSenderAvatar(
                    message.sender!,
                    fallbackAvatarUrl: message.senderIsChannel
                        ? channelAvatarUrl
                        : null,
                  ),
                ),
              ),
            if (isMe && !showAvatar) const SizedBox(width: 44),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: GestureDetector(
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, details.globalPosition),
        onLongPressStart: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: Row(
          mainAxisAlignment: isMe
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe && sender != null && showAvatar)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => _showSenderProfile(context, sender!),
                  onLongPress: () => _showSenderProfile(context, sender!),
                  child: _buildSenderAvatar(
                    sender!,
                    fallbackAvatarUrl: message.senderIsChannel
                        ? channelAvatarUrl
                        : null,
                  ),
                ),
              ),
            if (!isMe && !showAvatar) const SizedBox(width: 44),
            if (!isMe) const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(12),
                constraints: BoxConstraints(
                  maxWidth: _maxMessageBubbleWidth(context, 0.65),
                ),
                decoration: BoxDecoration(
                  color: isMe ? theme.myBubble : theme.otherBubble,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isMe ? 16 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 16),
                  ),
                  border: isHighlighted
                      ? Border.all(color: Colors.amberAccent, width: 1.4)
                      : null,
                  boxShadow: isHighlighted
                      ? [
                          BoxShadow(
                            color: Colors.amberAccent.withValues(alpha: 0.22),
                            blurRadius: 18,
                            spreadRadius: 1.2,
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: isMe
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    if (_shouldShowSenderName) _buildSenderName(),
                    _buildForwardedFrom(context),
                    GestureDetector(
                      onDoubleTap: onReaction == null
                          ? null
                          : () => onReaction!(message, doubleTapReaction),
                      onTap: () {
                        if (message.fileUrl == null) return;
                        final fileName = message.fileName ?? 'Файл';
                        final extension = fileName
                            .split('.')
                            .last
                            .toLowerCase();
                        if (extension == 'pdf') {
                          onOpenPdf?.call(message.fileUrl!, fileName);
                        } else {
                          onDownloadFile?.call(message.fileUrl!, fileName);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isMe
                              ? theme.myBubble.withValues(alpha: 0.15)
                              : const Color(0xFF1F1F1F),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _getFileColor(
                              fileName,
                            ).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: _getFileColor(
                                  fileName,
                                ).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                  _getFileIcon(fileName),
                                  style: const TextStyle(fontSize: 22),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    fileName,
                                    style: TextStyle(
                                      color: isMe
                                          ? theme.myText
                                          : theme.otherText,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 2,
                                  ),
                                  if (fileSize != null)
                                    Text(
                                      _formatFileSize(fileSize),
                                      style: TextStyle(
                                        color: isMe
                                            ? theme.myText.withValues(
                                                alpha: 0.6,
                                              )
                                            : Colors.grey[400],
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.cloud_download,
                              color: isMe
                                  ? theme.myText.withValues(alpha: 0.6)
                                  : Colors.grey,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (message.isEdited)
                          Text(
                            '(изменено)',
                            style: TextStyle(
                              color: isMe
                                  ? theme.myText.withValues(alpha: 0.5)
                                  : Colors.grey[400],
                              fontSize: 10,
                            ),
                          ),
                        if (message.isEdited) const SizedBox(width: 8),
                        if (message.replyToId != null)
                          Text(
                            'ответил',
                            style: TextStyle(
                              color: isMe
                                  ? theme.myText.withValues(alpha: 0.5)
                                  : Colors.grey[400],
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        if (message.replyToId != null) const SizedBox(width: 8),
                        Text(
                          _formatTime(message.createdAt),
                          style: TextStyle(
                            color: isMe
                                ? theme.myText.withValues(alpha: 0.5)
                                : Colors.grey,
                            fontSize: 11,
                          ),
                        ),
                        if (showReadReceipt && isMe) ...[
                          const SizedBox(width: 3),
                          _buildReadReceipt(),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (isMe && message.sender != null && showAvatar)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: GestureDetector(
                  onTap: () => _showSenderProfile(context, message.sender!),
                  onLongPress: () =>
                      _showSenderProfile(context, message.sender!),
                  child: _buildSenderAvatar(
                    message.sender!,
                    fallbackAvatarUrl: message.senderIsChannel
                        ? channelAvatarUrl
                        : null,
                  ),
                ),
              ),
            if (isMe && !showAvatar) const SizedBox(width: 44),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoFileMessage(
    BuildContext context,
    String fileName,
    int? fileSize,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: GestureDetector(
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, details.globalPosition),
        onLongPressStart: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: Row(
          mainAxisAlignment: isMe
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe && sender != null && showAvatar)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => _showSenderProfile(context, sender!),
                  child: _buildSenderAvatar(
                    sender!,
                    fallbackAvatarUrl: message.senderIsChannel
                        ? channelAvatarUrl
                        : null,
                  ),
                ),
              ),
            if (!isMe && !showAvatar) const SizedBox(width: 44),
            if (!isMe) const SizedBox(width: 8),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: _maxMessageBubbleWidth(context, 0.72),
                ),
                child: Column(
                  crossAxisAlignment: isMe
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    if (_shouldShowSenderName) _buildSenderName(),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _VideoMessagePlayer(
                        url: message.fileUrl!,
                        onSaveToGallery: onSaveVideoNote == null
                            ? null
                            : () =>
                                  onSaveVideoNote!(message.fileUrl!, fileName),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            '$fileName${fileSize == null ? '' : ' • ${_formatFileSize(fileSize)}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatTime(message.createdAt),
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                          ),
                        ),
                        if (showReadReceipt && isMe) ...[
                          const SizedBox(width: 3),
                          _buildReadReceipt(),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (isMe && !showAvatar) const SizedBox(width: 44),
          ],
        ),
      ),
    );
  }

  Widget _buildTextMessage(BuildContext context) {
    final isStickerMessage = message.isSticker;
    final hasBotKeyboard = message.botInlineKeyboard.isNotEmpty;
    final theme = ThemeService().currentTheme.value;
    final nftSlug = GiftService.giftNftSlugFromUrl(message.content);
    final maxWidth = _maxMessageBubbleWidth(
      context,
      isStickerMessage ? 0.8 : 0.65,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: GestureDetector(
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, details.globalPosition),
        onLongPressStart: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: Row(
          mainAxisAlignment: isMe
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe && sender != null && showAvatar)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => _showSenderProfile(context, sender!),
                  onLongPress: () => _showSenderProfile(context, sender!),
                  child: _buildSenderAvatar(
                    sender!,
                    fallbackAvatarUrl: message.senderIsChannel
                        ? channelAvatarUrl
                        : null,
                  ),
                ),
              ),
            if (!isMe && !showAvatar) const SizedBox(width: 44),
            if (!isMe) const SizedBox(width: 8),
            Flexible(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.all(
                  isStickerMessage || message.isImage ? 0 : 12,
                ),
                constraints: BoxConstraints(
                  minWidth: hasBotKeyboard ? maxWidth : 0,
                  maxWidth: maxWidth,
                ),
                decoration: BoxDecoration(
                  color: isStickerMessage || message.isImage
                      ? Colors.transparent
                      : (isHighlighted
                            ? (isMe
                                  ? Colors.amber.shade100.withValues(
                                      alpha: 0.95,
                                    )
                                  : Colors.amber.shade900.withValues(
                                      alpha: 0.85,
                                    ))
                            : (isMe ? theme.myBubble : theme.otherBubble)),
                  borderRadius: isStickerMessage
                      ? null
                      : BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(isMe ? 16 : 4),
                          bottomRight: Radius.circular(isMe ? 4 : 16),
                        ),
                  border: isHighlighted
                      ? Border.all(color: Colors.amberAccent, width: 1.4)
                      : null,
                  boxShadow: isHighlighted
                      ? [
                          BoxShadow(
                            color: Colors.amberAccent.withValues(alpha: 0.22),
                            blurRadius: 18,
                            spreadRadius: 1.2,
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: isMe
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    if (_shouldShowSenderName) _buildSenderName(),
                    _buildForwardedFrom(context),
                    if (message.replyToContent != null)
                      InkWell(
                        onTap: () {
                          onReplyPreviewTap?.call(
                            message.replyToId,
                            message.replyToContent,
                            message.replyToSender,
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isMe
                                ? Colors.blue.shade50.withValues(alpha: 0.25)
                                : const Color(0xFF1F1F1F),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isMe
                                  ? Colors.blue.shade200
                                  : Colors.white12,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Icon(
                                  Icons.reply,
                                  size: 16,
                                  color: isMe
                                      ? Colors.blue.shade700
                                      : Colors.grey[400],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "${message.replyToSender != null ? '@${message.replyToSender}' : 'Пользователь'}",
                                      style: TextStyle(
                                        color: isMe
                                            ? Colors.blue.shade700
                                            : const Color(0xFF9ABDE9),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      message.replyToContent!.length > 70
                                          ? '${message.replyToContent!.substring(0, 70)}...'
                                          : message.replyToContent!,
                                      style: TextStyle(
                                        color: isMe
                                            ? Colors.grey.shade700
                                            : Colors.grey[300],
                                        fontSize: 13,
                                      ),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (message.isImage) ...[
                      if (isStickerMessage) ...[
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 180,
                            maxHeight: 180,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            clipBehavior: Clip.antiAlias,
                            child: Image.network(
                              message.content,
                              fit: BoxFit.contain,
                              width: 140,
                              errorBuilder: (_, _, _) => Container(
                                width: 140,
                                height: 140,
                                color: Colors.grey[800],
                                child: const Center(
                                  child: Icon(
                                    Icons.broken_image,
                                    color: Colors.grey,
                                    size: 48,
                                  ),
                                ),
                              ),
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return SizedBox(
                                      width: 140,
                                      height: 140,
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          value:
                                              loadingProgress
                                                      .expectedTotalBytes !=
                                                  null
                                              ? loadingProgress
                                                        .cumulativeBytesLoaded /
                                                    loadingProgress
                                                        .expectedTotalBytes!
                                              : null,
                                          color: Colors.white,
                                        ),
                                      ),
                                    );
                                  },
                            ),
                          ),
                        ),
                      ] else ...[
                        GestureDetector(
                          onDoubleTap: onReaction == null
                              ? null
                              : () => onReaction!(message, doubleTapReaction),
                          onTap: () {
                            if (onOpenImage != null) {
                              onOpenImage!(
                                message.content,
                                caption: message.imageCaption,
                              );
                            }
                          },
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: _maxImageWidth(context),
                              maxHeight: _maxImageHeight(context),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              clipBehavior: Clip.antiAlias,
                              child: Image.network(
                                message.content,
                                fit: BoxFit.contain,
                                width: _maxImageWidth(context),
                                errorBuilder: (_, _, _) => Container(
                                  width: double.infinity,
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
                                loadingBuilder:
                                    (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return Container(
                                        width: double.infinity,
                                        height: 200,
                                        color: Colors.grey[800],
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            value:
                                                loadingProgress
                                                        .expectedTotalBytes !=
                                                    null
                                                ? loadingProgress
                                                          .cumulativeBytesLoaded /
                                                      loadingProgress
                                                          .expectedTotalBytes!
                                                : null,
                                            color: Colors.white,
                                          ),
                                        ),
                                      );
                                    },
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (!isStickerMessage &&
                          message.imageCaption != null &&
                          message.imageCaption!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: UsernameMentionText(
                            text: message.imageCaption!,
                            style: TextStyle(
                              color: isMe ? theme.myText : theme.otherText,
                              fontSize: 14,
                            ),
                            linkColor: _linkColorFor(
                              isMe ? theme.myBubble : theme.otherBubble,
                            ),
                            onUrlTap: onUrlTap,
                            onUsernameTap: onUsernameTap,
                            onCommandTap: onCommandTap,
                          ),
                        ),
                      ],
                    ] else
                      Padding(
                        padding: EdgeInsets.zero,
                        child: _buildRichText(message.content, isMe),
                      ),
                    if (nftSlug != null) GiftNftLinkPreview(slug: nftSlug),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (message.isEdited)
                          Text(
                            '(изменено)',
                            style: TextStyle(
                              color: isMe
                                  ? theme.myText.withValues(alpha: 0.5)
                                  : Colors.grey[400],
                              fontSize: 10,
                            ),
                          ),
                        if (message.isEdited) const SizedBox(width: 8),
                        if (message.replyToId != null)
                          Text(
                            'ответил',
                            style: TextStyle(
                              color: isMe
                                  ? theme.myText.withValues(alpha: 0.5)
                                  : Colors.grey[400],
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        if (message.replyToId != null) const SizedBox(width: 8),
                        Text(
                          _formatTime(message.createdAt),
                          style: TextStyle(
                            color: isMe
                                ? theme.myText.withValues(alpha: 0.5)
                                : Colors.grey,
                            fontSize: 11,
                          ),
                        ),
                        if (isMe && message.id.startsWith('temp_')) ...[
                          const SizedBox(width: 4),
                          const SizedBox.square(
                            dimension: 10,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          ),
                        ] else if (showReadReceipt && isMe) ...[
                          const SizedBox(width: 3),
                          _buildReadReceipt(),
                        ],
                      ],
                    ),
                    if (hasBotKeyboard && !message.isDeleted)
                      _buildBotKeyboard(),
                  ],
                ),
              ),
            ),
            if (isMe && message.sender != null && showAvatar)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: GestureDetector(
                  onTap: () => _showSenderProfile(context, message.sender!),
                  onLongPress: () =>
                      _showSenderProfile(context, message.sender!),
                  child: _buildSenderAvatar(
                    message.sender!,
                    fallbackAvatarUrl: message.senderIsChannel
                        ? channelAvatarUrl
                        : null,
                  ),
                ),
              ),
            if (isMe && !showAvatar) const SizedBox(width: 44),
          ],
        ),
      ),
    );
  }

  Widget _buildBotKeyboard() {
    const gap = 6.0;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: message.botInlineKeyboard.map((rowButtons) {
          final buttons = rowButtons
              .whereType<Map>()
              .where((button) => (button['text']?.toString() ?? '').isNotEmpty)
              .toList();
          if (buttons.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: gap),
            child: Row(
              children: [
                for (var index = 0; index < buttons.length; index++) ...[
                  if (index > 0) const SizedBox(width: gap),
                  Expanded(child: _buildBotButton(buttons[index])),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBotButton(Map button) {
    final text = button['text']?.toString() ?? '';
    final callbackData = button['callback_data']?.toString();
    final url = button['url']?.toString();
    final style = button['style']?.toString() ?? 'primary';
    final backgroundColor = switch (style) {
      'success' => const Color(0xFF218C63),
      'danger' => const Color(0xFFC84646),
      'secondary' => const Color(0xFF596579),
      _ => const Color(0xFF3478D4),
    };

    return FilledButton(
      onPressed: callbackData != null
          ? (onBotCallback == null
                ? null
                : () => onBotCallback!(message, callbackData))
          : (url == null || onUrlTap == null ? null : () => onUrlTap!(url)),
      style: FilledButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: Colors.white,
        disabledBackgroundColor: backgroundColor.withValues(alpha: 0.45),
        disabledForegroundColor: Colors.white70,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildVoiceMessage(BuildContext context) {
    if (message.isDeleted) return _buildDeletedMessage(context);
    final theme = ThemeService().currentTheme.value;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: GestureDetector(
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, details.globalPosition),
        onLongPressStart: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: Row(
          mainAxisAlignment: isMe
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe && sender != null && showAvatar)
              GestureDetector(
                onTap: () => _showSenderProfile(context, sender!),
                onLongPress: () => _showSenderProfile(context, sender!),
                child: _buildSenderAvatar(
                  sender!,
                  fallbackAvatarUrl: message.senderIsChannel
                      ? channelAvatarUrl
                      : null,
                ),
              ),
            if (!isMe && !showAvatar) const SizedBox(width: 38),
            if (!isMe) const SizedBox(width: 8),
            if (message.voiceUrl != null)
              GestureDetector(
                onDoubleTap: onReaction == null
                    ? null
                    : () => onReaction!(message, doubleTapReaction),
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: _maxMessageBubbleWidth(context, 0.72),
                  ),
                  decoration: BoxDecoration(
                    color: isMe ? theme.myBubble : theme.otherBubble,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      if (_shouldShowSenderName) _buildSenderName(),
                      _buildForwardedFrom(context),
                      _InlineAudioPlayer(
                        url: message.voiceUrl!,
                        title: null,
                        isMe: isMe,
                        fallbackDuration: message.voiceDuration,
                        showTimeAndReceipt: true,
                        createdAt: message.createdAt,
                        showReadReceipt: showReadReceipt && isMe,
                        readReceiptBuilder: _buildReadReceipt,
                        edited: message.isEdited,
                      ),
                    ],
                  ),
                ),
              ),
            if (isMe && message.sender != null && showAvatar)
              GestureDetector(
                onTap: () => _showSenderProfile(context, message.sender!),
                onLongPress: () => _showSenderProfile(context, message.sender!),
                child: _buildSenderAvatar(
                  message.sender!,
                  fallbackAvatarUrl: message.senderIsChannel
                      ? channelAvatarUrl
                      : null,
                ),
              ),
            if (isMe && !showAvatar) const SizedBox(width: 44),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoNoteMessage(BuildContext context) {
    final videoUrl = message.fileUrl;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: GestureDetector(
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, details.globalPosition),
        onLongPressStart: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: Row(
          mainAxisAlignment: isMe
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe && sender != null && showAvatar)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => _showSenderProfile(context, sender!),
                  child: _buildSenderAvatar(
                    sender!,
                    fallbackAvatarUrl: message.senderIsChannel
                        ? channelAvatarUrl
                        : null,
                  ),
                ),
              ),
            if (!isMe && !showAvatar) const SizedBox(width: 44),
            if (!isMe) const SizedBox(width: 8),
            Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (_shouldShowSenderName) _buildSenderName(),
                SizedBox(
                  width: 236,
                  child: videoUrl == null
                      ? const SizedBox(
                          height: 236,
                          child: Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: Colors.grey,
                              size: 40,
                            ),
                          ),
                        )
                      : _VideoNotePlayer(url: videoUrl),
                ),
                SizedBox(
                  width: 236,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        _formatTime(message.createdAt),
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                      if (showReadReceipt && isMe) ...[
                        const SizedBox(width: 3),
                        _buildReadReceipt(),
                      ],
                    ],
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

class _InlineAudioPlayer extends StatefulWidget {
  final String url;
  final String? title;
  final bool isMe;
  final String? sizeLabel;
  final VoidCallback? onAddToProfile;
  final Duration? fallbackDuration;
  final bool showTimeAndReceipt;
  final DateTime? createdAt;
  final bool showReadReceipt;
  final Widget Function()? readReceiptBuilder;
  final bool edited;

  const _InlineAudioPlayer({
    required this.url,
    required this.title,
    required this.isMe,
    this.sizeLabel,
    this.onAddToProfile,
    this.fallbackDuration,
    this.showTimeAndReceipt = false,
    this.createdAt,
    this.showReadReceipt = false,
    this.readReceiptBuilder,
    this.edited = false,
  });

  @override
  State<_InlineAudioPlayer> createState() => _InlineAudioPlayerState();
}

class _InlineAudioPlayerState extends State<_InlineAudioPlayer> {
  static AudioPlayer? _activePlayer;

  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _hasStarted = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _duration = widget.fallbackDuration ?? Duration.zero;
    _subscriptions.addAll([
      _player.onPositionChanged.listen((value) {
        if (mounted) setState(() => _position = value);
      }),
      _player.onDurationChanged.listen((value) {
        if (mounted && value > Duration.zero) {
          setState(() => _duration = value);
        }
      }),
      _player.onPlayerStateChanged.listen((state) {
        if (!mounted) return;
        setState(() => _isPlaying = state == PlayerState.playing);
        if (state != PlayerState.playing && _activePlayer == _player) {
          _activePlayer = null;
        }
      }),
      _player.onPlayerComplete.listen((_) {
        if (!mounted) return;
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
          _hasStarted = false;
        });
        if (_activePlayer == _player) _activePlayer = null;
      }),
    ]);
  }

  @override
  void didUpdateWidget(covariant _InlineAudioPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _player.stop();
      setState(() {
        _position = Duration.zero;
        _duration = widget.fallbackDuration ?? Duration.zero;
        _isPlaying = false;
        _hasStarted = false;
        _error = null;
      });
    }
  }

  Future<void> _togglePlayback() async {
    try {
      if (_isPlaying) {
        await _player.pause();
        return;
      }
      if (_activePlayer != null && _activePlayer != _player) {
        await _activePlayer!.pause();
      }
      _activePlayer = _player;
      if (_hasStarted) {
        await _player.resume();
      } else {
        await _player.play(UrlSource(widget.url));
        _hasStarted = true;
      }
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _seek(Duration position) async {
    if (!_hasStarted || _duration <= Duration.zero) return;
    try {
      await _player.seek(position);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  String _format(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    if (_activePlayer == _player) _activePlayer = null;
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.isMe
        ? const Color(0xFF78A9FF)
        : const Color(0xFF78A9FF);
    final textColor = widget.isMe ? Colors.white : Colors.white;
    final maxMilliseconds = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;
    final positionMilliseconds = _position.inMilliseconds
        .clamp(0, maxMilliseconds.toInt())
        .toDouble();

    return SizedBox(
      width: widget.title == null ? 230 : 250,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 7),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: Material(
                color: accent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _togglePlayback,
                  child: Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.title != null)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (widget.onAddToProfile != null)
                          SizedBox(
                            width: 30,
                            height: 30,
                            child: IconButton(
                              tooltip: 'Добавить в профиль',
                              padding: EdgeInsets.zero,
                              icon: const Icon(
                                Icons.person_add_alt_1_rounded,
                                size: 18,
                              ),
                              color: accent,
                              onPressed: widget.onAddToProfile,
                            ),
                          ),
                      ],
                    ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 5,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 10,
                      ),
                      activeTrackColor: accent,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: accent,
                      overlayColor: accent.withValues(alpha: 0.12),
                    ),
                    child: Slider(
                      min: 0,
                      max: maxMilliseconds,
                      value: positionMilliseconds,
                      onChanged: !_hasStarted || _duration <= Duration.zero
                          ? null
                          : (value) {
                              final target = Duration(
                                milliseconds: value.round(),
                              );
                              setState(() => _position = target);
                              _seek(target);
                            },
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        _format(_position),
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.72),
                          fontSize: 10,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _format(
                          _duration > Duration.zero
                              ? _duration
                              : (widget.fallbackDuration ?? Duration.zero),
                        ),
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.72),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  if (widget.showTimeAndReceipt && widget.createdAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.edited)
                            Text(
                              'изменено · ',
                              style: TextStyle(
                                color: textColor.withValues(alpha: 0.5),
                                fontSize: 9,
                              ),
                            ),
                          Text(
                            '${widget.createdAt!.hour.toString().padLeft(2, '0')}:${widget.createdAt!.minute.toString().padLeft(2, '0')}',
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.5),
                              fontSize: 9,
                            ),
                          ),
                          if (widget.showReadReceipt &&
                              widget.readReceiptBuilder != null) ...[
                            const SizedBox(width: 3),
                            widget.readReceiptBuilder!(),
                          ],
                        ],
                      ),
                    ),
                  if (widget.title != null &&
                      widget.sizeLabel != null &&
                      widget.sizeLabel!.isNotEmpty)
                    Text(
                      widget.sizeLabel!,
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.55),
                        fontSize: 10,
                      ),
                    ),
                  if (_error != null)
                    Text(
                      'Не удалось воспроизвести',
                      style: TextStyle(
                        color: Colors.red.shade200,
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoMessagePlayer extends StatefulWidget {
  final String url;
  final VoidCallback? onSaveToGallery;

  const _VideoMessagePlayer({required this.url, this.onSaveToGallery});

  @override
  State<_VideoMessagePlayer> createState() => _VideoMessagePlayerState();
}

class _VideoMessagePlayerState extends State<_VideoMessagePlayer> {
  late VideoPlayerController _controller;
  Object? _loadError;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _initialize();
  }

  @override
  void didUpdateWidget(covariant _VideoMessagePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _controller.dispose();
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      _loadError = null;
      _isInitialized = false;
      _initialize();
    }
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      if (mounted) setState(() => _isInitialized = true);
    } catch (error) {
      debugPrint('Не удалось загрузить видео: $error');
      if (mounted) setState(() => _loadError = error);
    }
  }

  Future<void> _openFullscreen() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullscreenVideoPlayer(
          url: widget.url,
          onSaveToGallery: widget.onSaveToGallery,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return const SizedBox(
        width: 280,
        height: 158,
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280, maxHeight: 360),
      child: AspectRatio(
        aspectRatio: _isInitialized && _controller.value.aspectRatio > 0
            ? _controller.value.aspectRatio
            : 16 / 9,
        child: GestureDetector(
          onTap: _openFullscreen,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              ColoredBox(
                color: Colors.black,
                child: _isInitialized
                    ? VideoPlayer(_controller)
                    : const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF78A9FF),
                        ),
                      ),
              ),
              if (_isInitialized)
                ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: _controller,
                  builder: (context, value, child) => Stack(
                    fit: StackFit.expand,
                    children: [
                      if (!value.isPlaying)
                        Center(
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              onPressed: _openFullscreen,
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 38,
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 8,
                        child: VideoProgressIndicator(
                          _controller,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: Color(0xFF78A9FF),
                            bufferedColor: Colors.white54,
                            backgroundColor: Colors.white24,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullscreenVideoPlayer extends StatefulWidget {
  final String url;
  final VoidCallback? onSaveToGallery;

  const _FullscreenVideoPlayer({required this.url, this.onSaveToGallery});

  @override
  State<_FullscreenVideoPlayer> createState() => _FullscreenVideoPlayerState();
}

class _FullscreenVideoPlayerState extends State<_FullscreenVideoPlayer> {
  late final VideoPlayerController _controller;
  Object? _loadError;
  bool _isInitialized = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      await _controller.play();
      if (mounted) setState(() => _isInitialized = true);
    } catch (error) {
      debugPrint('Не удалось открыть видео на весь экран: $error');
      if (mounted) setState(() => _loadError = error);
    }
  }

  Future<void> _togglePlayback() async {
    if (!_isInitialized) return;
    try {
      if (_controller.value.isPlaying) {
        await _controller.pause();
      } else {
        await _controller.play();
      }
    } catch (error) {
      debugPrint('Не удалось воспроизвести видео: $error');
      if (mounted) setState(() => _loadError = error);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (widget.onSaveToGallery != null)
            IconButton(
              tooltip: 'Сохранить в галерею',
              onPressed: widget.onSaveToGallery,
              icon: const Icon(Icons.save_alt_rounded),
            ),
        ],
      ),
      body: Center(
        child: _loadError != null
            ? const Icon(Icons.error_outline, color: Colors.redAccent, size: 42)
            : !_isInitialized
            ? const CircularProgressIndicator(color: Color(0xFF78A9FF))
            : GestureDetector(
                onTap: () => setState(() => _showControls = !_showControls),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AspectRatio(
                      aspectRatio: _controller.value.aspectRatio > 0
                          ? _controller.value.aspectRatio
                          : 16 / 9,
                      child: VideoPlayer(_controller),
                    ),
                    if (_showControls)
                      ValueListenableBuilder<VideoPlayerValue>(
                        valueListenable: _controller,
                        builder: (context, value, child) => Stack(
                          children: [
                            Center(
                              child: IconButton(
                                onPressed: _togglePlayback,
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black54,
                                  foregroundColor: Colors.white,
                                ),
                                iconSize: 64,
                                icon: Icon(
                                  value.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                              ),
                            ),
                            Positioned(
                              left: 20,
                              right: 20,
                              bottom: 20,
                              child: VideoProgressIndicator(
                                _controller,
                                allowScrubbing: true,
                                colors: const VideoProgressColors(
                                  playedColor: Color(0xFF78A9FF),
                                  bufferedColor: Colors.white54,
                                  backgroundColor: Colors.white24,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _VideoNotePlayer extends StatefulWidget {
  final String url;

  const _VideoNotePlayer({required this.url});

  @override
  State<_VideoNotePlayer> createState() => _VideoNotePlayerState();
}

class _VideoNotePlayerState extends State<_VideoNotePlayer> {
  late VideoPlayerController _controller;
  Timer? _controlsTimer;
  Object? _loadError;
  bool _isInitialized = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _initialize();
  }

  @override
  void didUpdateWidget(covariant _VideoNotePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _controlsTimer?.cancel();
      _controller.dispose();
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      _loadError = null;
      _isInitialized = false;
      _initialize();
    }
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      await _controller.setLooping(true);
      if (mounted) setState(() => _isInitialized = true);
    } catch (error) {
      debugPrint('Не удалось загрузить видеокружок: $error');
      if (mounted) setState(() => _loadError = error);
    }
  }

  Future<void> _togglePlayback() async {
    if (!_isInitialized) return;
    try {
      if (_controller.value.isPlaying) {
        await _controller.pause();
        _controlsTimer?.cancel();
        if (mounted) setState(() => _showControls = true);
      } else {
        await _controller.play();
        _revealControls();
      }
    } catch (error) {
      debugPrint('Не удалось воспроизвести видеокружок: $error');
      if (mounted) setState(() => _loadError = error);
    }
  }

  void _revealControls() {
    _controlsTimer?.cancel();
    if (mounted) setState(() => _showControls = true);
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    try {
      await _controller.setPlaybackSpeed(speed);
      _revealControls();
    } catch (error) {
      debugPrint('Не удалось изменить скорость видеокружка: $error');
      if (mounted) {
        setState(() => _loadError = error);
      }
    }
  }

  Future<void> _closePlayback() async {
    _controlsTimer?.cancel();
    try {
      if (_isInitialized) {
        await _controller.pause();
        await _controller.seekTo(Duration.zero);
        await _controller.setPlaybackSpeed(1);
      }
      if (mounted) setState(() => _showControls = false);
    } catch (error) {
      debugPrint('Не удалось закрыть видеокружок: $error');
      if (mounted) setState(() => _loadError = error);
    }
  }

  Future<void> _seekTo(Offset localPosition) async {
    if (!_isInitialized) return;
    final center = const Offset(118, 118);
    final offset = localPosition - center;
    final angle =
        (math.atan2(offset.dy, offset.dx) + math.pi / 2) % (2 * math.pi);
    final progress = (angle < 0 ? angle + 2 * math.pi : angle) / (2 * math.pi);
    final duration = _controller.value.duration;
    if (duration.inMilliseconds <= 0) return;
    _revealControls();
    await _controller.seekTo(
      Duration(milliseconds: (duration.inMilliseconds * progress).round()),
    );
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return const SizedBox(
        width: 236,
        height: 236,
        child: Center(
          child: Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_showControls) ...[
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: const Color(0xE61A1D24),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final speed in [0.5, 1.0, 1.5, 2.0])
                  _VideoSpeedButton(
                    speed: speed,
                    selected: _controller.value.playbackSpeed == speed,
                    onTap: () => _setPlaybackSpeed(speed),
                  ),
                const SizedBox(width: 2),
                IconButton(
                  tooltip: 'Закрыть кружок',
                  onPressed: _closePlayback,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white70,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
        GestureDetector(
          onTap: _togglePlayback,
          onPanStart: (_) => _revealControls(),
          onPanUpdate: (details) => unawaited(_seekTo(details.localPosition)),
          child: SizedBox.square(
            dimension: 236,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 220,
                  height: 220,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _isInitialized
                      ? VideoPlayer(_controller)
                      : const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF1A73E8),
                          ),
                        ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: _controller,
                      builder: (context, value, child) => CustomPaint(
                        painter: _VideoNoteProgressPainter(
                          progress: value.duration.inMilliseconds == 0
                              ? 0
                              : value.position.inMilliseconds /
                                    value.duration.inMilliseconds,
                          isPlaying: value.isPlaying,
                        ),
                      ),
                    ),
                  ),
                ),
                if (!_controller.value.isPlaying || _showControls)
                  IgnorePointer(
                    child: Icon(
                      _controller.value.isPlaying
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                      color: Colors.white,
                      size: 64,
                      shadows: const [
                        Shadow(color: Colors.black54, blurRadius: 8),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _VideoSpeedButton extends StatelessWidget {
  final double speed;
  final bool selected;
  final VoidCallback onTap;

  const _VideoSpeedButton({
    required this.speed,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = speed == 1
        ? '1×'
        : '${speed.toStringAsFixed(speed == speed.roundToDouble() ? 0 : 1)}×';
    return Material(
      color: selected ? const Color(0xFF2675D8) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoNoteProgressPainter extends CustomPainter {
  final double progress;
  final bool isPlaying;

  const _VideoNoteProgressPainter({
    required this.progress,
    required this.isPlaying,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 3.5;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - strokeWidth / 2;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final progressPaint = Paint()
      ..color = const Color(0xFF58A6FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(bounds, -math.pi / 2, 2 * math.pi, false, trackPaint);
    final normalizedProgress = progress.clamp(0.0, 1.0);
    final sweep = normalizedProgress * 2 * math.pi;
    canvas.drawArc(bounds, -math.pi / 2, sweep, false, progressPaint);

    if (isPlaying && normalizedProgress > 0) {
      final angle = -math.pi / 2 + sweep;
      final knobCenter = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      canvas.drawCircle(
        knobCenter,
        5,
        Paint()..color = const Color(0xFF58A6FF),
      );
      canvas.drawCircle(knobCenter, 2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _VideoNoteProgressPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.isPlaying != isPlaying;
}

class _QuickReactionsMenuEntry extends PopupMenuEntry<void> {
  const _QuickReactionsMenuEntry({
    required this.reactions,
    required this.onSelected,
  });

  final List<String> reactions;
  final ValueChanged<String> onSelected;

  @override
  double get height => 52;

  @override
  bool represents(Object? value) => false;

  @override
  State<_QuickReactionsMenuEntry> createState() =>
      _QuickReactionsMenuEntryState();
}

class _QuickReactionsMenuEntryState extends State<_QuickReactionsMenuEntry> {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF303642),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: widget.reactions.map((reaction) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onSelected(reaction),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Text(reaction, style: const TextStyle(fontSize: 22)),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _MessageSwipeGesture extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onSwipeRight;

  const _MessageSwipeGesture({
    required this.child,
    this.onSwipeLeft,
    this.onSwipeRight,
  });

  @override
  State<_MessageSwipeGesture> createState() => _MessageSwipeGestureState();
}

class _MessageSwipeGestureState extends State<_MessageSwipeGesture> {
  static const double _maxDrag = 92;
  static const double _actionThreshold = 68;
  double _dragOffset = 0;

  void _handleDragUpdate(DragUpdateDetails details) {
    if (widget.onSwipeLeft == null && widget.onSwipeRight == null) return;
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dx).clamp(-_maxDrag, _maxDrag);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    final shouldReply =
        widget.onSwipeLeft != null &&
        (_dragOffset <= -_actionThreshold ||
            (_dragOffset < 0 && velocity <= -700));
    final shouldForward =
        widget.onSwipeRight != null &&
        (_dragOffset >= _actionThreshold ||
            (_dragOffset > 0 && velocity >= 700));

    setState(() => _dragOffset = 0);
    if (shouldReply) {
      widget.onSwipeLeft?.call();
    } else if (shouldForward) {
      widget.onSwipeRight?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReplySwipe = _dragOffset < 0;
    final actionEnabled = isReplySwipe
        ? widget.onSwipeLeft != null
        : widget.onSwipeRight != null;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      onHorizontalDragCancel: () => setState(() => _dragOffset = 0),
      child: AnimatedContainer(
        duration: _dragOffset == 0
            ? const Duration(milliseconds: 180)
            : Duration.zero,
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(_dragOffset, 0, 0),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            widget.child,
            if (_dragOffset.abs() > 12 && actionEnabled)
              Positioned(
                left: isReplySwipe ? null : -38,
                right: isReplySwipe ? -38 : null,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Opacity(
                      opacity: (_dragOffset.abs() / _actionThreshold).clamp(
                        0.25,
                        1,
                      ),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1D3A5F),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(
                              0xFF4F84C4,
                            ).withValues(alpha: 0.65),
                          ),
                        ),
                        child: Icon(
                          isReplySwipe ? Icons.reply : Icons.forward,
                          color: const Color(0xFF9ABDE9),
                          size: 19,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
