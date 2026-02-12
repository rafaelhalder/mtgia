import 'dart:convert';
import 'package:postgres/postgres.dart';

/// Serviço de Conhecimento ML
/// 
/// Consulta as tabelas de aprendizado (card_meta_insights, synergy_packages, 
/// archetype_patterns) e fornece contexto enriquecido para a otimização de decks.
/// 
/// Este serviço implementa a segunda metade do "Imitation Learning":
/// - O script extract_meta_insights.dart EXTRAI conhecimento dos meta decks
/// - Este serviço APLICA esse conhecimento nas otimizações
class MLKnowledgeService {
  final dynamic _conn;
  
  MLKnowledgeService(this._conn);
  
  /// Busca contexto de conhecimento para um deck específico
  /// Retorna insights relevantes baseados no arquétipo, commander e cartas
  Future<MLContext> getContextForDeck({
    required String archetype,
    required String format,
    String? commanderName,
    List<String>? currentCards,
  }) async {
    final stopwatch = Stopwatch()..start();
    
    // 1. Buscar padrão do arquétipo
    final archetypeData = await _getArchetypePattern(archetype, format);
    
    // 2. Buscar sinergias relevantes
    final synergies = await _getRelevantSynergies(
      archetype: archetype,
      format: format,
      currentCards: currentCards ?? [],
    );
    
    // 3. Buscar insights de cartas que o deck já tem
    final cardInsights = currentCards != null && currentCards.isNotEmpty
        ? await _getCardInsights(currentCards)
        : <String, CardInsight>{};
    
    // 4. Buscar sugestões de cartas populares no arquétipo
    final recommendations = await _getRecommendations(
      archetype: archetype,
      format: format,
      existingCards: currentCards ?? [],
    );
    
    stopwatch.stop();
    
    return MLContext(
      archetype: archetype,
      format: format,
      archetypePattern: archetypeData,
      relevantSynergies: synergies,
      cardInsights: cardInsights,
      recommendations: recommendations,
      queryTimeMs: stopwatch.elapsedMilliseconds,
    );
  }
  
  /// Busca padrão do arquétipo
  Future<ArchetypePattern?> _getArchetypePattern(String archetype, String format) async {
    try {
      // Busca exata primeiro
      var result = await _conn.execute(
        Sql.named('''
          SELECT archetype, format, sample_size, core_cards, flex_options,
                 ideal_land_count, ideal_avg_cmc, typical_ramp, typical_draw,
                 typical_removal, typical_finishers, win_conditions
          FROM archetype_patterns
          WHERE LOWER(archetype) = LOWER(@archetype) AND LOWER(format) = LOWER(@format)
          LIMIT 1
        '''),
        parameters: {'archetype': archetype, 'format': format},
      );
      
      // Se não encontrou, tenta busca fuzzy
      if (result.isEmpty) {
        result = await _conn.execute(
          Sql.named('''
            SELECT archetype, format, sample_size, core_cards, flex_options,
                   ideal_land_count, ideal_avg_cmc, typical_ramp, typical_draw,
                   typical_removal, typical_finishers, win_conditions
            FROM archetype_patterns
            WHERE LOWER(archetype) LIKE LOWER(@pattern) AND LOWER(format) = LOWER(@format)
            ORDER BY sample_size DESC
            LIMIT 1
          '''),
          parameters: {'pattern': '%$archetype%', 'format': format},
        );
      }
      
      if (result.isEmpty) return null;
      
      final row = result.first.toColumnMap();
      return ArchetypePattern(
        archetype: row['archetype']?.toString() ?? archetype,
        format: row['format']?.toString() ?? format,
        sampleSize: (row['sample_size'] as int?) ?? 0,
        coreCards: _toStringList(row['core_cards']),
        flexOptions: _parseJsonList(row['flex_options']),
        idealLandCount: row['ideal_land_count'] as int?,
        idealAvgCmc: (row['ideal_avg_cmc'] as num?)?.toDouble(),
        typicalRamp: _toStringList(row['typical_ramp']),
        typicalDraw: _toStringList(row['typical_draw']),
        typicalRemoval: _toStringList(row['typical_removal']),
        typicalFinishers: _toStringList(row['typical_finishers']),
        winConditions: _toStringList(row['win_conditions']),
      );
    } catch (e) {
      print('[MLKnowledgeService] Erro ao buscar padrão: $e');
      return null;
    }
  }
  
