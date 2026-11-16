import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

const _versionManifestUrl = 'https://auth.strazh.chat/strazh/version.json';

class AppUpdateInfo {
  const AppUpdateInfo({required this.version});

  final String version;
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

    final latestVersion = decoded['version'];
    if (latestVersion is! String || !_isValidVersion(latestVersion)) {
      throw const FormatException('В version.json указана неверная версия');
    }

    final packageInfo = await PackageInfo.fromPlatform();
    if (!isNewerVersion(packageInfo.version, latestVersion)) return null;

    return AppUpdateInfo(version: latestVersion);
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

Map<String, dynamic> _decodeVersionManifest(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Неверный формат version.json');
  }
  return decoded;
}
