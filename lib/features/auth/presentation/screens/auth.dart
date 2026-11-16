import 'package:flutter/material.dart';
import 'package:strazh/features/auth/presentation/screens/okean_onboarding_screen.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/features/auth/data/services/okean_auth_service.dart';
import 'package:strazh/features/auth/data/services/auth_service.dart';
import 'package:strazh/features/auth/presentation/screens/phone_login.dart';
import 'package:strazh/features/home/presentation/screens/home.dart';
import 'package:strazh/features/auth/presentation/screens/login.dart';
import 'package:strazh/features/auth/presentation/screens/register.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _tagController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isLoading = false;
  String? _tagError;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );
    _rotationAnimation = Tween<double>(begin: -0.2, end: 0.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack),
      ),
    );
    _animationController.forward();

    _focusNode.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _tagController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool _isValidTag(String tag) {
    return RegExp(r'^[a-zA-Z0-9_]{3,}$').hasMatch(tag);
  }

  Future<void> nextStep() async {
    final String tag = _tagController.text.trim();

    if (tag.isEmpty) {
      setState(() => _tagError = 'Введите тег');
      return;
    }

    if (!_isValidTag(tag)) {
      setState(() => _tagError = 'Минимум 3 символа (буквы, цифры, _)');
      return;
    }

    setState(() {
      _tagError = null;
      _isLoading = true;
    });

    try {
      final normalizedTag = tag.toLowerCase();
      final response = await Supabase.instance.client.rpc(
        'get_user_by_tag_ci',
        params: {'p_tag': normalizedTag},
      );

      if (mounted) {
        bool userExists = false;
        if (response is List && response.isNotEmpty) {
          final first = response[0];
          if (first is Map && first['id'] != null) {
            userExists = true;
          }
        } else if (response is Map<String, dynamic> && response['id'] != null) {
          userExists = true;
        }

        if (userExists) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => LoginScreen(tag: normalizedTag),
            ),
            (route) => false,
          );
        } else {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => RegisterScreen(tag: normalizedTag),
            ),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Ошибка: $e"),
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ============================================================
  // Вход через Okean ID (SSO)
  // ============================================================
  Future<void> _signInWithOkean() async {
    setState(() => _isLoading = true);

    try {
      final result = await OkeanAuthService.signInWithOkean();

      if (!mounted) return;

      if (!result.isSuccess) {
        Toast.error(context, result.errorMessage ?? 'Не удалось войти');
        return;
      }

      // Проверяем, нужен ли онбординг (новый юзер через Okean ID)
      final meta = result.session?.user.userMetadata ?? {};
      final needsInvite = meta['needs_invite'] == true;

      if (!mounted) return;

      if (needsInvite) {
        // Новый юзер — вводим инвайт-код
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const OkeanOnboardingScreen()),
          (route) => false,
        );
        return;
      }

      // Обычный вход — сохраняем флаги и идём домой
      final authService = AuthService();
      await authService.saveUser(
        authService.getUserTag() ?? '',
        authService.currentUserId ?? '',
      );

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } catch (e) {
      debugPrint('❌ _signInWithOkean: $e');
      if (!mounted) return;
      Toast.error(context, 'Ошибка входа: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

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
                  // Логотип
                  TweenAnimationBuilder(
                    duration: const Duration(milliseconds: 1500),
                    tween: Tween<double>(begin: 0, end: 1),
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: AnimatedBuilder(
                          animation: _rotationAnimation,
                          builder: (context, child) {
                            return Transform.rotate(
                              angle: _rotationAnimation.value,
                              child: child,
                            );
                          },
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF6C5CE7,
                                  ).withOpacity(0.5),
                                  blurRadius: 50,
                                  spreadRadius: 10,
                                  offset: const Offset(0, 20),
                                ),
                                BoxShadow(
                                  color: const Color(
                                    0xFF4A9EFF,
                                  ).withOpacity(0.3),
                                  blurRadius: 80,
                                  spreadRadius: 20,
                                  offset: const Offset(0, 0),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: Image.asset(
                                'assets/icon/icon.png',
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: const Color(0xFF6C5CE7),
                                    child: const Icon(
                                      Icons.shield,
                                      color: Colors.white,
                                      size: 50,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 40),
                  const Text(
                    "Добро пожаловать",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Войдите или создайте аккаунт",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Регистрация: новый тег, затем код приглашения в анкете '
                    'и код подтверждения из email.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Поле тега
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _tagError != null
                            ? Colors.red.shade400
                            : isFocused
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
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Icon(
                            Icons.person_outline,
                            color: isFocused
                                ? Colors.white.withOpacity(0.8)
                                : Colors.white38,
                            size: 22,
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _tagController,
                            focusNode: _focusNode,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                            ),
                            onChanged: (_) {
                              if (_tagError != null) {
                                setState(() => _tagError = null);
                              }
                            },
                            decoration: InputDecoration(
                              hintText: "Имя пользователя",
                              hintStyle: TextStyle(
                                color: Colors.white.withOpacity(0.3),
                                fontSize: 15,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 18,
                              ),
                            ),
                          ),
                        ),
                        if (_tagController.text.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _tagController.clear();
                                _tagError = null;
                              });
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 14),
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white38,
                                size: 16,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_tagError != null) ...[
                    const SizedBox(height: 10),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Colors.red.shade400,
                            size: 14,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _tagError!,
                              style: TextStyle(
                                color: Colors.red.shade400,
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 36),
                  // Кнопка "Продолжить"
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : nextStep,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        disabledBackgroundColor: Colors.white.withOpacity(0.6),
                      ),
                      child: _isLoading
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.black.withOpacity(0.6),
                              ),
                            )
                          : const Text(
                              "Продолжить",
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Разделитель "или"
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 1,
                          color: Colors.white.withOpacity(0.06),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          "или",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.3),
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 1,
                          color: Colors.white.withOpacity(0.06),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Кнопка Okean ID
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : _signInWithOkean,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Colors.white.withOpacity(0.12),
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        foregroundColor: Colors.white,
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.asset(
                              'assets/icon/okean_id.jpg',
                              width: 35,
                              height: 35,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(
                                  Icons.broken_image,
                                  color: Colors.white,
                                  size: 35,
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            "Войти через Okean ID",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withOpacity(0.85),
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PhoneLoginScreen(),
                              ),
                            );
                          },
                    icon: const Icon(Icons.phone_iphone, size: 18),
                    label: const Text('Войти по номеру телефона'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF568AF2),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      "Продолжая, вы принимаете\nусловия использования",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.15),
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
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