  /// Busca sinergias relevantes para o deck
  Future<List<SynergyPackage>> _getRelevantSynergies({
    required String archetype,
    required String format,
    required List<String> currentCards,
  }) async {
    try {
      if (currentCards.isEmpty) return [];
      
      // Busca sinergias que contêm cartas que o deck já tem
      final result = await _conn.execute(
        Sql.named('''
          SELECT package_name, package_type, card_names, description,
                 occurrence_count, confidence_score, primary_archetype
          FROM synergy_packages
          WHERE (
            -- Sinergias do mesmo arquétipo
            LOWER(primary_archetype) LIKE LOWER(@archetype_pattern)
            -- OU sinergias que incluem cartas do deck
            OR EXISTS (
              SELECT 1 FROM unnest(card_names) AS cn
              WHERE cn = ANY(@cards::text[])
            )
          )
          ORDER BY confidence_score DESC, occurrence_count DESC
          LIMIT 20
        '''),
        parameters: {
          'archetype_pattern': '%$archetype%',
          'cards': '{${currentCards.map((c) => c.replaceAll("'", "''")).join(',')}}',
        },
      );
      
      return result.map((row) {
        final map = row.toColumnMap();
        return SynergyPackage(
          name: map['package_name']?.toString() ?? '',
          type: map['package_type']?.toString() ?? 'synergy',
          cards: _toStringList(map['card_names']),
          description: map['description']?.toString(),
          occurrenceCount: (map['occurrence_count'] as int?) ?? 0,
          confidenceScore: (map['confidence_score'] as num?)?.toDouble() ?? 0.5,
        );
      }).toList();
    } catch (e) {
      print('[MLKnowledgeService] Erro ao buscar sinergias: $e');
      return [];
    }
  }
  
  /// Busca insights das cartas do deck
  Future<Map<String, CardInsight>> _getCardInsights(List<String> cardNames) async {
    try {
      if (cardNames.isEmpty) return {};
      
      final result = await _conn.execute(
        Sql.named('''
          SELECT card_name, usage_count, meta_deck_count, common_archetypes,
                 top_pairs, learned_role, versatility_score
          FROM card_meta_insights
          WHERE card_name = ANY(@names::text[])
        '''),
        parameters: {
          'names': '{${cardNames.map((c) => '"${c.replaceAll('"', '\\"')}"').join(',')}}',
        },
      );
      
      final insights = <String, CardInsight>{};
      for (final row in result) {
        final map = row.toColumnMap();
        final name = map['card_name']?.toString() ?? '';
        insights[name] = CardInsight(
          cardName: name,
          usageCount: (map['usage_count'] as int?) ?? 0,
          metaDeckCount: (map['meta_deck_count'] as int?) ?? 0,
          commonArchetypes: _toStringList(map['common_archetypes']),
          topPairs: _parseJsonList(map['top_pairs']),
          learnedRole: map['learned_role']?.toString(),
          versatilityScore: (map['versatility_score'] as num?)?.toDouble() ?? 0.0,
        );
      }
      
      return insights;
    } catch (e) {
      print('[MLKnowledgeService] Erro ao buscar insights: $e');
      return {};
    }
  }
  
