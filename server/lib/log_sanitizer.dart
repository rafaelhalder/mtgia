String sanitizeLogMessage(String message) {
  var redacted = message;

  final patterns = <RegExp, String>{
    RegExp(r'(?i)(authorization\s*:\s*bearer\s+)[A-Za-z0-9\-\._~\+\/=]+'):
        r'$1[REDACTED]',
    RegExp(r'(?i)(api[_-]?key\s*[=:]\s*)[^\s,;]+'): r'$1[REDACTED]',
    RegExp(r'(?i)(openai[_-]?api[_-]?key\s*[=:]\s*)[^\s,;]+'):
        r'$1[REDACTED]',
    RegExp(r'(?i)(jwt[_-]?secret\s*[=:]\s*)[^\s,;]+'): r'$1[REDACTED]',
    RegExp(r'(?i)(password\s*[=:]\s*)[^\s,;]+'): r'$1[REDACTED]',
    RegExp(r'(?i)(db[_-]?pass\s*[=:]\s*)[^\s,;]+'): r'$1[REDACTED]',
    RegExp(r'\bsk-[A-Za-z0-9_-]{10,}\b'): '[REDACTED_OPENAI_KEY]',
  };

  for (final entry in patterns.entries) {
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
