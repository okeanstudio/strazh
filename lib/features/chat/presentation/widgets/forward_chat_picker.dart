import 'package:flutter/material.dart';
import 'package:strazh/shared/domain/models/chat.dart';
import 'package:strazh/shared/domain/models/message.dart';

Future<Chat?> showForwardChatPicker(
  BuildContext context, {
  required Message message,
  int messageCount = 1,
  required List<Chat> chats,
}) {
  return showModalBottomSheet<Chat>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ForwardChatPicker(
      message: message,
      messageCount: messageCount,
      chats: chats,
    ),
  );
}

class _ForwardChatPicker extends StatefulWidget {
  final Message message;
  final int messageCount;
  final List<Chat> chats;

  const _ForwardChatPicker({
    required this.message,
    required this.messageCount,
    required this.chats,
  });

  @override
  State<_ForwardChatPicker> createState() => _ForwardChatPickerState();
}

class _ForwardChatPickerState extends State<_ForwardChatPicker> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _messagePreview {
    if (widget.message.isDeleted) return 'Сообщение удалено';
    if (widget.message.isVoice) return 'Голосовое сообщение';
    if (widget.message.isFile) {
      return 'Файл: ${widget.message.fileName ?? 'Документ'}';
    }
    if (widget.message.isImage) {
      if (widget.message.isSticker) return 'Стикер';
      final caption = widget.message.imageCaption?.trim() ?? '';
      return caption.isEmpty ? 'Фото' : 'Фото: $caption';
    }
    return widget.message.content;
  }

  String get _originalAuthor {
    return widget.message.forwardedFromName ??
        widget.message.sender?.name ??
        'Вы';
  }

  List<Chat> get _filteredChats {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.chats;
    return widget.chats
        .where((chat) => chat.name.toLowerCase().contains(query))
        .toList();
  }

  Widget _buildChatAvatar(Chat chat) {
    final hasAvatar = chat.avatarUrl?.isNotEmpty == true;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: const Color(0xFF313843),
          backgroundImage: hasAvatar ? NetworkImage(chat.avatarUrl!) : null,
          child: hasAvatar
              ? null
              : Text(
                  chat.name.isEmpty ? '?' : chat.name[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
        if (chat.type == 'saved')
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              width: 17,
              height: 17,
              decoration: BoxDecoration(
                color: const Color(0xFFFFC857),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF151923)),
              ),
              child: const Icon(
                Icons.star_rounded,
                color: Color(0xFF30230A),
                size: 12,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredChats = _filteredChats;
    final screenHeight = MediaQuery.sizeOf(context).height;

    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            constraints: BoxConstraints(maxHeight: screenHeight * 0.84),
            decoration: BoxDecoration(
              color: const Color(0xFF151923),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.forward, color: Color(0xFF9ABDE9)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.messageCount == 1
                              ? 'Переслать сообщение'
                              : 'Переслать ${widget.messageCount} сообщений',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Закрыть',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1D3A5F), Color(0xFF2A2A2A)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF4F84C4).withValues(alpha: 0.45),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF1A73E8,
                            ).withValues(alpha: 0.22),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.forward,
                            color: Color(0xFF9ABDE9),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Переслано от $_originalAuthor',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF9ABDE9),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _messagePreview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.grey[300],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Поиск чата',
                      hintStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Colors.white54,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF202530),
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: filteredChats.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Чаты не найдены',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          itemCount: filteredChats.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            indent: 62,
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                          itemBuilder: (context, index) {
                            final chat = filteredChats[index];
                            return ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              leading: _buildChatAvatar(chat),
                              title: Text(
                                chat.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                chat.type == 'saved'
                                    ? 'Сообщения самому себе'
                                    : chat.lastMessage ?? 'Нет сообщений',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right,
                                color: Colors.white38,
                              ),
                              onTap: () => Navigator.pop(context, chat),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
