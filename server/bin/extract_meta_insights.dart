import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:postgres/postgres.dart';
import '../lib/database.dart';

/// Script de Extração de Insights dos Meta Decks
/// 
/// Este script implementa "Imitation Learning":
/// 1. Lê todos os decks competitivos da tabela meta_decks
/// 2. Analisa padrões de construção
/// 3. Detecta sinergias frequentes (co-ocorrências)
/// 4. Extrai padrões por arquétipo
/// 5. Popula as tabelas de conhecimento ML
/// 
/// Uso: dart run bin/extract_meta_insights.dart [--full | --incremental]

void main(List<String> args) async {
  final isFullRebuild = args.contains('--full');
  final startTime = DateTime.now();
  
  print('═══════════════════════════════════════════════════════════════');
  print('  META INSIGHTS EXTRACTOR - Imitation Learning Pipeline');
  print('  Modo: ${isFullRebuild ? "FULL REBUILD" : "INCREMENTAL"}');
  print('  Data: ${startTime.toIso8601String()}');
  print('═══════════════════════════════════════════════════════════════\n');

  final db = Database();
  await db.connect();
  final conn = db.connection;

  try {
    // 1. Carregar meta decks
    print('📥 Carregando meta decks do banco...');
    final metaDecks = await _loadMetaDecks(conn);
    print('   Encontrados ${metaDecks.length} decks\n');

    if (metaDecks.isEmpty) {
      print('⚠️ Nenhum meta deck encontrado. Execute fetch_meta.dart primeiro.');
      return;
    }

    // 2. Parsear e processar decks
    print('🔄 Processando deck lists...');
    final parsedDecks = metaDecks.map(_parseDeckList).toList();
    print('   ${parsedDecks.length} decks parseados\n');

    // 3. Extrair insights de cartas individuais
    print('📊 Extraindo insights de cartas...');
    final cardInsights = _extractCardInsights(parsedDecks, metaDecks);
    print('   ${cardInsights.length} cartas analisadas\n');

    // 4. Detectar sinergias (co-ocorrências frequentes)
    print('🔗 Detectando sinergias...');
    final synergies = _detectSynergies(parsedDecks, metaDecks);
    print('   ${synergies.length} pacotes de sinergia encontrados\n');

    // 5. Extrair padrões de arquétipo
    print('🎯 Extraindo padrões de arquétipo...');
    final archetypePatterns = _extractArchetypePatterns(parsedDecks, metaDecks);
    print('   ${archetypePatterns.length} arquétipos analisados\n');

    // 6. Salvar no banco
    print('💾 Salvando insights no banco...');
    stdout.flush();
    
    if (isFullRebuild) {
      print('   Limpando dados antigos (--full)...');
      stdout.flush();
      await conn.execute('TRUNCATE card_meta_insights CASCADE');
      await conn.execute('TRUNCATE synergy_packages CASCADE');
      await conn.execute('TRUNCATE archetype_patterns CASCADE');
    }

    print('   Salvando ${cardInsights.length} insights de cartas...');
    stdout.flush();
    await _saveCardInsights(conn, cardInsights);
    
    print('   Salvando ${synergies.length} sinergias...');
    stdout.flush();
    await _saveSynergies(conn, synergies);
    
    print('   Salvando ${archetypePatterns.length} padrões...');
    stdout.flush();
    await _saveArchetypePatterns(conn, archetypePatterns);

    // 7. Atualizar estado do modelo
    await _updateLearningState(conn, cardInsights.length, synergies.length, archetypePatterns.length);

    final duration = DateTime.now().difference(startTime);
    
    print('\n═══════════════════════════════════════════════════════════════');
    print('  ✅ EXTRAÇÃO CONCLUÍDA COM SUCESSO!');
    print('  ⏱️ Duração: ${duration.inSeconds}s');
    print('═══════════════════════════════════════════════════════════════');
    print('\n📋 Resumo:');
    print('   • ${cardInsights.length} insights de cartas');
    print('   • ${synergies.length} pacotes de sinergia');
    print('   • ${archetypePatterns.length} padrões de arquétipo');
    print('\n🚀 O sistema de otimização agora pode usar esses dados!');

  } catch (e, st) {
    print('❌ Erro na extração: $e');
    print(st);
    exit(1);
  } finally {
    await conn.close();
  }
}

