import 'package:flutter/material.dart';
import 'package:strazh/features/bots/data/bot_service.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

class AdminBotsScreen extends StatefulWidget {
  const AdminBotsScreen({super.key});

  @override
  State<AdminBotsScreen> createState() => _AdminBotsScreenState();
}

class _AdminBotsScreenState extends State<AdminBotsScreen> {
  final BotService _botService = BotService();
  List<Map<String, dynamic>> _bots = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final bots = await _botService.getAllBots();
      if (mounted) setState(() => _bots = bots);
    } catch (error) {
      if (mounted) Toast.error(context, 'Ошибка загрузки: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setVerified(Map<String, dynamic> bot, bool value) async {
    try {
      await _botService.setVerified(
        botId: bot['id'].toString(),
        verified: value,
      );
      setState(() => bot['is_verified'] = value);
      if (mounted) {
        Toast.success(context, value ? 'Галочка боту выдана' : 'Галочка снята');
      }
    } catch (error) {
      if (mounted) Toast.error(context, 'Ошибка: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0A0A),
        title: const Text('Боты'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _bots.length,
              itemBuilder: (_, index) {
                final bot = _bots[index];
                final verified = bot['is_verified'] == true;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.smart_toy)),
                    title: Text(
                      bot['name']?.toString() ?? 'Бот',
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      '@${bot['tag']}',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          verified ? Icons.verified : Icons.verified_outlined,
                          color: verified ? Colors.blue : Colors.grey,
                        ),
                        Switch(
                          value: verified,
                          onChanged: (value) => _setVerified(bot, value),
                          activeThumbColor: Colors.blue,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
