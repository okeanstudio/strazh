import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

const _versionManifestUrl = 'https://auth.strazh.chat/strazh/version.json';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.whatsNew,
    this.androidUrl,
    this.windowsUrl,
    this.downloadUrl,
  });

  final String version;
  final List<String> whatsNew;
  final String? androidUrl;
  final String? windowsUrl;
  final String? downloadUrl;
}

class AppUpdateService {
  static Future<AppUpdateInfo?> checkForUpdate() async {
    final response = await http
        .get(Uri.parse(_versionManifestUrl))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Сервер обновлений ответил ${response.statusCode}');
    }

    final Object? decoded;
    try {
      decoded = await compute(_decodeVersionManifest, response.body);
    } on FormatException {
      throw const FormatException('Неверный формат version.json');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Неверный формат version.json');
    }

    final update = _appUpdateInfoFromJson(decoded);
    final packageInfo = await PackageInfo.fromPlatform();
    if (!isNewerVersion(packageInfo.version, update.version)) return null;

    return update;
  }

  static AppUpdateInfo parseManifest(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Неверный формат version.json');
    }
    return _appUpdateInfoFromJson(decoded);
  }

  static bool isNewerVersion(String current, String latest) =>
      _compareVersions(current, latest) < 0;

  static bool _isValidVersion(String version) =>
      RegExp(r'^\d+(\.\d+)*([+-][0-9A-Za-z.-]+)?$').hasMatch(version);

  static int _compareVersions(String current, String latest) {
    final currentParts = _versionNumbers(current);
    final latestParts = _versionNumbers(latest);
    final length = currentParts.length > latestParts.length
        ? currentParts.length
        : latestParts.length;
    for (var index = 0; index < length; index++) {
      final currentPart = index < currentParts.length ? currentParts[index] : 0;
      final latestPart = index < latestParts.length ? latestParts[index] : 0;
      if (currentPart != latestPart) return currentPart.compareTo(latestPart);
    }
    return 0;
  }

  static List<int> _versionNumbers(String version) => version
      .split(RegExp(r'[+-]'))
      .first
      .split('.')
      .map((part) => int.parse(part))
      .toList();
}

AppUpdateInfo _appUpdateInfoFromJson(Map<String, dynamic> json) {
  final version = json['version'];
  if (version is! String || !AppUpdateService._isValidVersion(version)) {
    throw const FormatException('В version.json указана неверная версия');
  }

  final rawNotes = json['whats_new'];
  final notes = <String>[];
  if (rawNotes != null) {
    if (rawNotes is! List) {
      throw const FormatException('Поле whats_new должно быть списком строк');
    }
    for (final note in rawNotes) {
      if (note is! String || note.trim().isEmpty) {
        throw const FormatException(
          'Поле whats_new должно содержать непустые строки',
        );
      }
      notes.add(note.trim());
    }
  }

  return AppUpdateInfo(
    version: version,
    whatsNew: List.unmodifiable(notes),
    androidUrl: _readHttpsUrl(json, 'android_url'),
    windowsUrl: _readHttpsUrl(json, 'windows_url'),
    downloadUrl: _readHttpsUrl(json, 'download_url'),
  );
}

String? _readHttpsUrl(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('Поле $key должно быть строкой');
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw FormatException('В поле $key указан некорректный HTTPS URL');
  }
  return trimmed;
}

Map<String, dynamic> _decodeVersionManifest(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Неверный формат version.json');
  }
  return decoded;
}