/// Carrega meta decks do banco
Future<List<Map<String, dynamic>>> _loadMetaDecks(dynamic conn) async {
  final result = await conn.execute(
    'SELECT id, format, archetype, card_list, placement FROM meta_decks ORDER BY created_at DESC'
  );
  
  return result.map<Map<String, dynamic>>((row) {
    final map = row.toColumnMap();
    return {
      'id': map['id']?.toString(),
      'format': map['format']?.toString() ?? 'unknown',
      'archetype': map['archetype']?.toString() ?? 'unknown',
      'card_list': map['card_list']?.toString() ?? '',
      'placement': map['placement']?.toString() ?? '',
    };
  }).toList();
}

/// Parseia uma deck list em texto para lista de cartas
Map<String, dynamic> _parseDeckList(Map<String, dynamic> deck) {
  final cardList = deck['card_list'] as String;
  final cards = <String, int>{};
  final sideboardCards = <String, int>{};
  var inSideboard = false;
  
  for (var line in cardList.split('\n')) {
    line = line.trim();
    if (line.isEmpty) continue;
    
    // Detecta sideboard
    if (line.toLowerCase().contains('sideboard')) {
      inSideboard = true;
      continue;
    }
    
    // Formato: "4 Lightning Bolt" ou "1x Sol Ring"
    final match = RegExp(r'^(\d+)x?\s+(.+)$').firstMatch(line);
    if (match != null) {
      final quantity = int.tryParse(match.group(1)!) ?? 1;
      var cardName = match.group(2)!.trim();
      
      // Remove set code se presente: "Sol Ring (CMR)"
      cardName = cardName.replaceAll(RegExp(r'\s*\([^)]+\)\s*$'), '');
      
      if (inSideboard) {
        sideboardCards[cardName] = (sideboardCards[cardName] ?? 0) + quantity;
      } else {
        cards[cardName] = (cards[cardName] ?? 0) + quantity;
      }
    }
  }
  
  // Inferir arquétipo se ausente ou genérico
  var archetype = deck['archetype'] as String? ?? '';
  if (archetype.isEmpty || archetype == 'unknown') {
    archetype = _inferArchetypeFromCards(cards.keys.toList());
  }
  
  return {
    ...deck,
    'archetype': archetype, // Sobrescreve com inferido
    'parsed_cards': cards,
    'sideboard': sideboardCards,
    'total_cards': cards.values.fold<int>(0, (a, b) => a + b),
  };
}

