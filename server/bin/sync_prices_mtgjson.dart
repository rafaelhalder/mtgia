// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

/// Sincroniza preços USD das cartas via MTGJSON (AllPricesToday).
///
/// MTGJSON oferece preços de múltiplas fontes:
/// - tcgplayer (USD)
/// - cardkingdom (USD)
/// - cardmarket (EUR)
/// - cardsphere (USD)
/// - cardhoarder (MTGO tix)
///
/// Usa o UUID do MTGJSON para fazer o match com nossas cartas.
/// O nosso `cards.scryfall_id` guarda o `oracle_id`, mas podemos
/// fazer match pelo `name` + `set_code` se necessário.
///
/// Uso:
///   dart run bin/sync_prices_mtgjson.dart
///   dart run bin/sync_prices_mtgjson.dart --limit=5000
///   dart run bin/sync_prices_mtgjson.dart --dry-run
Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln('''
sync_prices_mtgjson.dart - Atualiza preços via MTGJSON (AllPricesToday)

Uso:
  dart run bin/sync_prices_mtgjson.dart

Opções:
  --limit=<N>   Limite de cartas a atualizar (default: sem limite)
  --dry-run     Não grava no banco (só mostra estatísticas)
  --help        Mostra esta ajuda

Fontes de preço (prioridade):
  1. tcgplayer.retail.normal (USD)
  2. cardkingdom.retail.normal (USD)
  3. tcgplayer.retail.foil (USD)
  4. cardkingdom.retail.foil (USD)
''');
    return;
  }

  final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();
  final connection = await Connection.open(
    Endpoint(
      host: env['DB_HOST'] ?? 'localhost',
      port: int.tryParse(env['DB_PORT'] ?? '5432') ?? 5432,
      database: env['DB_NAME'] ?? 'mtg_builder',
      username: env['DB_USER'] ?? 'postgres',
      password: env['DB_PASS'],
    ),
    settings: ConnectionSettings(sslMode: SslMode.disable),
  );

  final limit = _parseIntArg(args, '--limit=');
  final dryRun = args.contains('--dry-run');

  stdout.writeln('💲 Sync de preços via MTGJSON (limit=${limit ?? "all"}, dryRun=$dryRun)');
  stdout.writeln('📥 Baixando AllPricesToday.json...');

  try {
    // 1) Baixa o JSON de preços do MTGJSON
    final pricesUrl = Uri.parse('https://mtgjson.com/api/v5/AllPricesToday.json');
    final response = await http.get(pricesUrl, headers: {
      'Accept': 'application/json',
      'User-Agent': 'ManaLoom/1.0',
    });

    if (response.statusCode != 200) {
      stderr.writeln('❌ Erro ao baixar AllPricesToday: ${response.statusCode}');
      return;
    }

    final jsonData = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final data = jsonData['data'] as Map<String, dynamic>? ?? {};

    stdout.writeln('✅ Baixado! ${data.length} UUIDs com preços disponíveis.');

    // 2) Carrega mapeamento das nossas cartas (name+set → id)
    stdout.writeln('📊 Carregando cartas do banco...');
    
    final cardsResult = await connection.execute('''
      SELECT id::text, name, set_code
      FROM cards
      WHERE set_code IS NOT NULL
    ''');

    // Mapa: "name|set_code" → card_id
    final cardMap = <String, String>{};
    for (final row in cardsResult) {
      final id = row[0] as String;
      final name = (row[1] as String?)?.toLowerCase().trim() ?? '';
      final setCode = (row[2] as String?)?.toLowerCase().trim() ?? '';
      if (name.isNotEmpty && setCode.isNotEmpty) {
        cardMap['$name|$setCode'] = id;
      }
    }

    stdout.writeln('📊 ${cardMap.length} cartas no banco com set_code.');

    // 3) Processa preços do MTGJSON
    // O formato é: data[uuid] = { paper: { tcgplayer: { retail: { normal: { date: price } } } } }
    var updated = 0;
    var notFound = 0;
    var noPrice = 0;

    // MTGJSON também fornece um mapeamento UUID → card info em AllIdentifiers
    // Mas AllPricesToday não inclui nome/set diretamente.
    // Vamos baixar o mapeamento de identifiers primeiro.
    
    stdout.writeln('📥 Baixando AllIdentifiers.json (pode demorar)...');
    
    final identifiersUrl = Uri.parse('https://mtgjson.com/api/v5/AllIdentifiers.json');
    final identResponse = await http.get(identifiersUrl, headers: {
      'Accept': 'application/json',
      'User-Agent': 'ManaLoom/1.0',
    });

    if (identResponse.statusCode != 200) {
      stderr.writeln('❌ Erro ao baixar AllIdentifiers: ${identResponse.statusCode}');
      stderr.writeln('   Tentando método alternativo (por set)...');
      
      // Método alternativo: usar scryfall_id (oracle_id) se disponível
      await _syncViaOracleId(connection, data, dryRun, limit);
      return;
    }

    final identJson = jsonDecode(utf8.decode(identResponse.bodyBytes)) as Map<String, dynamic>;
    final identData = identJson['data'] as Map<String, dynamic>? ?? {};

    stdout.writeln('✅ AllIdentifiers baixado! ${identData.length} cards.');

    // Mapeia UUID → (name, setCode)
    final uuidToCard = <String, (String name, String setCode)>{};
    for (final entry in identData.entries) {
      final uuid = entry.key;
      final cardInfo = entry.value as Map<String, dynamic>? ?? {};
      final name = (cardInfo['name'] as String?)?.toLowerCase().trim() ?? '';
      final setCode = (cardInfo['setCode'] as String?)?.toLowerCase().trim() ?? '';
      if (name.isNotEmpty && setCode.isNotEmpty) {
        uuidToCard[uuid] = (name, setCode);
      }
    }

    stdout.writeln('📊 ${uuidToCard.length} UUIDs mapeados para name+set.');
    stdout.writeln('🔄 Processando preços...');

    var processed = 0;
    for (final entry in data.entries) {
      if (limit != null && updated >= limit) break;

      final uuid = entry.key;
      final priceData = entry.value as Map<String, dynamic>? ?? {};

      // Encontra a carta no nosso banco
      final cardInfo = uuidToCard[uuid];
      if (cardInfo == null) {
        notFound++;
        continue;
      }

      final (name, setCode) = cardInfo;
      final key = '$name|$setCode';
      final cardId = cardMap[key];

      if (cardId == null) {
        notFound++;
        continue;
      }

      // Extrai preço USD (prioridade: tcgplayer > cardkingdom)
      final price = _extractUsdPrice(priceData);
      if (price == null) {
        noPrice++;
        continue;
      }

      if (!dryRun) {
        await connection.execute(
          Sql.named('''
            UPDATE cards
            SET price = @price,
                price_updated_at = NOW()
            WHERE id = @id
          '''),
          parameters: {'price': price, 'id': cardId},
        );
      }
      updated++;

      processed++;
      if (processed % 5000 == 0) {
        stdout.writeln('   Processado: $processed...');
      }
    }

    stdout.writeln('');
    stdout.writeln('✅ Concluído!');
    stdout.writeln('   - Atualizados: $updated');
    stdout.writeln('   - Não encontrados no banco: $notFound');
    stdout.writeln('   - Sem preço USD: $noPrice');

  } catch (e, st) {
    stderr.writeln('❌ Erro: $e');
    stderr.writeln(st);
  } finally {
    await connection.close();
  }
}

