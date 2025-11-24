import '../lib/database.dart';

Future<void> main() async {
  final db = Database();
  await db.connect();
  final conn = db.connection;

  try {
    print('Adicionando coluna placement na tabela meta_decks...');
    await conn.execute('ALTER TABLE meta_decks ADD COLUMN IF NOT EXISTS placement TEXT');
    print('Coluna adicionada com sucesso!');
  } catch (e) {
    print('Erro ao migrar banco: $e');
  } finally {
    await conn.close();
  }
}