/// Infere o arquétipo do deck baseado nas cartas
String _inferArchetypeFromCards(List<String> cardNames) {
  final lower = cardNames.map((c) => c.toLowerCase()).toSet();
  
  // Contadores por categoria
  var controlScore = 0;
  var aggroScore = 0;
  var comboScore = 0;
  var midrangeScore = 0;
  var rampartScore = 0; // ramp/value
  var tribalScore = 0;
  var aristocratsScore = 0;
  var tokensScore = 0;
  
  // Keywords de controle
  const controlKeywords = ['counterspell', 'negate', 'mana leak', 'force of will', 
    'force of negation', 'cryptic command', 'supreme verdict', 'wrath of god',
    'damnation', 'cyclonic rift', 'teferi', 'jace', 'narset', 'dovin\'s veto',
    'archmage\'s charm', 'mystic confluence', 'fierce guardianship'];
  
  // Keywords de aggro
  const aggroKeywords = ['lightning bolt', 'goblin guide', 'monastery swiftspear',
    'ragavan', 'eidolon of the great revel', 'lava spike', 'chain lightning',
    'goblin', 'haste', 'sligh', 'burn', 'zurgo', 'najeela', 'winota'];
  
  // Keywords de combo
  const comboKeywords = ['thassa\'s oracle', 'demonic consultation', 'tainted pact',
    'doomsday', 'ad nauseam', 'aetherflux reservoir', 'isochron scepter',
    'dramatic reversal', 'infinite', 'thoracle', 'underworld breach', 'brain freeze',
    'grinding station', 'basalt monolith', 'rings of brighthearth'];
  
  // Keywords de ramp/value
  const rampKeywords = ['sol ring', 'mana crypt', 'arcane signet', 'cultivate',
    'kodama\'s reach', 'rampant growth', 'three visits', 'nature\'s lore',
    'signets', 'talismans', 'dockside extortionist', 'smothering tithe'];
  
  // Keywords de aristocrats
  const aristocratsKeywords = ['blood artist', 'zulaport cutthroat', 'viscera seer',
    'carrion feeder', 'phyrexian altar', 'ashnod\'s altar', 'grave pact',
    'dictate of erebos', 'pitiless plunderer', 'teysa', 'korvold', 'prossh'];
  
  // Keywords de tokens
  const tokensKeywords = ['anointed procession', 'doubling season', 'parallel lives',
    'second harvest', 'populate', 'divine visitation', 'krenko', 'adeline',
    'rabble rousing', 'rhys the redeemed', 'tendershoot dryad', 'avenger of zendikar'];
  
  // Keywords tribais
  const tribalKeywords = ['lord', 'kindred', 'coat of arms', 'metallic mimic',
    'icon of ancestry', 'vanquisher\'s banner', 'herald\'s horn'];
    
  for (final card in lower) {
    // Control
    for (final kw in controlKeywords) {
      if (card.contains(kw)) controlScore += 2;
    }
    if (card.contains('counter') && !card.contains('+1/+1')) controlScore++;
    if (card.contains('wrath') || card.contains('verdict')) controlScore += 2;
    
    // Aggro
    for (final kw in aggroKeywords) {
      if (card.contains(kw)) aggroScore += 2;
    }
    if (card.contains('bolt') || card.contains('burn')) aggroScore++;
    
    // Combo
    for (final kw in comboKeywords) {
      if (card.contains(kw)) comboScore += 3; // Combo pieces são muito indicativos
    }
    
    // Ramp
    for (final kw in rampKeywords) {
      if (card.contains(kw)) rampartScore++;
    }
    if (card.contains('signet') || card.contains('talisman')) rampartScore++;
    
    // Aristocrats
    for (final kw in aristocratsKeywords) {
      if (card.contains(kw)) aristocratsScore += 2;
    }
    if (card.contains('sacrifice') || card.contains('dies')) aristocratsScore++;
    
    // Tokens
    for (final kw in tokensKeywords) {
      if (card.contains(kw)) tokensScore += 2;
    }
    if (card.contains('token') || card.contains('create')) tokensScore++;
    
    // Tribal
    for (final kw in tribalKeywords) {
      if (card.contains(kw)) tribalScore += 2;
    }
    // Detectar tribos específicas
    if (card.contains('goblin') || card.contains('elf') || card.contains('merfolk') ||
        card.contains('zombie') || card.contains('vampire') || card.contains('dragon') ||
        card.contains('angel') || card.contains('wizard') || card.contains('sliver')) {
      tribalScore++;
    }
  }
  
  // Midrange é o "fallback" quando tem ramp mas sem combo forte
  midrangeScore = rampartScore ~/ 2;
  
  // Encontrar o maior score
  final scores = {
    'control': controlScore,
    'aggro': aggroScore,
    'combo': comboScore,
    'midrange': midrangeScore,
    'ramp': rampartScore,
    'aristocrats': aristocratsScore,
    'tokens': tokensScore,
    'tribal': tribalScore,
  };
  
  final sorted = scores.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  
  // Se o maior score é muito baixo, retornar 'value' como genérico
  if (sorted.first.value < 3) {
    return 'value';
  }
  
  // Se combo + control são altos, é control-combo
  if (comboScore >= 6 && controlScore >= 4) {
    return 'combo-control';
  }
  
  return sorted.first.key;
}

