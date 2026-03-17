class CardResolutionDecision {
  const CardResolutionDecision._({
    required this.inputName,
    required this.candidateNames,
    this.matchedName,
    this.strategy,
  });

  factory CardResolutionDecision.resolved({
    required String inputName,
    required List<String> candidateNames,
    required String matchedName,
    required String strategy,
  }) {
    return CardResolutionDecision._(
      inputName: inputName,
      candidateNames: candidateNames,
      matchedName: matchedName,
      strategy: strategy,
    );
  }

  factory CardResolutionDecision.ambiguous({
    required String inputName,
    required List<String> candidateNames,
  }) {
    return CardResolutionDecision._(
      inputName: inputName,
      candidateNames: candidateNames,
    );
  }

  factory CardResolutionDecision.unresolved(String inputName) {
    return CardResolutionDecision._(
      inputName: inputName,
      candidateNames: const [],
    );
  }

  final String inputName;
  final List<String> candidateNames;
  final String? matchedName;
  final String? strategy;

  bool get isResolved => matchedName != null;
  bool get isAmbiguous => !isResolved && candidateNames.isNotEmpty;
}

CardResolutionDecision resolveCardCandidateNames(
  String inputName,
  Iterable<String> candidateNames,
) {
  final normalizedInput = inputName.trim().toLowerCase();
  if (normalizedInput.isEmpty) {
    return CardResolutionDecision.unresolved(inputName);
  }

  final uniqueNames = <String>[];
  final seenNames = <String>{};
  for (final rawName in candidateNames) {
    final name = rawName.trim();
    if (name.isEmpty) continue;
    final lowered = name.toLowerCase();
    if (seenNames.add(lowered)) {
      uniqueNames.add(name);
    }
  }

  if (uniqueNames.isEmpty) {
    return CardResolutionDecision.unresolved(inputName);
  }

  final exactMatches = uniqueNames
      .where((name) => name.toLowerCase() == normalizedInput)
      .toList();
  if (exactMatches.length == 1) {
    return CardResolutionDecision.resolved(
      inputName: inputName,
      candidateNames: uniqueNames,
      matchedName: exactMatches.first,
      strategy: 'exact',
    );
  }

  final prefixMatches = uniqueNames
      .where((name) => name.toLowerCase().startsWith(normalizedInput))
      .toList();
  if (prefixMatches.length == 1) {
    return CardResolutionDecision.resolved(
      inputName: inputName,
      candidateNames: uniqueNames,
      matchedName: prefixMatches.first,
      strategy: 'prefix',
    );
  }
  if (prefixMatches.length > 1) {
    return CardResolutionDecision.ambiguous(
      inputName: inputName,
      candidateNames: prefixMatches.take(5).toList(),
    );
  }

  final containsMatches = uniqueNames
      .where((name) => name.toLowerCase().contains(normalizedInput))
      .toList();
  if (containsMatches.length == 1) {
    return CardResolutionDecision.resolved(
      inputName: inputName,
      candidateNames: uniqueNames,
      matchedName: containsMatches.first,
      strategy: 'contains',
    );
  }
  if (containsMatches.length > 1) {
    return CardResolutionDecision.ambiguous(
      inputName: inputName,
      candidateNames: containsMatches.take(5).toList(),
    );
  }

  return CardResolutionDecision.unresolved(inputName);
}