  /// Busca recomendações de cartas baseadas no arquétipo
  Future<List<CardRecommendation>> _getRecommendations({
    required String archetype,
    required String format,
    required List<String> existingCards,
  }) async {
    try {
      // Busca cartas populares no arquétipo que o deck ainda não tem
      final result = await _conn.execute(
        Sql.named('''
          SELECT card_name, usage_count, meta_deck_count, learned_role, versatility_score
          FROM card_meta_insights
          WHERE 
            @archetype_pattern = ANY(common_archetypes)
            AND card_name NOT IN (SELECT unnest(@existing::text[]))
          ORDER BY meta_deck_count DESC, usage_count DESC
          LIMIT 30
        '''),
        parameters: {
          'archetype_pattern': archetype,
          'existing': '{${existingCards.map((c) => '"${c.replaceAll('"', '\\"')}"').join(',')}}',
        },
      );
      
      return result.map((row) {
        final map = row.toColumnMap();
        return CardRecommendation(
          cardName: map['card_name']?.toString() ?? '',
          reason: 'Popular em $archetype (${map['meta_deck_count']} meta decks)',
          metaDeckCount: (map['meta_deck_count'] as int?) ?? 0,
          role: map['learned_role']?.toString(),
          score: (map['versatility_score'] as num?)?.toDouble() ?? 0.0,
        );
      }).toList();
    } catch (e) {
      print('[MLKnowledgeService] Erro ao buscar recomendações: $e');
      return [];
    }
  }
  
  /// Registra feedback do usuário sobre uma otimização
  Future<void> recordFeedback({
    required String? deckId,
    required String? userId,
    required String archetype,
    required String? commanderName,
    required List<String> cardsAccepted,
    required List<String> cardsRejected,
    required int? effectivenessScore,
    String? userComment,
  }) async {
    try {
      await _conn.execute(
        Sql.named('''
          INSERT INTO ml_prompt_feedback (
            deck_id, user_id, archetype, commander_name,
            cards_accepted, cards_rejected, effectiveness_score, user_comment,
            prompt_version
          ) VALUES (
            @deck_id::uuid, @user_id::uuid, @archetype, @commander,
            @accepted::text[], @rejected::text[], @score, @comment,
            'v1.1-hybrid'
          )
        '''),
        parameters: {
          'deck_id': deckId,
          'user_id': userId,
          'archetype': archetype,
          'commander': commanderName,
          'accepted': '{${cardsAccepted.map((c) => '"$c"').join(',')}}',
          'rejected': '{${cardsRejected.map((c) => '"$c"').join(',')}}',
          'score': effectivenessScore,
          'comment': userComment,
        },
      );
    } catch (e) {
      print('[MLKnowledgeService] Erro ao registrar feedback: $e');
    }
  }
  
  /// Gera texto de contexto para o prompt da IA
  String generatePromptContext(MLContext context) {
    final buffer = StringBuffer();
    
    // Padrão do arquétipo
    if (context.archetypePattern != null) {
      final pattern = context.archetypePattern!;
      buffer.writeln('\n[KNOWLEDGE BASE - ${pattern.archetype}]');
      
      if (pattern.coreCards.isNotEmpty) {
        buffer.writeln('Core staples (aparecem em ${pattern.sampleSize}+ meta decks):');
        buffer.writeln('  ${pattern.coreCards.take(15).join(', ')}');
      }
      
      if (pattern.idealLandCount != null) {
        buffer.writeln('Configuração ideal: ${pattern.idealLandCount} lands, CMC médio ${pattern.idealAvgCmc?.toStringAsFixed(2) ?? 'N/A'}');
      }
      
      if (pattern.typicalRamp.isNotEmpty) {
        buffer.writeln('Ramp típico: ${pattern.typicalRamp.take(5).join(', ')}');
      }
      
      if (pattern.typicalRemoval.isNotEmpty) {
        buffer.writeln('Removal típico: ${pattern.typicalRemoval.take(5).join(', ')}');
      }
    }
    
    // Sinergias encontradas
    if (context.relevantSynergies.isNotEmpty) {
      buffer.writeln('\n[SINERGIAS CONHECIDAS]');
      for (final synergy in context.relevantSynergies.take(5)) {
        buffer.writeln('• ${synergy.name} (${synergy.type}, conf: ${(synergy.confidenceScore * 100).toStringAsFixed(0)}%)');
      }
    }
    
    // Recomendações
    if (context.recommendations.isNotEmpty) {
      buffer.writeln('\n[RECOMENDAÇÕES BASEADAS EM META]');
      for (final rec in context.recommendations.take(10)) {
        buffer.writeln('• ${rec.cardName} - ${rec.reason}');
      }
    }
    
    return buffer.toString();
  }
  
