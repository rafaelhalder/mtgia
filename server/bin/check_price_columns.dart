// ignore_for_file: avoid_print

import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

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
    print('📊 Colunas da tabela cards relacionadas a preço:\n');
    
    final columns = await connection.execute('''
      SELECT column_name, data_type, is_nullable
      FROM information_schema.columns
      WHERE table_name = 'cards'
        AND (column_name LIKE '%price%' OR column_name LIKE '%cmc%')
      ORDER BY column_name
    ''');

    for (final row in columns) {
      print('  ${row[0]}: ${row[1]} (nullable: ${row[2]})');
    }

    // Verifica se há dados de preço
    final priceCount = await connection.execute('''
      SELECT 
        COUNT(*) FILTER (WHERE price IS NOT NULL) as price_count,
        COUNT(*) FILTER (WHERE price_usd IS NOT NULL) as price_usd_count,
        COUNT(*) as total
      FROM cards
    ''');

    if (priceCount.isNotEmpty) {
      final row = priceCount.first;
      print('\n📈 Dados de preço:');
      print('  - Cards com "price": ${row[0]}');
      print('  - Cards com "price_usd": ${row[1]}');
      print('  - Total de cards: ${row[2]}');
    }

  } catch (e) {
    print('Erro: $e');
  } finally {
    await connection.close();
  }
}
