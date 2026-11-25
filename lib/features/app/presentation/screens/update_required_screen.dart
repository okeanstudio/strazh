import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:strazh/core/services/app_update_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:strazh/shared/presentation/widgets/strzh_s_loader.dart';

const _background = Color(0xFF0D0A0A);
const _surface = Color(0xFF17131D);
const _accent = Color(0xFF9B7AE8);

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
    final fallback = Uri.parse('https://strazh.chat');
    final platformUrl = switch (defaultTargetPlatform) {
      TargetPlatform.android => _update?.androidUrl ?? _update?.downloadUrl,
      TargetPlatform.windows => _update?.windowsUrl ?? _update?.downloadUrl,
      _ => _update?.downloadUrl,
    };
    final opened = await launchUrl(
      Uri.parse(platformUrl ?? fallback.toString()),
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
        backgroundColor: _background,
        body: Center(child: StrazhSLoader(size: 96, label: 'ПРОВЕРКА')),
      );
    }

    final update = _update;
    if (update == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      backgroundColor: _background,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_background, Color(0xFF21162C), _background],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: _surface.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _accent.withValues(alpha: 0.16),
                        blurRadius: 48,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                _accent.withValues(alpha: 0.3),
                                const Color(0xFF4A9EFF).withValues(alpha: 0.18),
                              ],
                            ),
                          ),
                          child: const Icon(
                            Icons.system_update_alt_rounded,
                            size: 38,
                            color: _accent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Center(
                        child: Text(
                          'Доступно обновление',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _accent.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            'STRAZH  ${update.version}',
                            style: const TextStyle(
                              color: Color(0xFFCAB6FF),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'Что нового',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (update.whatsNew.isEmpty)
                        const Text(
                          'Исправления и улучшения приложения.',
                          style: TextStyle(color: Colors.white70, height: 1.5),
                        )
                      else
                        ...update.whatsNew.map(_buildNote),
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
                          style: FilledButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _openWebsite,
                          icon: const Icon(Icons.download_rounded),
                          label: const Text(
                            'Обновить приложение',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          onPressed: _continueToApp,
                          child: const Text('Позже'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNote(String note) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.check_circle_rounded, size: 18, color: _accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            note,
            style: const TextStyle(color: Colors.white70, height: 1.45),
          ),
        ),
      ],
    ),
  );
}
