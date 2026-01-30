import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import '../lib/database.dart';

// Instancia o banco de dados uma vez.
final _db = Database();
var _connected = false;

Handler middleware(Handler handler) {
  return (context) async {
    // Conecta ao banco de dados apenas na primeira requisição.
    if (!_connected) {
      await _db.connect();
      await _ensureRuntimeSchema(_db.connection);
      _connected = true;
    }

    // Fornece a conexão do banco de dados para todas as rotas filhas.
    // Agora injetamos o Pool, que é compatível com a interface Session/Connection para execuções simples
    return handler.use(provider<Pool>((_) => _db.connection))(context);
  };
}

Future<void> _ensureRuntimeSchema(Pool pool) async {
  // Idempotente: garante compatibilidade com bases antigas após deploy.
  // Importante para validações de Commander (color identity).
  await pool.execute(Sql.named(
      'ALTER TABLE cards ADD COLUMN IF NOT EXISTS color_identity TEXT[]'));
  await pool.execute(Sql.named(
      'CREATE INDEX IF NOT EXISTS idx_cards_color_identity ON cards USING GIN (color_identity)'));
}
