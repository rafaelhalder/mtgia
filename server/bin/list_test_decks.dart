// ignore_for_file: avoid_print
/// Lists all decks in the database for testing purposes.
import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

Future<void> main() async {
  final env = DotEnv(includePlatformEnvironment: true)..load(['.env']);
  final dbUrl = env['DATABASE_URL'] ?? '';
  final uri = Uri.parse(dbUrl);
  final pool = Pool.withEndpoints(
    [Endpoint(host: uri.host, port: uri.port, database: uri.pathSegments.first, username: uri.userInfo.split(':').first, password: uri.userInfo.split(':').last)],
    settings: PoolSettings(maxConnectionCount: 2, sslMode: SslMode.disable),
  );

  final rows = await pool.execute('''
    SELECT d.id, SUBSTRING(d.name,1,45) as nm, d.format,
           COALESCE(SUM(dc.quantity),0)::int as qty,
           COUNT(CASE WHEN dc.is_commander THEN 1 END)::int as cmd
    FROM decks d
    LEFT JOIN deck_cards dc ON dc.deck_id=d.id
    GROUP BY d.id,d.name,d.format
    ORDER BY qty DESC
  ''');

  print('=== DECKS IN DATABASE (${rows.length} total) ===');
  print('${'ID'.padRight(38)} ${'Name'.padRight(47)} ${'Format'.padRight(12)} ${'Qty'.padLeft(4)} ${'Cmd'.padLeft(4)}');
  print('-' * 110);
  for (final r in rows) {
    final id = r[0].toString();
    final nm = r[1].toString();
    final fmt = r[2].toString();
    final qty = r[3].toString();
    final cmd = r[4].toString();
    print('${id.padRight(38)} ${nm.padRight(47)} ${fmt.padRight(12)} ${qty.padLeft(4)} ${cmd.padLeft(4)}');
  }

  await pool.close();
}
