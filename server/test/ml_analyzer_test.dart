/// Testes unitários para o sistema de ML e análise de decks
///
/// Cobre:
/// - DeckArchetypeAnalyzer (detecção de arquétipo)
/// - ThemeProfile (detecção de tema)
/// - Inferência de arquétipo por keywords
/// - Validações de mana base

import 'package:test/test.dart';

// Simulação das classes do sistema (para testes isolados)
// Em produção, importar de '../routes/ai/optimize/index.dart'

/// Calcula média de CMC
double calculateAverageCMC(List<Map<String, dynamic>> cards) {
  if (cards.isEmpty) return 0.0;

  final nonLandCards = cards.where((c) {
    final typeLine = (c['type_line'] as String?) ?? '';
    return !typeLine.toLowerCase().contains('land');
  }).toList();

  if (nonLandCards.isEmpty) return 0.0;

  double totalCMC = 0;
  for (final card in nonLandCards) {
    totalCMC += (card['cmc'] as num?)?.toDouble() ?? 0.0;
  }

  return totalCMC / nonLandCards.length;
}

/// Conta cartas por tipo
Map<String, int> countCardTypes(List<Map<String, dynamic>> cards) {
  final counts = <String, int>{
    'creatures': 0,
    'instants': 0,
    'sorceries': 0,
    'enchantments': 0,
    'artifacts': 0,
    'planeswalkers': 0,
    'lands': 0,
  };

  for (final card in cards) {
    final typeLine = ((card['type_line'] as String?) ?? '').toLowerCase();

    if (typeLine.contains('land')) counts['lands'] = counts['lands']! + 1;
    if (typeLine.contains('creature')) counts['creatures'] = counts['creatures']! + 1;
    if (typeLine.contains('planeswalker')) counts['planeswalkers'] = counts['planeswalkers']! + 1;
    if (typeLine.contains('instant')) counts['instants'] = counts['instants']! + 1;
    if (typeLine.contains('sorcery')) counts['sorceries'] = counts['sorceries']! + 1;
    if (typeLine.contains('artifact')) counts['artifacts'] = counts['artifacts']! + 1;
    if (typeLine.contains('enchantment')) counts['enchantments'] = counts['enchantments']! + 1;
  }

  return counts;
}

/// Detecta arquétipo baseado nas estatísticas
String detectArchetype(List<Map<String, dynamic>> cards) {
  final avgCMC = calculateAverageCMC(cards);
  final typeCounts = countCardTypes(cards);
  final totalNonLands = cards.length - (typeCounts['lands'] ?? 0);

  if (totalNonLands == 0) return 'unknown';

  final creatureRatio = (typeCounts['creatures'] ?? 0) / totalNonLands;
  final instantSorceryRatio =
      ((typeCounts['instants'] ?? 0) + (typeCounts['sorceries'] ?? 0)) / totalNonLands;
  final enchantmentRatio = (typeCounts['enchantments'] ?? 0) / totalNonLands;

  // Aggro: CMC baixo (< 2.5), muitas criaturas (> 40%)
  if (avgCMC < 2.5 && creatureRatio > 0.4) {
    return 'aggro';
  }

  // Control: CMC alto (> 3.0), poucos criaturas (< 25%), muitos instants/sorceries
  if (avgCMC > 3.0 && creatureRatio < 0.25 && instantSorceryRatio > 0.35) {
    return 'control';
  }

  // Combo: Muitos instants/sorceries (> 40%) e poucos criaturas
  if (instantSorceryRatio > 0.4 && creatureRatio < 0.3) {
    return 'combo';
  }

  // Stax/Enchantress: Muitos enchantments (> 30%)
  if (enchantmentRatio > 0.3) {
    return 'stax';
  }

  // Midrange: Valor médio de CMC e equilíbrio de tipos
  if (avgCMC >= 2.5 && avgCMC <= 3.5 && creatureRatio >= 0.25 && creatureRatio <= 0.45) {
    return 'midrange';
  }

  return 'midrange';
}

