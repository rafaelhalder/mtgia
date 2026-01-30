import 'package:postgres/postgres.dart';
import 'package:dotenv/dotenv.dart';

void main() async {
  var env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();
  
  print('DB_HOST: ${env['DB_HOST']}');
  print('DB_USER: ${env['DB_USER']}');
  print('DB_PASS length: ${env['DB_PASS']?.length}');

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
    print('Adicionando coluna price na tabela cards...');
    await connection.execute("ALTER TABLE cards ADD COLUMN IF NOT EXISTS price DECIMAL(10, 2);");
    print('Coluna price adicionada com sucesso!');
  } catch (e) {
    print('Erro ao migrar: $e');
  } finally {
    await connection.close();
  }
}
