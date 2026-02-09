// ignore_for_file: avoid_print

import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

/// Migration: cria tabela price_history para rastrear variações diárias de preço.
///
/// A tabela armazena um snapshot do preço de cada carta por dia,
/// permitindo calcular gainers/losers comparando today vs yesterday.
Future<void> main(List<String> args) async {
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

  try {
    print('📊 Criando tabela price_history...');

    await connection.execute('''
      CREATE TABLE IF NOT EXISTS price_history (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        card_id UUID NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
        price_date DATE NOT NULL DEFAULT CURRENT_DATE,
        price_usd DECIMAL(10,2),
        price_usd_foil DECIMAL(10,2),
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(card_id, price_date)
      );
    ''');
    print('  ✅ Tabela price_history criada (ou já existia).');

    // Índices para queries de movers (ordenar por data, join com cards)
    await connection.execute('''
      CREATE INDEX IF NOT EXISTS idx_price_history_date 
      ON price_history(price_date DESC);
    ''');
    print('  ✅ Índice idx_price_history_date criado.');

    await connection.execute('''
      CREATE INDEX IF NOT EXISTS idx_price_history_card_date 
      ON price_history(card_id, price_date DESC);
    ''');
    print('  ✅ Índice idx_price_history_card_date criado.');

    // Seed inicial: copiar preços atuais da tabela cards como snapshot de "hoje"
    final result = await connection.execute('''
      INSERT INTO price_history (card_id, price_date, price_usd)
      SELECT id, CURRENT_DATE, price
      FROM cards
      WHERE price IS NOT NULL AND price > 0
      ON CONFLICT (card_id, price_date) DO NOTHING;
    ''');
    print('  ✅ Seed inicial: ${result.affectedRows} preços copiados para hoje.');

    print('\n✅ Migration price_history concluída!');
  } catch (e) {
    print('❌ Erro: $e');
  } finally {
    await connection.close();
  }
}
