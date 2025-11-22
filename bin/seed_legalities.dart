import 'dart:convert';
import 'dart:io';
import '../lib/database.dart';
import 'package:postgres/postgres.dart';

/// Este script lê o arquivo AtomicCards.json, encontra as cartas correspondentes
/// no banco de dados e popula a tabela `card_legalities` com os dados de
/// legalidade de cada carta para cada formato.
Future<void> main() async {
  print('Iniciando script para popular a tabela de legalidades...');

  final db = Database();
  await db.connect();
  final conn = db.connection;

  try {
    // 1. Carregar o arquivo JSON
    final jsonFile = File('AtomicCards.json');
    if (!await jsonFile.exists()) {
      print('Erro: Arquivo AtomicCards.json não encontrado. Execute o script de seed de cartas primeiro.');
      return;
    }
    final jsonString = await jsonFile.readAsString();
    final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
    final allCardsData = (jsonMap['data'] as Map<String, dynamic>).values.toList();

    print('Arquivo JSON carregado. ${allCardsData.length} entradas de cartas encontradas.');
    print('Iniciando a inserção de legalidades...');

    var legalitiesAdded = 0;
    var cardsProcessed = 0;

    // 2. Preparar a query de inserção
    final insertSql = Sql.named(
      'INSERT INTO card_legalities (card_id, format, status) VALUES (@cardId, @format, @status) ON CONFLICT (card_id, format) DO NOTHING',
    );

    // 3. Iterar sobre cada carta do JSON
    for (final cardPrintings in allCardsData) {
      final cardList = cardPrintings as List<dynamic>;
      if (cardList.isEmpty) {
        continue;
      }
      final firstCard = cardList.first as Map<String, dynamic>;

      final identifiers = firstCard['identifiers'] as Map<String, dynamic>?;
      final scryfallId = identifiers?['scryfallOracleId'] as String?;
      final legalities = firstCard['legalities'] as Map<String, dynamic>?;

      if (scryfallId == null || legalities == null) {
        continue;
      }

      // 4. Encontrar o ID da carta no nosso banco de dados, fazendo o cast para UUID
      final cardResult = await conn.execute(
        Sql.named('SELECT id FROM cards WHERE scryfall_id = @scryfallId::uuid'),
        parameters: {'scryfallId': scryfallId},
      );

      if (cardResult.isEmpty) {
        // A carta não está no nosso banco, podemos pular
        continue;
      }

      final cardId = cardResult.first.toColumnMap()['id'];

      // 5. Inserir os dados de legalidade
      for (final entry in legalities.entries) {
        final format = entry.key;
        final status = entry.value as String;

        await conn.execute(insertSql, parameters: {
          'cardId': cardId,
          'format': format,
          'status': status.toLowerCase(), // 'Legal' -> 'legal'
        });
        legalitiesAdded++;
      }
      
      cardsProcessed++;
      if (cardsProcessed % 1000 == 0) {
        print('  ... $cardsProcessed / ${allCardsData.length} cartas processadas, $legalitiesAdded legalidades adicionadas.');
      }
    }

    print('\nProcesso concluído!');
    print('Total de cartas processadas: $cardsProcessed');
    print('Total de entradas de legalidade adicionadas/verificadas: $legalitiesAdded');

  } catch (e) {
    print('Ocorreu um erro: $e');
  } finally {
    await db.close();
    print('Conexão com o banco de dados fechada.');
  }
}
