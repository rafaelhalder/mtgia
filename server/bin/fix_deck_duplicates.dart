import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:dotenv/dotenv.dart';

/// Script para verificar e corrigir duplicatas no deck_cards
void main(List<String> args) async {
  load();
  
  final dbHost = env['DB_HOST'] ?? 'localhost';
  final dbPort = int.tryParse(env['DB_PORT'] ?? '') ?? 5432;
  final dbName = env['DB_NAME'] ?? 'mtg';
  final dbUser = env['DB_USER'] ?? 'postgres';
  final dbPass = env['DB_PASS'] ?? '';
  final sslMode = (env['DB_SSL'] ?? 'disable').toLowerCase() == 'require' 
      ? SslMode.require 
      : SslMode.disable;

  print('🔍 Conectando ao banco: $dbHost:$dbPort/$dbName');

  final pool = Pool.withEndpoints(
    [Endpoint(host: dbHost, port: dbPort, database: dbName, username: dbUser, password: dbPass)],
    settings: PoolSettings(sslMode: sslMode, maxConnectionCount: 2),
  );

  try {
    // Verificar deck específico
    final deckId = args.isNotEmpty ? args[0] : 'f2a2a34a-4561-4a77-886d-7067b672ac85';
    print('\n📦 Analisando deck: $deckId');

    // Buscar todas as cartas do deck
    final result = await pool.execute(
      Sql.named('''
        SELECT dc.id, dc.card_id, dc.quantity, dc.is_commander, c.name
        FROM deck_cards dc
        JOIN cards c ON dc.card_id = c.id
        WHERE dc.deck_id = @deckId
        ORDER BY c.name
      '''),
      parameters: {'deckId': deckId},
    );

    print('📊 Total de registros no deck: ${result.length}');

    // Agrupar por card_id para encontrar duplicatas
    final byCardId = <String, List<Map<String, dynamic>>>{};
    for (final row in result) {
      final cardId = row[1] as String;
      final entry = {
        'id': row[0] as String,
        'card_id': cardId,
        'quantity': row[2] as int,
        'is_commander': row[3] as bool,
        'name': row[4] as String,
      };
      byCardId.putIfAbsent(cardId, () => []).add(entry);
    }

    // Encontrar duplicatas
    final duplicates = byCardId.entries.where((e) => e.value.length > 1).toList();
    
    if (duplicates.isEmpty) {
      print('✅ Nenhuma duplicata de card_id encontrada!');
    } else {
      print('\n⚠️ Duplicatas encontradas:');
      for (final dup in duplicates) {
        print('\n  Card ID: ${dup.key}');
        for (final entry in dup.value) {
          print('    - ${entry['name']} | qty=${entry['quantity']} | is_commander=${entry['is_commander']} | deck_cards.id=${entry['id']}');
        }
      }

      // Corrigir duplicatas
      print('\n🔧 Corrigindo duplicatas...');
      for (final dup in duplicates) {
        final entries = dup.value;
        
        // Priorizar is_commander: true
        entries.sort((a, b) {
          if (a['is_commander'] == true && b['is_commander'] != true) return -1;
          if (b['is_commander'] == true && a['is_commander'] != true) return 1;
          return 0;
        });

        // Manter o primeiro (prioridade commander), deletar os outros
        final toKeep = entries.first;
        final toDelete = entries.skip(1).toList();

        print('  Mantendo: ${toKeep['name']} (is_commander=${toKeep['is_commander']})');
        
        for (final del in toDelete) {
          print('  Deletando: deck_cards.id=${del['id']}');
          await pool.execute(
            Sql.named('DELETE FROM deck_cards WHERE id = @id'),
            parameters: {'id': del['id']},
          );
        }
      }
      
      print('\n✅ Duplicatas corrigidas!');
    }

    // Verificar contagem por NOME (regra de Commander)
    print('\n📋 Verificando regra de cópia única por nome...');
    final byName = <String, List<Map<String, dynamic>>>{};
    for (final row in result) {
      final name = (row[4] as String).toLowerCase();
      final entry = {
        'id': row[0] as String,
        'card_id': row[1] as String,
        'quantity': row[2] as int,
        'is_commander': row[3] as bool,
        'name': row[4] as String,
      };
      byName.putIfAbsent(name, () => []).add(entry);
    }

    final nameDups = byName.entries.where((e) {
      // Só conta não-commanders
      final nonCmdQty = e.value
          .where((x) => x['is_commander'] != true)
          .fold<int>(0, (sum, x) => sum + (x['quantity'] as int));
      return nonCmdQty > 1;
    }).toList();

    if (nameDups.isEmpty) {
      print('✅ Nenhuma violação de regra de cópias por nome!');
    } else {
      print('\n⚠️ Violações de regra de cópias (mais de 1 cópia não-commander):');
      for (final dup in nameDups) {
        final nonCmd = dup.value.where((x) => x['is_commander'] != true).toList();
        final total = nonCmd.fold<int>(0, (sum, x) => sum + (x['quantity'] as int));
        print('  ${dup.value.first['name']}: $total cópias não-commander');
      }
    }

  } finally {
    await pool.close();
  }
}
