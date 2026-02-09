import 'dart:convert';
import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:http/http.dart' as http;
import '../lib/database.dart';

/// Script para sincronizar staples de formato via Scryfall API
/// 
/// Este script busca as cartas mais populares do Scryfall (ordenadas por EDHREC rank)
/// e atualiza a tabela `format_staples` no banco de dados.
/// 
/// Uso:
///   dart run bin/sync_staples.dart [format]
///   dart run bin/sync_staples.dart commander  # Apenas Commander
///   dart run bin/sync_staples.dart ALL        # Todos os formatos
/// 
/// Recomendação: Executar semanalmente via cron job ou scheduler
/// Exemplo cron (toda segunda-feira às 3h):
///   0 3 * * 1 cd /path/to/server && dart run bin/sync_staples.dart ALL

/// Configuração de formatos e quantidades
const Map<String, String> supportedFormats = {
  'commander': 'format:commander',
  'standard': 'format:standard',
  'modern': 'format:modern',
  'legacy': 'format:legacy',
  'pioneer': 'format:pioneer',
  'pauper': 'format:pauper',
  'vintage': 'format:vintage',
};

/// Configuração de arquétipos e suas queries específicas
const Map<String, Map<String, String>> archetypeQueries = {
  'aggro': {
    'description': 'Cartas agressivas de baixo custo',
    'query': 'cmc<=3 (t:creature OR function:pump-spell OR function:haste)',
  },
  'control': {
    'description': 'Cartas de controle e remoção',
    'query': '(function:counterspell OR function:removal OR function:wipe)',
  },
  'combo': {
    'description': 'Tutors e peças de combo',
    'query': '(function:tutor OR oracle:infinite OR oracle:"win the game")',
  },
  'midrange': {
    'description': 'Cartas versáteis de valor',
    'query': 'cmc>=2 cmc<=5 (t:creature OR t:planeswalker)',
  },
  'ramp': {
    'description': 'Aceleração de mana',
    'query': '(function:mana-dork OR function:ramp OR oracle:"add {" t:artifact)',
  },
  'draw': {
    'description': 'Card draw e card advantage',
    'query': '(function:card-draw OR function:cantrip OR oracle:"draw cards")',
  },
  'removal': {
    'description': 'Remoção pontual e board wipes',
    'query': '(function:removal OR function:wipe OR oracle:"destroy target")',
  },
};

/// Cores para filtragem
const List<String> colorCombinations = [
  '', // Colorless / Universal
  'W', 'U', 'B', 'R', 'G', // Mono
  'WU', 'WB', 'WR', 'WG', 'UB', 'UR', 'UG', 'BR', 'BG', 'RG', // Dual
];

