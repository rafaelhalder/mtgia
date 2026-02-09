/// Migration: Adiciona coluna `condition` à tabela deck_cards
///
/// Padrão TCGPlayer para condição de cartas:
/// - NM  = Near Mint (padrão)
/// - LP  = Lightly Played
/// - MP  = Moderately Played
/// - HP  = Heavily Played
/// - DMG = Damaged
///
/// Uso: dart run bin/migrate_add_card_condition.dart
library;

import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

Future<void> main() async {
  final env = DotEnv(includePlatformEnvironment: true)..load(['.env']);

  final host = env['DB_HOST'] ?? 'localhost';
  final port = int.tryParse(env['DB_PORT'] ?? '5432') ?? 5432;
  final database = env['DB_NAME'] ?? 'mtg';
  final username = env['DB_USER'] ?? 'postgres';
  final password = env['DB_PASS'] ?? '';

  print('🔗 Conectando a $host:$port/$database...');

  final pool = Pool.withEndpoints(
    [Endpoint(host: host, port: port, database: database, username: username, password: password)],
    settings: PoolSettings(
      maxConnectionCount: 2,
      sslMode: SslMode.disable,
    ),
  );

  try {
    // 1) Adiciona coluna condition com default 'NM' (Near Mint)
    print('📝 Adicionando coluna condition à tabela deck_cards...');
    await pool.execute('''
      ALTER TABLE deck_cards
      ADD COLUMN IF NOT EXISTS condition TEXT DEFAULT 'NM'
    ''');

    // 2) Atualiza registros existentes que ficaram NULL
    print('📝 Preenchendo registros existentes com NM...');
    await pool.execute('''
      UPDATE deck_cards SET condition = 'NM' WHERE condition IS NULL
    ''');

    // 3) Adiciona constraint CHECK para garantir valores válidos
    // Primeiro verifica se já existe
    final existingConstraint = await pool.execute('''
      SELECT 1 FROM information_schema.check_constraints
      WHERE constraint_name = 'chk_deck_cards_condition'
    ''');
    if (existingConstraint.isEmpty) {
      print('📝 Adicionando constraint de validação...');
      await pool.execute('''
        ALTER TABLE deck_cards
        ADD CONSTRAINT chk_deck_cards_condition
        CHECK (condition IN ('NM', 'LP', 'MP', 'HP', 'DMG'))
      ''');
    }

    print('✅ Migration concluída com sucesso!');
    print('   - deck_cards.condition TEXT DEFAULT \'NM\'');
    print('   - Valores válidos: NM, LP, MP, HP, DMG');
    print('   - Registros existentes atualizados para NM');
  } catch (e, st) {
    print('❌ Erro na migration: $e');
    print(st);
    exitCode = 1;
  } finally {
    await pool.close();
  }
}
