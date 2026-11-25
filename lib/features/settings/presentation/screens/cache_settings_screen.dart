import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/features/chat/data/services/chat_message_cache.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

class CacheSettingsScreen extends StatefulWidget {
  const CacheSettingsScreen({super.key});

  @override
  State<CacheSettingsScreen> createState() => _CacheSettingsScreenState();
}

class _CacheSettingsScreenState extends State<CacheSettingsScreen> {
  static const _limits = <int>[
    256 * 1024 * 1024,
    512 * 1024 * 1024,
    1024 * 1024 * 1024,
    2 * 1024 * 1024 * 1024,
    5 * 1024 * 1024 * 1024,
    10 * 1024 * 1024 * 1024,
  ];

  String? _userId;
  int _cacheSizeBytes = 0;
  int _selectedLimit = _limits[2];
  bool _isLoading = true;
  bool _isClearing = false;
  bool _isSavingLimit = false;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _userId = Supabase.instance.client.auth.currentUser?.id;
    _refresh();
  }

  Future<void> _refresh() async {
    final userId = _userId;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final values = await Future.wait([
        ChatMessageCache.instance.getSizeBytes(userId: userId),
        ChatMessageCache.instance.getLimitBytes(),
      ]);
      if (!mounted) return;
      setState(() {
        _cacheSizeBytes = values[0];
        _selectedLimit = values[1];
        _isLoading = false;
        _loadError = null;
      });
    } catch (error) {
      debugPrint('Не удалось загрузить кэш сообщений: $error');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = error;
        });
      }
    }
  }

  Future<void> _changeLimit(int? bytes) async {
    final userId = _userId;
    if (bytes == null || userId == null || _isSavingLimit) return;
    setState(() => _isSavingLimit = true);
    try {
      await ChatMessageCache.instance.setLimitBytes(
        userId: userId,
        bytes: bytes,
      );
      if (!mounted) return;
      setState(() {
        _selectedLimit = bytes;
        _isSavingLimit = false;
      });
      await _refresh();
    } catch (error) {
      debugPrint('Не удалось изменить лимит кэша: $error');
      if (!mounted) return;
      setState(() => _isSavingLimit = false);
      Toast.error(context, 'Не удалось изменить лимит кэша');
    }
  }

  Future<void> _clearCache() async {
    final userId = _userId;
    if (userId == null || _isClearing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1428),
        title: const Text(
          'Очистить кэш сообщений?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Сохранённые на этом устройстве сообщения будут удалены. '
          'Их можно будет загрузить снова при подключении к интернету.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isClearing = true);
    try {
      await ChatMessageCache.instance.clear(userId: userId);
      if (!mounted) return;
      setState(() {
        _cacheSizeBytes = 0;
        _isClearing = false;
      });
      Toast.success(context, 'Кэш сообщений очищен');
    } catch (error) {
      debugPrint('Не удалось очистить кэш сообщений: $error');
      if (!mounted) return;
      setState(() => _isClearing = false);
      Toast.error(context, 'Не удалось очистить кэш сообщений');
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';
  }

  String _formatLimit(int bytes) =>
      '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(bytes < 1024 * 1024 * 1024 ? 2 : 0)} ГБ';

  @override
  Widget build(BuildContext context) {
    final selectedLimit = _limits.contains(_selectedLimit)
        ? _selectedLimit
        : _limits[2];
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      appBar: AppBar(
        title: const Text('Кэш сообщений'),
        backgroundColor: const Color(0xFF0D0A0A),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF171329),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Занято кэшем',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatSize(_cacheSizeBytes),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (_loadError != null) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Не удалось измерить размер кэша',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'ЛИМИТ ХРАНЕНИЯ',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF171329),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: selectedLimit,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF171329),
                      style: const TextStyle(color: Colors.white),
                      items: _limits
                          .map(
                            (limit) => DropdownMenuItem(
                              value: limit,
                              child: Text(_formatLimit(limit)),
                            ),
                          )
                          .toList(),
                      onChanged: _isSavingLimit ? null : _changeLimit,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isSavingLimit
                      ? 'Сохранение лимита...'
                      : 'При достижении лимита сначала удаляются самые старые '
                            'сохранённые сообщения. Новые остаются доступными '
                            'офлайн.',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isClearing ? null : _clearCache,
                  icon: _isClearing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                  label: Text(
                    _isClearing ? 'Очистка...' : 'Очистить кэш сообщений',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.85),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Обновить размер'),
                ),
              ],
            ),
    );
  }
}