/// Extrai insights de cartas individuais
Map<String, Map<String, dynamic>> _extractCardInsights(
  List<Map<String, dynamic>> parsedDecks,
  List<Map<String, dynamic>> rawDecks,
) {
  final insights = <String, Map<String, dynamic>>{};
  
  for (var i = 0; i < parsedDecks.length; i++) {
    final deck = parsedDecks[i];
    final cards = deck['parsed_cards'] as Map<String, int>;
    final format = deck['format'] as String; // Agora pega do deck parseado
    final archetype = deck['archetype'] as String; // Usa arquétipo inferido
    
    for (final cardName in cards.keys) {
      insights.putIfAbsent(cardName, () => {
        'card_name': cardName,
        'usage_count': 0,
        'meta_deck_count': 0,
        'archetypes': <String>{},
        'formats': <String>{},
        'co_cards': <String, int>{},
      });
      
      final insight = insights[cardName]!;
      insight['usage_count'] = (insight['usage_count'] as int) + cards[cardName]!;
      insight['meta_deck_count'] = (insight['meta_deck_count'] as int) + 1;
      (insight['archetypes'] as Set<String>).add(archetype);
      (insight['formats'] as Set<String>).add(format);
      
      // Registrar co-ocorrências
      final coCards = insight['co_cards'] as Map<String, int>;
      for (final otherCard in cards.keys) {
        if (otherCard != cardName) {
          coCards[otherCard] = (coCards[otherCard] ?? 0) + 1;
        }
      }
    }
  }
  
  // Converter Sets para Lists e calcular top pairs
  for (final insight in insights.values) {
    insight['archetypes'] = (insight['archetypes'] as Set<String>).toList();
    insight['formats'] = (insight['formats'] as Set<String>).toList();
    
    // Top 10 cartas que mais aparecem junto
    final coCards = insight['co_cards'] as Map<String, int>;
    final sortedPairs = coCards.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    insight['top_pairs'] = sortedPairs.take(10).map((e) => {
      'card': e.key,
      'count': e.value,
    }).toList();
    
    // Calcular versatility score (aparece em múltiplos arquétipos/formatos)
    final archetypeCount = (insight['archetypes'] as List).length;
    final formatCount = (insight['formats'] as List).length;
    insight['versatility_score'] = (archetypeCount * 0.6 + formatCount * 0.4).clamp(0.0, 10.0);
    
    // Inferir role/categoria com base no nome
    insight['learned_role'] = _inferCardRole(insight['card_name'] as String);
  }
  
  return insights;
}

/// Infere o papel de uma carta pelo nome (heurística simples)
String _inferCardRole(String cardName) {
  final lower = cardName.toLowerCase();
  
  if (lower.contains('land') || lower.contains('plains') || lower.contains('island') ||
      lower.contains('swamp') || lower.contains('mountain') || lower.contains('forest')) {
    return 'mana_base';
  }
  if (lower.contains('bolt') || lower.contains('path') || lower.contains('push') ||
      lower.contains('doom') || lower.contains('murder') || lower.contains('wrath')) {
    return 'removal';
  }
  if (lower.contains('signet') || lower.contains('mana') || lower.contains('sol ring') ||
      lower.contains('ramp') || lower.contains('cultivate')) {
    return 'ramp';
  }
  if (lower.contains('draw') || lower.contains('vision') || lower.contains('ponder') ||
      lower.contains('brainstorm') || lower.contains('divination')) {
    return 'card_advantage';
  }
  
  return 'unknown';
}

