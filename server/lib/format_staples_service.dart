import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

/// Serviço para gerenciar staples de formato de forma dinâmica
/// 
/// Este serviço busca staples de duas fontes:
/// 1. Banco de dados local (tabela format_staples) - Mais rápido, dados cacheados
/// 2. Scryfall API - Fallback quando DB não tem dados, sempre atualizado
/// 
/// A ordem de prioridade é:
/// 1. DB local (se tiver dados sincronizados nas últimas 24h)
/// 2. Scryfall API (fallback)
/// 
/// Exemplo de uso:
/// ```dart
/// final service = FormatStaplesService(pool);
/// final staples = await service.getStaples(
///   format: 'commander',
///   colors: ['U', 'B'],
///   archetype: 'control',
/// );
/// ```
class FormatStaplesService {
  final Pool _pool;
  
  /// Cache de duração máxima em horas
  static const int cacheMaxAgeHours = 24;
  
  /// Limite de EDHREC rank para considerar uma carta como staple
  /// Cartas com rank <= 500 são consideradas staples (Top 500 mais populares)
  static const int stapleRankThreshold = 500;
  
  FormatStaplesService(this._pool);

  /// Busca staples para um formato, cores e arquétipo específicos
  /// 
  /// [format] - Formato do jogo: 'commander', 'standard', 'modern', etc.
  /// [colors] - Lista de cores do deck: ['W', 'U'], ['R', 'G'], etc.
  /// [archetype] - Arquétipo opcional: 'aggro', 'control', 'combo', 'midrange'
  /// [limit] - Quantidade máxima de staples a retornar (default: 50)
  /// [excludeBanned] - Se deve excluir cartas banidas (default: true)
  Future<List<Map<String, dynamic>>> getStaples({
    required String format,
    List<String>? colors,
    String? archetype,
    int limit = 50,
    bool excludeBanned = true,
  }) async {
    // 1. Tentar buscar do banco de dados local
    final dbStaples = await _getStaplesFromDB(
      format: format,
      colors: colors,
      archetype: archetype,
      limit: limit,
      excludeBanned: excludeBanned,
    );

    if (dbStaples.isNotEmpty) {
      return dbStaples;
    }

    // 2. Fallback: Buscar diretamente do Scryfall
    return await _getStaplesFromScryfall(
      format: format,
      colors: colors,
      archetype: archetype,
      limit: limit,
    );
  }

  /// Busca staples do banco de dados local
  Future<List<Map<String, dynamic>>> _getStaplesFromDB({
    required String format,
    List<String>? colors,
    String? archetype,
    required int limit,
    required bool excludeBanned,
  }) async {
    try {
      // Construir query dinâmica
      final conditions = <String>['format = @format'];
      final parameters = <String, dynamic>{'format': format.toLowerCase()};

      // Filtro de cores (se fornecido)
      if (colors != null && colors.isNotEmpty) {
        // Buscar cartas que tenham identidade de cor compatível
        // Usa operador PostgreSQL <@ (array containment) para verificar se a identidade 
        // de cor da carta está contida nas cores do deck (ou é vazia/incolor)
        conditions.add('(color_identity <@ @colors OR color_identity = \'{}\')');
        parameters['colors'] = TypedValue(Type.textArray, colors);
      }

      // Filtro de arquétipo (se fornecido)
      if (archetype != null && archetype.isNotEmpty) {
        conditions.add('(archetype = @archetype OR archetype IS NULL)');
        parameters['archetype'] = archetype.toLowerCase();
      }

      // Filtro de banidas
      if (excludeBanned) {
        conditions.add('is_banned = FALSE');
      }

      // Verificar se dados são recentes (últimas 24h)
      conditions.add("last_synced_at > NOW() - INTERVAL '$cacheMaxAgeHours hours'");

      final query = '''
        SELECT card_name, edhrec_rank, category, color_identity, archetype
        FROM format_staples
        WHERE ${conditions.join(' AND ')}
        ORDER BY 
          CASE WHEN archetype IS NULL THEN 0 ELSE 1 END,  -- Universais primeiro
          edhrec_rank ASC NULLS LAST
        LIMIT @limit
      ''';

      parameters['limit'] = limit;

      final result = await _pool.execute(
        Sql.named(query),
        parameters: parameters,
      );

      return result.map((row) => {
        'name': row[0] as String,
        'edhrec_rank': row[1] as int?,
        'category': row[2] as String?,
        'color_identity': (row[3] as List?)?.cast<String>() ?? [],
        'archetype': row[4] as String?,
        'source': 'database',
      }).toList();

    } catch (e) {
      print('⚠️ Erro ao buscar staples do DB: $e');
      return [];
    }
  }

