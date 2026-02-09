/// Migration: Adiciona collector_number e foil à tabela cards
///
/// Essas colunas permitem identificar a impressão exata da carta:
/// - collector_number: "157" (número impresso na parte inferior da carta)
/// - foil: indica se a carta é foil (true), non-foil (false) ou null (desconhecido)
///
/// Uso: dart run bin/migrate_add_collector_number.dart
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
    // 1) Adiciona coluna collector_number (texto, ex: "157", "157a", "SLD-001")
    print('📝 Adicionando coluna collector_number...');
    await pool.execute('''
      ALTER TABLE cards ADD COLUMN IF NOT EXISTS collector_number TEXT
    ''');

    // 2) Adiciona coluna foil (boolean: true=foil, false=non-foil, null=desconhecido)
    print('📝 Adicionando coluna foil...');
    await pool.execute('''
      ALTER TABLE cards ADD COLUMN IF NOT EXISTS foil BOOLEAN
    ''');

    // 3) Índice para busca por collector_number + set_code (identificação exata)
    print('📝 Criando índice para collector_number + set_code...');
    await pool.execute('''
      CREATE INDEX IF NOT EXISTS idx_cards_collector_set
      ON cards (collector_number, set_code)
      WHERE collector_number IS NOT NULL
    ''');

    print('✅ Migration concluída com sucesso!');
    print('   - cards.collector_number TEXT (nullable)');
    print('   - cards.foil BOOLEAN (nullable)');
    print('   - idx_cards_collector_set (collector_number, set_code)');
  } catch (e, st) {
    print('❌ Erro na migration: $e');
    print(st);
    exitCode = 1;
  } finally {
    await pool.close();
  }
}