void main(List<String> args) async {
  final inputFormat = args.isNotEmpty ? args[0].toLowerCase() : 'commander';
  
  print('╔════════════════════════════════════════════════════════════════╗');
  print('║     SYNC STAPLES FROM SCRYFALL - MTG Deck Builder              ║');
  print('╚════════════════════════════════════════════════════════════════╝');
  print('');

  final formatsToProcess = inputFormat == 'all' 
      ? supportedFormats.keys.toList() 
      : [inputFormat];

  // Validar formato
  for (final format in formatsToProcess) {
    if (!supportedFormats.containsKey(format)) {
      print('❌ Formato desconhecido: $format');
      print('   Formatos suportados: ${supportedFormats.keys.join(", ")}');
      exit(1);
    }
  }

  final db = Database();
  await db.connect();
  final conn = db.connection;

  try {
    for (final format in formatsToProcess) {
      print('\n🎴 Sincronizando staples para formato: ${format.toUpperCase()}');
      print('${'─' * 60}');
      
      await conn.run((session) async {
        final syncLogId = await _createSyncLog(session, format);
        
        int totalInserted = 0;
        int totalUpdated = 0;
        int totalBanned = 0;

        // 1. Buscar staples universais do formato (Top 100)
        print('  📥 Buscando staples universais...');
        final universalStaples = await _fetchScryfallCards(
          query: '${supportedFormats[format]} -is:banned',
          limit: 100,
        );
        
        if (universalStaples.isNotEmpty) {
          final result = await _upsertStaples(
            conn: session, 
            cards: universalStaples, 
            format: format, 
            archetype: null,  // NULL = universal
            category: 'staple',
          );
          totalInserted += result['inserted']!;
          totalUpdated += result['updated']!;
          print('     ✓ ${universalStaples.length} staples universais processados');
        }

        // 2. Buscar staples por arquétipo
        for (final archetype in archetypeQueries.keys) {
          print('  📥 Buscando staples para arquétipo: $archetype...');
          
          final query = '${supportedFormats[format]} ${archetypeQueries[archetype]!['query']} -is:banned';
          final archetypeCards = await _fetchScryfallCards(query: query, limit: 50);
          
          if (archetypeCards.isNotEmpty) {
            final result = await _upsertStaples(
              conn: session,
              cards: archetypeCards,
              format: format,
              archetype: archetype,
              category: archetype, // Usa o arquétipo como categoria
            );
            totalInserted += result['inserted']!;
            totalUpdated += result['updated']!;
            print('     ✓ ${archetypeCards.length} staples de $archetype processados');
          }
          
          // Rate limiting para Scryfall API (máximo 10 req/s)
          await Future.delayed(Duration(milliseconds: 150));
        }

        // 3. Buscar staples por cor (para Commander especialmente)
        if (format == 'commander') {
          for (final color in colorCombinations.where((c) => c.isNotEmpty)) {
            print('  📥 Buscando staples para cor: $color...');
            
            final colorQuery = 'format:commander id=$color -is:banned';
            final colorCards = await _fetchScryfallCards(query: colorQuery, limit: 30);
            
            if (colorCards.isNotEmpty) {
              final result = await _upsertStaples(
                conn: session,
                cards: colorCards,
                format: format,
                archetype: null,
                category: 'color_staple',
                colorIdentity: color.split(''),
              );
              totalInserted += result['inserted']!;
              totalUpdated += result['updated']!;
            }
            
            await Future.delayed(Duration(milliseconds: 150));
          }
          print('     ✓ Staples por cor processados');
        }

        // 4. Verificar e marcar cartas banidas
        print('  🚫 Verificando cartas banidas...');
        totalBanned = await _syncBannedCards(session, format);
        print('     ✓ $totalBanned cartas marcadas como banidas');

        // 5. Atualizar log de sincronização
        await _updateSyncLog(
          conn: session,
          syncLogId: syncLogId,
          inserted: totalInserted,
          updated: totalUpdated,
          deleted: totalBanned,
          status: 'success',
        );

        print('');
        print('  ═══════════════════════════════════════════════════');
        print('  ✅ SINCRONIZAÇÃO COMPLETA PARA $format');
        print('     📊 Inseridos: $totalInserted | Atualizados: $totalUpdated | Banidos: $totalBanned');
        print('  ═══════════════════════════════════════════════════');
      });
    }

    print('\n🎉 Sincronização finalizada com sucesso!');

  } catch (e, stack) {
    print('\n❌ ERRO CRÍTICO: $e');
    print(stack);
    exit(1);
  } finally {
    await conn.close();
  }
}

