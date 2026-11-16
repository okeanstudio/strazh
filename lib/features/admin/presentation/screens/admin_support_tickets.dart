import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/features/support/presentation/screens/support_ticket_conversation_screen.dart';
import 'package:strazh/features/support/data/services/support_ticket_service.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

class AdminSupportTicketsScreen extends StatefulWidget {
  const AdminSupportTicketsScreen({super.key});

  @override
  State<AdminSupportTicketsScreen> createState() =>
      _AdminSupportTicketsScreenState();
}

class _AdminSupportTicketsScreenState extends State<AdminSupportTicketsScreen> {
  final SupportTicketService _service = SupportTicketService();
  List<Map<String, dynamic>> _tickets = [];
  RealtimeChannel? _channel;
  bool _isLoading = true;
  String _statusFilter = 'all';

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
      final tickets = await _service.getAllTickets();
      if (!mounted) return;
      setState(() {
        _tickets = tickets;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      Toast.error(context, 'Не удалось загрузить тикеты');
    }
  }

  void _subscribeToTickets() {
    _channel = Supabase.instance.client
        .channel('admin_support_tickets')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'support_tickets',
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
    final tickets = _statusFilter == 'all'
        ? _tickets
        : _tickets
              .where((ticket) => ticket['status'] == _statusFilter)
              .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0A0A),
        foregroundColor: Colors.white,
        title: const Text('Тикеты поддержки'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _loadTickets,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('Все')),
                ButtonSegment(value: 'open', label: Text('Открытые')),
                ButtonSegment(value: 'in_progress', label: Text('В работе')),
                ButtonSegment(value: 'closed', label: Text('Закрытые')),
              ],
              selected: {_statusFilter},
              onSelectionChanged: (value) {
                setState(() => _statusFilter = value.first);
              },
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : tickets.isEmpty
                ? const Center(
                    child: Text(
                      'Тикетов нет',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadTickets,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                      itemCount: tickets.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final ticket = tickets[index];
                        final status = ticket['status'] as String?;
                        final name =
                            ticket['user_name'] as String? ?? 'Пользователь';
                        final tag = ticket['user_tag'] as String? ?? '';
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
                                  isSupport: true,
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
                                  const SizedBox(height: 7),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '$name${tag.isEmpty ? '' : '  ·  @$tag'}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white70,
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
                                  const SizedBox(height: 4),
                                  Text(
                                    _categoryLabel(
                                      ticket['category'] as String?,
                                    ),
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
