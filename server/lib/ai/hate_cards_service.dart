import 'package:postgres/postgres.dart';

/// Serviço para buscar hate cards anti-meta do banco de dados.
/// 
/// Consulta a tabela `archetype_counters` para sugerir cartas que
/// counterão estratégias comuns (graveyard, artifacts, tokens, etc).
/// 
/// Exemplo de uso:
/// ```dart
/// final service = HateCardsService(db);
/// final hateCards = await service.getRelevantHateCards(
///   deckColors: ['W', 'U', 'B'],
///   detectedThemes: ['graveyard', 'artifacts'],
/// );
/// // Retorna: ['Rest in Peace', 'Collector Ouphe', ...]
/// ```
class HateCardsService {
  final dynamic _conn;
  
  HateCardsService(this._conn);
  
  /// Busca hate cards relevantes para incluir no deck
  /// 
  /// [deckColors] - Cores do deck (para filtrar cartas compatíveis)
  /// [detectedThemes] - Temas do deck (para NÃO incluir hate do próprio tema)
  /// [format] - Formato do jogo (default: 'commander')
  Future<List<Map<String, dynamic>>> getRelevantHateCards({
    required List<String> deckColors,
    List<String>? detectedThemes,
    String format = 'commander',
  }) async {
    try {
      // Buscar todos os counters disponíveis
      final result = await _conn.execute(
        Sql.named('''
          SELECT archetype, hate_cards, priority, effectiveness_score, notes
          FROM archetype_counters
          WHERE format = @format
          ORDER BY priority ASC, effectiveness_score DESC
        '''),
        parameters: {'format': format.toLowerCase()},
      );
      
      if (result.isEmpty) return [];
      
      final deckThemesLower = (detectedThemes ?? [])
          .map((t) => t.toLowerCase())
          .toSet();
      
      final recommendations = <Map<String, dynamic>>[];
      
      for (final row in result) {
        final archetype = (row[0] as String).toLowerCase();
        final hateCards = (row[1] as List?)?.cast<String>() ?? [];
        final priority = row[2] as int;
        final effectiveness = row[3] as int;
        final notes = row[4] as String?;
        
        // Não sugerir hate cards para o próprio tema do deck
        if (deckThemesLower.contains(archetype)) continue;
        
        // Filtrar hate cards compatíveis com as cores do deck
        final compatibleCards = await _filterByColorIdentity(
          hateCards, 
          deckColors,
        );
        
        if (compatibleCards.isNotEmpty) {
          recommendations.add({
            'archetype': archetype,
            'hate_cards': compatibleCards,
            'priority': priority,
            'effectiveness': effectiveness,
            'notes': notes,
            'reason': 'Anti-$archetype: $notes',
          });
        }
      }
      
      return recommendations;
    } catch (e) {
      print('HateCardsService error: $e');
      return [];
    }
  }
  
  /// Gera contexto de texto para incluir no prompt
  String generatePromptContext(List<Map<String, dynamic>> hateCards) {
    if (hateCards.isEmpty) return '';
    
    final buffer = StringBuffer();
    buffer.writeln('\n[ANTI-META HATE CARDS]');
    buffer.writeln('Considere incluir 2-4 destas cartas para proteção:');
    
    for (final entry in hateCards.take(5)) {
      final archetype = entry['archetype'] as String;
      final cards = (entry['hate_cards'] as List).take(4).join(', ');
      final notes = entry['notes'] as String?;
      buffer.writeln('• Anti-$archetype: $cards');
      if (notes != null && notes.isNotEmpty) {
        buffer.writeln('  (${notes})');
      }
    }
    
    return buffer.toString();
  }
  
  /// Filtra cartas por identidade de cor
  Future<List<String>> _filterByColorIdentity(
    List<String> cardNames,
    List<String> deckColors,
  ) async {
    if (cardNames.isEmpty) return [];
    
    try {
      // Converter cores para formato do banco (W, U, B, R, G)
      final colorsUpper = deckColors.map((c) => c.toUpperCase()).toList();
      
      // Query para buscar cartas que são incolores OU têm cor compatível
      final namesForQuery = cardNames.map((n) => n.replaceAll("'", "''")).toList();
      final namesIn = namesForQuery.map((n) => "'$n'").join(', ');
      
      final result = await _conn.execute(
        '''
          SELECT DISTINCT name
          FROM cards
          WHERE name IN ($namesIn)
            AND (
              color_identity IS NULL 
              OR color_identity = '{}'
              OR color_identity <@ ARRAY[${colorsUpper.map((c) => "'$c'").join(', ')}]::text[]
            )
        ''',
      );
      
      final names = <String>[];
      for (final row in result) {
        names.add(row[0] as String);
      }
      return names;
    } catch (e) {
      // Fallback: retornar todas as cartas (melhor do que nenhuma)
      print('HateCardsService filter error: $e');
      return cardNames;
    }
  }
  
  /// Verifica se há dados disponíveis
  Future<bool> hasData() async {
    try {
      final result = await _conn.execute(
        'SELECT COUNT(*)::int FROM archetype_counters',
      );
      return (result.first[0] as int) > 0;
    } catch (_) {
      return false;
    }
  }
}