/// Busca cartas no Scryfall ordenadas por EDHREC rank
Future<List<Map<String, dynamic>>> _fetchScryfallCards({
  required String query,
  int limit = 50,
}) async {
  final cards = <Map<String, dynamic>>[];
  
  try {
    final uri = Uri.https('api.scryfall.com', '/cards/search', {
      'q': query,
      'order': 'edhrec', // Crucial: Ordena por popularidade
      'unique': 'cards',
    });

    var response = await http.get(uri);
    
    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      var dataCards = data['data'] as List;
      
      for (final card in dataCards.take(limit)) {
        cards.add({
          'name': card['name'] as String,
          'scryfall_id': card['id'] as String,
          'color_identity': (card['color_identity'] as List?)?.cast<String>() ?? [],
          'edhrec_rank': card['edhrec_rank'] as int? ?? 99999,
          'type_line': card['type_line'] as String? ?? '',
          'oracle_text': card['oracle_text'] as String? ?? '',
        });
      }
      
      // Se precisar de mais cartas e houver próxima página
      while (data['has_more'] == true && cards.length < limit) {
        await Future.delayed(Duration(milliseconds: 100)); // Rate limit
        
        response = await http.get(Uri.parse(data['next_page']));
        if (response.statusCode != 200) break;
        
        data = jsonDecode(response.body);
        dataCards = data['data'] as List;
        
        for (final card in dataCards.take(limit - cards.length)) {
          cards.add({
            'name': card['name'] as String,
            'scryfall_id': card['id'] as String,
            'color_identity': (card['color_identity'] as List?)?.cast<String>() ?? [],
            'edhrec_rank': card['edhrec_rank'] as int? ?? 99999,
            'type_line': card['type_line'] as String? ?? '',
            'oracle_text': card['oracle_text'] as String? ?? '',
          });
        }
      }
    } else if (response.statusCode == 404) {
      // Nenhuma carta encontrada para essa query (normal)
      return [];
    } else {
      print('     ⚠️ Erro Scryfall ($query): ${response.statusCode}');
    }
  } catch (e) {
    print('     ⚠️ Erro ao buscar Scryfall: $e');
  }
  
  return cards;
}

/// Insere ou atualiza staples no banco de dados
/// Batch UPSERT: 1 query multi-VALUES por lote (antes: N queries 1-a-1)
Future<Map<String, int>> _upsertStaples({
  required Session conn,
  required List<Map<String, dynamic>> cards,
  required String format,
  required String? archetype,
  required String category,
  List<String>? colorIdentity,
}) async {
  if (cards.isEmpty) return {'inserted': 0, 'updated': 0};

  int inserted = 0;
  int updated = 0;

  // Processa em lotes de 50 para não estourar parâmetros
  const batchSize = 50;
  for (var i = 0; i < cards.length; i += batchSize) {
    final end = (i + batchSize > cards.length) ? cards.length : i + batchSize;
    final batch = cards.sublist(i, end);

    final values = <String>[];
    final params = <String, dynamic>{};

    for (var j = 0; j < batch.length; j++) {
      final card = batch[j];
      values.add(
        '(@name$j, @format$j, @arch$j, @colors$j, @rank$j, @cat$j, @sid$j::uuid, FALSE, CURRENT_TIMESTAMP)',
      );
      params['name$j'] = card['name'];
      params['format$j'] = format;
      params['arch$j'] = archetype;
      params['colors$j'] = TypedValue(
          Type.textArray, colorIdentity ?? card['color_identity'] ?? []);
      params['rank$j'] = card['edhrec_rank'];
      params['cat$j'] = category;
      params['sid$j'] = card['scryfall_id'];
    }

    try {
      final result = await conn.execute(
        Sql.named('''
          INSERT INTO format_staples 
            (card_name, format, archetype, color_identity, edhrec_rank, category, scryfall_id, is_banned, last_synced_at)
          VALUES ${values.join(', ')}
          ON CONFLICT (card_name, format, archetype) 
          DO UPDATE SET 
            edhrec_rank = EXCLUDED.edhrec_rank,
            color_identity = EXCLUDED.color_identity,
            scryfall_id = EXCLUDED.scryfall_id,
            is_banned = FALSE,
            last_synced_at = CURRENT_TIMESTAMP
          RETURNING (xmax = 0) AS inserted
        '''),
        parameters: params,
      );

      for (final row in result) {
        if (row[0] == true) {
          inserted++;
        } else {
          updated++;
        }
      }
    } catch (e) {
      // Fallback: se batch falhar, tenta individualmente
      for (final card in batch) {
        try {
          final result = await conn.execute(
            Sql.named('''
              INSERT INTO format_staples 
                (card_name, format, archetype, color_identity, edhrec_rank, category, scryfall_id, is_banned, last_synced_at)
              VALUES 
                (@name, @format, @archetype, @colors, @rank, @category, @scryfall_id::uuid, FALSE, CURRENT_TIMESTAMP)
              ON CONFLICT (card_name, format, archetype) 
              DO UPDATE SET 
                edhrec_rank = @rank,
                color_identity = @colors,
                scryfall_id = @scryfall_id::uuid,
                is_banned = FALSE,
                last_synced_at = CURRENT_TIMESTAMP
              RETURNING (xmax = 0) AS inserted
            '''),
            parameters: {
              'name': card['name'],
              'format': format,
              'archetype': archetype,
              'colors': TypedValue(Type.textArray,
                  colorIdentity ?? card['color_identity'] ?? []),
              'rank': card['edhrec_rank'],
              'category': category,
              'scryfall_id': card['scryfall_id'],
            },
          );
          if (result.isNotEmpty && result.first[0] == true) {
            inserted++;
          } else {
            updated++;
          }
        } catch (_) {}
      }
    }
  }

  return {'inserted': inserted, 'updated': updated};
}

