import 'package:postgres/postgres.dart';
import 'package:dotenv/dotenv.dart';

void main() async {
  final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();
  final host = env['DB_HOST']!;
  final port = int.parse(env['DB_PORT']!);
  final database = env['DB_NAME']!;
  final username = env['DB_USER']!;
  final password = env['DB_PASS']!;

  final conn = await Connection.open(
    Endpoint(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
    ),
    settings: ConnectionSettings(sslMode: SslMode.disable),
  );

  final patterns = [
    'command tower // %',
    'sol ring // %',
    'forest // %'
  ];

  print('Testing LIKE ANY query with patterns: $patterns');

  try {
    final result = await conn.execute(
      Sql.named('SELECT id, name FROM cards WHERE lower(name) LIKE ANY(@patterns)'),
      parameters: {'patterns': TypedValue(Type.textArray, patterns)},
    );

    print('Found ${result.length} matches:');
    for (final row in result) {
      print(' - ${row[1]} (ID: ${row[0]})');
    }
  } catch (e) {
    print('Error executing query: $e');
  }
  
  // Check Sol Ring specifically
  print('\nChecking Sol Ring exact match:');
  final solResult = await conn.execute(
      Sql.named("SELECT id, name FROM cards WHERE lower(name) = 'sol ring'"),
  );
  if (solResult.isEmpty) {
      print('Sol Ring NOT FOUND by exact match.');
      // Check if it exists with any other name
      final solLike = await conn.execute(
          Sql.named("SELECT id, name FROM cards WHERE lower(name) LIKE '%sol ring%'"),
      );
      print('Sol Ring LIKE search results:');
      for(final row in solLike) {
          print(' - ${row[1]}');
      }
  } else {
      print('Sol Ring FOUND by exact match.');
  }

  await conn.close();
}
