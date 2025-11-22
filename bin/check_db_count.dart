import '../lib/database.dart';
import 'package:postgres/postgres.dart';

Future<void> main() async {
  final db = Database();
  await db.connect();
  final conn = db.connection;

  try {
    final countResult = await conn.execute(Sql.named('SELECT count(*) FROM cards'));
    print('Total de cartas no banco: ${countResult.first[0]}');

    final sampleResult = await conn.execute(Sql.named('SELECT scryfall_id, name FROM cards LIMIT 1'));
    if (sampleResult.isNotEmpty) {
      print('Exemplo de carta:');
      print('Name: ${sampleResult.first[1]}');
      print('Scryfall ID: ${sampleResult.first[0]}');
    } else {
      print('Nenhuma carta encontrada para amostra.');
    }
  } catch (e) {
    print('Erro: $e');
  } finally {
    await db.close();
  }
}
