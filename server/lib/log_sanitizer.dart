String sanitizeLogMessage(String message) {
  var redacted = message;

  final patterns = <MapEntry<RegExp, String>>[
    MapEntry(
      RegExp(
        r'(authorization\s*:\s*bearer\s+)[A-Za-z0-9\-\._~\+\/=]+',
        caseSensitive: false,
      ),
      r'$1[REDACTED]',
    ),
    MapEntry(
      RegExp(r'(api[_-]?key\s*[=:]\s*)[^\s,;]+', caseSensitive: false),
      r'$1[REDACTED]',
    ),
    MapEntry(
      RegExp(
        r'(openai[_-]?api[_-]?key\s*[=:]\s*)[^\s,;]+',
        caseSensitive: false,
      ),
      r'$1[REDACTED]',
    ),
    MapEntry(
      RegExp(r'(jwt[_-]?secret\s*[=:]\s*)[^\s,;]+', caseSensitive: false),
      r'$1[REDACTED]',
    ),
    MapEntry(
      RegExp(r'(password\s*[=:]\s*)[^\s,;]+', caseSensitive: false),
      r'$1[REDACTED]',
    ),
    MapEntry(
      RegExp(r'(db[_-]?pass\s*[=:]\s*)[^\s,;]+', caseSensitive: false),
      r'$1[REDACTED]',
    ),
    MapEntry(RegExp(r'\bsk-[A-Za-z0-9_-]{10,}\b'), '[REDACTED_OPENAI_KEY]'),
  ];

  for (final entry in patterns) {
    redacted = redacted.replaceAllMapped(entry.key, (m) {
      final replacement = entry.value;
      if (replacement.contains(r'$1') && m.groupCount >= 1) {
        return replacement.replaceFirst(r'$1', m.group(1) ?? '');
      }
      return replacement;
    });
  }

  return redacted;
}
