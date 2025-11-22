import 'package:postgres/postgres.dart';
import 'package:dotenv/dotenv.dart';

/// Classe para gerenciar a conexão com o banco de dados PostgreSQL.
///
/// Utiliza o padrão Singleton para garantir uma única instância da conexão.
class Database {
  late final Connection _connection;
  bool _connected = false;

  // Singleton pattern
  static final Database _instance = Database._internal();
  factory Database() => _instance;
  Database._internal();

  /// Retorna a instância da conexão.
  ///
  /// Se a conexão não estiver ativa, lança uma exceção.
  Connection get connection {
    if (!_connected) {
      throw Exception('A conexão com o banco de dados não foi inicializada. Chame connect() primeiro.');
    }
    return _connection;
  }

  /// Carrega as variáveis de ambiente e estabelece a conexão com o banco.
  Future<void> connect() async {
    if (_connected) return;

    // Carrega as variáveis de ambiente do arquivo .env
    final env = DotEnv(includePlatformEnvironment: true)..load();

    final host = env['DB_HOST'];
    final port = int.tryParse(env['DB_PORT'] ?? '');
    final database = env['DB_NAME'];
    final username = env['DB_USER'];
    final password = env['DB_PASS'];

    if (host == null || port == null || database == null || username == null || password == null) {
      print('Erro: As variáveis de ambiente do banco de dados não estão configuradas no arquivo .env');
      return;
    }

    _connection = await Connection.open(
      Endpoint(
        host: host,
        port: port,
        database: database,
        username: username,
        password: password,
      ),
      settings: const ConnectionSettings(
        sslMode: SslMode.disable, // Conforme solicitado
      ),
    );
    _connected = true;
    print('Conectado ao PostgreSQL com sucesso!');
  }

  /// Fecha a conexão com o banco de dados.
  Future<void> close() async {
    if (!_connected) return;
    await _connection.close();
    _connected = false;
    print('Conexão com o PostgreSQL fechada.');
  }
}
