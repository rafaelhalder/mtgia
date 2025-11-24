import 'package:postgres/postgres.dart';
import '../lib/database.dart';

Future<void> main() async {
  final db = Database();
  await db.connect();
  final conn = db.connection;

  try {
    print('Adicionando coluna deleted_at na tabela decks...');

    // Verifica se a coluna já existe
    final checkResult = await conn.execute(Sql.named(
      "SELECT column_name FROM information_schema.columns WHERE table_name = 'decks' AND column_name = 'deleted_at'"
    ));

    if (checkResult.isNotEmpty) {
      print('⚠️ A coluna deleted_at já existe na tabela decks.');
    } else {
      // Adiciona a coluna
      await conn.execute(Sql.named(
        'ALTER TABLE decks ADD COLUMN deleted_at TIMESTAMP WITH TIME ZONE'
      ));
      print('✅ Coluna deleted_at adicionada com sucesso!');
    }

  } catch (e) {
    print('❌ Erro ao adicionar coluna: $e');
  } finally {
    // O Pool não fecha facilmente aqui, mas o script termina
    print('Migração finalizada.');
  }
}