/// Detecta pacotes de sinergia (cartas que frequentemente aparecem juntas)
List<Map<String, dynamic>> _detectSynergies(
  List<Map<String, dynamic>> parsedDecks,
  List<Map<String, dynamic>> rawDecks, // Mantido para compatibilidade
) {
  final pairCounts = <String, Map<String, dynamic>>{};
  final trioCounts = <String, Map<String, dynamic>>{};
  
  for (var i = 0; i < parsedDecks.length; i++) {
    final deck = parsedDecks[i];
    final cards = (deck['parsed_cards'] as Map<String, int>).keys.toList();
    final archetype = deck['archetype'] as String; // Usa arquétipo inferido
    final format = deck['format'] as String;
    
    // Pares de cartas
    for (var j = 0; j < cards.length; j++) {
      for (var k = j + 1; k < cards.length; k++) {
        final pair = [cards[j], cards[k]]..sort();
        final key = pair.join(' + ');
        
        pairCounts.putIfAbsent(key, () => {
          'cards': pair,
          'count': 0,
          'archetypes': <String>{},
          'formats': <String>{},
        });
        
        pairCounts[key]!['count'] = (pairCounts[key]!['count'] as int) + 1;
        (pairCounts[key]!['archetypes'] as Set<String>).add(archetype);
        (pairCounts[key]!['formats'] as Set<String>).add(format);
      }
    }
    
    // Trios (apenas se deck tiver poucas cartas ou seleção aleatória)
    if (cards.length <= 40) {
      for (var j = 0; j < cards.length; j++) {
        for (var k = j + 1; k < cards.length; k++) {
          for (var l = k + 1; l < cards.length; l++) {
            final trio = [cards[j], cards[k], cards[l]]..sort();
            final key = trio.join(' + ');
            
            trioCounts.putIfAbsent(key, () => {
              'cards': trio,
              'count': 0,
              'archetypes': <String>{},
              'formats': <String>{},
            });
            
            trioCounts[key]!['count'] = (trioCounts[key]!['count'] as int) + 1;
            (trioCounts[key]!['archetypes'] as Set<String>).add(archetype);
            (trioCounts[key]!['formats'] as Set<String>).add(format);
          }
        }
      }
    }
  }
  
  // Filtrar apenas pares/trios que aparecem em pelo menos 3 decks
  final synergies = <Map<String, dynamic>>[];
  final minOccurrence = max(3, (parsedDecks.length * 0.1).round());
  
  for (final entry in pairCounts.entries) {
    if ((entry.value['count'] as int) >= minOccurrence) {
      final cards = entry.value['cards'] as List<String>;
      synergies.add({
        'package_name': '${cards[0]} + ${cards[1]}',
        'package_type': 'synergy',
        'card_names': cards,
        'occurrence_count': entry.value['count'],
        'primary_archetype': (entry.value['archetypes'] as Set<String>).first,
        'formats': (entry.value['formats'] as Set<String>).toList(),
        'confidence_score': min(1.0, (entry.value['count'] as int) / parsedDecks.length),
      });
    }
  }
  
  for (final entry in trioCounts.entries) {
    if ((entry.value['count'] as int) >= minOccurrence) {
      final cards = entry.value['cards'] as List<String>;
      synergies.add({
        'package_name': cards.join(' + '),
        'package_type': 'package',
        'card_names': cards,
        'occurrence_count': entry.value['count'],
        'primary_archetype': (entry.value['archetypes'] as Set<String>).first,
        'formats': (entry.value['formats'] as Set<String>).toList(),
        'confidence_score': min(1.0, (entry.value['count'] as int) / parsedDecks.length),
      });
    }
  }
  
  // Ordenar por frequência
  synergies.sort((a, b) => 
    (b['occurrence_count'] as int).compareTo(a['occurrence_count'] as int));
  
  return synergies.take(500).toList(); // Limite de 500 sinergias
}