  /// Busca staples diretamente do Scryfall API (fallback)
  Future<List<Map<String, dynamic>>> _getStaplesFromScryfall({
    required String format,
    List<String>? colors,
    String? archetype,
    required int limit,
  }) async {
    try {
      // Construir query Scryfall
      final queryParts = <String>['format:$format', '-is:banned'];

      // Filtro de cores
      if (colors != null && colors.isNotEmpty) {
        queryParts.add('id<=${colors.join('')}');
      }

      // Filtro de arquétipo (queries específicas)
      if (archetype != null) {
        switch (archetype.toLowerCase()) {
          case 'aggro':
            queryParts.add('cmc<=3');
            break;
          case 'control':
            queryParts.add('(function:counterspell OR function:removal)');
            break;
          case 'combo':
            queryParts.add('function:tutor');
            break;
          case 'ramp':
            queryParts.add('(function:ramp OR function:mana-dork)');
            break;
          case 'draw':
            queryParts.add('function:card-draw');
            break;
        }
      }

      final uri = Uri.https('api.scryfall.com', '/cards/search', {
        'q': queryParts.join(' '),
        'order': 'edhrec',
        'unique': 'cards',
      });

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final cards = (data['data'] as List).take(limit);

        return cards.map<Map<String, dynamic>>((card) => {
          'name': card['name'] as String,
          'edhrec_rank': card['edhrec_rank'] as int? ?? 99999,
          'category': archetype ?? 'staple',
          'color_identity': (card['color_identity'] as List?)?.cast<String>() ?? [],
          'archetype': archetype,
          'source': 'scryfall',
        }).toList();
      }

      return [];
    } catch (e) {
      print('⚠️ Erro ao buscar staples do Scryfall: $e');
      return [];
    }
  }

  /// Busca staples por categoria específica
  Future<List<String>> getStaplesByCategory({
    required String format,
    required String category,
    List<String>? colors,
    int limit = 20,
  }) async {
    final staples = await getStaples(
      format: format,
      colors: colors,
      archetype: category,
      limit: limit,
    );

    return staples.map((s) => s['name'] as String).toList();
  }

  /// Verifica se uma carta é considerada staple no formato
  Future<bool> isStaple(String cardName, String format) async {
    try {
      final result = await _pool.execute(
        Sql.named('''
          SELECT 1 FROM format_staples 
          WHERE card_name = @name 
            AND format = @format 
            AND is_banned = FALSE
            AND edhrec_rank <= $stapleRankThreshold
          LIMIT 1
        '''),
        parameters: {
          'name': cardName,
          'format': format.toLowerCase(),
        },
      );

      return result.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Retorna a lista de cartas banidas no formato
  Future<List<String>> getBannedCards(String format) async {
    try {
      // Primeiro tenta do banco local
      final dbResult = await _pool.execute(
        Sql.named('''
          SELECT card_name FROM format_staples 
          WHERE format = @format AND is_banned = TRUE
        '''),
        parameters: {'format': format.toLowerCase()},
      );

      if (dbResult.isNotEmpty) {
        return dbResult.map((row) => row[0] as String).toList();
      }

      // Fallback: Scryfall
      final uri = Uri.https('api.scryfall.com', '/cards/search', {
        'q': 'format:$format is:banned',
        'unique': 'cards',
      });

      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['data'] as List).map<String>((c) => c['name'] as String).toList();
      }

      return [];
    } catch (e) {
      print('⚠️ Erro ao buscar cartas banidas: $e');
      return [];
    }
  }

  /// Verifica se uma carta está banida no formato
  Future<bool> isBanned(String cardName, String format) async {
    try {
      // Verifica no banco local primeiro
      final dbResult = await _pool.execute(
        Sql.named('''
          SELECT 1 FROM format_staples 
          WHERE card_name = @name AND format = @format AND is_banned = TRUE
          UNION
          SELECT 1 FROM card_legalities cl
          JOIN cards c ON c.id = cl.card_id
          WHERE c.name = @name AND cl.format = @format AND cl.status = 'banned'
          LIMIT 1
        '''),
        parameters: {
          'name': cardName,
          'format': format.toLowerCase(),
        },
      );

      if (dbResult.isNotEmpty) {
        return true;
      }

      // Fallback: Scryfall (mais lento, apenas se necessário)
      final uri = Uri.parse(
        'https://api.scryfall.com/cards/named?exact=${Uri.encodeComponent(cardName)}'
      );
      
      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final legalities = data['legalities'] as Map<String, dynamic>?;
        return legalities?[format.toLowerCase()] == 'banned';
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Retorna recomendações de staples organizadas por categoria
  /// Útil para construção de decks
  Future<Map<String, List<String>>> getRecommendationsForDeck({
    required String format,
    required List<String> colors,
    String? archetype,
  }) async {
    final recommendations = <String, List<String>>{
      'universal': [],
      'ramp': [],
      'draw': [],
      'removal': [],
      'archetype_specific': [],
    };

    try {
      // 1. Staples universais
      final universal = await getStaples(
        format: format,
        colors: colors,
        limit: 20,
      );
      recommendations['universal'] = universal.map((s) => s['name'] as String).toList();

      // 2. Ramp
      final ramp = await getStaplesByCategory(
        format: format,
        category: 'ramp',
        colors: colors,
        limit: 10,
      );
      recommendations['ramp'] = ramp;

      // 3. Card Draw
      final draw = await getStaplesByCategory(
        format: format,
        category: 'draw',
        colors: colors,
        limit: 10,
      );
      recommendations['draw'] = draw;

      // 4. Removal
      final removal = await getStaplesByCategory(
        format: format,
        category: 'removal',
        colors: colors,
        limit: 10,
      );
      recommendations['removal'] = removal;

      // 5. Específico do arquétipo (se fornecido)
      if (archetype != null) {
        final archetypeCards = await getStaples(
          format: format,
          colors: colors,
          archetype: archetype,
          limit: 15,
        );
        recommendations['archetype_specific'] = archetypeCards.map((s) => s['name'] as String).toList();
      }

    } catch (e) {
      print('⚠️ Erro ao gerar recomendações: $e');
    }

    return recommendations;
  }

  /// Verifica se os dados do banco estão atualizados
  Future<bool> isDataFresh(String format) async {
    try {
      final result = await _pool.execute(
        Sql.named('''
          SELECT 1 FROM format_staples 
          WHERE format = @format 
            AND last_synced_at > NOW() - INTERVAL '$cacheMaxAgeHours hours'
          LIMIT 1
        '''),
        parameters: {'format': format.toLowerCase()},
      );

      return result.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
}
