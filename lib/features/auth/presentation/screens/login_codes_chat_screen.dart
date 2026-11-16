import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/features/auth/data/services/phone_login_service.dart';
import 'package:strazh/shared/presentation/widgets/strzh_s_loader.dart';

class LoginCodesChatScreen extends StatefulWidget {
  const LoginCodesChatScreen({super.key});

  @override
  State<LoginCodesChatScreen> createState() => _LoginCodesChatScreenState();
}

class _LoginCodesChatScreenState extends State<LoginCodesChatScreen> {
  final _phoneLoginService = PhoneLoginService();
  List<Map<String, dynamic>> _requests = [];
  RealtimeChannel? _channel;
  Timer? _refreshTimer;
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRequests());
    _subscribe();
    unawaited(_markSeen());
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_loadRequests()),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }

  void _subscribe() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    _channel = Supabase.instance.client
        .channel('login_codes_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'phone_login_challenges',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => unawaited(_loadRequests()),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'phone_login_challenges',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => unawaited(_loadRequests()),
        )
        .subscribe();
  }

  Future<void> _loadRequests() async {
    if (_isRefreshing) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Войдите в аккаунт, чтобы просмотреть запросы.';
        });
      }
      return;
    }
    _isRefreshing = true;
    try {
      final requests = await _phoneLoginService.getRecentRequests();
      if (mounted) {
        setState(() {
          _requests = requests.reversed.toList();
          _isLoading = false;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Не удалось загрузить запросы входа.';
        });
      }
      debugPrint('Не удалось загрузить коды входа: $error');
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _markSeen() async {
    try {
      await _phoneLoginService.markRequestsSeen();
    } catch (error) {
      debugPrint('Не удалось отметить запросы входа прочитанными: $error');
    }
  }

  DateTime? _parseDate(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      appBar: AppBar(
        title: const Text('Коды входа'),
        backgroundColor: const Color(0xFF0D0A0A),
      ),
      body: _isLoading
          ? const Center(child: StrazhSLoader(size: 76))
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            )
          : _requests.isEmpty
          ? const _EmptyLoginCodes()
          : ListView.builder(
              reverse: true,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              itemCount: _requests.length,
              itemBuilder: (context, index) {
                final request = _requests[index];
                final expiresAt = _parseDate(request['expires_at']);
                final createdAt = _parseDate(request['created_at']);
                final consumedAt = request['consumed_at'];
                final code = request['login_code'] as String? ?? '';
                final isActive =
                    expiresAt != null &&
                    expiresAt.isAfter(DateTime.now()) &&
                    consumedAt == null;
                final phone = request['phone_number'] as String? ?? '';

                return _LoginCodeMessage(
                  phoneNumber: phone,
                  code: code,
                  createdAt: createdAt,
                  isActive: isActive,
                );
              },
            ),
    );
  }
}

class _EmptyLoginCodes extends StatelessWidget {
  const _EmptyLoginCodes();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.chat_bubble_outline,
              color: Colors.white54,
              size: 48,
            ),
            const SizedBox(height: 14),
            const Text(
              'Здесь будут появляться сообщения с кодами',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 17),
            ),
            const SizedBox(height: 8),
            Text(
              'Новые запросы по номеру аккаунта появятся здесь автоматически.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginCodeMessage extends StatelessWidget {
  const _LoginCodeMessage({
    required this.phoneNumber,
    required this.code,
    required this.createdAt,
    required this.isActive,
  });

  final String phoneNumber;
  final String code;
  final DateTime? createdAt;
  final bool isActive;

  Future<void> _copyCode(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Код скопирован')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final time = createdAt == null
        ? ''
        : '${createdAt!.hour.toString().padLeft(2, '0')}:'
              '${createdAt!.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
        decoration: const BoxDecoration(
          color: Color(0xFF252527),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Код входа для $phoneNumber',
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 7),
            if (isActive)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    code,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      letterSpacing: 5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Скопировать код',
                    onPressed: () => _copyCode(context),
                    icon: const Icon(
                      Icons.copy,
                      color: Colors.white60,
                      size: 18,
                    ),
                  ),
                ],
              )
            else
              const Text(
                'Код истёк или уже использован.',
                style: TextStyle(color: Colors.white60),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                time,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
