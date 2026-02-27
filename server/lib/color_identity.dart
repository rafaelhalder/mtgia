Set<String> normalizeColorIdentity(Iterable<String> identity) {
  final normalized = <String>{};
  final allowed = {'W', 'U', 'B', 'R', 'G', 'C'};

  for (final raw in identity) {
    final value = raw.toUpperCase().trim();
    if (value.isEmpty) continue;

    final matches = RegExp(r'[WUBRGC]').allMatches(value);
    for (final match in matches) {
      final symbol = match.group(0);
      if (symbol != null && allowed.contains(symbol)) {
        normalized.add(symbol);
      }
    }
  }

  return normalized;
}

/// Retorna `true` quando a identidade de cor da carta é um subconjunto da
/// identidade do comandante. Cartas incolores (identidade vazia) sempre passam.
bool isWithinCommanderIdentity({
  required Iterable<String> cardIdentity,
  required Set<String> commanderIdentity,
}) {
  final normalizedCard = normalizeColorIdentity(cardIdentity);
  if (normalizedCard.isEmpty) return true;
  return normalizedCard.every(commanderIdentity.contains);
}

