// ignore_for_file: avoid_print

import 'dart:math' show min;

import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

/// Script para popular a coluna CMC baseado no mana_cost
/// 
/// Uso: dart run bin/populate_cmc.dart
/// 
/// Regras de cálculo de CMC:
/// - Números: somados diretamente ({3} = 3)
/// - Cores: cada símbolo conta como 1 ({W}{U}{B} = 3)
/// - Híbrido: conta como 1 ({W/U} = 1)
/// - Phyrexian: conta como 1 ({W/P} = 1)
/// - X: conta como 0
/// - Terrenos: CMC = 0

void main() async {
  print('🔢 Populando coluna CMC...\n');
  
  final env = DotEnv()..load();

  final connection = await Connection.open(
    Endpoint(
      host: env['DB_HOST'] ?? 'localhost',
      database: env['DB_NAME'] ?? 'mtg_db',
      username: env['DB_USER'] ?? 'postgres',
      password: env['DB_PASS'] ?? 'postgres',
      port: int.parse(env['DB_PORT'] ?? '5432'),
    ),
    settings: ConnectionSettings(sslMode: SslMode.disable),
  );

  try {
    // Busca cartas sem CMC ou com CMC zerado que têm mana_cost
    final cards = await connection.execute('''
      SELECT id, name, mana_cost
      FROM cards
      WHERE mana_cost IS NOT NULL AND mana_cost != ''
    ''');

    print('📊 Total de cartas com mana_cost: ${cards.length}');
    
    // Calcula todos os CMCs em memória
    final cmcData = <(Object id, double cmc)>[];
    var errors = 0;

    for (final row in cards) {
      final id = row[0];
      final name = row[1] as String?;
      final manaCost = row[2] as String?;
      
      if (id == null || manaCost == null || manaCost.isEmpty) continue;
      
      try {
        cmcData.add((id, calculateCmc(manaCost)));
      } catch (e) {
        errors++;
        if (errors <= 10) {
          print('   ⚠️ Erro em "$name" ($manaCost): $e');
        }
      }
    }

    // Batch UPDATE: 1 query por lote de 500 (antes: 33k queries 1-a-1)
    const batchSize = 500;
    var updated = 0;

    for (var i = 0; i < cmcData.length; i += batchSize) {
      final batch = cmcData.sublist(i, min(i + batchSize, cmcData.length));

      final values = <String>[];
      final params = <String, dynamic>{};
      for (var j = 0; j < batch.length; j++) {
        final (id, cmc) = batch[j];
        values.add('(@id$j::uuid, @cmc$j::decimal)');
        params['id$j'] = id;
        params['cmc$j'] = cmc;
      }

      await connection.execute(
        Sql.named('''
          UPDATE cards c SET cmc = v.cmc
          FROM (VALUES ${values.join(', ')}) AS v(id, cmc)
          WHERE c.id = v.id
        '''),
        parameters: params,
      );

      updated += batch.length;
      if (updated % 2000 == 0 || updated == cmcData.length) {
        print('   ✅ $updated/${cmcData.length} cartas atualizadas...');
      }
    }
    
    // Define CMC = 0 para terrenos e cartas sem custo
    final landsUpdated = await connection.execute('''
      UPDATE cards 
      SET cmc = 0 
      WHERE (mana_cost IS NULL OR mana_cost = '') 
        AND cmc IS NULL
      RETURNING id
    ''');
    
    print('\n==================================================');
    print('✅ $updated cartas com CMC calculado');
    print('✅ ${landsUpdated.length} terrenos/cartas sem custo = CMC 0');
    if (errors > 0) print('⚠️ $errors erros encontrados');
    print('==================================================\n');
    
  } finally {
    await connection.close();
  }
}

/// Calcula o Converted Mana Cost (CMC) a partir do mana_cost string
/// 
/// Exemplos:
/// - "{3}{U}{U}" -> 5
/// - "{W}{U}{B}{R}{G}" -> 5
/// - "{X}{X}{G}" -> 1 (X conta como 0)
/// - "{2/W}{2/U}" -> 2 (híbrido conta como o maior valor)
/// - "{W/P}" -> 1 (phyrexian conta como 1)
double calculateCmc(String manaCost) {
  if (manaCost.isEmpty) return 0;
  
  double cmc = 0;
  
  // Regex para extrair símbolos entre chaves
  final symbolRegex = RegExp(r'\{([^}]+)\}');
  final matches = symbolRegex.allMatches(manaCost);
  
  for (final match in matches) {
    final symbol = match.group(1)!.toUpperCase();
    
    // X, Y, Z contam como 0
    if (symbol == 'X' || symbol == 'Y' || symbol == 'Z') {
      continue;
    }
    
    // Número puro (ex: "3", "10", "1000000")
    final number = int.tryParse(symbol);
    if (number != null) {
      cmc += number;
      continue;
    }
    
    // Híbrido genérico (ex: "2/W", "2/U") - conta como 2
    if (symbol.contains('/') && symbol.startsWith(RegExp(r'\d'))) {
      final parts = symbol.split('/');
      final numericPart = int.tryParse(parts[0]);
      if (numericPart != null) {
        cmc += numericPart;
        continue;
      }
    }
    
    // Híbrido de cor ou Phyrexian (ex: "W/U", "W/P", "G/P") - conta como 1
    if (symbol.contains('/')) {
      cmc += 1;
      continue;
    }
    
    // Símbolo de cor simples (W, U, B, R, G, C, S) - conta como 1
    if (RegExp(r'^[WUBRGCS]$').hasMatch(symbol)) {
      cmc += 1;
      continue;
    }
    
    // Símbolos especiais de snow, colorless, etc
    cmc += 1;
  }
  
  // Cap máximo para cartas joke como Gleemax
  return cmc > 999 ? 999 : cmc;
}