  // Helpers
  List<String> _toStringList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value.map((e) => e.toString()).toList();
    if (value is String) {
      // Parse PostgreSQL array format: {a,b,c}
      final cleaned = value.replaceAll('{', '').replaceAll('}', '');
      if (cleaned.isEmpty) return [];
      return cleaned.split(',').map((e) => e.trim().replaceAll('"', '')).toList();
    }
    return [];
  }
  
  List<Map<String, dynamic>> _parseJsonList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value.cast<Map<String, dynamic>>();
    if (value is String) {
      try {
        final parsed = jsonDecode(value);
        if (parsed is List) return parsed.cast<Map<String, dynamic>>();
      } catch (_) {}
    }
    return [];
  }
}

// Data Classes

class MLContext {
  final String archetype;
  final String format;
  final ArchetypePattern? archetypePattern;
  final List<SynergyPackage> relevantSynergies;
  final Map<String, CardInsight> cardInsights;
  final List<CardRecommendation> recommendations;
  final int queryTimeMs;
  
  MLContext({
    required this.archetype,
    required this.format,
    this.archetypePattern,
    required this.relevantSynergies,
    required this.cardInsights,
    required this.recommendations,
    required this.queryTimeMs,
  });
  
  Map<String, dynamic> toJson() => {
    'archetype': archetype,
    'format': format,
    'has_archetype_pattern': archetypePattern != null,
    'synergies_found': relevantSynergies.length,
    'card_insights_found': cardInsights.length,
    'recommendations_count': recommendations.length,
    'query_time_ms': queryTimeMs,
  };
}

class ArchetypePattern {
  final String archetype;
  final String format;
  final int sampleSize;
  final List<String> coreCards;
  final List<Map<String, dynamic>> flexOptions;
  final int? idealLandCount;
  final double? idealAvgCmc;
  final List<String> typicalRamp;
  final List<String> typicalDraw;
  final List<String> typicalRemoval;
  final List<String> typicalFinishers;
  final List<String> winConditions;
  
  ArchetypePattern({
    required this.archetype,
    required this.format,
    required this.sampleSize,
    required this.coreCards,
    required this.flexOptions,
    this.idealLandCount,
    this.idealAvgCmc,
    required this.typicalRamp,
    required this.typicalDraw,
    required this.typicalRemoval,
    required this.typicalFinishers,
    required this.winConditions,
  });
}

class SynergyPackage {
  final String name;
  final String type;
  final List<String> cards;
  final String? description;
  final int occurrenceCount;
  final double confidenceScore;
  
  SynergyPackage({
    required this.name,
    required this.type,
    required this.cards,
    this.description,
    required this.occurrenceCount,
    required this.confidenceScore,
  });
}

class CardInsight {
  final String cardName;
  final int usageCount;
  final int metaDeckCount;
  final List<String> commonArchetypes;
  final List<Map<String, dynamic>> topPairs;
  final String? learnedRole;
  final double versatilityScore;
  
  CardInsight({
    required this.cardName,
    required this.usageCount,
    required this.metaDeckCount,
    required this.commonArchetypes,
    required this.topPairs,
    this.learnedRole,
    required this.versatilityScore,
  });
}

class CardRecommendation {
  final String cardName;
  final String reason;
  final int metaDeckCount;
  final String? role;
  final double score;
  
  CardRecommendation({
    required this.cardName,
    required this.reason,
    required this.metaDeckCount,
    this.role,
    required this.score,
  });
}