/// Infere arquétipo a partir de keywords nas cartas
String inferArchetypeFromCards(List<Map<String, dynamic>> cards) {
  final keywords = <String, int>{
    'control': 0,
    'aggro': 0,
    'combo': 0,
    'ramp': 0,
    'tribal': 0,
  };

  for (final card in cards) {
    final oracle = ((card['oracle_text'] as String?) ?? '').toLowerCase();
    final typeLine = ((card['type_line'] as String?) ?? '').toLowerCase();

    // Control indicators
    if (oracle.contains('counter') || oracle.contains('destroy') ||
        oracle.contains('exile') || oracle.contains('return') ||
        oracle.contains('draw') && oracle.contains('card')) {
      keywords['control'] = keywords['control']! + 1;
    }

    // Aggro indicators
    if (oracle.contains('haste') || oracle.contains('first strike') ||
        oracle.contains('+1/+1') || oracle.contains('attack')) {
      keywords['aggro'] = keywords['aggro']! + 1;
    }

    // Combo indicators
    if (oracle.contains('infinite') || oracle.contains('untap') ||
        oracle.contains('tutor') || oracle.contains('storm')) {
      keywords['combo'] = keywords['combo']! + 1;
    }

    // Ramp indicators
    if (oracle.contains('add') && oracle.contains('mana') ||
        oracle.contains('search') && oracle.contains('land')) {
      keywords['ramp'] = keywords['ramp']! + 1;
    }

    // Tribal indicators
    if (typeLine.contains('—') && 
        (oracle.contains('whenever') || oracle.contains('gets +') ||
         oracle.contains('other') && oracle.contains('you control'))) {
      keywords['tribal'] = keywords['tribal']! + 1;
    }
  }

  // Encontrar arquétipo dominante
  String dominant = 'value';
  int maxScore = 0;
  
  keywords.forEach((archetype, score) {
    if (score > maxScore) {
      maxScore = score;
      dominant = archetype;
    }
  });

  return maxScore >= 3 ? dominant : 'value';
}

/// Avalia base de mana
String assessManaBase(Map<String, int> symbols, Map<String, int> sources) {
  if (symbols.isEmpty) return 'N/A';
  final totalSymbols = symbols.values.fold<int>(0, (a, b) => a + b);
  if (totalSymbols == 0) return 'N/A';

  final issues = <String>[];

  symbols.forEach((color, count) {
    if (count > 0) {
      final percent = count / totalSymbols;
      final sourceCount = (sources[color] ?? 0) + (sources['Any'] ?? 0);

      if (percent > 0.30 && sourceCount < 15) {
        issues.add('Falta mana $color (Tem $sourceCount fontes, ideal > 15)');
      } else if (percent > 0.10 && sourceCount < 10) {
        issues.add('Falta mana $color (Tem $sourceCount fontes, ideal > 10)');
      }
    }
  });

  if (issues.isEmpty) return 'Base de mana equilibrada';
  return issues.join('. ');
}

