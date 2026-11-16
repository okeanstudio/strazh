import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:strazh/features/home/presentation/screens/home.dart';
import 'package:strazh/features/auth/data/services/auth_service.dart';
import 'package:strazh/features/profile/data/services/avatar_service.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';
import 'package:strazh/features/auth/data/services/email_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EmailVerificationScreen extends StatefulWidget {
  final String email;
  final String tag;
  final String userId;
  final String code;
  final Map<String, dynamic>? tempData; // 👈 ВРЕМЕННЫЕ ДАННЫЕ

  const EmailVerificationScreen({
    super.key,
    required this.email,
    required this.tag,
    required this.userId,
    required this.code,
    this.tempData,
  });

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _emailEditController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isResending = false;
  bool _isVerifying = false;
  Timer? _timer;
  int _secondsRemaining = 60;
  bool _canResend = false;
  bool _isVerified = false;
  late String _email;
  late String _verificationCode;
  Map<String, dynamic>? _tempData;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _email = widget.email;
    _emailEditController.text = _email;
    _verificationCode = widget.code;
    _tempData = widget.tempData == null
        ? null
        : Map<String, dynamic>.from(widget.tempData!);
    _startTimer();

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

    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focusNode.removeListener(_handleFocusChange);
    _codeController.dispose();
    _emailEditController.dispose();
    _focusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _secondsRemaining = 60;
    _canResend = false;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_secondsRemaining > 0) {
          _secondsRemaining--;
        } else {
          _canResend = true;
          timer.cancel();
        }
      });
    });
  }

  // ========== ОСНОВНАЯ ЛОГИКА: ПРОВЕРКА КОДА И СОЗДАНИЕ ПОЛЬЗОВАТЕЛЯ ==========
  Future<void> _verifyCode() async {
    if (_isVerifying) return;
    final code = _codeController.text.trim();
    if (code.length != 6) {
      Toast.error(context, 'Введите 6-значный код');
      return;
    }

    setState(() => _isVerifying = true);

    try {
      if (code == _verificationCode) {
        setState(() => _isVerified = true);

        // ===== СОЗДАЁМ ПОЛЬЗОВАТЕЛЯ ТОЛЬКО СЕЙЧАС =====
        await _createUser();

        if (!mounted) return;
        Toast.success(context, 'Регистрация завершена! 🎉');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      } else {
        Toast.error(context, 'Неверный код');
        setState(() => _isVerified = false);
      }
    } catch (e) {
      if (mounted) {
        Toast.error(context, 'Ошибка: $e');
      }
      debugPrint('❌ Ошибка создания пользователя: $e');
    } finally {
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

  // ===== СОЗДАНИЕ ПОЛЬЗОВАТЕЛЯ ЧЕРЕЗ AUTH =====
  Future<void> _createUser() async {
    final temp = _tempData;
    if (temp == null) {
      throw Exception('Нет временных данных');
    }

    final authService = AuthService();

    // Создаём пользователя в Supabase Auth
    final session = await authService.signUpWithEmail(
      email: temp['email'],
      password: temp['password'],
      tag: temp['tag'],
      name: temp['displayName'],
      phone: temp['phone'],
      inviteCode: temp['inviteCode'],
      invitedByCode: temp['invitedByCode'] as String?,
    );

    if (session == null) {
      throw Exception('Сессия не создана');
    }

    // Сохраняем биографию
    if (temp['bio'] != null && temp['bio'].isNotEmpty) {
      await authService.updateUserMetadata({'bio': temp['bio']});
    }

    // Загружаем аватарку только после подтверждения кода и создания Auth-пользователя.
    final avatarPath = temp['avatarPath'] as String?;
    if (avatarPath != null && avatarPath.isNotEmpty) {
      final avatarUrl = await AvatarService.uploadAvatar(
        image: XFile(avatarPath),
        userId: session.user.id,
      );
      if (avatarUrl == null) {
        debugPrint('⚠️ Пользователь создан, но аватарку загрузить не удалось');
      }
    }

    // Сохраняем в БД
    await authService.saveUser(temp['tag'], session.user.id);
  }

  // ===== ПОВТОРНАЯ ОТПРАВКА КОДА =====
  Future<void> _resendEmail() async {
    if (!_canResend || _isResending) return;

    setState(() => _isResending = true);
    try {
      final emailService = EmailService();
      final newCode = _generateVerificationCode();

      await emailService.sendVerificationEmail(
        email: _email,
        code: newCode,
        name: 'Пользователь',
      );
      if (!mounted) return;

      _verificationCode = newCode;
      _tempData?['verificationCode'] = newCode;
      Toast.success(context, 'Письмо отправлено повторно');
      _codeController.clear();
      _startTimer();
    } catch (e) {
      if (mounted) {
        Toast.error(context, 'Ошибка: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
  }

  bool _isValidEmail(String email) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

  Future<void> _changeEmail() async {
    _emailEditController.text = _email;
    var isSending = false;
    String? emailError;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => PopScope(
          canPop: !isSending,
          child: AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: const Text(
              'Изменить email',
              style: TextStyle(color: Colors.white),
            ),
            content: TextField(
              controller: _emailEditController,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              style: const TextStyle(color: Colors.white),
              onChanged: (_) {
                if (emailError != null) {
                  setDialogState(() => emailError = null);
                }
              },
              decoration: InputDecoration(
                labelText: 'Новый email',
                labelStyle: TextStyle(color: Colors.white70),
                errorText: emailError,
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white30),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF6C5CE7)),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSending
                    ? null
                    : () => Navigator.pop(dialogContext),
                child: const Text(
                  'Отмена',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              TextButton(
                onPressed: isSending
                    ? null
                    : () async {
                        final newEmail = _emailEditController.text
                            .trim()
                            .toLowerCase();
                        if (!_isValidEmail(newEmail)) {
                          setDialogState(() {
                            emailError = 'Введите корректный email';
                          });
                          return;
                        }
                        if (newEmail == _email.toLowerCase()) {
                          Navigator.pop(dialogContext);
                          return;
                        }

                        setDialogState(() {
                          isSending = true;
                          emailError = null;
                        });
                        try {
                          final emailTaken = await Supabase.instance.client.rpc(
                            'is_email_taken',
                            params: {'p_email': newEmail},
                          );
                          if (!dialogContext.mounted) return;
                          if (emailTaken == true) {
                            setDialogState(() => isSending = false);
                            if (mounted) {
                              Toast.error(
                                this.context,
                                'Такая почта уже зарегистрирована',
                              );
                            }
                            return;
                          }

                          final newCode = _generateVerificationCode();
                          await EmailService().sendVerificationEmail(
                            email: newEmail,
                            code: newCode,
                            name:
                                _tempData?['displayName'] as String? ??
                                'Пользователь',
                          );
                          if (!mounted) return;

                          setState(() {
                            _email = newEmail;
                            _verificationCode = newCode;
                            _tempData?['email'] = newEmail;
                            _tempData?['verificationCode'] = newCode;
                            _isVerified = false;
                          });
                          _codeController.clear();
                          _startTimer();
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                          Toast.success(
                            this.context,
                            'Код отправлен на новый адрес',
                          );
                        } catch (error) {
                          if (dialogContext.mounted) {
                            setDialogState(() => isSending = false);
                          }
                          if (mounted) {
                            Toast.error(
                              this.context,
                              'Не удалось изменить email: $error',
                            );
                          }
                        }
                      },
                child: isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF6C5CE7),
                        ),
                      )
                    : const Text(
                        'Отправить код',
                        style: TextStyle(color: Color(0xFF8B7CF6)),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _generateVerificationCode() {
    final random = Random();
    return List.generate(6, (_) => random.nextInt(10).toString()).join();
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    final bool isFocused = _focusNode.hasFocus;

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
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF6C5CE7), Color(0xFF4A9EFF)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6C5CE7).withOpacity(0.4),
                          blurRadius: 40,
                          offset: const Offset(0, 15),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.email_outlined,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 32),

                  const Text(
                    'Подтвердите email',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Text(
                    'Мы отправили 6-значный код на',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    _email,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextButton(
                    onPressed: _isVerifying || _isResending
                        ? null
                        : _changeEmail,
                    child: const Text(
                      'Изменить email',
                      style: TextStyle(color: Color(0xFF8B7CF6)),
                    ),
                  ),
                  const SizedBox(height: 32),

                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Код подтверждения регистрации',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isFocused
                            ? Colors.white.withOpacity(0.3)
                            : Colors.white.withOpacity(0.08),
                        width: isFocused ? 2 : 1.5,
                      ),
                      boxShadow: isFocused
                          ? [
                              BoxShadow(
                                color: const Color(
                                  0xFF6C5CE7,
                                ).withOpacity(0.15),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ]
                          : null,
                    ),
                    child: TextField(
                      controller: _codeController,
                      focusNode: _focusNode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        letterSpacing: 8,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: '0 0 0 0 0 0',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.2),
                          fontSize: 24,
                          letterSpacing: 8,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 20,
                        ),
                        counterText: '',
                      ),
                      onChanged: (_) {
                        if (_codeController.text.length == 6) {
                          _verifyCode();
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isVerified
                          ? Colors.green.withOpacity(0.1)
                          : Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isVerified
                            ? Colors.green.withOpacity(0.3)
                            : Colors.white.withOpacity(0.06),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isVerified ? Icons.check_circle : Icons.info_outline,
                          color: _isVerified ? Colors.green : Colors.white38,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _isVerified
                              ? 'Email подтвержден'
                              : 'Введите код из письма',
                          style: TextStyle(
                            color: _isVerified ? Colors.green : Colors.white38,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
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
                          borderRadius: BorderRadius.circular(16),
                        ),
                        disabledBackgroundColor: Colors.white.withOpacity(0.4),
                      ),
                      onPressed: _isVerifying ? null : _verifyCode,
                      child: _isVerifying
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.black,
                              ),
                            )
                          : const Text(
                              'Подтвердить',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: OutlinedButton(
                      onPressed: _canResend ? _resendEmail : null,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: _canResend
                              ? Colors.white.withOpacity(0.2)
                              : Colors.white.withOpacity(0.06),
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        foregroundColor: _canResend
                            ? Colors.white
                            : Colors.white38,
                      ),
                      child: _isResending
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _canResend
                                  ? 'Отправить код повторно'
                                  : 'Повторно через $_secondsRemaining сек',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  GestureDetector(
                    onTap: () {
                      Navigator.pushReplacementNamed(context, '/auth');
                    },
                    child: Text(
                      'Вернуться ко входу',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.3),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
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
}
