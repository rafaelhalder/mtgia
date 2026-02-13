// ignore_for_file: avoid_print
/// Script de auditoria de integridade de dados
/// Verifica duplicatas, FKs órfãs, inconsistências de case, etc.

import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:dotenv/dotenv.dart';

Future<void> main() async {
  // Tenta carregar .env mas não falha se não existir
  try {
    DotEnv()..load();
  } catch (_) {}
  
  // Prioridade: DATABASE_URL ou variáveis DB_* separadas
  final dbUrl = Platform.environment['DATABASE_URL'];
  
  Endpoint endpoint;
  if (dbUrl != null && dbUrl.isNotEmpty) {
    final uri = Uri.parse(dbUrl);
    endpoint = Endpoint(
      host: uri.host,
      port: uri.port,
      database: uri.pathSegments.isNotEmpty ? uri.pathSegments.first : 'postgres',
      username: uri.userInfo.split(':').first,
      password: uri.userInfo.contains(':') ? uri.userInfo.split(':').last : null,
    );
  } else {
    // Usar variáveis DB_* separadas
    final host = Platform.environment['DB_HOST'];
    final port = int.tryParse(Platform.environment['DB_PORT'] ?? '5432') ?? 5432;
    final database = Platform.environment['DB_NAME'] ?? 'postgres';
    final username = Platform.environment['DB_USER'] ?? 'postgres';
    final password = Platform.environment['DB_PASS'];
    
    if (host == null) {
      print('❌ DATABASE_URL ou DB_HOST não configurado');
      exit(1);
    }
    
    endpoint = Endpoint(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
    );
  }

  final sslMode = Platform.environment['DB_SSL_MODE'] == 'disable' 
      ? SslMode.disable 
      : SslMode.require;

  final pool = Pool.withEndpoints(
    [endpoint], 
    settings: PoolSettings(
      maxConnectionCount: 3,
      sslMode: sslMode,
    ),
  );
  
  print('═══════════════════════════════════════════════════════════════');
  print('   AUDITORIA DE INTEGRIDADE DE DADOS - MTG API');
  print('═══════════════════════════════════════════════════════════════');
  print('');

  try {
    // 1. CARDS - Duplicatas por scryfall_id
    print('┌─────────────────────────────────────────────────────────────┐');
    print('│ 1. ANÁLISE DA TABELA CARDS                                  │');
    print('└─────────────────────────────────────────────────────────────┘');
    
    var result = await pool.execute(Sql('''
      SELECT COUNT(*) as total, COUNT(DISTINCT scryfall_id) as unique_scryfall 
      FROM cards
    '''));
    var row = result.first;
    final totalCards = row[0] as int;
    final uniqueScryfall = row[1] as int;
    print('   Total de cards: $totalCards');
    print('   Scryfall IDs únicos: $uniqueScryfall');
    if (totalCards != uniqueScryfall) {
      print('   ⚠️  DUPLICATAS por scryfall_id: ${totalCards - uniqueScryfall}');
    } else {
      print('   ✅ Sem duplicatas por scryfall_id');
    }

    // Cards duplicados por (name, set_code) - variantes
    result = await pool.execute(Sql('''
      SELECT name, set_code, COUNT(*) as cnt 
      FROM cards 
      GROUP BY name, set_code 
      HAVING COUNT(*) > 1 
      ORDER BY cnt DESC 
      LIMIT 10
    '''));
    if (result.isNotEmpty) {
      print('');
      print('   ⚠️  Cards duplicados por (name, set_code) - são variantes:');
      for (final r in result) {
        print('      - ${r[0]} [${r[1]}]: ${r[2]}x');
      }
    }

    // Case inconsistency no set_code
    result = await pool.execute(Sql('''
      SELECT LOWER(set_code) as lcode, COUNT(DISTINCT set_code) as variants
      FROM cards
      GROUP BY LOWER(set_code)
      HAVING COUNT(DISTINCT set_code) > 1
      ORDER BY variants DESC
      LIMIT 10
    '''));
    if (result.isNotEmpty) {
      print('');
      print('   ⚠️  Inconsistência de CASE em set_code:');
      for (final r in result) {
        final lcode = r[0];
        final variants = await pool.execute(Sql.named(
          'SELECT DISTINCT set_code FROM cards WHERE LOWER(set_code) = @lcode'
        ), parameters: {'lcode': lcode});
        final codes = variants.map((v) => v[0]).join(', ');
        print('      - $lcode tem variantes: $codes');
      }
    } else {
      print('   ✅ Sem inconsistência de case em set_code');
    }

    // 2. SETS - Duplicatas
    print('');
    print('┌─────────────────────────────────────────────────────────────┐');
    print('│ 2. ANÁLISE DA TABELA SETS                                   │');
    print('└─────────────────────────────────────────────────────────────┘');
    
    result = await pool.execute(Sql('''
      SELECT COUNT(*) as total, COUNT(DISTINCT code) as unique_codes 
      FROM sets
    '''));
    row = result.first;
    final totalSets = row[0] as int;
    final uniqueCodes = row[1] as int;
    print('   Total de sets: $totalSets');
    print('   Códigos únicos: $uniqueCodes');
    if (totalSets != uniqueCodes) {
      print('   ⚠️  DUPLICATAS em sets: ${totalSets - uniqueCodes}');
    } else {
      print('   ✅ Sem duplicatas');
    }

    // Cards sem set correspondente
    result = await pool.execute(Sql('''
      SELECT c.set_code, COUNT(*) as cnt
      FROM cards c
      LEFT JOIN sets s ON LOWER(s.code) = LOWER(c.set_code)
      WHERE s.code IS NULL AND c.set_code IS NOT NULL
      GROUP BY c.set_code
      ORDER BY cnt DESC
      LIMIT 10
    '''));
    if (result.isNotEmpty) {
      print('');
      print('   ⚠️  Cards com set_code sem entry na tabela sets:');
      for (final r in result) {
        print('      - ${r[0]}: ${r[1]} cards');
      }
    } else {
      print('   ✅ Todos os cards têm sets correspondentes');
    }

    // 3. DECK_CARDS - FKs órfãs
    print('');
    print('┌─────────────────────────────────────────────────────────────┐');
    print('│ 3. ANÁLISE DA TABELA DECK_CARDS                             │');
    print('└─────────────────────────────────────────────────────────────┘');
    
    result = await pool.execute(Sql('''
      SELECT COUNT(*) FROM deck_cards dc
      LEFT JOIN cards c ON c.id = dc.card_id
      WHERE c.id IS NULL
    '''));
    final orphanCards = result.first[0] as int;
    if (orphanCards > 0) {
      print('   ⚠️  deck_cards com card_id órfão: $orphanCards');
    } else {
      print('   ✅ Sem card_id órfãos');
    }

    result = await pool.execute(Sql('''
      SELECT COUNT(*) FROM deck_cards dc
      LEFT JOIN decks d ON d.id = dc.deck_id
      WHERE d.id IS NULL
    '''));
    final orphanDecks = result.first[0] as int;
    if (orphanDecks > 0) {
      print('   ⚠️  deck_cards com deck_id órfão: $orphanDecks');
    } else {
      print('   ✅ Sem deck_id órfãos');
    }

    // Duplicatas em deck_cards (mesmo deck_id + card_id)
    result = await pool.execute(Sql('''
      SELECT deck_id, card_id, COUNT(*) as cnt
      FROM deck_cards
      GROUP BY deck_id, card_id
      HAVING COUNT(*) > 1
      LIMIT 5
    '''));
    if (result.isNotEmpty) {
      print('   ⚠️  Duplicatas em deck_cards (mesmo deck+card):');
      for (final r in result) {
        print('      - deck ${r[0]}, card ${r[1]}: ${r[2]}x');
      }
    } else {
      print('   ✅ Sem duplicatas (deck_id, card_id)');
    }

    // 4. USER_BINDER_ITEMS - FKs órfãs
    print('');
    print('┌─────────────────────────────────────────────────────────────┐');
    print('│ 4. ANÁLISE DA TABELA USER_BINDER_ITEMS                      │');
    print('└─────────────────────────────────────────────────────────────┘');
    
    result = await pool.execute(Sql('''
      SELECT COUNT(*) FROM user_binder_items bi
      LEFT JOIN cards c ON c.id = bi.card_id
      WHERE c.id IS NULL
    '''));
    final binderOrphanCards = result.first[0] as int;
    if (binderOrphanCards > 0) {
      print('   ⚠️  binder_items com card_id órfão: $binderOrphanCards');
    } else {
      print('   ✅ Sem card_id órfãos');
    }

    result = await pool.execute(Sql('''
      SELECT COUNT(*) FROM user_binder_items bi
      LEFT JOIN users u ON u.id = bi.user_id
      WHERE u.id IS NULL
    '''));
    final binderOrphanUsers = result.first[0] as int;
    if (binderOrphanUsers > 0) {
      print('   ⚠️  binder_items com user_id órfão: $binderOrphanUsers');
    } else {
      print('   ✅ Sem user_id órfãos');
    }

    // 5. TRADES - Integridade
    print('');
    print('┌─────────────────────────────────────────────────────────────┐');
    print('│ 5. ANÁLISE DAS TABELAS DE TRADES                            │');
    print('└─────────────────────────────────────────────────────────────┘');
    
    result = await pool.execute(Sql('''
      SELECT COUNT(*) FROM trade_offers
    '''));
    print('   Total de trades: ${result.first[0]}');

    result = await pool.execute(Sql('''
      SELECT COUNT(*) FROM trade_items ti
      LEFT JOIN trade_offers t ON t.id = ti.trade_offer_id
      WHERE t.id IS NULL
    '''));
    final orphanTradeItems = result.first[0] as int;
    if (orphanTradeItems > 0) {
      print('   ⚠️  trade_items com trade_offer_id órfão: $orphanTradeItems');
    } else {
      print('   ✅ trade_items íntegros');
    }

    // 6. FOLLOWS - Integridade
    print('');
    print('┌─────────────────────────────────────────────────────────────┐');
    print('│ 6. ANÁLISE DA TABELA FOLLOWS                                │');
    print('└─────────────────────────────────────────────────────────────┘');
    
    try {
      result = await pool.execute(Sql('''
        SELECT COUNT(*) FROM follows f
        LEFT JOIN users u1 ON u1.id = f.follower_id
        LEFT JOIN users u2 ON u2.id = f.following_id
        WHERE u1.id IS NULL OR u2.id IS NULL
      '''));
      final orphanFollows = result.first[0] as int;
      if (orphanFollows > 0) {
        print('   ⚠️  follows com user_id órfão: $orphanFollows');
      } else {
        print('   ✅ follows íntegros');
      }

      // Self-follows
      result = await pool.execute(Sql('''
        SELECT COUNT(*) FROM follows WHERE follower_id = following_id
      '''));
      final selfFollows = result.first[0] as int;
      if (selfFollows > 0) {
        print('   ⚠️  Self-follows (usuário seguindo a si mesmo): $selfFollows');
      }
    } catch (e) {
      print('   ℹ️  Tabela follows não existe');
    }

    // 7. NOTIFICATIONS - Integridade
    print('');
    print('┌─────────────────────────────────────────────────────────────┐');
    print('│ 7. ANÁLISE DA TABELA NOTIFICATIONS                          │');
    print('└─────────────────────────────────────────────────────────────┘');
    
    try {
      result = await pool.execute(Sql('''
        SELECT COUNT(*) FROM notifications n
        LEFT JOIN users u ON u.id = n.user_id
        WHERE u.id IS NULL
      '''));
      final orphanNotifications = result.first[0] as int;
      if (orphanNotifications > 0) {
        print('   ⚠️  notifications com user_id órfão: $orphanNotifications');
      } else {
        print('   ✅ notifications íntegras');
      }
    } catch (e) {
      print('   ℹ️  Tabela notifications não existe');
    }

    // 8. CONVERSATIONS/MESSAGES - Integridade
    print('');
    print('┌─────────────────────────────────────────────────────────────┐');
    print('│ 8. ANÁLISE DE CONVERSATIONS E MESSAGES                      │');
    print('└─────────────────────────────────────────────────────────────┘');
    
    try {
      result = await pool.execute(Sql('''
        SELECT COUNT(*) FROM conversations c
        LEFT JOIN users u1 ON u1.id = c.user1_id
        LEFT JOIN users u2 ON u2.id = c.user2_id
        WHERE u1.id IS NULL OR u2.id IS NULL
      '''));
      final orphanConversations = result.first[0] as int;
      if (orphanConversations > 0) {
        print('   ⚠️  conversations com user_id órfão: $orphanConversations');
      } else {
        print('   ✅ conversations íntegras');
      }

      result = await pool.execute(Sql('''
        SELECT COUNT(*) FROM direct_messages m
        LEFT JOIN conversations c ON c.id = m.conversation_id
        WHERE c.id IS NULL
      '''));
      final orphanMessages = result.first[0] as int;
      if (orphanMessages > 0) {
        print('   ⚠️  messages com conversation_id órfão: $orphanMessages');
      } else {
        print('   ✅ messages íntegras');
      }
    } catch (e) {
      print('   ℹ️  Tabelas conversations/direct_messages não existem');
    }

    // 9. DECKS - Integridade
    print('');
    print('┌─────────────────────────────────────────────────────────────┐');
    print('│ 9. ANÁLISE DA TABELA DECKS                                  │');
    print('└─────────────────────────────────────────────────────────────┘');
    
    result = await pool.execute(Sql('''
      SELECT COUNT(*) FROM decks d
      LEFT JOIN users u ON u.id = d.user_id
      WHERE u.id IS NULL AND d.deleted_at IS NULL
    '''));
    final orphanDecks2 = result.first[0] as int;
    if (orphanDecks2 > 0) {
      print('   ⚠️  decks com user_id órfão: $orphanDecks2');
    } else {
      print('   ✅ decks íntegros');
    }

    // Decks públicos sem cartas
    result = await pool.execute(Sql('''
      SELECT d.id, d.name FROM decks d
      LEFT JOIN deck_cards dc ON dc.deck_id = d.id
      WHERE d.is_public = true AND d.deleted_at IS NULL
      GROUP BY d.id
      HAVING COUNT(dc.id) = 0
      LIMIT 5
    '''));
    if (result.isNotEmpty) {
      print('   ⚠️  Decks públicos sem cartas:');
      for (final r in result) {
        print('      - ${r[1]} (${r[0]})');
      }
    }

    // 10. ESTATÍSTICAS GERAIS
    print('');
    print('┌─────────────────────────────────────────────────────────────┐');
    print('│ 10. ESTATÍSTICAS GERAIS                                     │');
    print('└─────────────────────────────────────────────────────────────┘');

    final tables = ['users', 'cards', 'sets', 'decks', 'deck_cards', 
                    'user_binder_items', 'trade_offers', 'trade_items',
                    'follows', 'notifications', 'conversations', 'direct_messages'];
    
    for (final table in tables) {
      try {
        result = await pool.execute(Sql('SELECT COUNT(*) FROM $table'));
        print('   $table: ${result.first[0]} registros');
      } catch (_) {
        print('   $table: (tabela não existe)');
      }
    }

    print('');
    print('═══════════════════════════════════════════════════════════════');
    print('   AUDITORIA CONCLUÍDA');
    print('═══════════════════════════════════════════════════════════════');

  } finally {
    await pool.close();
  }
}