/// Extrai preço USD do objeto de preços do MTGJSON.
/// Prioridade: tcgplayer normal > cardkingdom normal > tcgplayer foil > cardkingdom foil
double? _extractUsdPrice(Map<String, dynamic> priceData) {
  final paper = priceData['paper'] as Map<String, dynamic>? ?? {};

  // Tenta tcgplayer primeiro
  final tcg = paper['tcgplayer'] as Map<String, dynamic>? ?? {};
  final tcgRetail = tcg['retail'] as Map<String, dynamic>? ?? {};

  // Normal (non-foil)
  final tcgNormal = tcgRetail['normal'] as Map<String, dynamic>? ?? {};
  if (tcgNormal.isNotEmpty) {
    // Pega o preço mais recente (última data)
    final price = _getLatestPrice(tcgNormal);
    if (price != null) return price;
  }

  // Tenta cardkingdom
  final ck = paper['cardkingdom'] as Map<String, dynamic>? ?? {};
  final ckRetail = ck['retail'] as Map<String, dynamic>? ?? {};

  final ckNormal = ckRetail['normal'] as Map<String, dynamic>? ?? {};
  if (ckNormal.isNotEmpty) {
    final price = _getLatestPrice(ckNormal);
    if (price != null) return price;
  }

  // Fallback: foil prices
  final tcgFoil = tcgRetail['foil'] as Map<String, dynamic>? ?? {};
  if (tcgFoil.isNotEmpty) {
    final price = _getLatestPrice(tcgFoil);
    if (price != null) return price;
  }

  final ckFoil = ckRetail['foil'] as Map<String, dynamic>? ?? {};
  if (ckFoil.isNotEmpty) {
    final price = _getLatestPrice(ckFoil);
    if (price != null) return price;
  }

  return null;
}

/// Pega o preço mais recente de um mapa date → price
double? _getLatestPrice(Map<String, dynamic> pricesByDate) {
  if (pricesByDate.isEmpty) return null;

  // Ordena por data (mais recente primeiro)
  final sorted = pricesByDate.entries.toList()
    ..sort((a, b) => b.key.compareTo(a.key));

  final value = sorted.first.value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

/// Método alternativo: sincroniza usando oracle_id (scryfall_id) ao invés de UUID do MTGJSON.
/// Menos preciso mas funciona sem baixar AllIdentifiers.
Future<void> _syncViaOracleId(
  Connection connection,
  Map<String, dynamic> priceData,
  bool dryRun,
  int? limit,
) async {
  stdout.writeln('⚠️  Usando método alternativo (menos preciso)...');
  // Este método requer um mapeamento adicional que não está disponível
  // diretamente no AllPricesToday. Seria necessário usar a API do Scryfall
  // para converter oracle_id → MTGJSON UUID.
  stdout.writeln('❌ Método alternativo não implementado. Use Scryfall sync.');
}

int? _parseIntArg(List<String> args, String prefix) {
  for (final a in args) {
    if (a.startsWith(prefix)) {
      final v = a.substring(prefix.length).trim();
      return int.tryParse(v);
    }
  }
  return null;
}
