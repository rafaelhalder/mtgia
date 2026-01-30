import 'package:postgres/postgres.dart';
import 'package:dotenv/dotenv.dart';

/// Classe para gerenciar a conexão com o banco de dados PostgreSQL.
///
/// Utiliza o padrão Singleton para garantir uma única instância do Pool de conexões.
class Database {
  late final Pool _pool;
  bool _connected = false;

  // Singleton pattern
  static final Database _instance = Database._internal();
  factory Database() => _instance;
  Database._internal();

  /// Retorna a instância do Pool.
  ///
  /// Se a conexão não estiver ativa, lança uma exceção.
  Pool get connection {
    if (!_connected) {
      throw Exception('A conexão com o banco de dados não foi inicializada. Chame connect() primeiro.');
    }
    return _pool;
  }

  /// Carrega as variáveis de ambiente e estabelece o Pool de conexões.
  Future<void> connect() async {
    if (_connected) return;

    // Carrega as variáveis de ambiente do arquivo .env
    final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();

    final host = env['DB_HOST'];
    final port = int.tryParse(env['DB_PORT'] ?? '');
    final database = env['DB_NAME'];
    final username = env['DB_USER'];
    final password = env['DB_PASS'];
    final environment = (env['ENVIRONMENT'] ?? 'development').toLowerCase();

    if (host == null || port == null || database == null || username == null || password == null) {
      print('Erro: As variáveis de ambiente do banco de dados não estão configuradas no arquivo .env');
      return;
    }

    // Determina o modo SSL baseado no ambiente
    // Produção: SSL obrigatório para segurança
    // Desenvolvimento: SSL desabilitado para facilitar setup local
    final sslMode = _parseSslMode(env['DB_SSL_MODE']) ?? (environment == 'production' ? SslMode.require : SslMode.disable);

    _pool = Pool.withEndpoints(
      [
        Endpoint(
          host: host,
          port: port,
          database: database,
          username: username,
          password: password,
        )
      ],
      settings: PoolSettings(
        maxConnectionCount: 10, // Ajuste conforme necessário
        sslMode: sslMode,
      ),
    );

    _connected = true;
    print('✅ Pool de conexões com o banco de dados inicializado (SSL: ${sslMode.name}).');
  }

  /// Fecha a conexão com o banco de dados.
  Future<void> close() async {
    if (!_connected) return;
    await _pool.close();
    _connected = false;
    print('Conexão com o PostgreSQL fechada.');
  }
}

SslMode? _parseSslMode(String? raw) {
  if (raw == null) return null;
  final value = raw.trim().toLowerCase();
  return switch (value) {
    'disable' || 'off' || 'false' || '0' => SslMode.disable,
    'require' || 'on' || 'true' || '1' => SslMode.require,
    'verifyfull' || 'verify_full' || 'verify-full' => SslMode.verifyFull,
    _ => null,
  };
}
