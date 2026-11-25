import 'dart:js_interop';

import 'package:web/web.dart' as web;

@JS('globalThis.navigator.standalone')
external JSBoolean? get _legacyStandalone;

@JS('globalThis.Notification')
external JSAny? get _notificationConstructor;

@JS('globalThis.navigator.serviceWorker')
external JSAny? get _serviceWorker;

@JS('globalThis.PushManager')
external JSAny? get _pushManagerConstructor;

bool get isIOSBrowser {
  final userAgent = web.window.navigator.userAgent;
  final platform = web.window.navigator.platform;
  final isIOS =
      userAgent.contains('iPhone') ||
      userAgent.contains('iPad') ||
      userAgent.contains('iPod');
  final isIPadOS =
      platform == 'MacIntel' && web.window.navigator.maxTouchPoints > 1;
  return isIOS || isIPadOS;
}

bool get isStandaloneApp {
  final displayModeStandalone = web.window
      .matchMedia('(display-mode: standalone)')
      .matches;
  return displayModeStandalone || (_legacyStandalone?.toDart ?? false);
}

bool get supportsWebPush =>
    _notificationConstructor != null &&
    _serviceWorker != null &&
    _pushManagerConstructor != null;
