import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:strazh/features/auth/data/services/email_change_service.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditProfileScreen extends StatefulWidget {
  final String initialName;
  final String initialTag;
  final String initialPhone;
  final String initialEmail;
  final String initialBio;
  final String? initialBirthDate;

  const EditProfileScreen({
    super.key,
    required this.initialName,
    required this.initialTag,
    required this.initialPhone,
    required this.initialEmail,
    required this.initialBio,
    this.initialBirthDate,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameController = TextEditingController();
  final _tagController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _bioController = TextEditingController();

  DateTime? _birthDate;
  late String _currentEmail;

  bool _isLoading = false;

  // Статусы полей
  String? _emailStatusText;
  Color? _emailStatusColor;
  bool _emailAvailable = true;

  String? _phoneStatusText;
  Color? _phoneStatusColor;
  bool _phoneAvailable = true;

  String? _tagStatusText;
  Color? _tagStatusColor;
  bool _tagAvailable = true;

  Timer? _emailCheckTimer;
  Timer? _phoneCheckTimer;
  Timer? _tagCheckTimer;

  // Тот же ключ, что и при регистрации — чтобы проверки работали одинаково
  static const String _serviceKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

  static const Color _bg = Color(0xFF0D0A0A);
  static const Color _card = Color(0xFF1A1A1A);
  static const Color _border = Color(0xFF333333);
  static const Color _textPrimary = Colors.white;
  static const Color _textMuted = Color(0xFF6E6E6E);
  static const Color _accent = Color(0xFF1A73E8);

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.initialName;
    _tagController.text = widget.initialTag;
    _phoneController.text = widget.initialPhone;
    _emailController.text = widget.initialEmail;
    _currentEmail = widget.initialEmail.trim();
    _bioController.text = widget.initialBio;

    if (widget.initialBirthDate != null) {
      _birthDate = DateTime.tryParse(widget.initialBirthDate!);
    }

    _emailController.addListener(_onEmailChanged);
    _phoneController.addListener(_onPhoneChanged);
    _tagController.addListener(_onTagChanged);
  }

  @override
  void dispose() {
    _emailCheckTimer?.cancel();
    _phoneCheckTimer?.cancel();
    _tagCheckTimer?.cancel();
    _emailController.removeListener(_onEmailChanged);
    _phoneController.removeListener(_onPhoneChanged);
    _tagController.removeListener(_onTagChanged);
    _nameController.dispose();
    _tagController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  // ============================================================
  // ВАЛИДАЦИЯ (такая же, как при регистрации)
  // ============================================================

  bool _isValidEmail(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  bool _isValidTag(String tag) {
    return RegExp(r'^[a-zA-Z0-9_]{3,}$').hasMatch(tag);
  }

  String _formatPhoneNumber(String input) {
    String digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';

    if (digits.startsWith('8')) {
      digits = '7' + digits.substring(1);
    }
    if (digits.length > 11) {
      digits = digits.substring(0, 11);
    }

    if (digits.startsWith('7')) {
      if (digits.length <= 1) return '+7';
      if (digits.length <= 4) return '+7 (${digits.substring(1)})';
      if (digits.length <= 7) {
        return '+7 (${digits.substring(1, 4)}) ${digits.substring(4)}';
      }
      if (digits.length <= 9) {
        return '+7 (${digits.substring(1, 4)}) ${digits.substring(4, 7)}-${digits.substring(7)}';
      }
      final p1 = digits.substring(1, 4);
      final p2 = digits.substring(4, 7);
      final p3 = digits.substring(7, 9);
      final p4 = digits.substring(9, 11);
      return '+7 ($p1) $p2-$p3-$p4';
    }
    return '+$digits';
  }

  String _getPhoneDigits(String phone) {
    String digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('8')) {
      digits = '7' + digits.substring(1);
    }
    if (digits.length > 11) digits = digits.substring(0, 11);
    return digits;
  }

  bool _isValidPhone(String phone) {
    final digitsOnly = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return digitsOnly.length == 11 &&
        (digitsOnly.startsWith('7') || digitsOnly.startsWith('8'));
  }

  // ============================================================
  // ПРОВЕРКИ (те же, что при регистрации)
  // ============================================================

  Future<bool> _checkEmailExists(String email) async {
    try {
      final response = await http.get(
        Uri.parse('https://auth.strazh.chat/auth/v1/admin/users'),
        headers: {
          'apikey': _serviceKey,
          'Authorization': 'Bearer $_serviceKey',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final users = data['users'] as List;
        final currentUser = Supabase.instance.client.auth.currentUser;
        return users.any(
          (user) => user['email'] == email && user['id'] != currentUser?.id,
        );
      }
      return false;
    } catch (e) {
      debugPrint('Ошибка проверки email: $e');
      return false;
    }
  }

  Future<bool> _checkPhoneExists(String phone) async {
    final phoneDigits = _getPhoneDigits(phone);
    if (phoneDigits.isEmpty) return false;

    try {
      final response = await http.get(
        Uri.parse('https://auth.strazh.chat/auth/v1/admin/users'),
        headers: {
          'apikey': _serviceKey,
          'Authorization': 'Bearer $_serviceKey',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final users = data['users'] as List;
        final currentUser = Supabase.instance.client.auth.currentUser;
        return users.any(
          (user) =>
              user['phone'] == phoneDigits && user['id'] != currentUser?.id,
        );
      }
      return false;
    } catch (e) {
      debugPrint('Ошибка проверки телефона: $e');
      return false;
    }
  }

  Future<bool> _checkTagExists(String tag) async {
    try {
      final response = await Supabase.instance.client.rpc(
        'get_user_by_tag_ci',
        params: {'p_tag': tag.trim().toLowerCase()},
      );
      final currentUser = Supabase.instance.client.auth.currentUser;
      Map<String, dynamic>? user;
      if (response is Map<String, dynamic>) {
        user = response;
      } else if (response is List &&
          response.isNotEmpty &&
          response.first is Map) {
        user = Map<String, dynamic>.from(response.first as Map);
      }
      if (user == null) return false;
      return user['id'] != null &&
          (user['id'] != currentUser?.id || user['is_primary'] != true);
    } catch (e) {
      debugPrint('Ошибка проверки тега: $e');
      return false;
    }
  }

  // ============================================================
  // ОБРАБОТЧИКИ ИЗМЕНЕНИЙ С ДЕБАУНСОМ
  // ============================================================

  void _onEmailChanged() {
    _emailCheckTimer?.cancel();
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      setState(() {
        _emailStatusText = null;
        _emailStatusColor = null;
        _emailAvailable = false;
      });
      return;
    }
    if (email.toLowerCase() == _currentEmail.toLowerCase()) {
      setState(() {
        _emailStatusText = null;
        _emailStatusColor = null;
        _emailAvailable = true;
      });
      return;
    }
    if (!_isValidEmail(email)) {
      setState(() {
        _emailStatusText = 'Некорректный email';
        _emailStatusColor = Colors.redAccent;
        _emailAvailable = false;
      });
      return;
    }

    setState(() {
      _emailStatusText = 'Проверяем...';
      _emailStatusColor = Colors.grey;
    });

    _emailCheckTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      final exists = await _checkEmailExists(email);
      if (!mounted) return;
      setState(() {
        _emailStatusText = exists ? 'Занято' : 'Свободно';
        _emailStatusColor = exists ? Colors.redAccent : Colors.greenAccent;
        _emailAvailable = !exists;
      });
    });
  }

  void _onPhoneChanged() {
    _phoneCheckTimer?.cancel();

    final rawText = _phoneController.text;
    final formatted = _formatPhoneNumber(rawText);
    if (formatted != rawText) {
      final selection = _phoneController.selection;
      final offset = selection.baseOffset + (formatted.length - rawText.length);
      _phoneController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(
          offset: offset.clamp(0, formatted.length),
        ),
      );
    }

    final phone = _phoneController.text.trim();

    if (phone.isEmpty) {
      setState(() {
        _phoneStatusText = null;
        _phoneStatusColor = null;
        _phoneAvailable = true;
      });
      return;
    }
    if (phone == widget.initialPhone) {
      setState(() {
        _phoneStatusText = null;
        _phoneStatusColor = null;
        _phoneAvailable = true;
      });
      return;
    }
    if (!_isValidPhone(phone)) {
      setState(() {
        _phoneStatusText = 'Неверный формат';
        _phoneStatusColor = Colors.redAccent;
        _phoneAvailable = false;
      });
      return;
    }

    setState(() {
      _phoneStatusText = 'Проверяем...';
      _phoneStatusColor = Colors.grey;
    });

    _phoneCheckTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      final exists = await _checkPhoneExists(phone);
      if (!mounted) return;
      setState(() {
        _phoneStatusText = exists ? 'Занят' : 'Свободен';
        _phoneStatusColor = exists ? Colors.redAccent : Colors.greenAccent;
        _phoneAvailable = !exists;
      });
    });
  }

  void _onTagChanged() {
    _tagCheckTimer?.cancel();
    final tag = _tagController.text.trim();

    if (tag.isEmpty) {
      setState(() {
        _tagStatusText = 'Тег не может быть пустым';
        _tagStatusColor = Colors.redAccent;
        _tagAvailable = false;
      });
      return;
    }

    // ✅ Проверка формата — та же, что при регистрации
    if (!_isValidTag(tag)) {
      setState(() {
        _tagStatusText = 'Минимум 3 символа (буквы, цифры, _)';
        _tagStatusColor = Colors.redAccent;
        _tagAvailable = false;
      });
      return;
    }

    if (tag.toLowerCase() == widget.initialTag.toLowerCase()) {
      setState(() {
        _tagStatusText = null;
        _tagStatusColor = null;
        _tagAvailable = true;
      });
      return;
    }

    setState(() {
      _tagStatusText = 'Проверяем...';
      _tagStatusColor = Colors.grey;
    });

    _tagCheckTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      final exists = await _checkTagExists(tag);
      if (!mounted) return;
      setState(() {
        _tagStatusText = exists ? 'Занят' : 'Свободен';
        _tagStatusColor = exists ? Colors.redAccent : Colors.greenAccent;
        _tagAvailable = !exists;
      });
    });
  }

  // ============================================================
  // СОХРАНЕНИЕ
  // ============================================================

  Future<String?> _showEmailCodeDialog(String email, {required int step}) {
    final controller = TextEditingController();
    String? errorText;
    final isOldAddress = step == 1;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF171820),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.09),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 32,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.mark_email_read_outlined,
                            color: Color(0xFF91B9FF),
                            size: 24,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Закрыть',
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close_rounded),
                          color: Colors.white54,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Подтверждение email',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      isOldAddress
                          ? 'Шаг 1 из 2 · проверяем текущий адрес'
                          : 'Шаг 2 из 2 · проверяем новый адрес',
                      style: const TextStyle(color: _textMuted, fontSize: 13),
                    ),
                    const SizedBox(height: 18),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: step / 2,
                        minHeight: 5,
                        backgroundColor: Color(0xFF30313B),
                        valueColor: AlwaysStoppedAnimation(Color(0xFF6C8DFF)),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.045),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.07),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.email_outlined,
                            color: Color(0xFF91B9FF),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              email,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Введите 6-значный код из письма. Код нужен, чтобы подтвердить, что адрес принадлежит вам.',
                      style: TextStyle(
                        color: _textMuted,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 24,
                        letterSpacing: 10,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        hintText: '••••••',
                        hintStyle: const TextStyle(
                          color: Colors.white24,
                          letterSpacing: 8,
                        ),
                        counterText: '',
                        errorText: errorText,
                        filled: true,
                        fillColor: const Color(0xFF101116),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 17,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: Color(0xFF6C8DFF),
                            width: 1.5,
                          ),
                        ),
                      ),
                      onChanged: (_) {
                        if (errorText != null) {
                          setDialogState(() => errorText = null);
                        }
                      },
                      onSubmitted: (_) {
                        final code = controller.text.trim();
                        if (!RegExp(r'^\d{6}$').hasMatch(code)) {
                          setDialogState(
                            () => errorText = 'Введите все 6 цифр кода',
                          );
                          return;
                        }
                        Navigator.pop(dialogContext, code);
                      },
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                              foregroundColor: Colors.white70,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.13),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                            child: const Text('Отмена'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              final code = controller.text.trim();
                              if (!RegExp(r'^\d{6}$').hasMatch(code)) {
                                setDialogState(
                                  () => errorText = 'Введите все 6 цифр кода',
                                );
                                return;
                              }
                              Navigator.pop(dialogContext, code);
                            },
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                              backgroundColor: _accent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                            child: const Text(
                              'Проверить код',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  Future<bool> _verifyEmailAddress(
    EmailChangeService service,
    String email,
    int step,
    Future<void> Function(String code) verifyCode,
  ) async {
    while (mounted) {
      final enteredCode = await _showEmailCodeDialog(email, step: step);
      if (enteredCode == null) return false;
      try {
        await verifyCode(enteredCode);
        return true;
      } catch (error) {
        if (!mounted) return false;
        final message = error.toString().replaceFirst('Exception: ', '');
        Toast.error(context, message);
        if (message != 'Неверный код') return false;
      }
    }
    return false;
  }

  Future<bool> _confirmEmailChange(String email) async {
    final service = EmailChangeService();
    await service.start(email);
    if (!await _verifyEmailAddress(
      service,
      _currentEmail,
      1,
      service.verifyOldEmail,
    )) {
      return false;
    }
    if (!mounted) return false;
    Toast.info(context, 'Старый email подтверждён. Отправляем код на новый.');
    if (!await _verifyEmailAddress(service, email, 2, service.verifyNewEmail)) {
      return false;
    }

    try {
      await Supabase.instance.client.auth.refreshSession();
      _currentEmail = email;
      return true;
    } catch (error) {
      if (mounted) {
        Toast.error(context, 'Email изменён, обновите сессию: $error');
      }
      return true;
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final tag = _tagController.text.trim().toLowerCase();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final bio = _bioController.text.trim();

    if (name.isEmpty) {
      Toast.error(context, 'Имя не может быть пустым');
      return;
    }
    if (tag.isEmpty) {
      Toast.error(context, 'Тег не может быть пустым');
      return;
    }
    if (!_isValidTag(tag)) {
      Toast.error(context, 'Тег: минимум 3 символа (буквы, цифры, _)');
      return;
    }
    if (!_tagAvailable) {
      Toast.error(context, 'Тег занят');
      return;
    }
    if (email.isEmpty ||
        (email.toLowerCase() != _currentEmail.toLowerCase() &&
            !_emailAvailable)) {
      Toast.error(context, 'Проверьте email');
      return;
    }
    if (!_phoneAvailable) {
      Toast.error(context, 'Проверьте телефон');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Пользователь не найден');

      // 1) Метаданные
      final metadata = Map<String, dynamic>.from(user.userMetadata ?? {});
      metadata['name'] = name;
      metadata['tag'] = tag;
      metadata['phone'] = phone.isEmpty ? null : _getPhoneDigits(phone);
      metadata['bio'] = bio.isEmpty ? null : bio;
      metadata['birth_date'] = _birthDate?.toIso8601String();

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: metadata),
      );

      if (email.toLowerCase() != _currentEmail.toLowerCase()) {
        final emailChanged = await _confirmEmailChange(email);
        if (!emailChanged) {
          if (mounted) {
            Toast.info(context, 'Профиль сохранён. Смена email не завершена.');
            setState(() => _isLoading = false);
          }
          return;
        }
      }

      if (mounted) {
        Toast.success(context, 'Профиль обновлён');
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('❌ Ошибка сохранения: $e');
      if (mounted) {
        Toast.error(context, 'Ошибка: $e');
        setState(() => _isLoading = false);
      }
    }
  }

  // ============================================================
  // ДАТА РОЖДЕНИЯ
  // ============================================================

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year - 5),
      locale: const Locale('ru'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: _accent,
              onPrimary: Colors.white,
              surface: _card,
              onSurface: _textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Не указана';
    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year}';
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: _textPrimary),
        ),
        title: const Text(
          'Аккаунт',
          style: TextStyle(
            color: _textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAccountHeader(),
                    const SizedBox(height: 26),
                    _buildSection(
                      title: 'Профиль',
                      subtitle: 'Как вас видят другие пользователи',
                      icon: Icons.person_outline,
                      children: [
                        _buildField(
                          label: 'Имя',
                          controller: _nameController,
                          hint: 'Ваше имя',
                          icon: Icons.badge_outlined,
                        ),
                        _buildField(
                          label: 'Тег',
                          controller: _tagController,
                          hint: 'username',
                          icon: Icons.alternate_email,
                          prefix: '@ ',
                          statusText: _tagStatusText,
                          statusColor: _tagStatusColor,
                        ),
                        _buildField(
                          label: 'О себе',
                          controller: _bioController,
                          hint: 'Пара слов о себе...',
                          icon: Icons.notes_rounded,
                          maxLines: 3,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _buildSection(
                      title: 'Контакты',
                      subtitle: 'Адрес для входа и восстановления',
                      icon: Icons.contact_mail_outlined,
                      children: [
                        _buildField(
                          label: 'Email',
                          controller: _emailController,
                          hint: 'you@example.com',
                          icon: Icons.mail_outline,
                          keyboardType: TextInputType.emailAddress,
                          statusText: _emailStatusText,
                          statusColor: _emailStatusColor,
                        ),
                        _buildField(
                          label: 'Телефон',
                          controller: _phoneController,
                          hint: '+7 (999) 999-99-99',
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                          statusText: _phoneStatusText,
                          statusColor: _phoneStatusColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _buildSection(
                      title: 'Личные данные',
                      subtitle: 'Необязательно',
                      icon: Icons.calendar_month_outlined,
                      children: [_buildDateTile()],
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              decoration: BoxDecoration(
                color: _bg,
                border: Border(
                  top: BorderSide(color: _border.withValues(alpha: 0.7)),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  onPressed: _isLoading ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _accent.withValues(alpha: 0.45),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(
                    _isLoading ? 'Сохраняем...' : 'Сохранить изменения',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountHeader() {
    final name = _nameController.text.trim();
    final tag = _tagController.text.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF24213A), Color(0xFF17151F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border.withValues(alpha: 0.8)),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.manage_accounts_outlined,
              color: Color(0xFF91B9FF),
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Ваш аккаунт' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  tag.isEmpty ? widget.initialEmail : '@$tag',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF91B9FF), size: 19),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(color: _textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(height: 16),
            children[index],
          ],
        ],
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    String? prefix,
    String? statusText,
    Color? statusColor,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    final isSuccess = statusColor == Colors.greenAccent;
    final isError = statusColor == Colors.redAccent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSuccess
                  ? Colors.greenAccent.withValues(alpha: 0.5)
                  : isError
                  ? Colors.redAccent.withValues(alpha: 0.5)
                  : _border,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Icon(
                  icon,
                  color: isSuccess
                      ? Colors.greenAccent
                      : isError
                      ? Colors.redAccent
                      : _textMuted,
                  size: 20,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  style: const TextStyle(color: _textPrimary, fontSize: 15),
                  keyboardType: keyboardType,
                  maxLines: maxLines,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: const TextStyle(color: _textMuted, fontSize: 14),
                    prefixText: prefix,
                    prefixStyle: const TextStyle(color: _textMuted),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      vertical: maxLines > 1 ? 12 : 16,
                      horizontal: 0,
                    ),
                  ),
                ),
              ),
              if (statusText != null)
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Icon(
                    isSuccess
                        ? Icons.check_circle
                        : isError
                        ? Icons.cancel
                        : Icons.hourglass_empty,
                    color: statusColor ?? _textMuted,
                    size: 18,
                  ),
                ),
            ],
          ),
        ),
        if (statusText != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor ?? _textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDateTile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Дата рождения',
          style: TextStyle(
            color: _textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _pickBirthDate,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border, width: 1.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.cake_outlined, color: _textMuted, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _formatDate(_birthDate),
                    style: TextStyle(
                      color: _birthDate == null ? _textMuted : _textPrimary,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (_birthDate != null)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => setState(() => _birthDate = null),
                    icon: const Icon(Icons.close, color: _textMuted, size: 18),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
