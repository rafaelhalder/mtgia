/// Script para corrigir URLs de imagem de cartas existentes.
///
/// Problema: URLs antigas usam formato `/cards/named?exact=...` que falha
/// para cartas com nomes especiais (vírgulas, apóstrofos, etc).
///
/// Solução: Buscar o scryfallId real via Scryfall API e atualizar para
/// formato direto `/cards/{id}?format=image`.
///
/// Uso:
///   dart run bin/fix_image_urls.dart [--dry-run] [--limit=N] [--batch-size=N]
///
/// Flags:
///   --dry-run     Simula sem salvar alterações
///   --limit=N     Processa no máximo N cartas (default: todas)
///   --batch-size=N Quantas cartas processar por batch (default: 50)
///   --set=CODE    Processa apenas cartas de um set específico
///   --broken-only Processa apenas cartas com URLs quebradas (named?exact=)
library;

import 'dart:convert';
import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

// Rate limit: Scryfall permite 10 req/s, usamos 5 para segurança
const _delayBetweenRequests = Duration(milliseconds: 200);
const _defaultBatchSize = 50;

Future<void> main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final brokenOnly = args.contains('--broken-only');
  final limit = _parseIntArg(args, '--limit');
  final batchSize = _parseIntArg(args, '--batch-size') ?? _defaultBatchSize;
  final setCode = _parseStringArg(args, '--set');

  print('🔧 Fix Card Image URLs');
  print('   Dry run: $dryRun');
  print('   Broken only: $brokenOnly');
  print('   Limit: ${limit ?? "all"}');
  print('   Batch size: $batchSize');
  if (setCode != null) print('   Set: $setCode');
  print('');

  // Carrega .env
  final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();

  final dbUrl = env['DATABASE_URL'] ?? '';
  if (dbUrl.isEmpty) {
    print('❌ DATABASE_URL não configurada');
    print('   Certifique-se de ter um arquivo .env com DATABASE_URL');
    exit(1);
  }

  // Conecta ao banco
  final endpoint = Endpoint(
    host: _parseHost(dbUrl),
    port: _parsePort(dbUrl),
    database: _parseDatabase(dbUrl),
    username: _parseUsername(dbUrl),
    password: _parsePassword(dbUrl),
  );

  final pool = Pool.withEndpoints(
    [endpoint],
    settings: PoolSettings(
      maxConnectionCount: 3,
      sslMode: SslMode.disable,
    ),
  );

  try {
    await pool.execute('SELECT 1');
    print('✅ Conectado ao banco\n');

    // Busca cartas que precisam de correção
    final cards = await _fetchCardsToFix(
      pool,
      brokenOnly: brokenOnly,
      setCode: setCode,
      limit: limit,
    );

    print('📊 ${cards.length} cartas para processar\n');

    if (cards.isEmpty) {
      print('✅ Nenhuma carta precisa de correção!');
      return;
    }

    var fixed = 0;
    var skipped = 0;
    var errors = 0;

    for (var i = 0; i < cards.length; i += batchSize) {
      final batch = cards.skip(i).take(batchSize).toList();
      print('📦 Batch ${(i ~/ batchSize) + 1}/${(cards.length / batchSize).ceil()} '
          '(${batch.length} cartas)');

      for (final card in batch) {
        final cardId = card['id'] as String;
        final cardName = card['name'] as String;
        final setCode = card['set_code'] as String?;
        final currentUrl = card['image_url'] as String?;

        // Se já tem URL direta do Scryfall CDN, pula
        if (currentUrl != null && 
            (currentUrl.contains('cards.scryfall.io') ||
             currentUrl.contains('format=image&version='))) {
          skipped++;
          continue;
        }

        try {
          final newUrl = await _fetchCorrectImageUrl(cardName, setCode);
          
          if (newUrl == null) {
            print('  ⚠️ $cardName ($setCode): não encontrada no Scryfall');
            skipped++;
            continue;
          }

          if (newUrl == currentUrl) {
            skipped++;
            continue;
          }

          if (!dryRun) {
            await pool.execute(
              Sql.named('UPDATE cards SET image_url = @url WHERE id = @id::uuid'),
              parameters: {'url': newUrl, 'id': cardId},
            );
          }

          fixed++;
          print('  ✅ $cardName ($setCode)');
          print('     Old: ${currentUrl?.substring(0, 60) ?? "(null)"}...');
          print('     New: ${newUrl.substring(0, 60)}...');
        } catch (e) {
          errors++;
          print('  ❌ $cardName ($setCode): $e');
        }

        // Rate limiting
        await Future.delayed(_delayBetweenRequests);
      }
    }

    print('\n📊 Resultado:');
    print('   ✅ Corrigidas: $fixed');
    print('   ⏭️ Puladas: $skipped');
    print('   ❌ Erros: $errors');
    
    if (dryRun) {
      print('\n⚠️ Modo dry-run: nenhuma alteração foi salva');
    }
  } finally {
    await pool.close();
  }
}

