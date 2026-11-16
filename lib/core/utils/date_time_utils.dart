DateTime parseDateTimeSafely(dynamic value, {DateTime? fallback}) {
  if (value is DateTime) return value.toLocal();

  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty || raw.toLowerCase() == 'null' || raw.toLowerCase() == 'forever') {
    return fallback ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  final parsed = DateTime.tryParse(raw);
  if (parsed != null) {
    return parsed.toLocal();
  }

  final normalized = raw.contains(' ') && !raw.contains('T')
      ? raw.replaceFirst(' ', 'T')
      : raw;
  final normalizedParsed = DateTime.tryParse(normalized);
  if (normalizedParsed != null) {
    return normalizedParsed.toLocal();
  }

  return fallback ?? DateTime.fromMillisecondsSinceEpoch(0);
}
