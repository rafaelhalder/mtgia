import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

void main() async {
  final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();
  final dbUrl = env['DATABASE_URL']!;
  final uri = Uri.parse(dbUrl);
  
  final pool = Pool.withEndpoints([
    Endpoint(
      host: uri.host,
      port: uri.port,
      database: uri.path.replaceFirst('/', ''),
      username: uri.userInfo.split(':').first,
      password: uri.userInfo.split(':').skip(1).join(':'),
    ),
  ], settings: PoolSettings(maxConnectionCount: 1, sslMode: SslMode.disable));

  final total = await pool.execute("SELECT COUNT(*) FROM cards");
  final broken = await pool.execute(
    "SELECT COUNT(*) FROM cards WHERE image_url LIKE '%/cards/named?exact=%'");
  final direct = await pool.execute(
    "SELECT COUNT(*) FROM cards WHERE image_url LIKE '%cards.scryfall.io%'");
  
  print('📊 Total de cartas: ${total[0][0]}');
  print('❌ URLs quebradas (named?exact=): ${broken[0][0]}');
  print('✅ URLs diretas (cards.scryfall.io): ${direct[0][0]}');
  
  // Exemplo de carta específica
  final jin = await pool.execute(Sql.named(
    "SELECT name, set_code, image_url FROM cards WHERE name ILIKE '%Jin-Gitaxias%' LIMIT 3"));
  print('\n🔍 Cartas Jin-Gitaxias:');
  for (final r in jin) {
    print('   ${r[0]} (${r[1]}): ${(r[2] as String).substring(0, 60)}...');
  }
  
  await pool.close();
}