/// Verifica cartas banidas e marca no banco (batch UPDATE)
Future<int> _syncBannedCards(Session conn, String format) async {
  int bannedCount = 0;

  try {
    // Busca a lista de banidas diretamente do Scryfall
    final bannedCards = await _fetchScryfallCards(
      query: 'format:$format is:banned',
      limit: 200,
    );

    // Batch UPDATE: 1 query com IN(...) ao invés de N queries 1-a-1
    if (bannedCards.isNotEmpty) {
      final nameParams = <String>[];
      final params = <String, dynamic>{'format': format};
      for (var i = 0; i < bannedCards.length; i++) {
        nameParams.add('@name$i');
        params['name$i'] = bannedCards[i]['name'];
      }

      final result = await conn.execute(
        Sql.named('''
          UPDATE format_staples 
          SET is_banned = TRUE, last_synced_at = CURRENT_TIMESTAMP
          WHERE card_name IN (${nameParams.join(', ')}) AND format = @format
        '''),
        parameters: params,
      );
      bannedCount = result.affectedRows;
    }

    // Também atualiza a tabela card_legalities se existir dados
    await conn.execute(
      Sql.named('''
        UPDATE format_staples fs
        SET is_banned = TRUE, last_synced_at = CURRENT_TIMESTAMP
        FROM card_legalities cl
        JOIN cards c ON c.id = cl.card_id
        WHERE fs.card_name = c.name 
          AND fs.format = cl.format
          AND cl.status = 'banned'
          AND fs.is_banned = FALSE
      '''),
    );

  } catch (e) {
    print('     ⚠️ Erro ao sincronizar banidas: $e');
  }

  return bannedCount;
}

/// Cria registro de log de sincronização
Future<String> _createSyncLog(Session conn, String format) async {
  final result = await conn.execute(
    Sql.named('''
      INSERT INTO sync_log (sync_type, format, status, started_at)
      VALUES ('staples', @format, 'running', CURRENT_TIMESTAMP)
      RETURNING id
    '''),
    parameters: {'format': format},
  );
  
  return result.first[0] as String;
}

/// Atualiza registro de log de sincronização
Future<void> _updateSyncLog({
  required Session conn,
  required String syncLogId,
  required int inserted,
  required int updated,
  required int deleted,
  required String status,
  String? errorMessage,
}) async {
  await conn.execute(
    Sql.named('''
      UPDATE sync_log 
      SET records_inserted = @inserted,
          records_updated = @updated,
          records_deleted = @deleted,
          status = @status,
          error_message = @error,
          finished_at = CURRENT_TIMESTAMP
      WHERE id = @id::uuid
    '''),
    parameters: {
      'id': syncLogId,
      'inserted': inserted,
      'updated': updated,
      'deleted': deleted,
      'status': status,
      'error': errorMessage,
    },
  );
}
