import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' as image_picker;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/features/auth/data/services/auth_service.dart';
import 'package:strazh/features/support/data/services/support_ticket_service.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';
import 'package:url_launcher/url_launcher.dart';

class SupportTicketConversationScreen extends StatefulWidget {
  final Map<String, dynamic> ticket;
  final bool isSupport;

  const SupportTicketConversationScreen({
    super.key,
    required this.ticket,
    required this.isSupport,
  });

  @override
  State<SupportTicketConversationScreen> createState() =>
      _SupportTicketConversationScreenState();
}

class _SupportTicketConversationScreenState
    extends State<SupportTicketConversationScreen> {
  final SupportTicketService _ticketService = SupportTicketService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _messagesScrollController = ScrollController();
  final String? _currentUserId = AuthService().currentUserId;
  List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _channel;
  XFile? _selectedAttachment;
  Uint8List? _selectedAttachmentPreview;
  bool _isLoading = true;
  bool _isSending = false;

  String get _ticketId => widget.ticket['id'] as String;
  bool get _isNearBottom =>
      !_messagesScrollController.hasClients ||
      _messagesScrollController.position.pixels >=
          _messagesScrollController.position.maxScrollExtent - 120;

  @override
  void initState() {
    super.initState();
    _loadMessages(scrollToBottom: true);
    _subscribeToMessages();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _messageController.dispose();
    _messagesScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages({bool scrollToBottom = false}) async {
    try {
      final messages = await _ticketService.getMessages(_ticketId);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _isLoading = false;
      });
      if (scrollToBottom) _scheduleScrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      Toast.error(context, 'Не удалось загрузить переписку');
    }
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_messagesScrollController.hasClients) return;
      _messagesScrollController.animateTo(
        _messagesScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _subscribeToMessages() {
    _channel = Supabase.instance.client
        .channel('support_ticket_$_ticketId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'support_ticket_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'ticket_id',
            value: _ticketId,
          ),
          callback: (payload) {
            unawaited(_loadMessages(scrollToBottom: _isNearBottom));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'support_tickets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: _ticketId,
          ),
          callback: (payload) {
            if (!mounted) return;
            setState(() {
              widget.ticket['status'] = payload.newRecord['status'];
            });
          },
        )
        .subscribe();
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if ((message.isEmpty && _selectedAttachment == null) || _isSending) return;

    setState(() => _isSending = true);
    try {
      await _ticketService.sendReply(
        ticketId: _ticketId,
        body: message,
        fromSupport: widget.isSupport,
        attachment: _selectedAttachment,
      );
      if (!mounted) return;
      _messageController.clear();
      setState(() {
        _selectedAttachment = null;
        _selectedAttachmentPreview = null;
      });
      await _loadMessages(scrollToBottom: true);
    } catch (error) {
      if (mounted) Toast.error(context, 'Не удалось отправить ответ');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _pickAttachment() async {
    try {
      final source = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: const Color(0xFF15121C),
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Фото из галереи'),
                onTap: () => Navigator.pop(sheetContext, 'gallery'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Сделать фото'),
                onTap: () => Navigator.pop(sheetContext, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: const Text('Выбрать файл'),
                onTap: () => Navigator.pop(sheetContext, 'file'),
              ),
            ],
          ),
        ),
      );
      if (source == null || !mounted) return;

      final XFile? attachment = switch (source) {
        'gallery' => await image_picker.ImagePicker().pickImage(
          source: image_picker.ImageSource.gallery,
        ),
        'camera' => await image_picker.ImagePicker().pickImage(
          source: image_picker.ImageSource.camera,
        ),
        _ => await openFile(),
      };

      if (attachment == null || !mounted) return;
      if (await attachment.length() > SupportTicketService.maxAttachmentSize) {
        if (mounted) Toast.error(context, 'Максимальный размер файла: 15 МБ');
        return;
      }
      final preview = _isImageFile(attachment.name)
          ? await attachment.readAsBytes()
          : null;
      if (!mounted) return;
      setState(() {
        _selectedAttachment = attachment;
        _selectedAttachmentPreview = preview;
      });
    } catch (_) {
      if (mounted) Toast.error(context, 'Не удалось выбрать файл');
    }
  }

  bool _isImageFile(String name) {
    final extension = name.split('.').last.toLowerCase();
    return const {
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'heic',
      'heif',
      'bmp',
    }.contains(extension);
  }

  Future<void> _closeTicket() async {
    final shouldClose = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF15121C),
        title: const Text(
          'Закрыть обращение?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'После закрытия отправлять сообщения в тикет будет нельзя.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
    if (shouldClose != true || !mounted) return;

    try {
      await _ticketService.closeOwnTicket(_ticketId);
      if (!mounted) return;
      setState(() => widget.ticket['status'] = 'closed');
      Toast.success(context, 'Обращение закрыто');
    } catch (_) {
      if (mounted) Toast.error(context, 'Не удалось закрыть обращение');
    }
  }

  String _categoryLabel(String? category) {
    switch (category) {
      case 'technical':
        return 'Техническая проблема';
      case 'account':
        return 'Аккаунт и доступ';
      case 'payments':
        return 'Оплата и подписка';
      case 'suggestion':
        return 'Предложение';
      default:
        return 'Другое';
    }
  }

  String _fileSizeLabel(dynamic rawSize) {
    final size = rawSize is num ? rawSize.toInt() : 0;
    if (size >= 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} МБ';
    }
    if (size >= 1024) {
      return '${(size / 1024).toStringAsFixed(0)} КБ';
    }
    return '$size Б';
  }

  Widget _buildAttachment(Map<String, dynamic> message) {
    final url = message['attachment_url'] as String?;
    final name = message['attachment_name'] as String? ?? 'Вложение';
    final mimeType = message['attachment_mime_type'] as String? ?? '';
    if (url == null) {
      return Text(
        'Вложение недоступно: $name',
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      );
    }

    if (mimeType.startsWith('image/')) {
      return Padding(
        padding: const EdgeInsets.only(top: 7),
        child: GestureDetector(
          onTap: () =>
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              width: 220,
              height: 180,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(
                width: 220,
                height: 80,
                child: Center(
                  child: Text(
                    'Не удалось загрузить фото',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: InkWell(
        onTap: () =>
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minWidth: 180, maxWidth: 240),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.insert_drive_file_outlined,
                color: Colors.white70,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    Text(
                      _fileSizeLabel(message['attachment_size']),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.open_in_new, color: Colors.white54, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'in_progress':
        return 'В работе';
      case 'answered':
        return 'Есть ответ';
      case 'closed':
        return 'Закрыт';
      default:
        return 'Открыт';
    }
  }

  String _formatTime(dynamic rawDate) {
    final date = DateTime.tryParse(rawDate?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildMessage(Map<String, dynamic> message) {
    final isOwn = message['sender_id'] == _currentUserId;
    final isSupportReply = message['sender_type'] == 'support';
    final label = isSupportReply
        ? (widget.isSupport && isOwn ? 'Вы · Поддержка' : 'Поддержка')
        : (isOwn ? 'Вы' : (widget.ticket['user_name'] ?? 'Пользователь'));

    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
          decoration: BoxDecoration(
            color: isSupportReply
                ? const Color(0xFF174C48)
                : const Color(0xFF24212B),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isSupportReply
                      ? const Color(0xFF8CE0C9)
                      : Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                message['body'] as String? ?? '',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              if (message['attachment_path'] != null) _buildAttachment(message),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _formatTime(message['created_at']),
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isClosed = widget.ticket['status'] == 'closed';
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0A0A),
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.ticket['subject'] as String? ?? 'Обращение',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              _statusLabel(widget.ticket['status'] as String?),
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
        actions: [
          if (!widget.isSupport && !isClosed)
            IconButton(
              tooltip: 'Закрыть обращение',
              onPressed: _closeTicket,
              icon: const Icon(Icons.check_circle_outline),
            ),
          if (widget.isSupport)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (status) async {
                try {
                  await _ticketService.setTicketStatus(_ticketId, status);
                  if (mounted) setState(() => widget.ticket['status'] = status);
                } catch (_) {
                  if (!context.mounted) return;
                  Toast.error(context, 'Не удалось сменить статус');
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'open', child: Text('Открыт')),
                PopupMenuItem(value: 'in_progress', child: Text('В работе')),
                PopupMenuItem(value: 'closed', child: Text('Закрыть')),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          if (widget.isSupport)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              color: const Color(0xFF15121C),
              child: Text(
                '${widget.ticket['user_name'] ?? 'Пользователь'}  ·  ${widget.ticket['user_tag'] == '' ? '' : '@${widget.ticket['user_tag']}  ·  '}${_categoryLabel(widget.ticket['category'] as String?)}',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? const Center(
                    child: Text(
                      'Сообщений пока нет',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    controller: _messagesScrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) =>
                        _buildMessage(_messages[index]),
                  ),
          ),
          if (isClosed && !widget.isSupport)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Обращение закрыто',
                style: TextStyle(color: Colors.white54),
              ),
            )
          else
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'Прикрепить файл',
                          onPressed: _isSending ? null : _pickAttachment,
                          icon: const Icon(Icons.attach_file),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            minLines: 1,
                            maxLines: 5,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Напишите ответ...',
                              hintStyle: const TextStyle(color: Colors.white38),
                              filled: true,
                              fillColor: const Color(0xFF1A1A1A),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 11,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: 'Отправить',
                          onPressed: _isSending ? null : _sendMessage,
                          icon: _isSending
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send),
                        ),
                      ],
                    ),
                    if (_selectedAttachment != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            if (_selectedAttachmentPreview != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.memory(
                                  _selectedAttachmentPreview!,
                                  width: 52,
                                  height: 52,
                                  fit: BoxFit.cover,
                                ),
                              )
                            else
                              const Icon(
                                Icons.attach_file,
                                size: 16,
                                color: Colors.white54,
                              ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedAttachment!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Убрать вложение',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => setState(() {
                                _selectedAttachment = null;
                                _selectedAttachmentPreview = null;
                              }),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ],
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
