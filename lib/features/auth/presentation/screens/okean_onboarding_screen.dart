import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';
import 'package:strazh/features/auth/data/services/auth_service.dart';
import 'package:strazh/features/home/presentation/screens/home.dart';

class OkeanOnboardingScreen extends StatefulWidget {
  const OkeanOnboardingScreen({super.key});

  @override
  State<OkeanOnboardingScreen> createState() => _OkeanOnboardingScreenState();
}

class _OkeanOnboardingScreenState extends State<OkeanOnboardingScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length < 8) {
      Toast.error(context, 'Введите 8-символьный код');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await Supabase.instance.client.rpc(
        'activate_with_single_use_invite',
        params: {'p_invite_code': code},
      );

      if (!mounted) return;

      final ok = result is Map && result['ok'] == true;
      if (ok) {
        final auth = AuthService();
        await auth.saveUser(auth.getUserTag() ?? '', auth.currentUserId ?? '');
        if (!mounted) return;
        Toast.success(context, 'Аккаунт активирован');
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      } else {
        final err = result is Map ? result['error'] : 'unknown';
        final map = {
          'invalid_invite_code': 'Неверный инвайт-код',
          'already_activated': 'Аккаунт уже активирован',
          'not_authenticated': 'Не авторизован',
        };
        Toast.error(context, map[err] ?? 'Ошибка: $err');
      }
    } catch (e) {
      if (mounted) Toast.error(context, 'Ошибка: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6C5CE7).withOpacity(0.4),
                      blurRadius: 50,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/icon/icon.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFF6C5CE7),
                      child: const Icon(
                        Icons.shield,
                        color: Colors.white,
                        size: 50,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Добро пожаловать!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Вы первый раз в Strazh.\nВведите инвайт-код, чтобы продолжить.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 40),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.08),
                    width: 1.5,
                  ),
                ),
                child: TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 4,
                  ),
                  textAlign: TextAlign.center,
                  maxLength: 8,
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'XXXXXXXX',
                    hintStyle: TextStyle(
                      color: Colors.white.withOpacity(0.2),
                      letterSpacing: 4,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 20),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.black,
                          ),
                        )
                      : const Text(
                          'Активировать',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
