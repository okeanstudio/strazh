import 'package:flutter/material.dart';
import 'package:strazh/features/auth/data/services/auth_service.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _isSaving = false;
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _showConfirmation = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      await AuthService().changePassword(
        currentPassword: _currentPasswordController.text.trim(),
        newPassword: _newPasswordController.text.trim(),
      );

      if (!mounted) return;
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmationController.clear();
      Toast.success(context, 'Пароль успешно изменён');
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().toLowerCase();
      if (message.contains('invalid login credentials') ||
          message.contains('invalid_credentials')) {
        Toast.error(context, 'Неверный текущий пароль');
      } else {
        Toast.error(context, 'Не удалось сменить пароль. Проверьте данные');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  InputDecoration _passwordDecoration({
    required String label,
    required bool isVisible,
    required VoidCallback onToggleVisibility,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white60),
      filled: true,
      fillColor: const Color(0xFF15121C),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      suffixIcon: IconButton(
        tooltip: isVisible ? 'Скрыть пароль' : 'Показать пароль',
        onPressed: onToggleVisibility,
        icon: Icon(
          isVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          color: Colors.white60,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      appBar: AppBar(
        title: const Text('Сменить пароль'),
        backgroundColor: const Color(0xFF0D0A0A),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _currentPasswordController,
                  obscureText: !_showCurrentPassword,
                  autofillHints: const [AutofillHints.password],
                  style: const TextStyle(color: Colors.white),
                  decoration: _passwordDecoration(
                    label: 'Текущий пароль',
                    isVisible: _showCurrentPassword,
                    onToggleVisibility: () => setState(
                      () => _showCurrentPassword = !_showCurrentPassword,
                    ),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Введите текущий пароль'
                      : null,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: !_showNewPassword,
                  style: const TextStyle(color: Colors.white),
                  decoration: _passwordDecoration(
                    label: 'Новый пароль',
                    isVisible: _showNewPassword,
                    onToggleVisibility: () =>
                        setState(() => _showNewPassword = !_showNewPassword),
                  ),
                  validator: (value) {
                    final password = value?.trim() ?? '';
                    if (password.length < 6) {
                      return 'Минимум 6 символов';
                    }
                    if (password == _currentPasswordController.text.trim()) {
                      return 'Новый пароль должен отличаться';
                    }
                    return null;
                  },
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmationController,
                  obscureText: !_showConfirmation,
                  style: const TextStyle(color: Colors.white),
                  decoration: _passwordDecoration(
                    label: 'Повторите новый пароль',
                    isVisible: _showConfirmation,
                    onToggleVisibility: () =>
                        setState(() => _showConfirmation = !_showConfirmation),
                  ),
                  validator: (value) =>
                      value?.trim() != _newPasswordController.text.trim()
                      ? 'Пароли не совпадают'
                      : null,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _changePassword(),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isSaving ? null : _changePassword,
                  icon: _isSaving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_reset),
                  label: Text(_isSaving ? 'Сохранение...' : 'Сменить пароль'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
