import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class FirebaseWebConfig {
  FirebaseWebConfig._();

  static FirebaseOptions? options;
  static String? vapidKey;
  static bool get isConfigured => options != null && vapidKey != null;

  static Future<FirebaseOptions?> load() async {
    final response = await http
        .get(Uri.base.resolve('firebase-messaging-config.json'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw StateError(
        'Не удалось загрузить Firebase Web config (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Некорректный Firebase Web config');
    }

    final apiKey = decoded['apiKey'] as String? ?? '';
    final appId = decoded['appId'] as String? ?? '';
    vapidKey = (decoded['vapidKey'] as String?)?.trim();
    if (apiKey.isEmpty || appId.isEmpty || vapidKey?.isNotEmpty != true) {
      debugPrint(
        'Firebase Web Push отключён: заполните Firebase Web App и VAPID '
        'в web/firebase-messaging-config.json',
      );
      return null;
    }

    final firebaseOptions = FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      authDomain: decoded['authDomain'] as String?,
      messagingSenderId:
          decoded['messagingSenderId'] as String? ?? '685600608862',
      projectId: decoded['projectId'] as String? ?? 'strazh-e2ee',
      storageBucket: decoded['storageBucket'] as String?,
    );
    options = firebaseOptions;
    return firebaseOptions;
  }
}
