import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SoundSettings {
  final bool notificationsEnabled;
  final bool incomingMessage;
  final bool outgoingMessage;
  final bool groupMessage;
  final bool incomingCall;
  final bool vibrate;
  final bool silentMode;
  final double volume;

  const SoundSettings({
    this.notificationsEnabled = true,
    this.incomingMessage = true,
    this.outgoingMessage = false,
    this.groupMessage = true,
    this.incomingCall = true,
    this.vibrate = true,
    this.silentMode = false,
    this.volume = 0.7,
  });

  SoundSettings copyWith({
    bool? notificationsEnabled,
    bool? incomingMessage,
    bool? outgoingMessage,
    bool? groupMessage,
    bool? incomingCall,
    bool? vibrate,
    bool? silentMode,
    double? volume,
  }) {
    return SoundSettings(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      incomingMessage: incomingMessage ?? this.incomingMessage,
      outgoingMessage: outgoingMessage ?? this.outgoingMessage,
      groupMessage: groupMessage ?? this.groupMessage,
      incomingCall: incomingCall ?? this.incomingCall,
      vibrate: vibrate ?? this.vibrate,
      silentMode: silentMode ?? this.silentMode,
      volume: volume ?? this.volume,
    );
  }
}

class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  // ===== КЛЮЧИ ДЛЯ SHARED PREFERENCES =====
  static const String _kNotificationsEnabled = 'notifications_enabled';
  static const String _kIncomingMessage = 'sound_incoming_message';
  static const String _kOutgoingMessage = 'sound_outgoing_message';
  static const String _kGroupMessage = 'sound_group_message';
  static const String _kIncomingCall = 'sound_incoming_call';
  static const String _kVibrate = 'sound_vibrate';
  static const String _kSilentMode = 'sound_silent_mode';
  static const String _kVolume = 'sound_volume';

  /// Текущие настройки. UI подписывается на этот notifier.
  final ValueNotifier<SoundSettings> settings = ValueNotifier(
    const SoundSettings(),
  );

  /// Загрузить настройки из SharedPreferences
  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      settings.value = SoundSettings(
        notificationsEnabled: prefs.getBool(_kNotificationsEnabled) ?? true,
        incomingMessage: prefs.getBool(_kIncomingMessage) ?? true,
        outgoingMessage: prefs.getBool(_kOutgoingMessage) ?? false,
        groupMessage: prefs.getBool(_kGroupMessage) ?? true,
        incomingCall: prefs.getBool(_kIncomingCall) ?? true,
        vibrate: prefs.getBool(_kVibrate) ?? true,
        silentMode: prefs.getBool(_kSilentMode) ?? false,
        volume: prefs.getDouble(_kVolume) ?? 0.7,
      );

      debugPrint('✅ SoundService: настройки загружены: ${settings.value}');
    } catch (e) {
      debugPrint('❌ SoundService: ошибка загрузки: $e');
    }
  }

  /// Сохранить текущие настройки в SharedPreferences
  Future<void> saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = settings.value;

      await prefs.setBool(_kNotificationsEnabled, s.notificationsEnabled);
      await prefs.setBool(_kIncomingMessage, s.incomingMessage);
      await prefs.setBool(_kOutgoingMessage, s.outgoingMessage);
      await prefs.setBool(_kGroupMessage, s.groupMessage);
      await prefs.setBool(_kIncomingCall, s.incomingCall);
      await prefs.setBool(_kVibrate, s.vibrate);
      await prefs.setBool(_kSilentMode, s.silentMode);
      await prefs.setDouble(_kVolume, s.volume);

      debugPrint('✅ SoundService: настройки сохранены: $s');
    } catch (e) {
      debugPrint('❌ SoundService: ошибка сохранения: $e');
    }
  }

  /// Обновить настройки в памяти (без сохранения в хранилище)
  void setSettings(SoundSettings s) {
    settings.value = s;
  }

  /// Удобные геттеры для использования в других местах приложения
  bool get incomingMessageEnabled =>
      settings.value.notificationsEnabled &&
      !settings.value.silentMode &&
      settings.value.incomingMessage;

  bool get outgoingMessageEnabled =>
      settings.value.notificationsEnabled &&
      !settings.value.silentMode &&
      settings.value.outgoingMessage;

  bool get groupMessageEnabled =>
      settings.value.notificationsEnabled &&
      !settings.value.silentMode &&
      settings.value.groupMessage;

  bool get incomingCallEnabled =>
      settings.value.notificationsEnabled &&
      !settings.value.silentMode &&
      settings.value.incomingCall;

  bool get vibrateEnabled =>
      settings.value.notificationsEnabled &&
      !settings.value.silentMode &&
      settings.value.vibrate;

  double get currentVolume =>
      !settings.value.notificationsEnabled || settings.value.silentMode
      ? 0.0
      : settings.value.volume;
}
