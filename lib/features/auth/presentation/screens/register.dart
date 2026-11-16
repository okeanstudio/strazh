import 'dart:async';
import 'dart:math';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:strazh/features/auth/presentation/screens/email_verification.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:strazh/features/auth/presentation/screens/auth.dart';
import 'package:strazh/features/auth/data/services/email_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:strazh/features/profile/data/services/avatar_service.dart';
import 'package:strazh/shared/presentation/widgets/avatar_preview.dart';

class RegisterScreen extends StatefulWidget {
  final String tag;
  const RegisterScreen({super.key, required this.tag});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  // Контроллеры
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _password2Controller = TextEditingController();
  final TextEditingController _inviteCodeController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final FocusNode _passwordFocusNode = FocusNode();
  final FocusNode _password2FocusNode = FocusNode();
  final FocusNode _bioFocusNode = FocusNode();
  late final TextEditingController _tagController;

  int _currentStep = 1;

  File? _avatarImage;

  Timer? _emailCheckTimer;
  Timer? _phoneCheckTimer;

  String? _emailStatusText;
  Color? _emailStatusColor;
  String? _phoneStatusText;
  Color? _phoneStatusColor;
  String? _inviteCodeStatusText;
  Color? _inviteCodeStatusColor;
  bool _isInviteCodeValid = false;
  bool _isAgreed = false;

  bool _isLoading = false;
  bool _passwordVisible = false;
  bool _password2Visible = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  // ⚠️ _serviceKey УДАЛЁН. Проверки идут через RPC:
  //   - is_invite_code_taken(p_code)
  //   - is_email_taken(p_email)
  //   - is_phone_taken(p_phone)

