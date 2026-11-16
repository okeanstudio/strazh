import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_desktop_notifications/flutter_desktop_notifications.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_communication_avatar/flutter_communication_avatar.dart';
import 'package:strazh/shared/domain/models/chat.dart';
import 'package:strazh/features/settings/data/services/sound_service.dart';
import 'package:strazh/features/chat/data/services/chat_list_preferences.dart';
import 'package:strazh/features/chat/data/services/end_to_end_encryption_service.dart';
import 'package:window_manager/window_manager.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final WindowsNotification _notifier = WindowsNotification(
    applicationId: 'com.denotestudio.strazh',
  );
  static const MethodChannel _communicationAvatarChannel = MethodChannel(
    'flutter_communication_avatar',
  );

  bool _isInitialized = false;
  bool _communicationNotificationsInitialized = false;

  void Function(String chatId)? _onChatSelected;
  String? _pendingChatId;

  set onChatSelected(void Function(String chatId)? callback) {
    _onChatSelected = callback;
    final pendingChatId = _pendingChatId;
    if (callback != null && pendingChatId != null) {
      _pendingChatId = null;
      callback(pendingChatId);
    }
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final isDesktop =
          !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.macOS ||
              defaultTargetPlatform == TargetPlatform.linux);

      if (isDesktop) {
        await _notifier.setCallback((details) {
          switch (details.event) {
            case NotificationEvent.activated:
              _showWindow();
              final chatId = details.arguments;
              if (chatId != null && _onChatSelected != null) {
                _onChatSelected!(chatId);
              }
              break;
            case NotificationEvent.dismissedByUser:
              debugPrint('Уведомление закрыто пользователем');
              break;
            default:
              break;
          }
        });
      }

      final isMobile =
          !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS);
      if (isMobile) {
        await _initializeCommunicationNotifications();

        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          unawaited(_showMobileNotification(message));
        });

        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          _handleNotificationTap(message);
        });

        final initialMessage = await FirebaseMessaging.instance
            .getInitialMessage();
        if (initialMessage != null) _handleNotificationTap(initialMessage);
      }

      _isInitialized = true;
      debugPrint('✅ Уведомления инициализированы');
    } catch (e) {
      debugPrint('❌ Ошибка инициализации уведомлений: $e');
    }
  }

  Future<void> _initializeCommunicationNotifications() async {
    if (_communicationNotificationsInitialized) return;

    if (defaultTargetPlatform == TargetPlatform.android) {
      final created = await FlutterCommunicationAvatar.instance
          .createNotificationChannel(
            const NotificationChannelConfig(
              id: 'messages_channel',
              name: 'Сообщения',
              description: 'Уведомления о новых сообщениях',
              importance: 5,
            ),
          );
      if (!created) {
        throw StateError(
          'Не удалось создать канал уведомлений messages_channel',
        );
      }

      _communicationAvatarChannel.setMethodCallHandler((call) async {
        if (call.method == 'onNotificationTapped') {
          _handleLocalNotificationTap(call.arguments as String?);
        }
      });
      final initialChatId = await _communicationAvatarChannel
          .invokeMethod<String>('getInitialNotificationTap');
      _handleLocalNotificationTap(initialChatId);
    }

    _communicationNotificationsInitialized = true;
  }

  void _handleNotificationTap(RemoteMessage message) {
    _handleLocalNotificationTap(message.data['chatId'] as String?);
  }

  void _handleLocalNotificationTap(String? chatId) {
    if (chatId is! String || chatId.isEmpty) return;

    final callback = _onChatSelected;
    if (callback == null) {
      _pendingChatId = chatId;
    } else {
      callback(chatId);
    }
  }

  Future<void> showPushNotification(RemoteMessage message) =>
      _showMobileNotification(message);

  Future<void> _showMobileNotification(RemoteMessage message) async {
    if (!SoundService().settings.value.notificationsEnabled) return;
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }

    try {
      await _initializeCommunicationNotifications();
      final data = message.data;
      final chatId = data['chatId'] as String? ?? '';
      if (chatId.isNotEmpty &&
          await ChatListPreferences.isMutedForCurrentUser(chatId)) {
        return;
      }
      final senderId = data['senderId'] as String? ?? '';
      final senderName = data['senderName'] as String? ?? 'Новое сообщение';
      final avatarUrl = data['imageUrl'] as String?;
      var body = '🔒 Новое сообщение';
      final messageId = data['messageId'] as String?;
      if (chatId.isNotEmpty && messageId != null && senderId.isNotEmpty) {
        try {
          body = await EndToEndEncryptionService.instance.decryptPushedMessage(
            roomId: chatId,
            messageId: messageId,
            expectedSenderId: senderId,
          );
        } catch (error) {
          debugPrint('Не удалось расшифровать push-сообщение: $error');
        }
      }

      final sender = CommunicationPerson(
        id: senderId.isEmpty ? 'unknown' : senderId,
        name: senderName,
        avatarUrl: avatarUrl?.isNotEmpty == true ? avatarUrl : null,
      );
      final notificationId =
          message.messageId?.hashCode ??
          messageId?.hashCode ??
          DateTime.now().microsecondsSinceEpoch;

      final shown = await FlutterCommunicationAvatar.instance.showNotification(
        CommunicationNotification(
          id: notificationId,
          title: senderName,
          body: body,
          sender: sender,
          conversationId: chatId,
          isGroupConversation: false,
          channelId: 'messages_channel',
          channelName: 'Сообщения',
          channelDescription: 'Уведомления о новых сообщениях',
          smallIcon: 'ic_stat_strazh',
          payload: {'chatId': chatId},
        ),
      );
      if (!shown) {
        debugPrint('Не удалось показать уведомление о сообщении $chatId');
      }
    } catch (e) {
      debugPrint('❌ Ошибка мобильного уведомления: $e');
    }
  }

  Future<void> _showWindow() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      debugPrint('Ошибка показа окна: $e');
    }
  }

  Future<void> showChatNotification({required Chat chat}) async {
    if (!_isInitialized ||
        !SoundService().settings.value.notificationsEnabled) {
      return;
    }

    try {
      if (await ChatListPreferences.isMutedForCurrentUser(chat.id)) return;
      const title = 'Strazh';
      const subtitle = 'Новое сообщение';

      final notificationMessage = NotificationMessage.fromPluginTemplate(
        'chat-${chat.id}',
        title,
        subtitle,
        actions: [
          NotificationAction(content: 'Открыть чат', arguments: chat.id),
        ],
      );

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        await _notifier.showNotificationPluginTemplate(notificationMessage);
      }
    } catch (e) {
      debugPrint('❌ Ошибка показа уведомления: $e');
    }
  }

  Future<void> cancelAllNotifications() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      await _notifier.clearNotificationHistory();
    }
  }
}
