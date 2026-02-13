import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

/// Salva um snapshot diário dos preços atuais das cartas em price_history.
///
/// Uso: dart run bin/snapshot_price_history.dart
Future<void> main() async {
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
    print('📊 Salvando snapshot de preços em price_history...');

    final result = await connection.execute('''
      INSERT INTO price_history (card_id, price_date, price_usd)
      SELECT id, CURRENT_DATE, price
      FROM cards
      WHERE price IS NOT NULL AND price > 0
      ON CONFLICT (card_id, price_date)
      DO UPDATE SET price_usd = EXCLUDED.price_usd
    ''');

    print('✅ price_history: ${result.affectedRows} registros salvos para hoje');

    // Verificação rápida
    final check = await connection.execute(
      "SELECT COUNT(*) FROM price_history WHERE price_date = CURRENT_DATE",
    );
    print('📋 Total registros hoje: ${check[0][0]}');

    final dates = await connection.execute(
      "SELECT price_date, COUNT(*) FROM price_history GROUP BY price_date ORDER BY price_date DESC LIMIT 5",
    );
    print('📅 Últimas datas:');
    for (final row in dates) {
      print('   ${row[0]} → ${row[1]} registros');
    }
  } finally {
    await connection.close();
  }
}
