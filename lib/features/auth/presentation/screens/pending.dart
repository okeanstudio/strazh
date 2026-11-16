import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/features/auth/presentation/screens/auth.dart';
import 'package:strazh/features/home/presentation/screens/home.dart';

class PendingScreen extends StatefulWidget {
  const PendingScreen({super.key});

  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.hourglass_empty, color: Colors.white, size: 80),
              const SizedBox(height: 30),
              const Text(
                'Заявка на рассмотрении',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Ваша заявка ожидает подтверждения администратором.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () async {
                  const storage = FlutterSecureStorage();
                  final username = await storage.read(key: 'username');
                  if (username == null) return;

                  final request = await Supabase.instance.client
                      .from('registration_requests')
                      .select('*')
                      .eq('username', username)
                      .maybeSingle();

                  if (request == null) return;

                  final status = request['request_status'] as String;

                  if (status == 'approved') {
                    String? invitedByUserId =
                        request['invited_by_user_id'] as String?;
                    if ((invitedByUserId == null || invitedByUserId.isEmpty) &&
                        request['invited_by_code'] != null) {
                      final inviter = await Supabase.instance.client
                          .from('users')
                          .select('id')
                          .eq('invite_code', request['invited_by_code'])
                          .maybeSingle();
                      invitedByUserId = inviter?['id'];
                    }

                    final existingUser = await Supabase.instance.client
                        .from('users')
                        .select('id')
                        .eq('username', username)
                        .maybeSingle();

                    if (existingUser == null) {
                      await Supabase.instance.client.from('users').insert({
                        'name': request['name'],
                        'username': request['username'],
                        'password_hash': request['password_hash'],
                        'identity_public_key': request['identity_public_key'],
                        'phone': request['phone'],
                        'birth_date': request['birth_date'],
                        'invite_code': request['invite_code'],
                        'invited_by_user_id': invitedByUserId,
                      });
                    }

                    if (context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const HomeScreen(),
                        ),
                      );
                    }
                  } else if (status == 'rejected') {
                    await storage.deleteAll();
                    if (context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AuthScreen(),
                        ),
                      );
                    }
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Заявка всё ещё на рассмотрении'),
                        ),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A73E8),
                ),
                child: const Text(
                  'Проверить статус',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
