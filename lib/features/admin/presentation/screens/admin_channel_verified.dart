import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

class AdminChannelVerifiedScreen extends StatefulWidget {
  const AdminChannelVerifiedScreen({super.key});

  @override
  State<AdminChannelVerifiedScreen> createState() =>
      _AdminChannelVerifiedScreenState();
}

class _AdminChannelVerifiedScreenState
    extends State<AdminChannelVerifiedScreen> {
  List<Map<String, dynamic>> _channels = [];
  final Set<String> _updatingChannels = {};
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  Future<void> _loadChannels() async {
    setState(() => _isLoading = true);
    try {
      final result = await Supabase.instance.client.rpc(
        'get_channels_for_verification',
      );
      if (!mounted) return;
      setState(() {
        _channels = (result as List)
            .map((channel) => Map<String, dynamic>.from(channel as Map))
            .toList();
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('Ошибка загрузки каналов для верификации: $error');
      if (!mounted) return;
      setState(() => _isLoading = false);
      Toast.error(context, 'Не удалось загрузить каналы');
    }
  }

  Future<void> _setVerified(String channelId, bool isVerified) async {
    if (!_updatingChannels.add(channelId)) return;
    setState(() {});
    try {
      await Supabase.instance.client.rpc(
        'set_channel_verified',
        params: {'p_room_id': channelId, 'p_is_verified': !isVerified},
      );
      if (!mounted) return;
      setState(() {
        final index = _channels.indexWhere(
          (channel) => channel['id'] == channelId,
        );
        if (index != -1) _channels[index]['is_verified'] = !isVerified;
      });
      Toast.success(
        context,
        !isVerified ? 'Галочка каналу выдана' : 'Галочка канала снята',
      );
    } catch (error) {
      debugPrint('Ошибка изменения верификации канала: $error');
      if (mounted) Toast.error(context, 'Не удалось изменить галочку канала');
    } finally {
      _updatingChannels.remove(channelId);
      if (mounted) setState(() {});
    }
  }

  List<Map<String, dynamic>> get _filteredChannels {
    final query = _searchQuery.toLowerCase();
    return _channels.where((channel) {
      final name = (channel['name'] as String? ?? '').toLowerCase();
      final tag = (channel['tag'] as String? ?? '').toLowerCase();
      return name.contains(query) || tag.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0A0A),
        elevation: 0,
        title: const Text(
          'Галочки каналов',
          style: TextStyle(color: Colors.white, fontSize: 20),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        actions: [
          IconButton(
            onPressed: _loadChannels,
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
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Поиск канала...',
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
                : _filteredChannels.isEmpty
                ? const Center(
                    child: Text(
                      'Каналы не найдены',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _filteredChannels.length,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemBuilder: (context, index) {
                      final channel = _filteredChannels[index];
                      final id = channel['id'] as String;
                      final name = channel['name'] as String? ?? 'Канал';
                      final avatarUrl = channel['avatar_url'] as String?;
                      final isVerified = channel['is_verified'] == true;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.grey[800],
                            backgroundImage:
                                avatarUrl != null && avatarUrl.isNotEmpty
                                ? NetworkImage(avatarUrl)
                                : null,
                            child: avatarUrl == null || avatarUrl.isEmpty
                                ? Text(
                                    name.isNotEmpty
                                        ? name[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(color: Colors.white),
                                  )
                                : null,
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            channel['tag'] == null
                                ? 'Канал'
                                : '@${channel['tag']}',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                          trailing: Switch(
                            value: isVerified,
                            onChanged: _updatingChannels.contains(id)
                                ? null
                                : (_) => _setVerified(id, isVerified),
                            activeColor: const Color(0xFF1A73E8),
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
