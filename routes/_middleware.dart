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
      _connected = true;
    }
    
    // Fornece a conexão do banco de dados para todas as rotas filhas.
    // Agora injetamos o Pool, que é compatível com a interface Session/Connection para execuções simples
    return handler.use(provider<Pool>((_) => _db.connection))(context);
  };
}
