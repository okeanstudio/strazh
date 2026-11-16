import 'package:flutter/material.dart';

class CreatePollDialog extends StatefulWidget {
  const CreatePollDialog({super.key});

  @override
  State<CreatePollDialog> createState() => _CreatePollDialogState();
}

class _CreatePollDialogState extends State<CreatePollDialog> {
  static const _accent = Color(0xFF75A8F8);
  static const _surface = Color(0xFF171B22);
  static const _fieldSurface = Color(0xFF222832);

  final _formKey = GlobalKey<FormState>();
  final _questionController = TextEditingController();
  final _optionControllers = [TextEditingController(), TextEditingController()];
  bool _allowMultiple = false;

  InputDecoration _inputDecoration(String label, {Widget? prefixIcon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white60),
      prefixIcon: prefixIcon,
      filled: true,
      fillColor: _fieldSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      counterStyle: const TextStyle(color: Colors.white38, fontSize: 11),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white10),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accent, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
      ),
    );
  }

  void _removeOption(int index) {
    final controller = _optionControllers[index];
    setState(() => _optionControllers.removeAt(index));
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop<Map<String, dynamic>>({
      'question': _questionController.text.trim(),
      'options': _optionControllers
          .map((controller) => controller.text.trim())
          .toList(),
      'allowMultiple': _allowMultiple,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      title: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.poll_outlined, color: _accent, size: 23),
          ),
          const SizedBox(width: 13),
          const Expanded(
            child: Text(
              'Новый опрос',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _questionController,
                  maxLength: 200,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('Ваш вопрос'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Введите вопрос'
                      : null,
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Text(
                    'ВАРИАНТЫ ОТВЕТА',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                for (var index = 0; index < _optionControllers.length; index++)
                  Padding(
                    key: ValueKey(_optionControllers[index]),
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: ValueKey('field-${_optionControllers[index]}'),
                            controller: _optionControllers[index],
                            maxLength: 100,
                            style: const TextStyle(color: Colors.white),
                            decoration: _inputDecoration(
                              'Вариант ${index + 1}',
                              prefixIcon: Center(
                                widthFactor: 1,
                                child: Container(
                                  width: 23,
                                  height: 23,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ).copyWith(counterText: ''),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Заполните вариант'
                                : null,
                          ),
                        ),
                        if (_optionControllers.length > 2) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: 'Удалить вариант',
                            onPressed: () => _removeOption(index),
                            icon: const Icon(Icons.close_rounded, size: 19),
                            color: Colors.white54,
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ],
                    ),
                  ),
                if (_optionControllers.length < 10)
                  TextButton.icon(
                    onPressed: () => setState(
                      () => _optionControllers.add(TextEditingController()),
                    ),
                    style: TextButton.styleFrom(foregroundColor: _accent),
                    icon: const Icon(Icons.add_rounded, size: 19),
                    label: const Text('Добавить вариант'),
                  ),
                const SizedBox(height: 4),
                Container(
                  decoration: BoxDecoration(
                    color: _fieldSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SwitchListTile.adaptive(
                    value: _allowMultiple,
                    onChanged: (value) =>
                        setState(() => _allowMultiple = value),
                    activeTrackColor: _accent,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    title: const Text(
                      'Несколько ответов',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: const Color(0xFF101722),
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
          icon: const Icon(Icons.send_rounded, size: 17),
          label: const Text('Создать'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _questionController.dispose();
    for (final controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }
}
