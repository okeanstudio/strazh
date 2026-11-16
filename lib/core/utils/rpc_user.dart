Map<String, dynamic>? rpcUserRecord(dynamic response) {
  Map<String, dynamic>? record;
  if (response is Map<String, dynamic>) {
    record = response;
  } else if (response is List && response.isNotEmpty && response.first is Map) {
    record = Map<String, dynamic>.from(response.first as Map);
  }
  if (record == null) return null;

  final metadata = <String, dynamic>{};
  final rawMetadata = record['raw_user_meta_data'] ?? record['user_metadata'];
  if (rawMetadata is Map) {
    metadata.addAll(Map<String, dynamic>.from(rawMetadata));
  }

  String? value(String key, [String? fallbackKey]) {
    final direct = record![key];
    if (direct is String && direct.isNotEmpty) return direct;
    final fallback = fallbackKey == null ? null : metadata[fallbackKey];
    return fallback is String && fallback.isNotEmpty ? fallback : null;
  }

  return {
    ...metadata,
    ...record,
    'id': record['id'] ?? record['user_id'],
    'name': value('name', 'display_name') ?? 'Пользователь',
    'tag': value('tag'),
    'avatar_url': value('avatar_url'),
    'status': value('status') ?? 'offline',
    'phone': value('phone'),
  };
}