  @override
  void initState() {
    super.initState();
    _tagController = TextEditingController(text: widget.tag);
    _emailController.addListener(_onEmailChanged);
    _inviteCodeController.addListener(_onInviteCodeChanged);

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _emailCheckTimer?.cancel();
    _phoneCheckTimer?.cancel();
    _emailController.removeListener(_onEmailChanged);
    _inviteCodeController.removeListener(_onInviteCodeChanged);
    _displayNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _password2Controller.dispose();
    _inviteCodeController.dispose();
    _bioController.dispose();
    _passwordFocusNode.dispose();
    _password2FocusNode.dispose();
    _bioFocusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // ==================== ВЫБОР АВАТАРКИ ====================
  Future<void> _pickAvatar() async {
    try {
      final image = await AvatarService.pickImage(
        context: context,
        source: ImageSource.gallery,
      );
      if (image != null && mounted) {
        setState(() {
          _avatarImage = File(image.path);
        });
      }
    } catch (e) {
      Toast.error(context, 'Ошибка выбора изображения');
    }
  }

  // ==================== ГЕНЕРАЦИЯ КОДОВ ====================
  String generateInviteCode() {
    final random = Random();
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const numbers = '0123456789';
    final code = StringBuffer();
    for (int i = 0; i < 3; i++) {
      code.write(letters[random.nextInt(letters.length)]);
    }
    for (int i = 0; i < 5; i++) {
      code.write(numbers[random.nextInt(numbers.length)]);
    }
    return code.toString();
  }

  Future<String> generateUniqueInviteCode() async {
    String code;
    bool exists;
    do {
      code = generateInviteCode();
      exists = await _checkInviteCodeExists(code);
    } while (exists);
    return code;
  }

  // ✅ ИСПРАВЛЕНО: RPC вместо HTTP + service_role
  Future<bool> _checkInviteCodeExists(String code) async {
    try {
      final result = await Supabase.instance.client.rpc(
        'is_invite_code_taken',
        params: {'p_code': code},
      );
      return result == true;
    } catch (e) {
      debugPrint('Ошибка проверки инвайт-кода: $e');
      return false;
    }
  }

  // ==================== ВАЛИДАЦИЯ ====================
  bool _isValidEmail(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  String _formatPhoneNumber(String input) {
    var digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';

    if (digits.startsWith('8')) {
      digits = '7' + digits.substring(1);
    }

    if (digits.length > 11) {
      digits = digits.substring(0, 11);
    }

    if (digits.startsWith('7')) {
      if (digits.length <= 1) return '+7';
      final areaEnd = digits.length.clamp(1, 4);
      final area = digits.substring(1, areaEnd);
      if (digits.length <= 4) return '+7 ($area)';

      final firstPartEnd = digits.length.clamp(4, 7);
      final firstPart = digits.substring(4, firstPartEnd);
      if (digits.length <= 7) return '+7 ($area) $firstPart';

      final secondPartEnd = digits.length.clamp(7, 9);
      final secondPart = digits.substring(7, secondPartEnd);
      if (digits.length <= 9) return '+7 ($area) $firstPart-$secondPart';

      final thirdPartEnd = digits.length.clamp(9, 11);
      final thirdPart = digits.substring(9, thirdPartEnd);
      return '+7 ($area) $firstPart-$secondPart-$thirdPart';
    }
    return '+$digits';
  }

  String _getPhoneDigits(String phone) {
    String digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('8')) {
      digits = '7' + digits.substring(1);
    }
    if (digits.length > 11) {
      digits = digits.substring(0, 11);
    }
    return digits;
  }

  bool _isValidPhone(String phone) {
    final digitsOnly = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return digitsOnly.length == 11 &&
        (digitsOnly.startsWith('7') || digitsOnly.startsWith('8'));
  }

  // ==================== ПРОВЕРКИ В БД (RPC) ====================
  // ✅ ИСПРАВЛЕНО: RPC вместо HTTP + service_role
  Future<bool> _checkEmailExists(String email) async {
    try {
      final result = await Supabase.instance.client.rpc(
        'is_email_taken',
        params: {'p_email': email.toLowerCase().trim()},
      );
      return result == true;
    } catch (e) {
      debugPrint('Ошибка проверки email: $e');
      return false;
    }
  }

  // ✅ ИСПРАВЛЕНО: RPC вместо HTTP + service_role
  Future<bool> _checkPhoneExists(String phone) async {
    final phoneDigits = _getPhoneDigits(phone);
    if (phoneDigits.isEmpty) return false;

    try {
      final result = await Supabase.instance.client.rpc(
        'is_phone_taken',
        params: {'p_phone': phoneDigits},
      );
      return result == true;
    } catch (e) {
      debugPrint('Ошибка проверки телефона: $e');
      return false;
    }
  }

  // ==================== ОБРАБОТЧИКИ ИЗМЕНЕНИЙ ====================
  void _onEmailChanged() {
    _emailCheckTimer?.cancel();
    final email = _emailController.text.trim();
    if (email.isEmpty || !_isValidEmail(email)) {
      if (mounted) {
        setState(() {
          _emailStatusText = null;
          _emailStatusColor = null;
        });
      }
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
      });
    });
  }

  void _onPhoneChanged(String phone) {
    if (!mounted) return;
    _phoneCheckTimer?.cancel();

    phone = phone.trim();
    if (phone.isEmpty) {
      if (mounted) {
        setState(() {
          _phoneStatusText = null;
          _phoneStatusColor = null;
        });
      }
      return;
    }
    if (!_isValidPhone(phone)) {
      if (mounted) {
        setState(() {
          _phoneStatusText = 'Неверный формат';
          _phoneStatusColor = Colors.redAccent;
        });
      }
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
      });
    });
  }

  void _onInviteCodeChanged() {
    final code = _inviteCodeController.text.trim().toUpperCase();
    if (code.length == 8) {
      _checkInviteCode(code);
    } else {
      setState(() {
        _isInviteCodeValid = false;
        _inviteCodeStatusText = null;
        _inviteCodeStatusColor = null;
      });
    }
  }

  Future<void> _checkInviteCode(String code) async {
    setState(() {
      _inviteCodeStatusText = 'Проверяем...';
      _inviteCodeStatusColor = Colors.grey;
    });

    try {
      final response = await Supabase.instance.client.rpc(
        'get_user_by_invite_code',
        params: {'p_code': code},
      );

      if (mounted) {
        final inviter = response is Map<String, dynamic>
            ? response
            : response is List && response.isNotEmpty && response.first is Map
            ? Map<String, dynamic>.from(response.first as Map)
            : null;
        final isValid = inviter?['id'] != null;
        setState(() {
          _isInviteCodeValid = isValid;
          _inviteCodeStatusText = isValid ? 'Действителен' : 'Недействителен';
          _inviteCodeStatusColor = isValid
              ? Colors.greenAccent
              : Colors.redAccent;
        });
      }
    } catch (e) {
      debugPrint('Ошибка проверки инвайт-кода: $e');
      if (mounted) {
        setState(() {
          _isInviteCodeValid = false;
          _inviteCodeStatusText = 'Ошибка проверки';
          _inviteCodeStatusColor = Colors.redAccent;
        });
      }
    }
  }

  String _generateVerificationCode() {
    final random = Random();
    return List.generate(6, (_) => random.nextInt(10).toString()).join();
  }

  // ==================== РЕГИСТРАЦИЯ (БЕЗ СОЗДАНИЯ ПОЛЬЗОВАТЕЛЯ) ====================
  Future<void> _registerUser() async {
    if (_isLoading || !mounted) return;
    setState(() => _isLoading = true);
    try {
      await _submitRegistration();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submitRegistration() async {
    final String displayName = _displayNameController.text.trim();
    final String email = _emailController.text.trim();
    final String phone = _phoneController.text.trim();
    final String password = _passwordController.text.trim();
    final String tag = _tagController.text.trim().toLowerCase();
    final String inviteCode = _inviteCodeController.text.trim().toUpperCase();
    final String bio = _bioController.text.trim();

    // ===== ВСЕ ПРОВЕРКИ ОСТАВЛЯЕМ =====
    if (displayName.isEmpty) {
      Toast.error(context, 'Введите имя для отображения');
      return;
    }
    if (displayName.length < 2) {
      Toast.error(context, 'Имя должно содержать минимум 2 символа');
      return;
    }
    if (email.isEmpty || !_isValidEmail(email)) {
      Toast.error(context, 'Введите корректный email');
      return;
    }
    final emailExists = await _checkEmailExists(email);
    if (!mounted) return;
    if (emailExists) {
      Toast.error(context, 'Такая почта уже зарегистрирована');
      return;
    }
    if (phone.isNotEmpty) {
      if (!_isValidPhone(phone)) {
        Toast.error(context, 'Введите корректный номер телефона');
        return;
      }
      final phoneExists = await _checkPhoneExists(phone);
      if (!mounted) return;
      if (phoneExists) {
        Toast.error(context, 'Такой телефон уже зарегистрирован');
        return;
      }
    }
    if (inviteCode.isEmpty || !_isInviteCodeValid) {
      Toast.error(context, 'Неверный код приглашения');
      return;
    }
    if (!_isAgreed) {
      Toast.error(context, 'Необходимо согласиться с условиями');
      return;
    }

    try {
      final emailService = EmailService();
      final verificationCode = _generateVerificationCode();

      // ===== ОТПРАВЛЯЕМ КОД НА ПОЧТУ =====
      await emailService.sendVerificationEmail(
        email: email,
        code: verificationCode,
        name: displayName,
      );
      if (!mounted) return;

      // ===== СОХРАНЯЕМ ВРЕМЕННЫЕ ДАННЫЕ =====
      final ownInviteCode = await generateUniqueInviteCode();
      if (!mounted) return;
      final tempData = {
        'email': email,
        'password': password,
        'tag': tag,
        'displayName': displayName,
        'phone': _getPhoneDigits(phone),
        'inviteCode': ownInviteCode,
        'invitedByCode': inviteCode,
        'bio': bio,
        'avatarPath': _avatarImage?.path,
        'verificationCode': verificationCode,
      };

      // ===== ПЕРЕХОД НА ЭКРАН ПОДТВЕРЖДЕНИЯ =====
      if (mounted) {
        Toast.success(context, 'Код отправлен на почту');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => EmailVerificationScreen(
              email: email,
              tag: tag,
              userId: '',
              code: verificationCode,
              tempData: tempData,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Toast.error(context, 'Ошибка отправки кода: $e');
        debugPrint('❌ Ошибка: $e');
      }
    }
  }

  // ==================== НАВИГАЦИЯ ПО ШАГАМ ====================
  void _nextStep() async {
    if (_currentStep == 1) {
      final String email = _emailController.text.trim();
      final String phone = _phoneController.text.trim();
      final String inviteCode = _inviteCodeController.text.trim().toUpperCase();

      if (email.isEmpty || !_isValidEmail(email)) {
        Toast.error(context, 'Введите корректный email');
        return;
      }
      final emailExists = await _checkEmailExists(email);
      if (!mounted) return;
      if (emailExists) {
        Toast.error(context, 'Такая почта уже зарегистрирована');
        return;
      }
      if (phone.isNotEmpty) {
        if (!_isValidPhone(phone)) {
          Toast.error(context, 'Введите корректный номер телефона');
          return;
        }
        final phoneExists = await _checkPhoneExists(phone);
        if (!mounted) return;
        if (phoneExists) {
          Toast.error(context, 'Такой телефон уже зарегистрирован');
          return;
        }
      }
      if (inviteCode.isEmpty || !_isInviteCodeValid) {
        Toast.error(context, 'Неверный код приглашения');
        return;
      }
      setState(() => _currentStep = 2);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _passwordFocusNode.requestFocus();
      });
    } else if (_currentStep == 2) {
      final String password = _passwordController.text.trim();
      final String password2 = _password2Controller.text.trim();

      if (password.isEmpty || password.length < 6) {
        Toast.error(context, 'Пароль должен быть не менее 6 символов');
        return;
      }
      if (password != password2) {
        Toast.error(context, 'Пароли не совпадают');
        return;
      }
      setState(() => _currentStep = 3);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _bioFocusNode.requestFocus();
      });
    } else if (_currentStep == 3) {
      await _registerUser();
    }
  }

  void _goBackToAuth() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AuthScreen()),
      );
    }
  }

  void _previousStep() {
    if (_currentStep > 1) {
      setState(() => _currentStep--);
    } else {
      _goBackToAuth();
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть документ')),
        );
      }
    } catch (error) {
      debugPrint('Не удалось открыть документ $url: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть документ')),
        );
      }
    }
  }

  // ==================== СТРОИТЕЛЬ ====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28.0),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: _previousStep,
                          icon: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.08),
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          'Регистрация',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        const SizedBox(width: 44),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _currentStep >= 1
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.1),
                              ),
                              child: Center(
                                child: Text(
                                  '1',
                                  style: TextStyle(
                                    color: _currentStep >= 1
                                        ? Colors.black
                                        : Colors.white54,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Контакты',
                              style: TextStyle(
                                color: _currentStep >= 1
                                    ? Colors.white70
                                    : Colors.white.withOpacity(0.3),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 20,
                        height: 2,
                        color: _currentStep >= 2
                            ? Colors.white
                            : Colors.white.withOpacity(0.1),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _currentStep >= 2
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.1),
                              ),
                              child: Center(
                                child: Text(
                                  '2',
                                  style: TextStyle(
                                    color: _currentStep >= 2
                                        ? Colors.black
                                        : Colors.white54,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Безопасность',
                              style: TextStyle(
                                color: _currentStep >= 2
                                    ? Colors.white70
                                    : Colors.white.withOpacity(0.3),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 20,
                        height: 2,
                        color: _currentStep >= 3
                            ? Colors.white
                            : Colors.white.withOpacity(0.1),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _currentStep >= 3
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.1),
                              ),
                              child: Center(
                                child: Text(
                                  '3',
                                  style: TextStyle(
                                    color: _currentStep >= 3
                                        ? Colors.black
                                        : Colors.white54,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Профиль',
                              style: TextStyle(
                                color: _currentStep >= 3
                                    ? Colors.white70
                                    : Colors.white.withOpacity(0.3),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _currentStep == 1
                                ? 'Контактные данные'
                                : _currentStep == 2
                                ? 'Безопасность аккаунта'
                                : 'Завершение профиля',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _currentStep == 1
                                ? 'Укажите email и 8-значный код приглашения. Код подтверждения регистрации придет на почту после заполнения анкеты.'
                                : _currentStep == 2
                                ? 'Придумайте надежный пароль'
                                : 'Добавьте информацию о себе',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 32),

                          if (_currentStep == 1) ...[
                            _buildTextField(
                              label: 'Email *',
                              controller: _emailController,
                              icon: Icons.mail_outline,
                              hint: 'example@mail.com',
                              statusText: _emailStatusText,
                              statusColor: _emailStatusColor,
                            ),
                            const SizedBox(height: 20),
                            _buildTextField(
                              label: 'Номер телефона',
                              controller: _phoneController,
                              icon: Icons.phone_outlined,
                              hint: '+7 (999) 999-99-99',
                              statusText: _phoneStatusText,
                              statusColor: _phoneStatusColor,
                              onChanged: _onPhoneChanged,
                              inputFormatters: [
                                TextInputFormatter.withFunction((
                                  oldValue,
                                  newValue,
                                ) {
                                  final formatted = _formatPhoneNumber(
                                    newValue.text,
                                  );
                                  final offset =
                                      newValue.selection.baseOffset +
                                      (formatted.length - newValue.text.length);
                                  return TextEditingValue(
                                    text: formatted,
                                    selection: TextSelection.collapsed(
                                      offset: offset.clamp(0, formatted.length),
                                    ),
                                  );
                                }),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Необязательно, но поможет восстановить доступ',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.3),
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 20),
                            _buildTextField(
                              label: 'Код приглашения (8 символов) *',
                              controller: _inviteCodeController,
                              icon: Icons.card_giftcard_outlined,
                              hint: 'ABC12345',
                              statusText: _inviteCodeStatusText,
                              statusColor: _inviteCodeStatusColor,
                              isCode: true,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Введите код от пригласившего вас пользователя. '
                              'Это не код подтверждения из email.',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.3),
                                fontSize: 11,
                              ),
                            ),
                          ],

                          if (_currentStep == 2) ...[
                            _buildTextField(
                              label: 'Пароль *',
                              controller: _passwordController,
                              icon: Icons.lock_outline,
                              hint: 'Минимум 6 символов',
                              obscure: !_passwordVisible,
                              showVisibilityToggle: true,
                              onToggleVisibility: () => setState(
                                () => _passwordVisible = !_passwordVisible,
                              ),
                              focusNode: _passwordFocusNode,
                            ),
                            const SizedBox(height: 20),
                            _buildTextField(
                              label: 'Подтвердите пароль *',
                              controller: _password2Controller,
                              icon: Icons.lock_outline,
                              hint: 'Повторите пароль',
                              obscure: !_password2Visible,
                              showVisibilityToggle: true,
                              onToggleVisibility: () => setState(
                                () => _password2Visible = !_password2Visible,
                              ),
                              focusNode: _password2FocusNode,
                            ),
                          ],

                          if (_currentStep == 3) ...[
                            Center(
                              child: Column(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      final image = _avatarImage;
                                      if (image == null) {
                                        _pickAvatar();
                                      } else {
                                        showAvatarPreview(
                                          context,
                                          image: FileImage(image),
                                        );
                                      }
                                    },
                                    child: Container(
                                      width: 120,
                                      height: 120,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white.withOpacity(0.05),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.15),
                                          width: 2,
                                        ),
                                        image: _avatarImage != null
                                            ? DecorationImage(
                                                image: FileImage(_avatarImage!),
                                                fit: BoxFit.cover,
                                              )
                                            : null,
                                      ),
                                      child: _avatarImage == null
                                          ? Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.add_photo_alternate,
                                                  color: Colors.white
                                                      .withOpacity(0.3),
                                                  size: 40,
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  'Добавить фото',
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withOpacity(0.3),
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            )
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Нажмите чтобы выбрать аватар',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.3),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),
                            _buildTextField(
                              label: 'Имя для отображения *',
                              controller: _displayNameController,
                              icon: Icons.person_outline,
                              hint: 'Как другие будут вас видеть',
                            ),
                            const SizedBox(height: 20),
                            _buildTextField(
                              label: 'О себе',
                              controller: _bioController,
                              icon: Icons.description_outlined,
                              hint: 'Расскажите о себе',
                              maxLines: 3,
                              focusNode: _bioFocusNode,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Краткое описание вашего профиля',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.3),
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 32),
                            Text(
                              'Перед регистрацией ознакомьтесь с документами:',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                TextButton.icon(
                                  onPressed: () =>
                                      _openUrl('https://strazh.chat/terms'),
                                  icon: const Icon(Icons.description_outlined),
                                  label: const Text('Условия использования'),
                                ),
                                TextButton.icon(
                                  onPressed: () =>
                                      _openUrl('https://strazh.chat/privacy'),
                                  icon: const Icon(Icons.privacy_tip_outlined),
                                  label: const Text(
                                    'Политика конфиденциальности',
                                  ),
                                ),
                              ],
                            ),
                            CheckboxListTile(
                              value: _isAgreed,
                              onChanged: (value) =>
                                  setState(() => _isAgreed = value ?? false),
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              activeColor: const Color(0xFF6C5CE7),
                              title: const Text(
                                'Я ознакомился(ась) и согласен(на) с условиями '
                                'использования и политикой конфиденциальности',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],

                          const SizedBox(height: 32),
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: _isLoading ? null : _nextStep,
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.black,
                                      ),
                                    )
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          _currentStep == 3
                                              ? 'Завершить'
                                              : 'Далее',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(
                                          _currentStep == 3
                                              ? Icons.check
                                              : Icons.arrow_forward,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Center(
                            child: GestureDetector(
                              onTap: _goBackToAuth,
                              child: Text(
                                'Использовать другой тег',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.4),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    String? statusText,
    Color? statusColor,
    bool isCode = false,
    bool obscure = false,
    bool showVisibilityToggle = false,
    VoidCallback? onToggleVisibility,
    FocusNode? focusNode,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final isSuccess = statusColor == Colors.greenAccent;
    final isError = statusColor == Colors.redAccent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSuccess
                  ? Colors.greenAccent.withOpacity(0.5)
                  : isError
                  ? Colors.redAccent.withOpacity(0.5)
                  : Colors.white.withOpacity(0.08),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Icon(
                  icon,
                  color: isSuccess
                      ? Colors.greenAccent
                      : isError
                      ? Colors.redAccent
                      : Colors.white24,
                  size: 20,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  obscureText: obscure,
                  focusNode: focusNode,
                  maxLines: maxLines,
                  onChanged: onChanged,
                  inputFormatters: inputFormatters,
                  textCapitalization: isCode
                      ? TextCapitalization.characters
                      : TextCapitalization.none,
                  decoration: InputDecoration(
                    hintText: hint,
                    suffixIcon: showVisibilityToggle
                        ? IconButton(
                            tooltip: obscure
                                ? 'Показать пароль'
                                : 'Скрыть пароль',
                            onPressed: onToggleVisibility,
                            icon: Icon(
                              obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            color: Colors.white54,
                          )
                        : null,
                    hintStyle: TextStyle(
                      color: Colors.white.withOpacity(0.25),
                      fontSize: 14,
                    ),
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
                    isSuccess ? Icons.check_circle : Icons.cancel,
                    color: statusColor ?? Colors.grey,
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
                color: statusColor ?? Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
