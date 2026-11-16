import 'dart:convert';

import 'package:http/http.dart' as http;

class UploadLimitException implements Exception {
  final String message;

  const UploadLimitException(this.message);

  @override
  String toString() => message;
}

class UploadSizeLimitExceeded extends UploadLimitException {
  const UploadSizeLimitExceeded(super.message);
}

class UploadLimitsService {
  static final Uri _limitsUri = Uri.parse(
    'https://strazh.chat/api/limits.json',
  );
  static const int _bytesPerMegabyte = 1024 * 1024;
  static const Duration _cacheDuration = Duration(minutes: 5);
  static Map<String, double>? _cachedLimits;
  static DateTime? _cachedAt;

  static Future<void> ensureWithinLimit({
    required int sizeBytes,
    required String role,
    required bool isPremium,
  }) async {
    if (sizeBytes < 0) {
      throw const UploadLimitException('Не удалось определить размер файла.');
    }

    final normalizedRole = role.trim().toLowerCase();
    if (const {'moderator', 'admin', 'owner'}.contains(normalizedRole)) {
      return;
    }

    final limits = await _loadLimits();
    final plan = isPremium || normalizedRole == 'premium' ? 'premium' : 'user';
    final maxSizeMb = limits[plan]!;
    final maxBytes = maxSizeMb * _bytesPerMegabyte;
    if (sizeBytes > maxBytes) {
      final sizeMb = sizeBytes / _bytesPerMegabyte;
      throw UploadSizeLimitExceeded(
        'Размер файла ${sizeMb.toStringAsFixed(1)} МБ превышает лимит '
        '${maxSizeMb.toStringAsFixed(maxSizeMb % 1 == 0 ? 0 : 1)} МБ '
        'для ${plan == 'premium' ? 'Strazh Infinity' : 'обычного тарифа'}.',
      );
    }
  }

  static Future<Map<String, double>> _loadLimits() async {
    final cachedLimits = _cachedLimits;
    final cachedAt = _cachedAt;
    if (cachedLimits != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheDuration) {
      return cachedLimits;
    }

    final http.Response response;
    try {
      response = await http
          .get(_limitsUri)
          .timeout(const Duration(seconds: 15));
    } catch (error) {
      throw UploadLimitException(
        'Не удалось загрузить лимиты отправки: $error',
      );
    }

    if (response.statusCode != 200) {
      throw UploadLimitException(
        'Сервер лимитов ответил с кодом ${response.statusCode}.',
      );
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Ожидался JSON-объект с тарифами.');
      }

      final userLimit = _readLimit(decoded, 'user');
      final premiumLimit = _readLimit(decoded, 'premium');
      _cachedLimits = {'user': userLimit, 'premium': premiumLimit};
      _cachedAt = DateTime.now();
      return _cachedLimits!;
    } on FormatException catch (error) {
      throw UploadLimitException('Некорректный JSON лимитов: $error');
    }
  }

  static double _readLimit(Map<String, dynamic> json, String plan) {
    final planData = json[plan];
    if (planData is! Map<String, dynamic>) {
      throw FormatException('Отсутствует объект "$plan".');
    }

    final maxSize = planData['max_file_size_mb'];
    if (maxSize is! num || !maxSize.isFinite || maxSize <= 0) {
      throw FormatException(
        'Поле "$plan.max_file_size_mb" должно быть положительным числом.',
      );
    }

    return maxSize.toDouble();
  }
}
