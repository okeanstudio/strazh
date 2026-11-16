import 'package:flutter/material.dart';
import 'package:strazh/shared/domain/models/chat.dart';

enum ChatListAction { togglePin, toggleArchive, toggleMute, moveToFolder }

Future<ChatListAction?> showChatActionsSheet({
  required BuildContext context,
  required Chat chat,
  required bool isPinned,
  required bool isArchived,
  required bool isMuted,
}) {
  return showModalBottomSheet<ChatListAction>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => _ChatActionsSheet(
      chat: chat,
      isPinned: isPinned,
      isArchived: isArchived,
      isMuted: isMuted,
    ),
  );
}

class _ChatActionsSheet extends StatelessWidget {
  const _ChatActionsSheet({
    required this.chat,
    required this.isPinned,
    required this.isArchived,
    required this.isMuted,
  });

  final Chat chat;
  final bool isPinned;
  final bool isArchived;
  final bool isMuted;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = chat.avatarUrl;
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
    final chatType = switch (chat.type) {
      'channel' => 'Канал',
      'group' => 'Группа',
      'saved' => 'Избранное',
      'login_codes' => 'Защищённый чат',
      _ => 'Личный чат',
    };

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        decoration: BoxDecoration(
          color: const Color(0xFF191820),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: const Color(0xFF302B3A),
                  backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
                  child: hasAvatar
                      ? null
                      : Text(
                          chat.name.isEmpty ? '?' : chat.name[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chat.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        chatType,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.46),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Закрыть',
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close_rounded,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _ActionTile(
              icon: isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              color: const Color(0xFF8F8BFF),
              title: isPinned ? 'Открепить' : 'Закрепить',
              subtitle: 'Чат будет выше остальных',
              onTap: () => Navigator.pop(context, ChatListAction.togglePin),
            ),
            _ActionTile(
              icon: isArchived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
              color: const Color(0xFF67C6B0),
              title: isArchived ? 'Вернуть из архива' : 'В архив',
              subtitle: isArchived
                  ? 'Чат снова появится в общем списке'
                  : 'Чат исчезнет из общего списка',
              onTap: () => Navigator.pop(context, ChatListAction.toggleArchive),
            ),
            _ActionTile(
              icon: isMuted
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
              color: const Color(0xFFFFB86B),
              title: isMuted ? 'Включить уведомления' : 'Выключить звук',
              subtitle: isMuted
                  ? 'Снова получать уведомления о сообщениях'
                  : 'Не показывать уведомления для этого чата',
              onTap: () => Navigator.pop(context, ChatListAction.toggleMute),
            ),
            const SizedBox(height: 5),
            _ActionTile(
              icon: Icons.folder_open_rounded,
              color: const Color(0xFF6FB8FF),
              title: 'Переместить в папку',
              subtitle: 'Разложить чаты по своим папкам',
              onTap: () => Navigator.pop(context, ChatListAction.moveToFolder),
              isLast: true,
            ),
            const SizedBox(height: 8),
            Text(
              'Настройки синхронизируются с аккаунтом',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.32),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isLast = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(17),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 21),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.42),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 19,
                  color: Colors.white.withValues(alpha: 0.24),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
