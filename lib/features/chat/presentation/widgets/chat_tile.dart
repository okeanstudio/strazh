import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:strazh/shared/domain/models/chat.dart';
import 'package:strazh/features/chat/presentation/screens/chat.dart';
import 'package:strazh/features/auth/presentation/screens/login_codes_chat_screen.dart';
import 'package:strazh/shared/domain/models/user.dart' as app;
import 'package:strazh/shared/presentation/widgets/avatar_preview.dart';

class ChatTile extends StatefulWidget {
  final Chat chat;
  final app.User currentUser;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isPinned;
  final bool isMuted;
  final int animationIndex;

  const ChatTile({
    super.key,
    required this.chat,
    required this.currentUser,
    this.onTap,
    this.onLongPress,
    this.isPinned = false,
    this.isMuted = false,
    this.animationIndex = 0,
  });

  @override
  State<ChatTile> createState() => _ChatTileState();
}

class _ChatTileState extends State<ChatTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _entryOpacity;
  late final Animation<Offset> _entrySlide;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    final entryCurve = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );
    _entryOpacity = entryCurve;
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(entryCurve);

    final delay = (widget.animationIndex * 24).clamp(0, 280).toInt();
    Future<void>.delayed(Duration(milliseconds: delay), () {
      if (mounted) _entryController.forward();
    });
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  String _formatLastMessageTime(DateTime? time) {
    if (time == null) return '';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(time.year, time.month, time.day);

    if (messageDate == today) {
      return 'Сегодня';
    }

    if (messageDate == yesterday) {
      return 'Вчера';
    }

    final weekAgo = today.subtract(const Duration(days: 7));
    if (messageDate.isAfter(weekAgo) && messageDate.isBefore(today)) {
      const weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
      return weekdays[time.weekday - 1];
    }

    return '${time.day.toString().padLeft(2, '0')}.${time.month.toString().padLeft(2, '0')}.${time.year}';
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = widget.chat.unreadCount > 0;
    final avatarUrl = widget.chat.avatarUrl;
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;

    return FadeTransition(
      opacity: _entryOpacity,
      child: SlideTransition(
        position: _entrySlide,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () {
              if (widget.onTap != null) {
                widget.onTap!();
              } else if (widget.chat.type == 'login_codes') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LoginCodesChatScreen(),
                  ),
                );
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(
                      chat: widget.chat,
                      currentUser: widget.currentUser,
                    ),
                  ),
                );
              }
            },
            onLongPress: widget.onLongPress == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    widget.onLongPress!();
                  },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _hover
                    ? Colors.white.withValues(alpha: 0.055)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  // ===== АВАТАРКА С ПОДДЕРЖКОЙ URL =====
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      GestureDetector(
                        onTap: hasAvatar
                            ? () => showAvatarPreview(
                                context,
                                image: NetworkImage(avatarUrl),
                              )
                            : null,
                        child: CircleAvatar(
                          radius: 26,
                          backgroundColor: const Color(0xFF29262A),
                          backgroundImage: hasAvatar
                              ? NetworkImage(avatarUrl)
                              : null,
                          child: !hasAvatar
                              ? (widget.chat.type == 'saved'
                                    ? const Icon(
                                        Icons.bookmark,
                                        color: Colors.white,
                                        size: 26,
                                      )
                                    : Text(
                                        widget.chat.name.isNotEmpty
                                            ? widget.chat.name[0].toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ))
                              : null,
                        ),
                      ),
                      // Звездочку убрали — этот блок удалён
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
                                widget.chat.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (widget.chat.type == 'channel' &&
                                widget.chat.isVerified) ...[
                              const SizedBox(width: 5),
                              const Icon(
                                Icons.verified,
                                color: Color(0xFF1A73E8),
                                size: 16,
                              ),
                            ],
                            if (widget.isPinned) ...[
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.push_pin_rounded,
                                color: Color(0xFF8F8BFF),
                                size: 13,
                              ),
                            ],
                            if (widget.isMuted) ...[
                              const SizedBox(width: 5),
                              Icon(
                                Icons.notifications_off_outlined,
                                color: Colors.grey[500],
                                size: 14,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (widget.chat.lastMessageIsMe) ...[
                              Icon(
                                widget.chat.lastMessageReadByOthers
                                    ? Icons.done_all
                                    : Icons.done,
                                color: widget.chat.lastMessageReadByOthers
                                    ? const Color(0xFF64B5F6)
                                    : Colors.grey[500],
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                widget.chat.lastMessage ?? 'Нет сообщений',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (widget.chat.lastMessageTime != null) ...[
                        Text(
                          _formatLastMessageTime(widget.chat.lastMessageTime),
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 13,
                          ),
                        ),
                      ],
                      if (hasUnread) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 0,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 20,
                            minHeight: 20,
                          ),
                          child: Center(
                            child: Text(
                              widget.chat.unreadCount > 99
                                  ? '99+'
                                  : widget.chat.unreadCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
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
