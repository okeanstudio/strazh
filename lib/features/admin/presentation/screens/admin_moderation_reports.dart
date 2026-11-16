import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

class AdminModerationReportsScreen extends StatefulWidget {
  const AdminModerationReportsScreen({super.key});

  @override
  State<AdminModerationReportsScreen> createState() =>
      _AdminModerationReportsScreenState();
}

class _AdminModerationReportsScreenState
    extends State<AdminModerationReportsScreen> {
  List<Map<String, dynamic>> _reports = [];
  bool _isLoading = true;
  String _statusFilter = 'open';

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    try {
      final result = await Supabase.instance.client
          .from('moderation_reports')
          .select()
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _reports = List<Map<String, dynamic>>.from(result);
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('Не удалось загрузить жалобы: $error');
      if (!mounted) return;
      setState(() => _isLoading = false);
      Toast.error(context, 'Не удалось загрузить жалобы');
    }
  }

  Future<void> _updateStatus(String reportId, String status) async {
    try {
      await Supabase.instance.client
          .from('moderation_reports')
          .update({'status': status})
          .eq('id', reportId);
      await _loadReports();
      if (mounted) Toast.success(context, 'Статус жалобы обновлён');
    } catch (error) {
      debugPrint('Не удалось обновить жалобу: $error');
      if (mounted) Toast.error(context, 'Не удалось обновить статус жалобы');
    }
  }

  String _reasonLabel(String? reason) {
    return switch (reason) {
      'spam' => 'Спам или мошенничество',
      'harassment' => 'Оскорбления или травля',
      'inappropriate' => 'Неприемлемый контент',
      'illegal' => 'Незаконный или опасный контент',
      _ => 'Другое',
    };
  }

  String _statusLabel(String? status) {
    return switch (status) {
      'reviewing' => 'Рассматривается',
      'resolved' => 'Решена',
      'rejected' => 'Отклонена',
      _ => 'Открыта',
    };
  }

  String _dateLabel(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year} ${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  void _showReport(Map<String, dynamic> report) {
    final isMessage = report['target_type'] == 'message';
    final content = (report['content_snapshot'] ?? '').toString();
    final details = (report['details'] ?? '').toString();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1428),
        title: Text(
          isMessage ? 'Жалоба на сообщение' : 'Жалоба на пользователя',
          style: const TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            [
              'Пользователь: ${report['reported_user_name'] ?? 'неизвестен'}',
              'ID пользователя: ${report['reported_user_id'] ?? 'удалён'}',
              'ID отправителя жалобы: ${report['reporter_id']}',
              'Причина: ${_reasonLabel(report['reason']?.toString())}',
              if (content.isNotEmpty) 'Текст сообщения: $content',
              if (details.isNotEmpty) 'Комментарий: $details',
              'Дата: ${_dateLabel(report['created_at'])}',
            ].join('\n\n'),
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        actions: [
          if (report['status'] != 'reviewing')
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _updateStatus(report['id'].toString(), 'reviewing');
              },
              child: const Text('Взять в работу'),
            ),
          if (report['status'] != 'resolved')
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _updateStatus(report['id'].toString(), 'resolved');
              },
              child: const Text('Решена'),
            ),
          if (report['status'] != 'rejected')
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _updateStatus(report['id'].toString(), 'rejected');
              },
              child: const Text(
                'Отклонить',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reports = _statusFilter == 'all'
        ? _reports
        : _reports
              .where((report) => report['status'] == _statusFilter)
              .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0A0A),
        foregroundColor: Colors.white,
        title: const Text('Жалобы пользователей'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _loadReports,
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
                ButtonSegment(value: 'open', label: Text('Открытые')),
                ButtonSegment(value: 'reviewing', label: Text('В работе')),
                ButtonSegment(value: 'all', label: Text('Все')),
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
                : reports.isEmpty
                ? const Center(
                    child: Text(
                      'Жалоб нет',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadReports,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                      itemCount: reports.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final report = reports[index];
                        final isMessage = report['target_type'] == 'message';
                        return Material(
                          color: const Color(0xFF15121C),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            leading: Icon(
                              isMessage
                                  ? Icons.chat_bubble_outline
                                  : Icons.person,
                              color: Colors.orangeAccent,
                            ),
                            title: Text(
                              isMessage
                                  ? 'Жалоба на сообщение'
                                  : 'Жалоба на пользователя',
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              '${_reasonLabel(report['reason']?.toString())}'
                              ' · ${report['reported_user_name'] ?? 'Пользователь'}'
                              '\n${_dateLabel(report['created_at'])}'
                              ' · ${_statusLabel(report['status']?.toString())}',
                              style: const TextStyle(color: Colors.white60),
                            ),
                            isThreeLine: true,
                            trailing: const Icon(
                              Icons.chevron_right,
                              color: Colors.white54,
                            ),
                            onTap: () => _showReport(report),
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
