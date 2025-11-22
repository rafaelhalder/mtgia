import 'dart:convert';
import 'dart:io';
import '../lib/database.dart';
import 'package:postgres/postgres.dart';

Future<void> main() async {
  print('Iniciando script OTIMIZADO de legalidades...');
  final db = Database();
  await db.connect();
  final conn = db.connection;

  try {
    // 1. Carregar Mapa de IDs (Cache em Memória)
    print('Carregando mapa de IDs do banco de dados...');
    final result = await conn.execute(Sql.named('SELECT scryfall_id::text, id::text FROM cards'));
    
    final Map<String, String> cardIdMap = {};
    for (final row in result) {
      final scryfallId = row[0] as String;
      final dbId = row[1] as String;
      cardIdMap[scryfallId] = dbId;
    }
    print('Mapa carregado com ${cardIdMap.length} cartas.');

    // 2. Carregar JSON
    final jsonFile = File('AtomicCards.json');
    if (!await jsonFile.exists()) {
      print('Erro: AtomicCards.json não encontrado.');
      return;
    }
    print('Lendo JSON...');
    final jsonString = await jsonFile.readAsString();
    final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
    final allCardsData = (jsonMap['data'] as Map<String, dynamic>).values.toList();

    // 3. Preparar Lotes
    print('Processando dados e inserindo em lotes...');
    
    final batchSize = 2000; // Inserir 2000 linhas por vez
    var valueBuffer = <String>[];
    var totalInserted = 0;

    for (final cardPrintings in allCardsData) {
      final cardList = cardPrintings as List<dynamic>;
      if (cardList.isEmpty) continue;
      
      final firstCard = cardList.first as Map<String, dynamic>;
      final identifiers = firstCard['identifiers'] as Map<String, dynamic>?;
      final scryfallId = identifiers?['scryfallOracleId'] as String?;
      final legalities = firstCard['legalities'] as Map<String, dynamic>?;

      if (scryfallId == null || legalities == null) continue;

      // Busca instantânea na memória
      final dbId = cardIdMap[scryfallId];
      if (dbId == null) continue;

      for (final entry in legalities.entries) {
        final format = entry.key;
        final status = entry.value as String;
        
        // Sanitização básica para SQL string injection (embora os dados sejam confiáveis)
        final safeFormat = format.replaceAll("'", "''");
        final safeStatus = status.toLowerCase().replaceAll("'", "''");
        
        // Adiciona ao buffer: ('uuid', 'format', 'status')
        valueBuffer.add("('$dbId', '$safeFormat', '$safeStatus')");

        if (valueBuffer.length >= batchSize) {
          await _flushBatch(conn, valueBuffer);
          totalInserted += valueBuffer.length;
          valueBuffer.clear();
          stdout.write('\rInseridos: $totalInserted...');
        }
      }
    }

    // Inserir o restante
    if (valueBuffer.isNotEmpty) {
      await _flushBatch(conn, valueBuffer);
      totalInserted += valueBuffer.length;
    }

    print('\n\nSucesso! Total de legalidades inseridas: $totalInserted');

  } catch (e) {
    print('\nErro: $e');
  } finally {
    await db.close();
  }
}

Future<void> _flushBatch(Connection conn, List<String> values) async {
  if (values.isEmpty) return;
  final valuesStr = values.join(',');
  final sql = 'INSERT INTO card_legalities (card_id, format, status) VALUES $valuesStr ON CONFLICT (card_id, format) DO NOTHING';
  await conn.execute(Sql.named(sql));
}
