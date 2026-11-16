import 'package:flutter/material.dart';
import 'package:strazh/core/services/app_update_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:strazh/shared/presentation/widgets/strzh_s_loader.dart';

class UpdateReminderScreen extends StatefulWidget {
  const UpdateReminderScreen({super.key, required this.upToDateScreen});

  final Widget upToDateScreen;

  @override
  State<UpdateReminderScreen> createState() => _UpdateReminderScreenState();
}

class _UpdateReminderScreenState extends State<UpdateReminderScreen> {
  AppUpdateInfo? _update;
  bool _checking = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    try {
      final update = await AppUpdateService.checkForUpdate();
      if (!mounted) return;

      if (update == null) {
        _continueToApp();
      } else {
        setState(() {
          _update = update;
          _checking = false;
        });
      }
    } catch (error) {
      debugPrint('Не удалось проверить наличие обновления: $error');
      if (mounted) _continueToApp();
    }
  }

  void _continueToApp() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => widget.upToDateScreen),
    );
  }

  Future<void> _openWebsite() async {
    final opened = await launchUrl(
      Uri.parse('https://strazh.chat'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      setState(() => _error = 'Не удалось открыть сайт strazh.chat.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D0A0A),
        body: Center(child: StrazhSLoader(size: 96, label: 'ПРОВЕРКА')),
      );
    }

    final update = _update;
    if (update == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.system_update_alt,
                    size: 54,
                    color: Color(0xFF9B7AE8),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Доступно обновление',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Вышла версия ${update.version}. Обновите приложение на сайте strazh.chat или продолжите пользоваться текущей версией.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, height: 1.5),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _openWebsite,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Обновить на strazh.chat'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _continueToApp,
                    child: const Text('Продолжить без обновления'),
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
