import 'package:postgres/postgres.dart';

import 'card_validation_service.dart';
import 'deck_rules_service.dart';
import 'import_card_lookup_service.dart';

abstract class GeneratedDeckRepository {
  Future<Map<String, Map<String, dynamic>>> resolveCardNames(
    List<Map<String, dynamic>> parsedItems,
  );

  Future<Map<String, List<String>>> findSuggestions(List<String> names);

  Future<void> validateDeck({
    required String format,
    required List<Map<String, dynamic>> cards,
  });
}

class PostgresGeneratedDeckRepository implements GeneratedDeckRepository {
  PostgresGeneratedDeckRepository(this._pool)
      : _cardValidationService = CardValidationService(_pool);

  final Pool _pool;
  final CardValidationService _cardValidationService;

  @override
  Future<Map<String, List<String>>> findSuggestions(List<String> names) async {
    if (names.isEmpty) return const {};
    return _cardValidationService.findSuggestions(names);
  }

  @override
  Future<Map<String, Map<String, dynamic>>> resolveCardNames(
    List<Map<String, dynamic>> parsedItems,
  ) {
    return resolveImportCardNames(_pool, parsedItems);
  }

  @override
  Future<void> validateDeck({
    required String format,
    required List<Map<String, dynamic>> cards,
  }) async {
    await _pool.runTx(
      (session) => DeckRulesService(session).validateAndThrow(
        format: format,
        cards: cards,
        strict: true,
      ),
    );
  }
}

class GeneratedDeckValidationResult {
  const GeneratedDeckValidationResult({
    required this.generatedDeck,
    required this.errors,
    required this.invalidCards,
    required this.suggestions,
    required this.warnings,
    required this.totalSuggestedEntries,
    required this.totalSuggestedCards,
    required this.totalResolvedEntries,
    required this.totalResolvedCards,
  });

  final Map<String, dynamic> generatedDeck;
  final List<String> errors;
  final List<String> invalidCards;
  final Map<String, List<String>> suggestions;
  final List<String> warnings;
  final int totalSuggestedEntries;
  final int totalSuggestedCards;
  final int totalResolvedEntries;
  final int totalResolvedCards;

  bool get isValid => errors.isEmpty;

  Map<String, dynamic> validationSummary() {
    return {
      'is_valid': isValid,
      'errors': errors,
      'invalid_cards': invalidCards,
      'suggestions': suggestions,
      'warnings': warnings,
    };
  }
}

class GeneratedDeckValidationService {
  GeneratedDeckValidationService(this._repository);

  final GeneratedDeckRepository _repository;

