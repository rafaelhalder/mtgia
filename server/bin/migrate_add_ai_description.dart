import 'package:postgres/postgres.dart';
import 'package:dotenv/dotenv.dart';

void main() async {
  var env = DotEnv(includePlatformEnvironment: true)..load();

  final host = env['DB_HOST'] ?? 'localhost';
  final port = int.tryParse(env['DB_PORT'] ?? '5432') ?? 5432;
  final database = env['DB_NAME'] ?? 'postgres';
  final user = env['DB_USER'] ?? 'postgres';
  final password = env['DB_PASS'];

  print('Conectando em $host:$port/$database...');

  final endpoint = Endpoint(
    host: host,
    port: port,
    database: database,
    username: user,
    password: password,
  );

  final connection = await Connection.open(endpoint, settings: ConnectionSettings(sslMode: SslMode.disable));

  try {
    print('Verificando tabela cards...');
    
    // Verifica se a coluna já existe
    final result = await connection.execute(
      "SELECT column_name FROM information_schema.columns WHERE table_name='cards' AND column_name='ai_description'"
    );

    if (result.isEmpty) {
      print('Adicionando coluna ai_description na tabela cards...');
      await connection.execute('ALTER TABLE cards ADD COLUMN ai_description TEXT');
      print('Coluna adicionada com sucesso.');
    } else {
      print('Coluna ai_description já existe.');
    }

  } catch (e) {
    print('Erro: $e');
  } finally {
    await connection.close();
  }
}