Future<List<Map<String, dynamic>>> _fetchCardsToFix(
  Pool pool, {
  bool brokenOnly = false,
  String? setCode,
  int? limit,
}) async {
  var query = 'SELECT id::text, name, set_code, image_url FROM cards WHERE 1=1';
  final params = <String, Object?>{};

  if (brokenOnly) {
    query += " AND (image_url LIKE '%/cards/named?exact=%' OR image_url IS NULL)";
  }

  if (setCode != null) {
    query += ' AND set_code = @set_code';
    params['set_code'] = setCode;
  }

  query += ' ORDER BY name';

  if (limit != null) {
    query += ' LIMIT @limit';
    params['limit'] = limit;
  }

  final result = await pool.execute(Sql.named(query), parameters: params);
  return result.map((row) => row.toColumnMap()).toList();
}

Future<String?> _fetchCorrectImageUrl(String cardName, String? setCode) async {
  // Primeiro tenta busca exata com set
  final encodedName = Uri.encodeQueryComponent(cardName);
  var url = 'https://api.scryfall.com/cards/named?exact=$encodedName';
  if (setCode != null && setCode.isNotEmpty) {
    url += '&set=$setCode';
  }

  try {
    var response = await http.get(
      Uri.parse(url),
      headers: {'Accept': 'application/json', 'User-Agent': 'ManaLoom/1.0'},
    );

    // Se não encontrou com set, tenta sem set
    if (response.statusCode == 404 && setCode != null) {
      url = 'https://api.scryfall.com/cards/named?exact=$encodedName';
      response = await http.get(
        Uri.parse(url),
        headers: {'Accept': 'application/json', 'User-Agent': 'ManaLoom/1.0'},
      );
    }

    // Se ainda não encontrou, tenta fuzzy
    if (response.statusCode == 404) {
      url = 'https://api.scryfall.com/cards/named?fuzzy=$encodedName';
      response = await http.get(
        Uri.parse(url),
        headers: {'Accept': 'application/json', 'User-Agent': 'ManaLoom/1.0'},
      );
    }

    if (response.statusCode != 200) {
      return null;
    }

    final card = jsonDecode(response.body) as Map<String, dynamic>;
    
    // Extrai URL direta da imagem
    final imageUris = card['image_uris'] as Map<String, dynamic>?;
    if (imageUris != null && imageUris['normal'] != null) {
      return imageUris['normal'].toString();
    }

    // Para double-faced cards
    final cardFaces = card['card_faces'] as List?;
    if (cardFaces != null && cardFaces.isNotEmpty) {
      final firstFace = cardFaces[0] as Map<String, dynamic>;
      final faceImageUris = firstFace['image_uris'] as Map<String, dynamic>?;
      if (faceImageUris != null && faceImageUris['normal'] != null) {
        return faceImageUris['normal'].toString();
      }
    }

    // Fallback: usa ID da carta
    final cardId = card['id']?.toString();
    if (cardId != null && cardId.isNotEmpty) {
      return 'https://api.scryfall.com/cards/$cardId?format=image&version=normal';
    }

    return null;
  } catch (e) {
    print('  [API Error] $cardName: $e');
    return null;
  }
}

int? _parseIntArg(List<String> args, String prefix) {
  for (final arg in args) {
    if (arg.startsWith('$prefix=')) {
      return int.tryParse(arg.split('=').last);
    }
  }
  return null;
}

String? _parseStringArg(List<String> args, String prefix) {
  for (final arg in args) {
    if (arg.startsWith('$prefix=')) {
      return arg.split('=').last;
    }
  }
  return null;
}

// Parse helpers para DATABASE_URL
String _parseHost(String url) {
  final uri = Uri.parse(url);
  return uri.host;
}

int _parsePort(String url) {
  final uri = Uri.parse(url);
  return uri.port != 0 ? uri.port : 5432;
}

String _parseDatabase(String url) {
  final uri = Uri.parse(url);
  return uri.path.replaceFirst('/', '');
}

String _parseUsername(String url) {
  final uri = Uri.parse(url);
  return uri.userInfo.split(':').first;
}

String _parsePassword(String url) {
  final uri = Uri.parse(url);
  final parts = uri.userInfo.split(':');
  return parts.length > 1 ? parts.skip(1).join(':') : '';
}