  Future<GeneratedDeckValidationResult> validate({
    required String format,
    required List<Map<String, dynamic>> cards,
    String? commanderName,
  }) async {
    final normalizedFormat = _normalizeFormat(format);
    final requiresCommander =
        normalizedFormat == 'commander' || normalizedFormat == 'brawl';

    final sanitizedCards = <Map<String, dynamic>>[];
    final warnings = <String>[];

    for (final rawCard in cards) {
      final rawName = rawCard['name']?.toString() ?? '';
      final name = CardValidationService.sanitizeCardName(rawName);
      if (name.isEmpty) {
        warnings.add('Uma entrada sem nome foi descartada.');
        continue;
      }

      final rawQuantity = rawCard['quantity'];
      final quantity = rawQuantity is int
          ? rawQuantity
          : int.tryParse(rawQuantity?.toString() ?? '') ?? 1;

      if (quantity <= 0) {
        warnings.add('A carta "$name" foi descartada por quantidade invalida.');
        continue;
      }

      sanitizedCards.add({
        'name': name,
        'quantity': quantity,
      });
    }

    final sanitizedCommander = commanderName == null
        ? null
        : CardValidationService.sanitizeCardName(commanderName);

    final parsedItems = [
      for (final card in sanitizedCards) {'name': card['name']},
      if (sanitizedCommander != null && sanitizedCommander.isNotEmpty)
        {'name': sanitizedCommander},
    ];

    final foundCardsMap = await _repository.resolveCardNames(parsedItems);

    final invalidCards = <String>[];
    final resolvedCards = <Map<String, dynamic>>[];

    for (final card in sanitizedCards) {
      final name = card['name'] as String;
      final lookupKey = _lookupKey(name, foundCardsMap);
      final resolved = foundCardsMap[lookupKey];

      if (resolved == null) {
        invalidCards.add(name);
        continue;
      }

      resolvedCards.add({
        'card_id': resolved['id'],
        'name': resolved['name'],
        'quantity': card['quantity'],
        'is_commander': false,
      });
    }

    Map<String, dynamic>? resolvedCommander;
    if (sanitizedCommander != null && sanitizedCommander.isNotEmpty) {
      final commanderKey = _lookupKey(sanitizedCommander, foundCardsMap);
      final commanderCard = foundCardsMap[commanderKey];
      if (commanderCard == null) {
        invalidCards.add(sanitizedCommander);
      } else {
        resolvedCommander = {
          'card_id': commanderCard['id'],
          'name': commanderCard['name'],
          'quantity': 1,
          'is_commander': true,
        };
      }
    }

    final consolidatedCards = _consolidateResolvedCards([
      ...resolvedCards,
      if (resolvedCommander != null) resolvedCommander,
    ]);

    final errors = <String>[];
    if (requiresCommander && resolvedCommander == null) {
      errors.add(
        'Deck $normalizedFormat precisa de um comandante valido no campo "commander".',
      );
    }

    if (invalidCards.isNotEmpty) {
      warnings.add(
        '${invalidCards.length} carta(s) sugerida(s) nao foram encontradas e foram removidas.',
      );
    }

    if (consolidatedCards.isEmpty) {
      errors.add('Nenhuma carta valida restou apos a resolucao dos nomes.');
    } else {
      try {
        await _repository.validateDeck(
          format: normalizedFormat,
          cards: consolidatedCards,
        );
      } on DeckRulesException catch (e) {
        errors.add(e.message);
      } catch (e) {
        errors.add(e.toString());
      }
    }

    final suggestions = invalidCards.isEmpty
        ? const <String, List<String>>{}
        : await _repository.findSuggestions(invalidCards.toSet().toList());

    final generatedDeck = <String, dynamic>{
      if (resolvedCommander != null)
        'commander': {'name': resolvedCommander['name']},
      'cards': [
        for (final card in consolidatedCards)
          if (card['is_commander'] != true)
            {
              'name': card['name'],
              'quantity': card['quantity'],
            },
      ],
    };

    return GeneratedDeckValidationResult(
      generatedDeck: generatedDeck,
      errors: errors,
      invalidCards: invalidCards,
      suggestions: suggestions,
      warnings: warnings,
      totalSuggestedEntries: sanitizedCards.length,
      totalSuggestedCards: sanitizedCards.fold<int>(
        0,
        (sum, card) => sum + (card['quantity'] as int),
      ),
      totalResolvedEntries: resolvedCards.length,
      totalResolvedCards: resolvedCards.fold<int>(
        0,
        (sum, card) => sum + (card['quantity'] as int),
      ),
    );
  }

  static List<Map<String, dynamic>> _consolidateResolvedCards(
    List<Map<String, dynamic>> cards,
  ) {
    final byId = <String, Map<String, dynamic>>{};

    for (final card in cards) {
      final cardId = card['card_id'] as String;
      final existing = byId[cardId];
      if (existing == null) {
        byId[cardId] = Map<String, dynamic>.from(card);
        continue;
      }

      existing['quantity'] =
          (existing['quantity'] as int) + (card['quantity'] as int);
      if (card['is_commander'] == true) {
        existing['is_commander'] = true;
      }
    }

    return byId.values.toList();
  }

  static String _lookupKey(
    String name,
    Map<String, Map<String, dynamic>> foundCardsMap,
  ) {
    final originalKey = name.toLowerCase();
    final cleanedKey = cleanImportLookupKey(originalKey);
    return foundCardsMap.containsKey(originalKey) ? originalKey : cleanedKey;
  }

  static String _normalizeFormat(String format) {
    final normalized = format.trim().toLowerCase();
    if (normalized == 'edh') return 'commander';
    return normalized;
  }
}
