import 'package:flutter/material.dart';
import 'package:strazh/features/chat/data/services/fcm_service.dart';
import 'package:strazh/features/settings/data/services/sound_service.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

class SoundSettingsScreen extends StatefulWidget {
  const SoundSettingsScreen({super.key});

  @override
  State<SoundSettingsScreen> createState() => _SoundSettingsScreenState();
}

class _SoundSettingsScreenState extends State<SoundSettingsScreen> {
  static const _accent = Color(0xFF48C5B5);

  late bool _notificationsEnabled;
  late bool _initialNotificationsEnabled;
  late bool _incomingMessage;
  late bool _outgoingMessage;
  late bool _groupMessage;
  late bool _incomingCall;
  late bool _vibrate;
  late bool _silentMode;
  late double _volume;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final settings = SoundService().settings.value;
    _notificationsEnabled = settings.notificationsEnabled;
    _initialNotificationsEnabled = settings.notificationsEnabled;
    _incomingMessage = settings.incomingMessage;
    _outgoingMessage = settings.outgoingMessage;
    _groupMessage = settings.groupMessage;
    _incomingCall = settings.incomingCall;
    _vibrate = settings.vibrate;
    _silentMode = settings.silentMode;
    _volume = settings.volume;
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    SoundService().setSettings(
      SoundSettings(
        notificationsEnabled: _notificationsEnabled,
        incomingMessage: _incomingMessage,
        outgoingMessage: _outgoingMessage,
        groupMessage: _groupMessage,
        incomingCall: _incomingCall,
        vibrate: _vibrate,
        silentMode: _silentMode,
        volume: _volume,
      ),
    );
    await SoundService().saveSettings();

    var deliveryEnabled = true;
    if (_notificationsEnabled != _initialNotificationsEnabled) {
      deliveryEnabled = await FcmService().setNotificationsEnabled(
        _notificationsEnabled,
      );
    }

    if (!mounted) return;
    setState(() => _isSaving = false);
    if (!deliveryEnabled && _notificationsEnabled) {
      setState(() => _notificationsEnabled = false);
      SoundService().setSettings(
        SoundService().settings.value.copyWith(notificationsEnabled: false),
      );
      await FcmService().setNotificationsEnabled(false);
      await SoundService().saveSettings();
      if (!mounted) return;
      Toast.warning(context, 'Разрешите уведомления в настройках устройства');
      return;
    }

    Toast.success(context, 'Настройки уведомлений сохранены');
    Navigator.pop(context, true);
  }

  Future<void> _resetDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF171B22),
        title: const Text('Сбросить настройки?'),
        content: const Text('Все параметры вернутся к значениям по умолчанию.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _notificationsEnabled = true;
      _incomingMessage = true;
      _outgoingMessage = false;
      _groupMessage = true;
      _incomingCall = true;
      _vibrate = true;
      _silentMode = false;
      _volume = 0.7;
    });
  }

  @override
  Widget build(BuildContext context) {
    final alertsEnabled = _notificationsEnabled && !_silentMode;

    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101418),
        foregroundColor: Colors.white,
        title: const Text(
          'Уведомления',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: const Text('Сохранить'),
            style: TextButton.styleFrom(foregroundColor: _accent),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
              children: [
                _buildStatusBanner(),
                const SizedBox(height: 24),
                _buildSectionHeader('Общие'),
                const SizedBox(height: 8),
                _buildCard([
                  _buildSwitchTile(
                    icon: Icons.notifications_active_outlined,
                    iconColor: _accent,
                    title: 'Разрешить уведомления',
                    subtitle: 'Сообщения, звонки, звук и вибрация',
                    value: _notificationsEnabled,
                    onChanged: (value) =>
                        setState(() => _notificationsEnabled = value),
                  ),
                ]),
                const SizedBox(height: 22),
                _buildSectionHeader('Сообщения'),
                const SizedBox(height: 8),
                _buildCard([
                  _buildSwitchTile(
                    icon: Icons.chat_bubble_outline,
                    iconColor: const Color(0xFF68A9F5),
                    title: 'Личные сообщения',
                    subtitle: 'Звук при новом сообщении',
                    value: _incomingMessage,
                    enabled: alertsEnabled,
                    onChanged: (value) =>
                        setState(() => _incomingMessage = value),
                  ),
                  _buildDivider(),
                  _buildSwitchTile(
                    icon: Icons.groups_outlined,
                    iconColor: const Color(0xFF5AB6D6),
                    title: 'Групповые чаты',
                    subtitle: 'Звук при новом сообщении в группе',
                    value: _groupMessage,
                    enabled: alertsEnabled,
                    onChanged: (value) => setState(() => _groupMessage = value),
                  ),
                  _buildDivider(),
                  _buildSwitchTile(
                    icon: Icons.send_outlined,
                    iconColor: const Color(0xFF79C994),
                    title: 'Отправленные сообщения',
                    subtitle: 'Звук после отправки',
                    value: _outgoingMessage,
                    enabled: alertsEnabled,
                    onChanged: (value) =>
                        setState(() => _outgoingMessage = value),
                  ),
                ]),
                const SizedBox(height: 22),
                _buildSectionHeader('Звонки и вибрация'),
                const SizedBox(height: 8),
                _buildCard([
                  _buildSwitchTile(
                    icon: Icons.call_outlined,
                    iconColor: const Color(0xFFF1AA64),
                    title: 'Входящие звонки',
                    subtitle: 'Звуковой сигнал при вызове',
                    value: _incomingCall,
                    enabled: alertsEnabled,
                    onChanged: (value) => setState(() => _incomingCall = value),
                  ),
                  _buildDivider(),
                  _buildSwitchTile(
                    icon: Icons.vibration_rounded,
                    iconColor: const Color(0xFFE7839B),
                    title: 'Вибрация',
                    subtitle: 'Тактильный отклик при сообщениях',
                    value: _vibrate,
                    enabled: alertsEnabled,
                    onChanged: (value) => setState(() => _vibrate = value),
                  ),
                ]),
                const SizedBox(height: 22),
                _buildSectionHeader('Звук'),
                const SizedBox(height: 8),
                _buildCard([
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.volume_up_outlined, color: _accent),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Громкость',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          '${(_volume * 100).round()}%',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  Slider(
                    value: _volume,
                    min: 0,
                    max: 1,
                    divisions: 10,
                    activeColor: _accent,
                    onChanged: alertsEnabled
                        ? (value) => setState(() => _volume = value)
                        : null,
                  ),
                  _buildDivider(),
                  _buildSwitchTile(
                    icon: Icons.notifications_off_outlined,
                    iconColor: const Color(0xFFE7836F),
                    title: 'Беззвучный режим',
                    subtitle: 'Отключить звук и вибрацию',
                    value: _silentMode,
                    enabled: _notificationsEnabled,
                    onChanged: (value) => setState(() => _silentMode = value),
                  ),
                ]),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _resetDefaults,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Сбросить настройки'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accent,
                    side: BorderSide(color: _accent.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBanner() {
    final enabled = _notificationsEnabled && !_silentMode;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF192328),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              enabled ? Icons.notifications_active : Icons.notifications_off,
              color: _accent,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Оповещения Strazh',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  enabled ? 'Уведомления включены' : 'Уведомления отключены',
                  style: TextStyle(
                    color: enabled ? _accent : Colors.white54,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF191E23),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch.adaptive(
              value: value,
              onChanged: enabled ? onChanged : null,
              activeTrackColor: _accent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() => Divider(
    color: Colors.white.withValues(alpha: 0.06),
    height: 1,
    indent: 64,
  );
}
