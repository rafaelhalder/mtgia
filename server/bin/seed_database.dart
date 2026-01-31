import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';
import '../lib/database.dart';

/// URL do arquivo AtomicCards.json do MTGJSON
const mtgJsonUrl = 'https://mtgjson.com/api/v5/AtomicCards.json';

Future<void> main() async {
  final db = Database();
  await db.connect();
  final conn = db.connection;

  try {
    print('Iniciando o processo de seed...');
    
    // 1. Baixar o JSON
    final jsonFile = await _downloadJson();
    
    // 2. Ler e Processar o JSON
    print('Lendo arquivo JSON (isso pode levar um momento)...');
    final content = await jsonFile.readAsString();
    final Map<String, dynamic> data = jsonDecode(content);
    
    // O JSON do AtomicCards tem a estrutura: { "data": { "CardName": [ ... ] }, "meta": ... }
    final Map<String, dynamic> cardsMap = data['data'];
    
    print('Encontradas ${cardsMap.length} cartas únicas no JSON.');
    
    // 3. Inserir no Banco usando uma conexão do pool
    await conn.run((connection) async {
      await _processAndInsertCards(connection, cardsMap);
    });
    
  } catch (e) {
    print('Erro fatal no seed: $e');
  } finally {
    await conn.close();
    // Limpeza do arquivo temporário
    // if (await File('AtomicCards.json').exists()) {
    //   await File('AtomicCards.json').delete();
    // }
  }
}

Future<File> _downloadJson() async {
  final file = File('AtomicCards.json');
  if (await file.exists()) {
    print('Arquivo AtomicCards.json já existe. Usando cache local.');
    return file;
  }

  print('Baixando $mtgJsonUrl ...');
  final response = await http.get(Uri.parse(mtgJsonUrl));
  
  if (response.statusCode == 200) {
    await file.writeAsBytes(response.bodyBytes);
    print('Download concluído!');
    return file;
  } else {
    throw Exception('Falha ao baixar o JSON: ${response.statusCode}');
  }
}

Future<void> _processAndInsertCards(Session conn, Map<String, dynamic> cardsMap) async {
  print('Iniciando processamento e inserção...');
  
  final batchSize = 500;
  var batch = <List<dynamic>>[];
  var count = 0;

  // Prepara a query de inserção
  // Usamos ON CONFLICT para evitar duplicatas se rodarmos o seed de novo
  final sql = '''
    INSERT INTO cards (
      scryfall_id, name, mana_cost, type_line, oracle_text, colors, image_url, set_code, rarity
    ) VALUES (
      \$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9
    )
    ON CONFLICT (scryfall_id) DO UPDATE SET
      name = EXCLUDED.name,
      image_url = EXCLUDED.image_url;
  ''';

  for (final entry in cardsMap.entries) {
    final cardName = entry.key;
    final cardList = entry.value as List;

    // AtomicCards pode ter várias entradas para a mesma carta (variações).
    // Vamos pegar a primeira que tenha um scryfallOracleId válido.
    for (final cardData in cardList) {
      final identifiers = cardData['identifiers'] as Map<String, dynamic>?;
      // AtomicCards usa scryfallOracleId, pois representa a carta abstrata
      final scryfallId = identifiers?['scryfallOracleId'] as String?;

      if (scryfallId == null) continue;

      // Extração de dados
      final name = cardData['name'] ?? cardName;
      final manaCost = cardData['manaCost'];
      final typeLine = cardData['type'];
      final oracleText = cardData['text'];
      final colors = cardData['colors'] as List?;
      
      final setCode = (cardData['printings'] as List?)?.firstOrNull?.toString();
      final rarity = cardData['rarity'];

      // Construindo a URL da imagem usando o endpoint "named" da Scryfall com set específico
      final encodedName = Uri.encodeQueryComponent(name);
      final setParam = (setCode != null && setCode.isNotEmpty) ? '&set=$setCode' : '';
      final imageUrl = 'https://api.scryfall.com/cards/named?exact=$encodedName$setParam&format=image';

      batch.add([
        scryfallId,
        name,
        manaCost,
        typeLine,
        oracleText,
        colors ?? [],
        imageUrl,
        setCode,
        rarity
      ]);

      count++;
      
      if (batch.length >= batchSize) {
        await _insertBatch(conn, sql, batch);
        batch.clear();
        print('Processadas $count cartas...');
      }

      break; 
    }
  }

  // Insere o restante
  if (batch.isNotEmpty) {
    await _insertBatch(conn, sql, batch);
  }

  print('Seed concluído! Total de $count cartas inseridas/atualizadas.');
}

Future<void> _insertBatch(Session conn, String sql, List<List<dynamic>> batch) async {
  final stmt = await conn.prepare(sql);
  try {
    for (final row in batch) {
      await stmt.run([
        row[0], // scryfall_id
        row[1], // name
        row[2], // mana_cost
        row[3], // type_line
        row[4], // oracle_text
        row[5], // colors
        row[6], // image_url
        row[7], // set_code
        row[8], // rarity
      ]);
    }
  } finally {
    await stmt.dispose();
  }
}
