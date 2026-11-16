import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  final TextEditingController _phoneController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  String? _currentUserId;
  Map<String, dynamic> _privacySettings = {
    'who_can_add_to_groups': 'everyone',
    'who_can_send_messages': 'everyone',
    'show_phone': false,
    'show_email': false,
    'show_status': true,
    'show_last_seen': true,
    'show_profile_picture': true,
    'block_unknown': false,
    'hide_expired_stories': false,
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final userId = await Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // Проверяем, есть ли настройки в таблице
      final response = await Supabase.instance.client
          .from('privacy_settings')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _currentUserId = userId;
          if (response != null) {
            _privacySettings = Map<String, dynamic>.from(response);
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки настроек: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() {
      _isSaving = true;
    });

    try {
      if (_currentUserId == null) return;

      await Supabase.instance.client.from('privacy_settings').upsert({
        'user_id': _currentUserId,
        ..._privacySettings,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');

      if (mounted) {
        Toast.success(context, 'Настройки сохранены');
        setState(() {
          _isSaving = false;
        });
      }
    } catch (e) {
      debugPrint('Ошибка сохранения: $e');
      if (mounted) {
        Toast.error(context, 'Ошибка сохранения');
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showPhoneDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Номер телефона',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: '+7 (999) 123-45-67',
            hintStyle: TextStyle(color: Colors.grey[600]),
            filled: true,
            fillColor: const Color(0xFF2A2A2A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              final phone = _phoneController.text.trim();
              if (phone.isNotEmpty) {
                try {
                  await Supabase.instance.client.auth.refreshSession();
                } catch (e) {
                  debugPrint('⚠️ Не удалось обновить сессию: $e');
                }

                // Обновляем телефон в Supabase Auth метаданных
                final metadata =
                    Supabase.instance.client.auth.currentUser?.userMetadata ??
                    {};
                metadata['phone'] = phone;
                await Supabase.instance.client.auth.updateUser(
                  UserAttributes(data: metadata),
                );

                setState(() {
                  _privacySettings['phone'] = phone;
                });
                Navigator.pop(context);
                Toast.success(context, 'Телефон обновлен');
              }
            },
            child: const Text(
              'Сохранить',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D0A0A),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0A0A),
        title: const Text(
          'Конфиденциальность',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // СЕКЦИЯ 1: Кто может добавлять в группы
            _buildSectionHeader(
              icon: Icons.group_add,
              title: 'Кто может добавлять в группы',
            ),
            _buildDropdownSetting(
              title: 'Кто может добавлять вас в группы',
              value: _privacySettings['who_can_add_to_groups'] ?? 'everyone',
              options: {
                'everyone': 'Все',
                'contacts': 'Контакты',
                'nobody': 'Никто',
              },
              onChanged: (value) {
                setState(() {
                  _privacySettings['who_can_add_to_groups'] = value;
                });
              },
            ),

            const SizedBox(height: 32),

            // СЕКЦИЯ 2: Сообщения
            _buildSectionHeader(
              icon: Icons.chat_bubble_outline,
              title: 'Сообщения',
            ),
            _buildDropdownSetting(
              title: 'Кто может писать вам',
              value: _privacySettings['who_can_send_messages'] ?? 'everyone',
              options: {
                'everyone': 'Все',
                'contacts': 'Контакты',
                'nobody': 'Никто',
              },
              onChanged: (value) {
                setState(() {
                  _privacySettings['who_can_send_messages'] = value;
                });
              },
            ),
            _buildSwitchSetting(
              title: 'Блокировать сообщения от неизвестных',
              subtitle: 'Отклонять сообщения от людей не из контактов',
              value: _privacySettings['block_unknown'] ?? false,
              onChanged: (value) {
                setState(() {
                  _privacySettings['block_unknown'] = value;
                });
              },
            ),

            const SizedBox(height: 32),

            // СЕКЦИЯ 3: Профиль
            _buildSectionHeader(icon: Icons.person_outline, title: 'Профиль'),
            _buildSwitchSetting(
              title: 'Показывать номер телефона',
              subtitle: 'Виден ли ваш номер телефона другим пользователям',
              value: _privacySettings['show_phone'] ?? false,
              onChanged: (value) {
                setState(() {
                  _privacySettings['show_phone'] = value;
                });
              },
            ),
            _buildSwitchSetting(
              title: 'Показывать email',
              subtitle: 'Виден ли ваш email другим пользователям',
              value: _privacySettings['show_email'] ?? false,
              onChanged: (value) {
                setState(() {
                  _privacySettings['show_email'] = value;
                });
              },
            ),
            _buildSwitchSetting(
              title: 'Показывать статус',
              subtitle: 'Виден ли ваш онлайн-статус',
              value: _privacySettings['show_status'] ?? true,
              onChanged: (value) {
                setState(() {
                  _privacySettings['show_status'] = value;
                });
              },
            ),
            _buildSwitchSetting(
              title: 'Показывать фото профиля',
              subtitle: 'Видна ли ваша аватарка другим',
              value: _privacySettings['show_profile_picture'] ?? true,
              onChanged: (value) {
                setState(() {
                  _privacySettings['show_profile_picture'] = value;
                });
              },
            ),
            _buildSwitchSetting(
              title: 'Показывать время последнего визита',
              subtitle: 'Видно ли, когда вы были онлайн',
              value: _privacySettings['show_last_seen'] ?? true,
              onChanged: (value) {
                setState(() {
                  _privacySettings['show_last_seen'] = value;
                });
              },
            ),
            _buildSwitchSetting(
              title: 'Скрывать истёкшие публикации',
              subtitle: 'Истёкшие публикации не будут видны в вашем профиле',
              value: _privacySettings['hide_expired_stories'] ?? false,
              onChanged: (value) {
                setState(() {
                  _privacySettings['hide_expired_stories'] = value;
                });
              },
            ),

            const SizedBox(height: 32),

            // Кнопка сохранения
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isSaving ? null : _saveSettings,
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.black)
                    : const Text(
                        'Сохранить настройки',
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
    );
  }

  // Вспомогательные методы
  Widget _buildSectionHeader({required IconData icon, required String title}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.black, size: 22),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownSetting({
    required String title,
    required String value,
    required Map<String, String> options,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF333333), width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
          DropdownButton<String>(
            value: value,
            dropdownColor: const Color(0xFF2A2A2A),
            style: const TextStyle(color: Colors.white),
            underline: Container(height: 1, color: Colors.white54),
            items: options.entries.map((entry) {
              return DropdownMenuItem<String>(
                value: entry.key,
                child: Text(entry.value),
              );
            }).toList(),
            onChanged: (newValue) {
              if (newValue != null) {
                onChanged(newValue);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchSetting({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF333333), width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: Colors.white24,
          ),
        ],
      ),
    );
  }
}
