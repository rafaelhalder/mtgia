// ignore_for_file: avoid_print

import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

/// Migration: Adiciona índices críticos para melhorar performance de queries
/// 
/// Índices adicionados:
/// - cards(name) - Busca por nome de carta
/// - cards(color_identity) GIN - Busca por identidade de cor
/// - deck_cards(deck_id) - Listagem de cartas do deck
/// - card_legalities(card_id, format) - Verificação de legalidade
void main() async {
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
    print('🔄 Criando índices críticos para performance...\n');

    // 1. Índice para busca de cartas por nome (case-insensitive)
    print('1️⃣ Índice para busca por nome (cards.name)...');
    await connection.execute('''
      CREATE INDEX IF NOT EXISTS idx_cards_name_lower 
      ON cards (LOWER(name))
    ''');
    print('   ✅ idx_cards_name_lower criado\n');

    // 2. Índice trigram para busca fuzzy (LIKE '%query%')
    print('2️⃣ Habilitando extensão pg_trgm para busca fuzzy...');
    try {
      await connection.execute('CREATE EXTENSION IF NOT EXISTS pg_trgm');
      print('   ✅ pg_trgm habilitado');
      
      await connection.execute('''
        CREATE INDEX IF NOT EXISTS idx_cards_name_trgm 
        ON cards USING gin (name gin_trgm_ops)
      ''');
      print('   ✅ idx_cards_name_trgm criado\n');
    } catch (e) {
      print('   ⚠️ pg_trgm não disponível (pode precisar de superuser): $e\n');
    }

    // 3. Índice GIN para identidade de cor (busca em array)
    print('3️⃣ Índice GIN para identidade de cor (cards.color_identity)...');
    await connection.execute('''
      CREATE INDEX IF NOT EXISTS idx_cards_color_identity_gin 
      ON cards USING gin (color_identity)
    ''');
    print('   ✅ idx_cards_color_identity_gin criado\n');

    // 4. Índice para deck_cards.deck_id (muito usado)
    print('4️⃣ Índice para deck_cards.deck_id...');
    await connection.execute('''
      CREATE INDEX IF NOT EXISTS idx_deck_cards_deck_id 
      ON deck_cards (deck_id)
    ''');
    print('   ✅ idx_deck_cards_deck_id criado\n');

    // 5. Índice composto para verificação de legalidade
    print('5️⃣ Índice composto para card_legalities (card_id, format)...');
    await connection.execute('''
      CREATE INDEX IF NOT EXISTS idx_card_legalities_card_format 
      ON card_legalities (card_id, format)
    ''');
    print('   ✅ idx_card_legalities_card_format criado\n');

    // 6. Índice para decks.user_id (listagem de decks do usuário)
    print('6️⃣ Índice para decks.user_id...');
    await connection.execute('''
      CREATE INDEX IF NOT EXISTS idx_decks_user_id 
      ON decks (user_id)
    ''');
    print('   ✅ idx_decks_user_id criado\n');

    // 7. Índice para cards.scryfall_id (busca por ID do Scryfall)
    print('7️⃣ Índice para cards.scryfall_id...');
    await connection.execute('''
      CREATE INDEX IF NOT EXISTS idx_cards_scryfall_id 
      ON cards (scryfall_id)
    ''');
    print('   ✅ idx_cards_scryfall_id criado\n');

    // 8. Índice para type_line (busca por tipo de carta)
    print('8️⃣ Índice para cards.type_line...');
    await connection.execute('''
      CREATE INDEX IF NOT EXISTS idx_cards_type_line 
      ON cards (type_line)
    ''');
    print('   ✅ idx_cards_type_line criado\n');

    // Atualizar estatísticas para o query planner
    print('📊 Atualizando estatísticas (ANALYZE)...');
    await connection.execute('ANALYZE cards');
    await connection.execute('ANALYZE deck_cards');
    await connection.execute('ANALYZE card_legalities');
    await connection.execute('ANALYZE decks');
    print('   ✅ Estatísticas atualizadas\n');

    print('=' * 50);
    print('✅ Todos os índices críticos foram criados!');
    print('=' * 50);
    print('\nRecomendação: Execute o smoke test de performance');
    print('para verificar a melhoria nas queries.');

  } catch (e) {
    print('❌ Erro na migração: $e');
    exit(1);
  } finally {
    await connection.close();
  }
}
