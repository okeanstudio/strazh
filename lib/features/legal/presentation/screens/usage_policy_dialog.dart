import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Future<bool?> showUsagePolicyDialog(BuildContext context) {
  var isAccepted = false;

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        backgroundColor: const Color(0xFF171717),
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Color(0xFF6C9EFF)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Правила использования Strazh',
                style: TextStyle(color: Colors.white, fontSize: 19),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Пожалуйста, ознакомьтесь с правилами перед использованием '
                  'мессенджера.',
                  style: TextStyle(color: Colors.white70, height: 1.45),
                ),
                const SizedBox(height: 16),
                _PolicyRule(
                  text:
                      'Используйте Strazh законно и уважайте других '
                      'пользователей.',
                ),
                _PolicyRule(
                  text:
                      'Не отправляйте угрозы, травлю, мошеннические сообщения, '
                      'спам или материалы, нарушающие права других людей.',
                ),
                _PolicyRule(
                  text:
                      'Не публикуйте чужие персональные данные и не выдавайте '
                      'себя за другого человека.',
                ),
                _PolicyRule(
                  text:
                      'Вы отвечаете за содержание сообщений и файлов, которые '
                      'отправляете.',
                ),
                _PolicyRule(
                  text:
                      'Для защиты от нежелательных контактов используйте '
                      'доступные настройки приватности и блокировку.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _PolicyLink(
                      title: 'Условия использования',
                      url: Uri.parse('https://strazh.chat/terms'),
                    ),
                    _PolicyLink(
                      title: 'Политика конфиденциальности',
                      url: Uri.parse('https://strazh.chat/privacy'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: isAccepted,
                  onChanged: (value) {
                    setDialogState(() => isAccepted = value ?? false);
                  },
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: const Color(0xFF6C9EFF),
                  title: const Text(
                    'Я прочитал(а) и принимаю условия использования и '
                    'политику конфиденциальности',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              'Выйти из аккаунта',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          FilledButton(
            onPressed: isAccepted
                ? () => Navigator.of(dialogContext).pop(true)
                : null,
            child: const Text('Принять и продолжить'),
          ),
        ],
      ),
    ),
  );
}

class _PolicyRule extends StatelessWidget {
  final String text;

  const _PolicyRule({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Icon(Icons.circle, color: Color(0xFF6C9EFF), size: 7),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicyLink extends StatelessWidget {
  final String title;
  final Uri url;

  const _PolicyLink({required this.title, required this.url});

  Future<void> _open(BuildContext context) async {
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть документ')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(onPressed: () => _open(context), child: Text(title));
  }
}
