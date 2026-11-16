import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/features/auth/data/services/auth_service.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String _searchQuery = '';

  // ===== РЕДАКТИРОВАНИЕ =====
  Map<String, dynamic>? _editingUser;
  final TextEditingController _editNameController = TextEditingController();
  final TextEditingController _editTagController = TextEditingController();
  final TextEditingController _editBioController = TextEditingController();
  final TextEditingController _editAvatarController = TextEditingController();
  final TextEditingController _editInviteCodeController =
      TextEditingController();
  String _editInvitedByUserId = '';
  String _editStatus = 'offline';
  String _editRole = 'user';

  // ===== СОЗДАНИЕ =====
  final TextEditingController _newEmailController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _newNameController = TextEditingController();
  final TextEditingController _newTagController = TextEditingController();
  final TextEditingController _newPhoneController = TextEditingController();
  String _newRole = 'user';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _editNameController.dispose();
    _editTagController.dispose();
    _editBioController.dispose();
    _editAvatarController.dispose();
    _editInviteCodeController.dispose();
    _newEmailController.dispose();
    _newPasswordController.dispose();
    _newNameController.dispose();
    _newTagController.dispose();
    _newPhoneController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final result = await Supabase.instance.client.rpc('get_all_users');
      if (mounted) {
        if (result is List) {
          setState(() {
            _users = result.cast<Map<String, dynamic>>();
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      debugPrint('Ошибка загрузки: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        Toast.error(context, 'Ошибка загрузки');
      }
    }
  }

  List<Map<String, dynamic>> get _filteredUsers {
    return _users.where((user) {
      final name = (user['name'] ?? '').toLowerCase();
      final tag = (user['tag'] ?? '').toLowerCase();
      final email = (user['email'] ?? '').toLowerCase();
      final query = _searchQuery.toLowerCase();
      return name.contains(query) ||
          tag.contains(query) ||
          email.contains(query);
    }).toList();
  }

  Map<String, dynamic>? _metadataFor(Map<String, dynamic> user) {
    final metadata = user['raw_user_meta_data'];
    if (metadata is Map) return Map<String, dynamic>.from(metadata);
    return null;
  }

  String _invitedByUserId(Map<String, dynamic> user) {
    final metadata = _metadataFor(user);
    return (user['invited_by_user_id'] ?? metadata?['invited_by_user_id'] ?? '')
        .toString();
  }

  String _inviteCode(Map<String, dynamic> user) {
    final metadata = _metadataFor(user);
    return (user['invite_code'] ?? metadata?['invite_code'] ?? '').toString();
  }

  String _invitedByCode(Map<String, dynamic> user) {
    final metadata = _metadataFor(user);
    return (user['invited_by_code'] ?? metadata?['invited_by_code'] ?? '')
        .toString();
  }

  String _userLabel(Map<String, dynamic> user) {
    final name = (user['name'] ?? 'Без имени').toString();
    final tag = (user['tag'] ?? '').toString();
    return tag.isEmpty ? name : '$name (@$tag)';
  }

  Map<String, dynamic>? _findUserById(String userId) {
    for (final user in _users) {
      if (user['id']?.toString() == userId) return user;
    }
    return null;
  }

  void _openEditDialog(Map<String, dynamic> user) {
    _editingUser = Map<String, dynamic>.from(user);

    _editNameController.text = user['name'] ?? '';
    _editTagController.text = user['tag'] ?? '';
    _editBioController.text = user['bio'] ?? '';
    _editAvatarController.text = user['avatar_url'] ?? '';
    _editInviteCodeController.text = _inviteCode(user);
    _editInvitedByUserId = _invitedByUserId(user);
    _editStatus = user['status'] ?? 'offline';
    _editRole = user['role'] ?? 'user';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Редактировать',
            style: TextStyle(color: Colors.white, fontSize: 20),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildField('Имя', _editNameController),
                const SizedBox(height: 12),
                _buildField('Тег', _editTagController),
                const SizedBox(height: 12),
                _buildField('Био', _editBioController, maxLines: 3),
                const SizedBox(height: 12),
                _buildField('URL аватара', _editAvatarController),
                const SizedBox(height: 12),
                _buildField('Личный инвайт-код', _editInviteCodeController),
                const SizedBox(height: 12),
                _buildInviterDropdown(user, setDialogState),
                const SizedBox(height: 12),
                _buildReadOnlyField(
                  'Инвайт-код пригласившего',
                  _selectedInviterInviteCode(user),
                ),
                const SizedBox(height: 12),
                _buildDropdown(
                  label: 'Статус',
                  value: _editStatus,
                  items: const ['online', 'offline'],
                  onChanged: (v) => setDialogState(() => _editStatus = v!),
                ),
                const SizedBox(height: 12),
                _buildDropdown(
                  label: 'Роль',
                  value: _editRole,
                  items: const [
                    'user',
                    'admin',
                    'moderator',
                    'owner',
                    'premium',
                  ],
                  onChanged: (v) => setDialogState(() => _editRole = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A73E8),
                foregroundColor: Colors.white,
              ),
              onPressed: _saveUser,
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  String _selectedInviterInviteCode(Map<String, dynamic> editedUser) {
    final inviterId = _editInvitedByUserId;
    if (inviterId.isEmpty) return '';

    final inviter = _findUserById(inviterId);
    if (inviter != null) return _inviteCode(inviter);

    return _invitedByCode(editedUser);
  }

  Widget _buildInviterDropdown(
    Map<String, dynamic> editedUser,
    StateSetter setDialogState,
  ) {
    final currentUserId = editedUser['id']?.toString();
    final inviterOptions = _users
        .where((user) => user['id']?.toString() != currentUserId)
        .toList();
    final selectedId =
        inviterOptions.any(
          (user) => user['id']?.toString() == _editInvitedByUserId,
        )
        ? _editInvitedByUserId
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Пригласивший пользователь',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedId,
              dropdownColor: const Color(0xFF2A2A2A),
              style: const TextStyle(color: Colors.white),
              isExpanded: true,
              items: [
                const DropdownMenuItem(value: '', child: Text('Не выбран')),
                ...inviterOptions.map(
                  (user) => DropdownMenuItem(
                    value: user['id'].toString(),
                    child: Text(
                      _userLabel(user),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (value) {
                setDialogState(() => _editInvitedByUserId = value ?? '');
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    bool obscureText = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          maxLines: maxLines,
          obscureText: obscureText,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF2A2A2A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value.isEmpty ? 'Не указан' : value,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              dropdownColor: const Color(0xFF2A2A2A),
              style: const TextStyle(color: Colors.white),
              items: items.map((item) {
                return DropdownMenuItem(value: item, child: Text(item));
              }).toList(),
              onChanged: onChanged,
              isExpanded: true,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveUser() async {
    if (_editingUser == null) return;

    final userId = _editingUser!['id'];
    final newName = _editNameController.text.trim();
    final newTag = _editTagController.text.trim();
    final newBio = _editBioController.text.trim();
    final newAvatar = _editAvatarController.text.trim();
    final newInviteCode = _editInviteCodeController.text.trim();
    final newInvitedByCode = _selectedInviterInviteCode(_editingUser!);

    if (newName.isEmpty || newTag.isEmpty) {
      Toast.error(context, 'Имя и тег обязательны');
      return;
    }

    try {
      final metadata = {
        'name': newName,
        'tag': newTag,
        'bio': newBio.isEmpty ? null : newBio,
        'status': _editStatus,
        'role': _editRole,
        'avatar_url': newAvatar.isEmpty ? null : newAvatar,
        'invite_code': newInviteCode.isEmpty ? null : newInviteCode,
        'invited_by_code': newInvitedByCode.isEmpty ? null : newInvitedByCode,
        'invited_by_user_id': _editInvitedByUserId.isEmpty
            ? null
            : _editInvitedByUserId,
      };

      await Supabase.instance.client.rpc(
        'update_user_metadata',
        params: {'p_user_id': userId, 'p_metadata': metadata},
      );

      setState(() {
        final index = _users.indexWhere((u) => u['id'] == userId);
        if (index != -1) {
          _users[index] = {
            ..._users[index],
            'name': newName,
            'tag': newTag,
            'bio': newBio,
            'status': _editStatus,
            'role': _editRole,
            'avatar_url': newAvatar.isEmpty ? null : newAvatar,
            'invite_code': newInviteCode.isEmpty ? null : newInviteCode,
            'invited_by_code': newInvitedByCode.isEmpty
                ? null
                : newInvitedByCode,
            'invited_by_user_id': _editInvitedByUserId.isEmpty
                ? null
                : _editInvitedByUserId,
          };
        }
      });

      Toast.success(context, '✅ Пользователь обновлён');
      Navigator.pop(context);
    } catch (e) {
      debugPrint('Ошибка обновления: $e');
      Toast.error(context, 'Ошибка: $e');
    }
  }

  Future<void> _deleteUser(String userId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Удалить?', style: TextStyle(color: Colors.white)),
        content: const Text('Необратимо', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: Colors.red.withValues(alpha: 0.1),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await Supabase.instance.client.rpc(
        'delete_user',
        params: {'p_user_id': userId},
      );
      if (mounted) {
        setState(() => _users.removeWhere((u) => u['id'] == userId));
        Toast.success(context, 'Удалён');
      }
    } catch (e) {
      if (mounted) {
        Toast.error(context, 'Ошибка: $e');
      }
    }
  }

  void _openCreateDialog() {
    _newEmailController.clear();
    _newPasswordController.clear();
    _newNameController.clear();
    _newTagController.clear();
    _newPhoneController.clear();
    _newRole = 'user';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Создать пользователя',
          style: TextStyle(color: Colors.white, fontSize: 20),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildField('Email *', _newEmailController),
              const SizedBox(height: 12),
              _buildField(
                'Пароль *',
                _newPasswordController,
                obscureText: true,
              ),
              const SizedBox(height: 12),
              _buildField('Имя *', _newNameController),
              const SizedBox(height: 12),
              _buildField('Тег *', _newTagController),
              const SizedBox(height: 12),
              _buildField('Телефон', _newPhoneController),
              const SizedBox(height: 12),
              _buildDropdown(
                label: 'Роль',
                value: _newRole,
                items: const ['user', 'admin', 'moderator', 'owner', 'premium'],
                onChanged: (v) => setState(() => _newRole = v!),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A73E8),
              foregroundColor: Colors.white,
            ),
            onPressed: _createUser,
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }

  Future<void> _createUser() async {
    final email = _newEmailController.text.trim();
    final password = _newPasswordController.text.trim();
    final name = _newNameController.text.trim();
    final tag = _newTagController.text.trim();

    if (email.isEmpty || password.isEmpty || name.isEmpty || tag.isEmpty) {
      if (mounted) {
        Toast.error(context, 'Заполните все поля');
      }
      return;
    }

    try {
      await _authService.signUpWithEmail(
        email: email,
        password: password,
        tag: tag,
        name: name,
        phone: _newPhoneController.text.trim().isEmpty
            ? null
            : _newPhoneController.text.trim(),
      );
      if (mounted) {
        Toast.success(context, 'Создан');
        Navigator.pop(context);
        _loadUsers();
      }
    } catch (e) {
      if (mounted) {
        Toast.error(context, 'Ошибка: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0A0A),
        elevation: 0,
        title: const Text(
          'Пользователи',
          style: TextStyle(color: Colors.white, fontSize: 20),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        actions: [
          IconButton(
            onPressed: _openCreateDialog,
            icon: const Icon(Icons.person_add, color: Colors.white),
          ),
          IconButton(
            onPressed: _loadUsers,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              onChanged: (v) {
                if (mounted) {
                  setState(() => _searchQuery = v);
                }
              },
              decoration: InputDecoration(
                hintText: 'Поиск...',
                hintStyle: TextStyle(color: Colors.grey[500]),
                prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                filled: true,
                fillColor: const Color(0xFF1A1A1A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _filteredUsers.length,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemBuilder: (context, index) {
                      final user = _filteredUsers[index];
                      final isAdmin = [
                        'admin',
                        'owner',
                        'moderator',
                      ].contains(user['role']);
                      final hasInviteCode =
                          user['invite_code'] != null &&
                          user['invite_code'].toString().isNotEmpty;
                      final inviterId = _invitedByUserId(user);
                      final inviter = _findUserById(inviterId);
                      final inviterCode = _invitedByCode(user);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isAdmin
                              ? Colors.amber.withValues(alpha: 0.08)
                              : const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(12),
                          border: isAdmin
                              ? Border.all(
                                  color: Colors.amber.withValues(alpha: 0.3),
                                  width: 1,
                                )
                              : null,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isAdmin
                                ? Colors.amber
                                : Colors.grey[800],
                            backgroundImage:
                                user['avatar_url'] != null &&
                                    user['avatar_url'].toString().isNotEmpty
                                ? NetworkImage(user['avatar_url'])
                                : null,
                            child:
                                user['avatar_url'] == null ||
                                    user['avatar_url'].toString().isEmpty
                                ? Text(
                                    (user['name'] ?? '?')[0].toUpperCase(),
                                    style: TextStyle(
                                      color: isAdmin
                                          ? Colors.black
                                          : Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          ),
                          title: Text(
                            user['name'] ?? 'Без имени',
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '@${user['tag'] ?? ''} • ${user['role'] ?? 'user'}',
                                style: TextStyle(
                                  color: isAdmin
                                      ? Colors.amber[300]
                                      : Colors.grey[500],
                                  fontSize: 12,
                                ),
                              ),
                              if (hasInviteCode)
                                Text(
                                  '🔑 Личный: ${user['invite_code']}',
                                  style: TextStyle(
                                    color: Colors.green[400],
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              if (inviter != null)
                                Text(
                                  '📨 Пригласил: ${_userLabel(inviter)}',
                                  style: TextStyle(
                                    color: Colors.purple[300],
                                    fontSize: 11,
                                  ),
                                )
                              else if (inviterCode.isNotEmpty)
                                Text(
                                  '📨 Приглашён по коду: $inviterCode',
                                  style: TextStyle(
                                    color: Colors.purple[300],
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isAdmin)
                                const Icon(
                                  Icons.shield,
                                  color: Colors.amber,
                                  size: 16,
                                ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.blue,
                                  size: 20,
                                ),
                                onPressed: () => _openEditDialog(user),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                  size: 20,
                                ),
                                onPressed: () => _deleteUser(user['id']),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