/// Extrai padrões de construção por arquétipo
List<Map<String, dynamic>> _extractArchetypePatterns(
  List<Map<String, dynamic>> parsedDecks,
  List<Map<String, dynamic>> rawDecks, // Mantido para compatibilidade
) {
  final patterns = <String, Map<String, dynamic>>{};
  
  for (var i = 0; i < parsedDecks.length; i++) {
    final deck = parsedDecks[i];
    final archetype = deck['archetype'] as String; // Usa arquétipo inferido
    final format = deck['format'] as String;
    final key = '$archetype|$format';
    
    patterns.putIfAbsent(key, () => {
      'archetype': archetype,
      'format': format,
      'sample_size': 0,
      'total_cards_sum': 0,
      'land_counts': <int>[],
      'creature_counts': <int>[],
      'all_cards': <String, int>{},
    });
    
    final pattern = patterns[key]!;
    pattern['sample_size'] = (pattern['sample_size'] as int) + 1;
    pattern['total_cards_sum'] = (pattern['total_cards_sum'] as int) + (deck['total_cards'] as int);
    
    final cards = deck['parsed_cards'] as Map<String, int>;
    final allCards = pattern['all_cards'] as Map<String, int>;
    
    for (final entry in cards.entries) {
      allCards[entry.key] = (allCards[entry.key] ?? 0) + 1;
    }
    
    // TODO: Calcular land/creature counts quando tivermos tipo de carta
  }
  
  // Processar padrões
  final result = <Map<String, dynamic>>[];
  
  for (final pattern in patterns.values) {
    if ((pattern['sample_size'] as int) < 2) continue;
    
    final sampleSize = pattern['sample_size'] as int;
    final allCards = pattern['all_cards'] as Map<String, int>;
    
    // Core cards: aparecem em >80% dos decks deste arquétipo
    final coreCards = allCards.entries
      .where((e) => e.value / sampleSize >= 0.8)
      .map((e) => e.key)
      .toList();
    
    // Flex cards: aparecem em 30-80% dos decks
    final flexCards = allCards.entries
      .where((e) => e.value / sampleSize >= 0.3 && e.value / sampleSize < 0.8)
      .map((e) => {'card': e.key, 'frequency': e.value / sampleSize})
      .toList();
    
    result.add({
      'archetype': pattern['archetype'],
      'format': pattern['format'],
      'sample_size': sampleSize,
      'core_cards': coreCards,
      'flex_options': flexCards,
      'data_sources': ['meta_decks'],
    });
  }
  
  return result;
}

/// Salva insights de cartas no banco
Future<void> _saveCardInsights(dynamic conn, Map<String, Map<String, dynamic>> insights) async {
  var saved = 0;
  var failed = 0;
  
  for (final insight in insights.values) {
    try {
      // Preparar arrays de forma segura escapando aspas e vírgulas
      final archetypes = (insight['archetypes'] as List).cast<String>();
      final formats = (insight['formats'] as List).cast<String>();
      final pairsJson = jsonEncode(insight['top_pairs']);
      
      await conn.execute(
        Sql.named('''
          INSERT INTO card_meta_insights (
            card_name, usage_count, meta_deck_count, 
            common_archetypes, common_formats, top_pairs,
            learned_role, versatility_score
          ) VALUES (
            @name, @usage, @deck_count,
            @archetypes::text[], @formats::text[], @pairs::jsonb,
            @role, @versatility
          )
          ON CONFLICT (card_name) DO UPDATE SET
            usage_count = card_meta_insights.usage_count + @usage,
            meta_deck_count = card_meta_insights.meta_deck_count + @deck_count,
            top_pairs = @pairs::jsonb,
            versatility_score = GREATEST(card_meta_insights.versatility_score, @versatility),
            last_updated_at = CURRENT_TIMESTAMP
        '''),
        parameters: {
          'name': insight['card_name'],
          'usage': insight['usage_count'],
          'deck_count': insight['meta_deck_count'],
          'archetypes': archetypes,  // Passar lista direta, driver converte
          'formats': formats,        // Passar lista direta, driver converte
          'pairs': pairsJson,
          'role': insight['learned_role'],
          'versatility': insight['versatility_score'],
        },
      );
      saved++;
      if (saved % 100 == 0) {
        print('      Progresso: $saved/${insights.length}');
        stdout.flush();
      }
    } catch (e) {
      failed++;
      if (failed <= 3) {
        print('      ⚠️ Erro ao salvar ${insight['card_name']}: $e');
      }
    }
  }
  
  print('   ✅ $saved insights de cartas salvos ($failed falhas)');
}

