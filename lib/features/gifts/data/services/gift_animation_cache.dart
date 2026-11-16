import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:universal_io/io.dart';

class GiftAnimationCache {
  static const _cacheDirectoryName = 'gift_animations';
  static const _maxAnimationBytes = 5 * 1024 * 1024;
  static final Map<String, Future<Uint8List?>> _pendingAnimations = {};
  static int _generation = 0;

  static Future<Uint8List?> load({
    required String giftId,
    required String url,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw FormatException('Некорректная HTTPS-ссылка на анимацию: $url');
    }

    final cacheKey = '$giftId\n${uri.toString()}';
    final cached = _pendingAnimations[cacheKey];
    if (cached != null) return cached;

    final generation = _generation;
    final request = _load(cacheKey: cacheKey, uri: uri, generation: generation);
    _pendingAnimations[cacheKey] = request;
    try {
      return await request;
    } catch (_) {
      if (identical(_pendingAnimations[cacheKey], request)) {
        _pendingAnimations.remove(cacheKey);
      }
      rethrow;
    }
  }

  static Future<Uint8List> _load({
    required String cacheKey,
    required Uri uri,
    required int generation,
  }) async {
    if (!kIsWeb) {
      final file = await _fileFor(cacheKey);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (_isValidLottieJson(bytes)) return bytes;
        await file.delete();
      }
    }

    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Не удалось загрузить анимацию (HTTP ${response.statusCode})',
        uri: uri,
      );
    }
    final bytes = response.bodyBytes;
    if (bytes.length > _maxAnimationBytes) {
      throw FormatException('Файл анимации превышает 5 МБ: $uri');
    }
    if (!_isValidLottieJson(bytes)) {
      throw FormatException('По ссылке находится некорректный JSON Lottie: $uri');
    }

    if (!kIsWeb && generation == _generation) {
      final file = await _fileFor(cacheKey);
      await file.parent.create(recursive: true);
      final temporaryFile = File('${file.path}.part');
      await temporaryFile.writeAsBytes(bytes, flush: true);
      await temporaryFile.rename(file.path);
    }
    return bytes;
  }

  static bool _isValidLottieJson(Uint8List bytes) {
    try {
      return jsonDecode(utf8.decode(bytes)) is Map;
    } on FormatException {
      return false;
    }
  }

  static Future<File> _fileFor(String cacheKey) async {
    final directory = await getApplicationSupportDirectory();
    return File(
      '${directory.path}/$_cacheDirectoryName/${_stableHash(cacheKey)}.json',
    );
  }

  static String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(value)) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static Future<void> clear() async {
    _generation++;
    _pendingAnimations.clear();
    if (kIsWeb) return;

    final directory = await getApplicationSupportDirectory();
    final cacheDirectory = Directory(
      '${directory.path}/$_cacheDirectoryName',
    );
    if (await cacheDirectory.exists()) {
      await cacheDirectory.delete(recursive: true);
    }
  }
}
