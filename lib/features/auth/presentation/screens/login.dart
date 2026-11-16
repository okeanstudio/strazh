import 'package:flutter/material.dart';
import 'package:strazh/features/home/presentation/screens/home.dart';
import 'package:strazh/features/auth/data/services/auth_service.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/features/auth/presentation/screens/auth.dart';

class LoginScreen extends StatefulWidget {
  final String tag;
  const LoginScreen({super.key, required this.tag});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _passwordController = TextEditingController();
  bool _passwordVisible = false;
  late String _username;
  bool _isLoading = false;
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _username = widget.tag.trim().toLowerCase();
    _getUserEmail();
  }

  Future<void> _getUserEmail() async {
    try {
      final response = await Supabase.instance.client.rpc(
        'get_user_by_tag_ci',
        params: {'p_tag': _username},
      );

      // ✅ ИСПРАВЛЕНО: RPC возвращает List — берём первый элемент
      String? email;
      if (response is List && response.isNotEmpty) {
        final first = response[0];
        if (first is Map && first['email'] != null) {
          email = first['email'].toString();
        }
      } else if (response is Map<String, dynamic> &&
          response['email'] != null) {
        // на случай если RPC вернёт JSON-объект
        email = response['email'].toString();
      }

      if (mounted) {
        setState(() {
          _userEmail = email;
        });
      }
    } catch (e) {
      debugPrint('❌ Ошибка получения email: $e');
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final String password = _passwordController.text.trim();

    if (password.isEmpty) {
      Toast.warning(context, 'Введите пароль');
      return;
    }

    if (_userEmail == null) {
      Toast.error(context, 'Пользователь не найден');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authService = AuthService();
      final session = await authService.signInWithEmail(_userEmail!, password);

      if (session == null) {
        throw Exception('Сессия не создана');
      }

      final user = Supabase.instance.client.auth.currentUser;
      final metadata = user?.userMetadata;

      await authService.saveUser(metadata?['tag'] ?? _username, user!.id);

      if (mounted) {
        Toast.success(context, 'Добро пожаловать, @$_username');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        Toast.error(context, 'Неверный пароль или ошибка входа');
        debugPrint('❌ Ошибка входа: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0A0A),
        leading: IconButton(
          onPressed: _goBackToAuth,
          icon: Container(
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color.fromARGB(255, 29, 28, 28),
                width: 3,
              ),
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
          ),
        ),
        title: Center(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color.fromARGB(255, 29, 28, 28),
                width: 3,
              ),
            ),
            child: const Icon(Icons.lock_open, color: Colors.white, size: 45),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'С возвращением',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Введите пароль для входа',
              style: TextStyle(color: Color(0xFF808080), fontSize: 14),
            ),
            const SizedBox(height: 32),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF333333), width: 1),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.person,
                      color: Colors.black,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '@$_username',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Аккаунт найден',
                          style: TextStyle(
                            color: Color(0xFF4CAF50),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _goBackToAuth,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF333333),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            const Text(
              'ПАРОЛЬ',
              style: TextStyle(
                color: Color(0xFF808080),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF333333), width: 1),
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    child: const Icon(
                      Icons.lock_outline,
                      color: Color(0xFF666666),
                      size: 20,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _passwordController,
                      obscureText: !_passwordVisible,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Введите пароль',
                        hintStyle: TextStyle(color: Color(0xFF666666)),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                        filled: true,
                        fillColor: Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _passwordVisible = !_passwordVisible;
                      });
                    },
                    child: Container(
                      width: 50,
                      child: Icon(
                        _passwordVisible
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: const Color(0xFF666666),
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isLoading ? null : _login,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.black)
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Войти',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward, size: 20),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 20),

            Center(
              child: GestureDetector(
                onTap: _goBackToAuth,
                child: const Text(
                  'Использовать другой тег',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
