import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/features/support/presentation/screens/support_ticket_conversation_screen.dart';
import 'package:strazh/features/support/data/services/support_ticket_service.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

class SupportTicketsScreen extends StatefulWidget {
  const SupportTicketsScreen({super.key});

  @override
  State<SupportTicketsScreen> createState() => _SupportTicketsScreenState();
}

class _SupportTicketsScreenState extends State<SupportTicketsScreen> {
  final SupportTicketService _service = SupportTicketService();
  List<Map<String, dynamic>> _tickets = [];
  RealtimeChannel? _channel;
  bool _isLoading = true;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _loadTickets();
    _subscribeToTickets();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadTickets() async {
    try {
      final tickets = await _service.getMyTickets();
      if (!mounted) return;
      setState(() {
        _tickets = tickets;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      Toast.error(context, 'Не удалось загрузить обращения');
    }
  }

  void _subscribeToTickets() {
    _channel = Supabase.instance.client
        .channel(
          'my_support_tickets_${Supabase.instance.client.auth.currentUser?.id}',
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'support_ticket_messages',
          callback: (payload) => unawaited(_loadTickets()),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'support_tickets',
          callback: (payload) => unawaited(_loadTickets()),
        )
        .subscribe();
  }

  Future<void> _showCreateTicket() async {
    final ticketData = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _CreateTicketDialog(),
    );
    if (ticketData == null || !mounted) return;

    setState(() => _isCreating = true);
    try {
      final ticket = await _service.createTicket(
        category: ticketData['category']!,
        subject: ticketData['subject']!,
        message: ticketData['message']!,
      );
      if (!mounted) return;
      await _loadTickets();
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              SupportTicketConversationScreen(ticket: ticket, isSupport: false),
        ),
      );
    } catch (error) {
      if (mounted) Toast.error(context, 'Не удалось создать обращение');
    } finally {
      if (mounted) setState(() => _isCreating = false);
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

  Color _statusColor(String? status) {
    switch (status) {
      case 'answered':
        return const Color(0xFF65D6A6);
      case 'in_progress':
        return const Color(0xFF78B7FF);
      case 'closed':
        return Colors.white54;
      default:
        return const Color(0xFFFFC46B);
    }
  }

  String _formatDate(dynamic rawDate) {
    final date = DateTime.tryParse(rawDate?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      appBar: AppBar(
        title: const Text('Поддержка'),
        backgroundColor: const Color(0xFF0D0A0A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _loadTickets,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isCreating ? null : _showCreateTicket,
        icon: _isCreating
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: const Text('Новое обращение'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _tickets.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.support_agent,
                    color: Colors.white38,
                    size: 44,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Пока нет обращений',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Создайте тикет, чтобы связаться с поддержкой',
                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadTickets,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                itemCount: _tickets.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final ticket = _tickets[index];
                  final status = ticket['status'] as String?;
                  return Material(
                    color: const Color(0xFF15121C),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SupportTicketConversationScreen(
                            ticket: ticket,
                            isSupport: false,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    ticket['subject'] as String? ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _statusLabel(status),
                                  style: TextStyle(
                                    color: _statusColor(status),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _categoryLabel(
                                      ticket['category'] as String?,
                                    ),
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                Text(
                                  _formatDate(ticket['updated_at']),
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _CreateTicketDialog extends StatefulWidget {
  const _CreateTicketDialog();

  @override
  State<_CreateTicketDialog> createState() => _CreateTicketDialogState();
}

class _CreateTicketDialogState extends State<_CreateTicketDialog> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  String _category = 'technical';

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF15121C),
      title: const Text(
        'Новое обращение',
        style: TextStyle(color: Colors.white),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _category,
                dropdownColor: const Color(0xFF24212B),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Категория',
                  labelStyle: TextStyle(color: Colors.white60),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'technical',
                    child: Text('Техническая проблема'),
                  ),
                  DropdownMenuItem(
                    value: 'account',
                    child: Text('Аккаунт и доступ'),
                  ),
                  DropdownMenuItem(
                    value: 'payments',
                    child: Text('Оплата и подписка'),
                  ),
                  DropdownMenuItem(
                    value: 'suggestion',
                    child: Text('Предложение'),
                  ),
                  DropdownMenuItem(value: 'other', child: Text('Другое')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _subjectController,
                maxLength: 100,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Тема',
                  labelStyle: TextStyle(color: Colors.white60),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Введите тему обращения'
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _messageController,
                minLines: 3,
                maxLines: 6,
                maxLength: 3000,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Опишите вопрос',
                  labelStyle: TextStyle(color: Colors.white60),
                  alignLabelWithHint: true,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Напишите первое сообщение'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, {
              'category': _category,
              'subject': _subjectController.text.trim(),
              'message': _messageController.text.trim(),
            });
          },
          child: const Text('Создать'),
        ),
      ],
    );
  }
}
