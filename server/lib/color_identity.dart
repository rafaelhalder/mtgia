Set<String> normalizeColorIdentity(Iterable<String> identity) =>
    identity.map((e) => e.toUpperCase().trim()).where((e) => e.isNotEmpty).toSet();

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