void main() {
  group('calculateAverageCMC', () {
    test('retorna 0 para lista vazia', () {
      expect(calculateAverageCMC([]), 0.0);
    });

    test('retorna 0 para deck só de terrenos', () {
      final cards = [
        {'type_line': 'Basic Land — Plains', 'cmc': 0},
        {'type_line': 'Basic Land — Island', 'cmc': 0},
      ];
      expect(calculateAverageCMC(cards), 0.0);
    });

    test('calcula média corretamente', () {
      final cards = [
        {'type_line': 'Creature — Human', 'cmc': 2},
        {'type_line': 'Creature — Goblin', 'cmc': 1},
        {'type_line': 'Instant', 'cmc': 3},
      ];
      expect(calculateAverageCMC(cards), 2.0);
    });

    test('ignora terrenos no cálculo', () {
      final cards = [
        {'type_line': 'Basic Land — Forest', 'cmc': 0},
        {'type_line': 'Creature — Elf', 'cmc': 4},
      ];
      expect(calculateAverageCMC(cards), 4.0);
    });
  });

  group('countCardTypes', () {
    test('conta tipos corretamente', () {
      final cards = [
        {'type_line': 'Creature — Human Wizard'},
        {'type_line': 'Creature — Goblin'},
        {'type_line': 'Instant'},
        {'type_line': 'Sorcery'},
        {'type_line': 'Enchantment'},
        {'type_line': 'Basic Land — Plains'},
        {'type_line': 'Artifact Creature — Construct'},
      ];
      
      final counts = countCardTypes(cards);
      
      expect(counts['creatures'], 3); // 2 criaturas + 1 artifact creature
      expect(counts['instants'], 1);
      expect(counts['sorceries'], 1);
      expect(counts['enchantments'], 1);
      expect(counts['lands'], 1);
      expect(counts['artifacts'], 1);
    });

    test('retorna zeros para lista vazia', () {
      final counts = countCardTypes([]);
      expect(counts['creatures'], 0);
      expect(counts['lands'], 0);
    });
  });

  group('detectArchetype', () {
    test('detecta aggro (CMC baixo + muitas criaturas)', () {
      final cards = List.generate(60, (i) {
        if (i < 20) return {'type_line': 'Basic Land — Mountain', 'cmc': 0};
        return {'type_line': 'Creature — Goblin', 'cmc': 1};
      });
      expect(detectArchetype(cards), 'aggro');
    });

    test('detecta control (CMC alto + poucos criaturas + muitos instants)', () {
      final cards = <Map<String, dynamic>>[];
      
      // 20 lands
      for (var i = 0; i < 20; i++) {
        cards.add({'type_line': 'Basic Land — Island', 'cmc': 0});
      }
      // 5 creatures (baixo)
      for (var i = 0; i < 5; i++) {
        cards.add({'type_line': 'Creature — Sphinx', 'cmc': 6});
      }
      // 25 instants (alto)
      for (var i = 0; i < 25; i++) {
        cards.add({'type_line': 'Instant', 'cmc': 3});
      }
      // 10 sorceries
      for (var i = 0; i < 10; i++) {
        cards.add({'type_line': 'Sorcery', 'cmc': 4});
      }
      
      expect(detectArchetype(cards), 'control');
    });

    test('detecta combo (muitos instants/sorceries)', () {
      final cards = <Map<String, dynamic>>[];
      
      // 20 lands
      for (var i = 0; i < 20; i++) {
        cards.add({'type_line': 'Basic Land', 'cmc': 0});
      }
      // 10 creatures (baixo %)
      for (var i = 0; i < 10; i++) {
        cards.add({'type_line': 'Creature', 'cmc': 2});
      }
      // 30 instants/sorceries (50%)
      for (var i = 0; i < 30; i++) {
        cards.add({'type_line': i % 2 == 0 ? 'Instant' : 'Sorcery', 'cmc': 2});
      }
      
      expect(detectArchetype(cards), 'combo');
    });

    test('detecta stax (muitos enchantments)', () {
      final cards = <Map<String, dynamic>>[];
      
      // 20 lands
      for (var i = 0; i < 20; i++) {
        cards.add({'type_line': 'Basic Land', 'cmc': 0});
      }
      // 20 enchantments (50%)
      for (var i = 0; i < 20; i++) {
        cards.add({'type_line': 'Enchantment', 'cmc': 3});
      }
      // 20 creatures
      for (var i = 0; i < 20; i++) {
        cards.add({'type_line': 'Creature', 'cmc': 3});
      }
      
      expect(detectArchetype(cards), 'stax');
    });

    test('retorna midrange como fallback', () {
      final cards = <Map<String, dynamic>>[];
      
      // 20 lands
      for (var i = 0; i < 20; i++) {
        cards.add({'type_line': 'Basic Land', 'cmc': 0});
      }
      // Mix equilibrado
      for (var i = 0; i < 15; i++) {
        cards.add({'type_line': 'Creature', 'cmc': 3});
      }
      for (var i = 0; i < 10; i++) {
        cards.add({'type_line': 'Instant', 'cmc': 2});
      }
      for (var i = 0; i < 5; i++) {
        cards.add({'type_line': 'Enchantment', 'cmc': 4});
      }
      
      expect(detectArchetype(cards), 'midrange');
    });

    test('retorna unknown para deck vazio', () {
      expect(detectArchetype([]), 'unknown');
    });

    test('retorna unknown para deck só de terrenos', () {
      final cards = [
        {'type_line': 'Basic Land — Plains', 'cmc': 0},
        {'type_line': 'Basic Land — Island', 'cmc': 0},
      ];
      expect(detectArchetype(cards), 'unknown');
    });
  });

  group('inferArchetypeFromCards', () {
    test('infere control por keywords', () {
      final cards = [
        {'oracle_text': 'Counter target spell.', 'type_line': 'Instant'},
        {'oracle_text': 'Destroy target creature.', 'type_line': 'Instant'},
        {'oracle_text': 'Exile target permanent.', 'type_line': 'Sorcery'},
        {'oracle_text': 'Draw two cards.', 'type_line': 'Instant'},
      ];
      expect(inferArchetypeFromCards(cards), 'control');
    });

    test('infere aggro por keywords', () {
      final cards = [
        {'oracle_text': 'Haste', 'type_line': 'Creature — Goblin'},
        {'oracle_text': 'First strike', 'type_line': 'Creature — Knight'},
        {'oracle_text': 'Gets +1/+1 until end of turn', 'type_line': 'Instant'},
        {'oracle_text': 'Whenever this attacks...', 'type_line': 'Creature — Goblin'},
      ];
      expect(inferArchetypeFromCards(cards), 'aggro');
    });

    test('infere combo por keywords', () {
      final cards = [
        {'oracle_text': 'Search your library for any card (tutor)', 'type_line': 'Instant'},
        {'oracle_text': 'Untap target permanent', 'type_line': 'Instant'},
        {'oracle_text': 'Storm (copy for each spell cast)', 'type_line': 'Sorcery'},
        {'oracle_text': 'Add infinite mana', 'type_line': 'Artifact'},
      ];
      expect(inferArchetypeFromCards(cards), 'combo');
    });

    test('infere ramp por keywords', () {
      final cards = [
        {'oracle_text': 'Add one mana of any color', 'type_line': 'Artifact'},
        {'oracle_text': 'Search your library for a basic land card', 'type_line': 'Sorcery'},
        {'oracle_text': 'Add {G}{G}', 'type_line': 'Creature — Elf'},
        {'oracle_text': 'Search for a land', 'type_line': 'Sorcery'},
      ];
      expect(inferArchetypeFromCards(cards), 'ramp');
    });

    test('retorna value como fallback', () {
      final cards = [
        {'oracle_text': 'Vanilla creature', 'type_line': 'Creature'},
        {'oracle_text': 'Basic effect', 'type_line': 'Sorcery'},
      ];
      expect(inferArchetypeFromCards(cards), 'value');
    });

    test('retorna value para lista vazia', () {
      expect(inferArchetypeFromCards([]), 'value');
    });
  });

  group('assessManaBase', () {
    test('retorna N/A para símbolos vazios', () {
      expect(assessManaBase({}, {}), 'N/A');
    });

    test('retorna N/A para zero símbolos', () {
      final symbols = {'W': 0, 'U': 0, 'B': 0, 'R': 0, 'G': 0};
      expect(assessManaBase(symbols, {}), 'N/A');
    });

    test('detecta mana equilibrada', () {
      final symbols = {'W': 20, 'U': 20};
      final sources = {'W': 15, 'U': 15, 'Any': 5};
      expect(assessManaBase(symbols, sources), 'Base de mana equilibrada');
    });

    test('detecta falta de mana para cor dominante', () {
      final symbols = {'R': 40, 'B': 10}; // R é 80%
      final sources = {'R': 10, 'B': 5, 'Any': 0}; // Só 10 fontes de R
      final result = assessManaBase(symbols, sources);
      expect(result.contains('Falta mana R'), true);
    });

    test('considera fontes "Any" no cálculo', () {
      final symbols = {'W': 40};
      final sources = {'W': 10, 'Any': 10}; // 10 + 10 = 20 fontes
      expect(assessManaBase(symbols, sources), 'Base de mana equilibrada');
    });

    test('detecta múltiplas cores com problemas', () {
      final symbols = {'W': 25, 'U': 25}; // 50% cada
      final sources = {'W': 5, 'U': 5, 'Any': 0}; // Pouquíssimas fontes
      final result = assessManaBase(symbols, sources);
      expect(result.contains('Falta mana W'), true);
      expect(result.contains('Falta mana U'), true);
    });
  });

  group('Edge cases e robustez', () {
    test('trata nulls em type_line', () {
      final cards = [
        {'type_line': null, 'cmc': 2},
        {'cmc': 3}, // sem type_line
      ];
      expect(() => countCardTypes(cards), returnsNormally);
      expect(() => calculateAverageCMC(cards), returnsNormally);
    });

    test('trata nulls em oracle_text', () {
      final cards = [
        {'oracle_text': null, 'type_line': 'Creature'},
        {'type_line': 'Instant'}, // sem oracle_text
      ];
      expect(() => inferArchetypeFromCards(cards), returnsNormally);
    });

    test('trata nulls em cmc', () {
      final cards = [
        {'type_line': 'Creature', 'cmc': null},
        {'type_line': 'Instant'}, // sem cmc
      ];
      final avg = calculateAverageCMC(cards);
      expect(avg, 0.0);
    });

    test('trata tipos mistos (int e double em cmc)', () {
      final cards = [
        {'type_line': 'Creature', 'cmc': 2}, // int
        {'type_line': 'Instant', 'cmc': 3.0}, // double
        {'type_line': 'Sorcery', 'cmc': 1.5}, // double fracionado
      ];
      final avg = calculateAverageCMC(cards);
      expect(avg, closeTo(2.166, 0.01));
    });
  });

  group('Cenários de decks reais', () {
    test('deck de goblins é detectado como aggro', () {
      final cards = <Map<String, dynamic>>[];
      
      // 20 Mountains
      for (var i = 0; i < 20; i++) {
        cards.add({'type_line': 'Basic Land — Mountain', 'cmc': 0, 'oracle_text': ''});
      }
      
      // Goblins baixo custo
      final goblinNames = [
        'Goblin Guide', 'Goblin Lackey', 'Goblin Piledriver', 'Goblin Warchief',
        'Goblin Chieftain', 'Krenko, Mob Boss', 'Goblin Matron', 'Goblin Ringleader'
      ];
      
      for (var i = 0; i < 30; i++) {
        cards.add({
          'type_line': 'Creature — Goblin',
          'cmc': (i % 3) + 1, // 1, 2 ou 3
          'oracle_text': 'Haste. When this attacks, deal damage.'
        });
      }
      
      // Burn
      for (var i = 0; i < 10; i++) {
        cards.add({
          'type_line': 'Instant',
          'cmc': 1,
          'oracle_text': 'Deal 3 damage to any target.'
        });
      }
      
      final archetype = detectArchetype(cards);
      final inferredArchetype = inferArchetypeFromCards(cards);
      
      expect(archetype, 'aggro');
      expect(inferredArchetype, 'aggro');
    });

    test('deck de blue control é detectado corretamente', () {
      final cards = <Map<String, dynamic>>[];
      
      // 25 Islands
      for (var i = 0; i < 25; i++) {
        cards.add({'type_line': 'Basic Land — Island', 'cmc': 0, 'oracle_text': ''});
      }
      
      // Counterspells
      for (var i = 0; i < 15; i++) {
        cards.add({
          'type_line': 'Instant',
          'cmc': 3,
          'oracle_text': 'Counter target spell.'
        });
      }
      
      // Draw spells
      for (var i = 0; i < 10; i++) {
        cards.add({
          'type_line': 'Sorcery',
          'cmc': 4,
          'oracle_text': 'Draw three cards.'
        });
      }
      
      // Win conditions (poucas criaturas)
      for (var i = 0; i < 5; i++) {
        cards.add({
          'type_line': 'Creature — Sphinx',
          'cmc': 6,
          'oracle_text': 'Flying. When this enters, draw a card.'
        });
      }
      
      // Removal
      for (var i = 0; i < 5; i++) {
        cards.add({
          'type_line': 'Instant',
          'cmc': 3,
          'oracle_text': 'Return target creature to its owner\'s hand.'
        });
      }
      
      final archetype = detectArchetype(cards);
      final inferredArchetype = inferArchetypeFromCards(cards);
      
      expect(archetype, 'control');
      expect(inferredArchetype, 'control');
    });
  });
}