/// Salva sinergias no banco
Future<void> _saveSynergies(dynamic conn, List<Map<String, dynamic>> synergies) async {
  var saved = 0;
  var failed = 0;
  
  for (final synergy in synergies) {
    try {
      final cardNames = (synergy['card_names'] as List).cast<String>();
      final formats = (synergy['formats'] as List).cast<String>();
      
      await conn.execute(
        Sql.named('''
          INSERT INTO synergy_packages (
            package_name, package_type, card_names,
            primary_archetype, supported_formats, occurrence_count, confidence_score
          ) VALUES (
            @name, @type, @cards::text[],
            @archetype, @formats::text[], @count, @confidence
          )
          ON CONFLICT (package_name) DO UPDATE SET
            occurrence_count = synergy_packages.occurrence_count + @count,
            confidence_score = GREATEST(synergy_packages.confidence_score, @confidence)
        '''),
        parameters: {
          'name': synergy['package_name'],
          'type': synergy['package_type'],
          'cards': cardNames,
          'archetype': synergy['primary_archetype'],
          'formats': formats,
          'count': synergy['occurrence_count'],
          'confidence': synergy['confidence_score'],
        },
      );
      saved++;
      if (saved % 100 == 0) {
        print('      Progresso: $saved/${synergies.length}');
        stdout.flush();
      }
    } catch (e) {
      failed++;
      if (failed <= 3) {
        print('      ⚠️ Erro ao salvar sinergia: $e');
      }
    }
  }
  
  print('   ✅ $saved sinergias salvas ($failed falhas)');
}

/// Salva padrões de arquétipo
Future<void> _saveArchetypePatterns(dynamic conn, List<Map<String, dynamic>> patterns) async {
  var saved = 0;
  var failed = 0;
  
  for (final pattern in patterns) {
    try {
      final coreCards = (pattern['core_cards'] as List).cast<String>();
      final flexJson = jsonEncode(pattern['flex_options']);
      
      await conn.execute(
        Sql.named('''
          INSERT INTO archetype_patterns (
            archetype, format, sample_size, core_cards, flex_options, data_sources
          ) VALUES (
            @archetype, @format, @sample, @core::text[], @flex::jsonb, @sources::text[]
          )
          ON CONFLICT (archetype, format) DO UPDATE SET
            sample_size = archetype_patterns.sample_size + @sample,
            flex_options = @flex::jsonb,
            last_analyzed_at = CURRENT_TIMESTAMP
        '''),
        parameters: {
          'archetype': pattern['archetype'],
          'format': pattern['format'],
          'sample': pattern['sample_size'],
          'core': coreCards,
          'flex': flexJson,
          'sources': ['meta_decks'],
        },
      );
      saved++;
    } catch (e) {
      failed++;
      if (failed <= 3) {
        print('      ⚠️ Erro ao salvar padrão: $e');
      }
    }
  }
  
  print('   ✅ $saved padrões de arquétipo salvos ($failed falhas)');
}

/// Atualiza estado do modelo de aprendizado
Future<void> _updateLearningState(
  dynamic conn, int cardCount, int synergyCount, int patternCount
) async {
  await conn.execute(
    Sql.named('''
      UPDATE ml_learning_state
      SET 
        active_rules = jsonb_set(
          COALESCE(active_rules, '{}'::jsonb),
          '{extraction_stats}',
          @stats::jsonb
        ),
        last_updated_at = CURRENT_TIMESTAMP
      WHERE model_version = 'v1.0-imitation-learning'
    '''),
    parameters: {
      'stats': jsonEncode({
        'card_insights': cardCount,
        'synergies': synergyCount,
        'archetype_patterns': patternCount,
        'extracted_at': DateTime.now().toIso8601String(),
      }),
    },
  );
}
